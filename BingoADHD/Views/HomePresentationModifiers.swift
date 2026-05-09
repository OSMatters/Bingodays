import SwiftUI

struct HomePrimaryCoversModifier: ViewModifier {
    @Binding var isQuickEditPresented: Bool
    @Binding var isBlackBoxModePresented: Bool
    @Binding var isPointsFlowPresented: Bool
    @Binding var selectedStickerID: UUID?
    @Binding var isDiaryPresented: Bool
    @Binding var isPremiumPaywallPresented: Bool

    @ObservedObject var viewModel: BingoViewModel
    @ObservedObject var pointsFeatureStore: PointsFeatureStore

    let isPadLayout: Bool
    let availablePoints: Int
    let totalPoints: Int
    let premiumPaywallSource: String
    let onQuickEditSuccess: (String) -> Void

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isQuickEditPresented) {
                QuickEditView(viewModel: viewModel, onSaveSuccess: onQuickEditSuccess)
            }
            .fullScreenCover(isPresented: $isBlackBoxModePresented) {
                BlackBoxModeEntryView()
            }
            .fullScreenCover(isPresented: $isPointsFlowPresented) {
                PointsFlowPresenter(
                    isPadLayout: isPadLayout,
                    points: availablePoints,
                    totalPoints: totalPoints,
                    pointsFeatureStore: pointsFeatureStore,
                    onAddStickerToHomeSuccess: {
                        isPointsFlowPresented = false
                        selectedStickerID = nil
                    }
                )
            }
            .fullScreenCover(isPresented: $isDiaryPresented) {
                BingoDiaryScreen()
            }
            .fullScreenCover(isPresented: $isPremiumPaywallPresented) {
                PremiumPaywallView(entrySource: premiumPaywallSource)
            }
    }
}

struct HomeBoardAlertsModifier: ViewModifier {
    @Binding var isCreateBoardAlertPresented: Bool
    @Binding var createBoardNameDraft: String
    @Binding var isRenameBoardAlertPresented: Bool
    @Binding var renameBoardNameDraft: String
    @Binding var boardPendingRenameID: UUID?
    @Binding var isBoardDeleteAlertPresented: Bool
    @Binding var pendingBoardDeleteID: UUID?
    @Binding var isClearBoardConfirmationPresented: Bool

    let pendingBoardDeleteMessage: String
    let onCreateBoard: () -> Void
    let onRenameBoard: () -> Void
    let onDeleteBoard: (UUID) -> Void
    let onClearBoard: () -> Void

    func body(content: Content) -> some View {
        content
            .alert(L10n.boardCreateTitle, isPresented: $isCreateBoardAlertPresented) {
                TextField(L10n.boardNamePlaceholder, text: $createBoardNameDraft)
                Button(L10n.cancel, role: .cancel) {
                    createBoardNameDraft = ""
                }
                Button(L10n.boardCreateAction) {
                    onCreateBoard()
                }
            }
            .alert(L10n.boardRenameTitle, isPresented: $isRenameBoardAlertPresented) {
                TextField(L10n.boardNamePlaceholder, text: $renameBoardNameDraft)
                Button(L10n.cancel, role: .cancel) {
                    renameBoardNameDraft = ""
                    boardPendingRenameID = nil
                }
                Button(L10n.boardRenameAction) {
                    onRenameBoard()
                }
            }
            .alert(
                L10n.tr("Delete board?", zhHans: "删除棋盘？", zhHant: "刪除棋盤？"),
                isPresented: $isBoardDeleteAlertPresented
            ) {
                Button(L10n.cancel, role: .cancel) {
                    pendingBoardDeleteID = nil
                }
                Button(L10n.deleteConfirmationTitle, role: .destructive) {
                    guard let pendingBoardDeleteID else { return }
                    onDeleteBoard(pendingBoardDeleteID)
                }
            } message: {
                Text(pendingBoardDeleteMessage)
            }
            .alert(
                L10n.clearBoardConfirmationTitle,
                isPresented: $isClearBoardConfirmationPresented
            ) {
                Button(L10n.cancel, role: .cancel) {}
                Button(L10n.clearBoard, role: .destructive) {
                    onClearBoard()
                }
            } message: {
                Text(L10n.clearBoardConfirmationMessage)
            }
    }
}
