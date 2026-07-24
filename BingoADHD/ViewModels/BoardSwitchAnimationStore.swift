import SwiftUI

@MainActor
final class BoardSwitchAnimationStore: ObservableObject {
    struct SwipeBlockingState {
        var isSidebarPresented = false
        var isQuickEditPresented = false
        var isEditActionsExpanded = false
        var isBoardCountdownPresented = false
        var isBoardRulesPresented = false
        var hasTimeoutDelayPicker = false
        var hasExpiredTaskEvent = false
        var hasExpiredBoardCountdownEvent = false
        var hasScheduledTaskReplacementEvent = false

        var allowsBoardSwipe: Bool {
            !isSidebarPresented &&
            !isQuickEditPresented &&
            !isEditActionsExpanded &&
            !isBoardCountdownPresented &&
            !isBoardRulesPresented &&
            !hasTimeoutDelayPicker &&
            !hasExpiredTaskEvent &&
            !hasExpiredBoardCountdownEvent &&
            !hasScheduledTaskReplacementEvent
        }
    }

    @Published var isAnimating = false
    @Published var offsetX: CGFloat = 0

    private let selectionLockDuration: TimeInterval = 0.42
    private let swipeExitDuration: TimeInterval = 0.16

    func beginSelection() -> Bool {
        guard !isAnimating else { return false }
        isAnimating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + selectionLockDuration) { [weak self] in
            self?.isAnimating = false
        }
        return true
    }

    func switchBySwipe(
        horizontalTranslation: CGFloat,
        boardWidth: CGFloat,
        namedBoards: [BingoBoardStore.NamedBoard],
        selectedBoardID: UUID?,
        onTargetResolved: @escaping (UUID) -> Void,
        selectBoard: @escaping (UUID) -> Void
    ) {
        guard namedBoards.count > 1 else { return }
        guard let currentBoardID = selectedBoardID ?? namedBoards.first?.id,
              let currentIndex = namedBoards.firstIndex(where: { $0.id == currentBoardID }) else {
            return
        }

        let targetIndex: Int?
        if horizontalTranslation <= -1 {
            let nextIndex = currentIndex + 1
            targetIndex = namedBoards.indices.contains(nextIndex) ? nextIndex : nil
        } else if horizontalTranslation >= 1 {
            let previousIndex = currentIndex - 1
            targetIndex = namedBoards.indices.contains(previousIndex) ? previousIndex : nil
        } else {
            targetIndex = nil
        }

        guard let targetIndex else { return }
        let offscreenDistance = boardWidth + 40
        let exitOffset = horizontalTranslation < 0 ? -offscreenDistance : offscreenDistance
        let enterOffset = -exitOffset
        let targetBoardID = namedBoards[targetIndex].id
        onTargetResolved(targetBoardID)

        withAnimation(.easeOut(duration: swipeExitDuration)) {
            offsetX = exitOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + swipeExitDuration) { [weak self] in
            selectBoard(targetBoardID)
            self?.offsetX = enterOffset
            withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.1)) {
                self?.offsetX = 0
            }
        }
    }

    func completeSwipe(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat,
        boardWidth: CGFloat,
        isPadLayout: Bool,
        blockingState: SwipeBlockingState,
        namedBoards: [BingoBoardStore.NamedBoard],
        selectedBoardID: UUID?,
        onTargetResolved: @escaping (UUID) -> Void,
        selectBoard: @escaping (UUID) -> Void
    ) {
        guard blockingState.allowsBoardSwipe else { return }
        guard abs(horizontalTranslation) > abs(verticalTranslation) else { return }

        let swipeThreshold: CGFloat = isPadLayout ? 96 : 68
        guard abs(horizontalTranslation) >= swipeThreshold else { return }

        switchBySwipe(
            horizontalTranslation: horizontalTranslation,
            boardWidth: boardWidth,
            namedBoards: namedBoards,
            selectedBoardID: selectedBoardID,
            onTargetResolved: onTargetResolved,
            selectBoard: selectBoard
        )
    }
}
