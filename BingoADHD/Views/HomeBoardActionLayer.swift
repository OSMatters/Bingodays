import SwiftUI

struct HomeBoardActionLayer: View {
    @ObservedObject var boardActionPresentationStore: BoardActionPresentationStore

    let namedBoards: [BingoBoardStore.NamedBoard]
    let contentWidth: CGFloat
    let bottomInset: CGFloat
    let isPadLayout: Bool
    let allowsDeletingFirstBoard: Bool
    let protectedBoardID: UUID?
    let onBoardRules: (UUID) -> Void
    let onRenameBoard: (UUID) -> Void
    let onDeleteBoard: (UUID) -> Void

    var body: some View {
        if let boardActionSheetBoardID = boardActionPresentationStore.actionSheetBoardID,
           let board = namedBoards.first(where: { $0.id == boardActionSheetBoardID }) {
            BoardActionsOverlayView(
                canDelete: BoardActionPresentationStore.canDeleteBoard(
                    board.id,
                    namedBoards: namedBoards,
                    allowsDeletingFirstBoard: allowsDeletingFirstBoard,
                    protectedBoardID: protectedBoardID
                ),
                contentWidth: contentWidth,
                bottomInset: bottomInset,
                isPadLayout: isPadLayout,
                onDismiss: boardActionPresentationStore.dismissActions,
                onBoardRules: {
                    boardActionPresentationStore.performAfterDismissingActions {
                        onBoardRules(board.id)
                    }
                },
                onEdit: {
                    boardActionPresentationStore.performAfterDismissingActions {
                        onRenameBoard(board.id)
                    }
                },
                onDelete: {
                    boardActionPresentationStore.performAfterDismissingActions {
                        onDeleteBoard(board.id)
                    }
                }
            )
            .transition(.opacity)
        }
    }
}
