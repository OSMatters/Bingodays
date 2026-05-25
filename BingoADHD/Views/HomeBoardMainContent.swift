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
    let countdownText: String?
    let isTemplateShareDisabled: Bool
    let isEditActionsExpanded: Bool
    let surfaceShadowColor: Color
    let boardSwipeBlockingState: BoardSwitchAnimationStore.SwipeBlockingState
    let onSelectBoard: (UUID) -> Void
    let onBoardLongPress: (UUID) -> Void
    let onCreateBoard: () -> Void
    let onDismissBoardEditHint: () -> Void
    let onCellCompletionToggled: () -> Void
    let onTemplateShare: () -> Void
    let onCountdown: () -> Void
    let onEditActionsToggle: () -> Void

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
                isTemplateShareDisabled: isTemplateShareDisabled,
                isEditActionsExpanded: isEditActionsExpanded,
                surfaceShadowColor: surfaceShadowColor,
                onTemplateShare: onTemplateShare,
                onCountdown: onCountdown,
                onEditActionsToggle: onEditActionsToggle
            )
            .padding(.top, 10)
        }
        .frame(width: contentWidth)
        .padding(.top, 32)
        .offset(y: (usesPadLayout ? -35 : 0) - 35)
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
