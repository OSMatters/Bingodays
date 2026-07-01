import SwiftUI

struct HomeBoardMainContent: View {
    @ObservedObject var viewModel: BingoViewModel
    @ObservedObject var boardSwitchAnimationStore: BoardSwitchAnimationStore

    let namedBoards: [BingoBoardStore.NamedBoard]
    let selectedBoardID: UUID?
    let contentWidth: CGFloat
    let usesPadLayout: Bool
    let isPadLayout: Bool
    let currentTime: Date
    let shouldShowCenterLongPressHint: Bool
    let shouldShowBoardEditHint: Bool
    let shouldReserveBoardEditHintSpace: Bool
    let countdownText: String?
    let isEditActionsExpanded: Bool
    let surfaceShadowColor: Color
    let themeColor: Color
    let boardSwipeBlockingState: BoardSwitchAnimationStore.SwipeBlockingState
    let onSelectBoard: (UUID) -> Void
    let onBoardLongPress: (UUID) -> Void
    let onCreateBoard: () -> Void
    let onDismissBoardEditHint: () -> Void
    let onCellCompletionToggled: () -> Void
    let onCountdown: () -> Void
    let onEditActionsToggle: () -> Void
    let onDismissEditActions: () -> Void
    let onShuffle: () -> Void
    let onClearBoard: () -> Void
    let onGridSize: () -> Void
    let onQuickEdit: () -> Void

    @GestureState private var boardDragTranslationX: CGFloat = 0
    @State private var isCellReordering = false

    var body: some View {
        VStack(spacing: 16) {
            BoardSwitcherControlsView(
                boards: namedBoards,
                selectedBoardID: selectedBoardID,
                contentWidth: contentWidth,
                isPadLayout: isPadLayout,
                shouldShowBoardEditHint: shouldShowBoardEditHint,
                shouldReserveBoardEditHintSpace: shouldReserveBoardEditHintSpace,
                onSelectBoard: onSelectBoard,
                onBoardLongPress: onBoardLongPress,
                onCreateBoard: onCreateBoard,
                onDismissBoardEditHint: onDismissBoardEditHint
            )
            .padding(.top, 14)

            swipeableBoardView

            BoardBottomControlsView(
                countdownText: countdownText,
                isPadLayout: isPadLayout,
                isEditActionsExpanded: isEditActionsExpanded,
                surfaceShadowColor: surfaceShadowColor,
                themeColor: themeColor,
                onCountdown: onCountdown,
                onEditActionsToggle: onEditActionsToggle,
                onDismissEditActions: onDismissEditActions,
                onShuffle: onShuffle,
                onClearBoard: onClearBoard,
                onGridSize: onGridSize,
                onQuickEdit: onQuickEdit
            )
            .padding(.top, 10)
        }
        .frame(width: contentWidth)
        .padding(.top, 32)
        .offset(y: (usesPadLayout ? -35 : 0) - 65)
    }

    private var swipeableBoardView: some View {
        ZStack {
            BingoBoardView(
                viewModel: viewModel,
                currentTime: currentTime,
                shouldShowCenterLongPressHint: shouldShowCenterLongPressHint,
                onCellCompletionToggled: onCellCompletionToggled,
                onCellReorderActiveChanged: { isActive in
                    isCellReordering = isActive
                }
            )
        }
        .animation(.interactiveSpring(response: 0.52, dampingFraction: 0.88, blendDuration: 0.15), value: selectedBoardID)
        .frame(width: contentWidth, height: contentWidth)
        .padding(.top, 8)
        .offset(x: boardDragTranslationX + boardSwitchAnimationStore.offsetX)
        .contentShape(Rectangle())
        .simultaneousGesture(boardSwipeGesture)
    }

    private var boardSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 28, coordinateSpace: .local)
            .updating($boardDragTranslationX) { value, state, _ in
                guard !isCellReordering else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }
                state = horizontal
            }
            .onEnded { value in
                guard !isCellReordering else { return }
                boardSwitchAnimationStore.completeSwipe(
                    horizontalTranslation: value.translation.width,
                    verticalTranslation: value.translation.height,
                    boardWidth: contentWidth,
                    isPadLayout: isPadLayout,
                    blockingState: boardSwipeBlockingState,
                    namedBoards: namedBoards,
                    selectedBoardID: selectedBoardID,
                    selectBoard: onSelectBoard
                )
            }
    }
}
