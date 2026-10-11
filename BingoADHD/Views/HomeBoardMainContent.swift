import SwiftUI

struct HomeBoardMainContent: View {
    @ObservedObject var viewModel: BingoViewModel

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
    let allowsBoardSwipe: Bool
    let onSelectBoard: (UUID) -> Bool
    let onBoardLongPress: (UUID) -> Void
    let onCreateBoard: () -> Void
    let onDismissBoardEditHint: () -> Void
    let onCellCompletionToggled: () -> Void
    let onTaskPresentationChange: (Bool) -> Void
    let onCountdown: () -> Void
    let onEditActionsToggle: () -> Void
    let onDismissEditActions: () -> Void
    let onBoardRules: () -> Void
    let onBoardOrder: () -> Void
    let onShuffle: () -> Void
    let onClearBoard: () -> Void
    let onGridSize: () -> Void
    let onQuickEdit: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            BoardSwitcherControlsView(
                boards: namedBoards,
                selectedBoardID: selectedBoardID,
                contentWidth: contentWidth,
                isPadLayout: isPadLayout,
                shouldShowBoardEditHint: shouldShowBoardEditHint,
                shouldReserveBoardEditHintSpace: shouldReserveBoardEditHintSpace,
                onSelectBoard: selectBoardFromControls,
                onBoardLongPress: onBoardLongPress,
                onCreateBoard: onCreateBoard,
                onDismissBoardEditHint: onDismissBoardEditHint
            )
            .padding(.top, 14)

            BoardSwipePagerView(
                viewModel: viewModel,
                namedBoards: namedBoards,
                selectedBoardID: selectedBoardID,
                contentWidth: contentWidth,
                currentTime: currentTime,
                shouldShowCenterLongPressHint: shouldShowCenterLongPressHint,
                allowsBoardSwipe: allowsBoardSwipe,
                onSelectBoard: onSelectBoard,
                onCellCompletionToggled: onCellCompletionToggled,
                onTaskPresentationChange: onTaskPresentationChange
            )
            .padding(.top, 8)

            BoardBottomControlsView(
                countdownText: countdownText,
                isPadLayout: isPadLayout,
                isEditActionsExpanded: isEditActionsExpanded,
                surfaceShadowColor: surfaceShadowColor,
                themeColor: themeColor,
                onCountdown: onCountdown,
                onEditActionsToggle: onEditActionsToggle,
                onDismissEditActions: onDismissEditActions,
                onBoardRules: onBoardRules,
                onBoardOrder: onBoardOrder,
                onShuffle: onShuffle,
                onClearBoard: onClearBoard,
                onGridSize: onGridSize,
                onQuickEdit: onQuickEdit,
                liveActivityBoardID: selectedBoardID
            )
            .padding(.top, 10)
        }
        .frame(width: contentWidth)
        .padding(.top, 32)
        .offset(y: (usesPadLayout ? -35 : 0) - 65)
    }

    private func selectBoardFromControls(_ boardID: UUID) {
        _ = onSelectBoard(boardID)
    }
}
