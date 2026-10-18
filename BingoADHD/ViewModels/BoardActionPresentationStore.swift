import Foundation
import SwiftUI

@MainActor
final class BoardActionPresentationStore: ObservableObject {
    enum BoardDeleteAvailability {
        case allowed
        case blocked(String)
    }

    private static let actionsAnimation = Animation.easeInOut(duration: 0.2)
    private static let actionSelectionDelay: DispatchTimeInterval = .milliseconds(120)

    @Published var isCreateAlertPresented = false
    @Published var createNameDraft = ""
    @Published var isRenameAlertPresented = false
    @Published var renameNameDraft = ""
    @Published var pendingRenameID: UUID?
    @Published var actionSheetBoardID: UUID?
    @Published var pendingDeleteID: UUID?
    @Published var isDeleteAlertPresented = false

    func presentActions(for boardID: UUID) {
        withAnimation(Self.actionsAnimation) {
            actionSheetBoardID = boardID
        }
    }

    func dismissActions() {
        withAnimation(Self.actionsAnimation) {
            actionSheetBoardID = nil
        }
    }

    func performAfterDismissingActions(_ action: @escaping @MainActor () -> Void) {
        dismissActions()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.actionSelectionDelay) {
            action()
        }
    }

    func beginCreate(defaultName: String) {
        createNameDraft = defaultName
        isCreateAlertPresented = true
    }

    func clearCreateDraft() {
        createNameDraft = ""
    }

    func beginRename(board: BingoBoardStore.NamedBoard) {
        pendingRenameID = board.id
        renameNameDraft = board.name
        isRenameAlertPresented = true
    }

    func clearRenameDraft() {
        renameNameDraft = ""
        pendingRenameID = nil
    }

    func beginDelete(boardID: UUID) {
        pendingDeleteID = boardID
        isDeleteAlertPresented = true
    }

    func clearPendingDelete() {
        pendingDeleteID = nil
    }

    static func deleteAvailability(
        for boardID: UUID,
        namedBoards: [BingoBoardStore.NamedBoard],
        allowsDeletingFirstBoard: Bool,
        protectedBoardID: UUID? = nil
    ) -> BoardDeleteAvailability {
        guard namedBoards.count > 1 else {
            return .blocked(
                L10n.tr(
                    "At least one board must remain.",
                    zhHans: "至少需要保留一个棋盘。",
                    zhHant: "至少需要保留一個棋盤。"
                )
            )
        }

        if !allowsDeletingFirstBoard,
           boardID == (protectedBoardID ?? namedBoards.first?.id) {
            return .blocked(
                L10n.tr(
                    "On Free plan, Board 1 cannot be deleted.",
                    zhHans: "非会员模式下，Board 1 不能删除。",
                    zhHant: "非會員模式下，Board 1 不能刪除。"
                )
            )
        }

        return .allowed
    }

    static func canDeleteBoard(
        _ boardID: UUID,
        namedBoards: [BingoBoardStore.NamedBoard],
        allowsDeletingFirstBoard: Bool,
        protectedBoardID: UUID? = nil
    ) -> Bool {
        switch deleteAvailability(
            for: boardID,
            namedBoards: namedBoards,
            allowsDeletingFirstBoard: allowsDeletingFirstBoard,
            protectedBoardID: protectedBoardID
        ) {
        case .allowed:
            return true
        case .blocked:
            return false
        }
    }

    static func pendingDeleteMessage(boardName: String) -> String {
        L10n.tr(
            "This will permanently delete \"\(boardName)\" and its progress.",
            zhHans: "将永久删除「\(boardName)」及其进度。",
            zhHant: "將永久刪除「\(boardName)」及其進度。"
        )
    }
}
