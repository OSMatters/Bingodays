import SwiftUI

/// A horizontally paged board container that keeps neighboring boards alive while
/// the finger is moving. This avoids swapping the board data in the gap between
/// pages, while leaving every cell's existing interaction untouched.
struct BoardSwipePagerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // The active BingoBoardView owns the observation; the pager only forwards it.
    let viewModel: BingoViewModel

    let namedBoards: [BingoBoardStore.NamedBoard]
    let selectedBoardID: UUID?
    let contentWidth: CGFloat
    let currentTime: Date
    let shouldShowCenterLongPressHint: Bool
    let allowsBoardSwipe: Bool
    let onSelectBoard: (UUID) -> Bool
    let onCellCompletionToggled: () -> Void
    let onTaskPresentationChange: (Bool) -> Void

    @GestureState(
        resetTransaction: Transaction(
            animation: .interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.1)
        )
    ) private var dragTranslationX: CGFloat = 0

    @State private var pageOffsetX: CGFloat = 0
    @State private var isCellReordering = false
    @State private var isPagerTransitioning = false
    @State private var settledBoardID: UUID?
    @State private var retainedPageRange: Range<Int> = 0..<0
    @State private var pageAnimationID = UUID()

    var body: some View {
        let pageRange = renderedPageRange
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                // Preserve absolute page positions without constructing offscreen boards.
                Color.clear
                    .frame(width: CGFloat(pageRange.lowerBound) * contentWidth, height: contentWidth)
                    .accessibilityHidden(true)

                ForEach(namedBoards[pageRange]) { board in
                    page(for: board)
                        .frame(width: contentWidth, height: contentWidth)
                        .accessibilityHidden(board.id != activeBoardID)
                }
            }
            .offset(x: pageOffsetX + displayedDragOffset)
        }
        .frame(width: contentWidth, height: contentWidth, alignment: .leading)
        // Restrict the carousel horizontally, but leave room above and below so
        // completion effects from cells at the board edge can extend outward.
        .mask {
            Rectangle()
                .frame(width: contentWidth, height: contentWidth * 3)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(pagingGesture)
        .onAppear {
            setPageOffsetWithoutAnimation(to: activeBoardID)
        }
        .onChange(of: selectedBoardID) { _, _ in
            synchronizePageOffsetWithSelectedBoard()
        }
        .onChange(of: namedBoards.map(\.id)) { _, _ in
            reconcilePageOffsetAfterBoardListChange()
        }
        .onChange(of: contentWidth) { _, _ in
            setPageOffsetWithoutAnimation(to: activeBoardID)
        }
    }

    @ViewBuilder
    private func page(for board: BingoBoardStore.NamedBoard) -> some View {
        if board.id == activeBoardID {
            BingoBoardView(
                viewModel: viewModel,
                currentTime: currentTime,
                shouldShowCenterLongPressHint: shouldShowCenterLongPressHint,
                onCellCompletionToggled: onCellCompletionToggled,
                onTaskPresentationChange: onTaskPresentationChange,
                onCellReorderActiveChanged: { isActive in
                    isCellReordering = isActive
                }
            )
            .id(board.id)
        } else {
            BoardSwipePreviewView(
                savedBoard: board.board,
                currentTime: currentTime,
                sideLength: contentWidth
            )
            .equatable()
        }
    }

    private var renderedPageRange: Range<Int> {
        let activeIndex = namedBoards.firstIndex { $0.id == activeBoardID }
        let visibleIndex = contentWidth > 0 ? Int(floor(-(pageOffsetX + displayedDragOffset) / contentWidth)) : nil
        return BoardSwipePageWindow.range(
            boardCount: namedBoards.count,
            activeIndex: activeIndex,
            settledIndex: reduceMotion ? activeIndex : namedBoards.firstIndex { $0.id == settledBoardID },
            retainedRange: reduceMotion ? 0..<0 : retainedPageRange,
            visibleIndex: reduceMotion || settledBoardID == nil ? nil : visibleIndex
        )
    }

    private var activeBoardID: UUID? {
        selectedBoardID ?? namedBoards.first?.id
    }

    private var displayedDragOffset: CGFloat {
        guard !isPagerTransitioning, !reduceMotion else { return 0 }
        return resistedDragOffset(for: dragTranslationX)
    }

    private var pagingGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .updating($dragTranslationX) { value, state, _ in
                guard canHandlePagingGesture(value) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                completePagingGesture(with: value)
            }
    }

    private func canHandlePagingGesture(_ value: DragGesture.Value) -> Bool {
        allowsBoardSwipe
            && !isCellReordering
            && !isPagerTransitioning
            && abs(value.translation.width) > abs(value.translation.height)
    }

    private func completePagingGesture(with value: DragGesture.Value) {
        guard canHandlePagingGesture(value) else { return }

        let releaseTranslation = releaseTranslation(for: value)
        guard abs(releaseTranslation) >= swipeCommitThreshold,
              let destinationBoardID = adjacentBoardID(for: releaseTranslation) else {
            return
        }

        // @GestureState resets at the end of this callback. Preserve the precise
        // finger position first, then animate from there to the next board.
        isPagerTransitioning = true
        pageOffsetX += resistedDragOffset(for: value.translation.width)

        let didSelectBoard = onSelectBoard(destinationBoardID)
        animateToPage(didSelectBoard ? destinationBoardID : activeBoardID)
    }

    private func releaseTranslation(for value: DragGesture.Value) -> CGFloat {
        let predicted = value.predictedEndTranslation.width
        guard abs(predicted) > abs(value.translation.width),
              predicted.sign == value.translation.width.sign else {
            return value.translation.width
        }
        return predicted
    }

    private var swipeCommitThreshold: CGFloat {
        max(contentWidth * 0.18, 68)
    }

    private func adjacentBoardID(for translation: CGFloat) -> UUID? {
        guard let activeBoardID,
              let activeIndex = namedBoards.firstIndex(where: { $0.id == activeBoardID }) else {
            return nil
        }

        let targetIndex = translation < 0 ? activeIndex + 1 : activeIndex - 1
        guard namedBoards.indices.contains(targetIndex) else { return nil }
        return namedBoards[targetIndex].id
    }

    private func resistedDragOffset(for translation: CGFloat) -> CGFloat {
        guard canMoveToward(translation) else {
            let resistanceLimit = max(contentWidth * 0.16, 1)
            return translation / (1 + abs(translation) / resistanceLimit)
        }
        return translation
    }

    private func canMoveToward(_ translation: CGFloat) -> Bool {
        adjacentBoardID(for: translation) != nil
    }

    private func synchronizePageOffsetWithSelectedBoard() {
        guard pageOffsetX != pageOffset(for: activeBoardID) else { return }
        animateToPage(activeBoardID)
    }

    private func reconcilePageOffsetAfterBoardListChange() {
        guard let activeBoardID,
              namedBoards.contains(where: { $0.id == activeBoardID }) else {
            setPageOffsetWithoutAnimation(to: namedBoards.first?.id)
            return
        }
        setPageOffsetWithoutAnimation(to: activeBoardID)
    }

    private func animateToPage(_ boardID: UUID?) {
        let destinationOffset = pageOffset(for: boardID)

        guard !reduceMotion else {
            setPageOffsetWithoutAnimation(to: boardID)
            return
        }

        // Keep every page crossed by a jump until the latest animation finishes.
        // Rapid retargeting must not release pages still visible in the old animation.
        retainedPageRange = renderedPageRange
        let animationID = UUID()
        pageAnimationID = animationID
        withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.1)) {
            pageOffsetX = destinationOffset
        } completion: {
            guard pageAnimationID == animationID else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                settledBoardID = boardID
                retainedPageRange = 0..<0
                isPagerTransitioning = false
            }
        }
    }

    private func setPageOffsetWithoutAnimation(to boardID: UUID?) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            pageAnimationID = UUID()
            pageOffsetX = pageOffset(for: boardID)
            settledBoardID = boardID
            retainedPageRange = 0..<0
            isPagerTransitioning = false
        }
    }

    private func pageOffset(for boardID: UUID?) -> CGFloat {
        guard let boardID,
              let index = namedBoards.firstIndex(where: { $0.id == boardID }) else {
            return 0
        }
        return -CGFloat(index) * contentWidth
    }
}
