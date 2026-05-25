import SwiftUI

struct HomePrimaryCoversModifier: ViewModifier {
    @Binding var isQuickEditPresented: Bool
    @Binding var isBlackBoxModePresented: Bool
    @Binding var isPointsFlowPresented: Bool
    @Binding var selectedStickerID: UUID?
    @Binding var isDiaryPresented: Bool
    @Binding var isPremiumPaywallPresented: Bool
    @Binding var isLimitedTimeDiscountPresented: Bool

    @ObservedObject var viewModel: BingoViewModel
    @ObservedObject var pointsFeatureStore: PointsFeatureStore

    let isPadLayout: Bool
    let availablePoints: Int
    let totalPoints: Int
    let premiumPaywallSource: String
    let onQuickEditSuccess: (String) -> Void
    let onQuickEditBoardApplied: () -> Void

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isQuickEditPresented) {
                QuickEditView(
                    viewModel: viewModel,
                    onSaveSuccess: onQuickEditSuccess,
                    onBoardApplied: onQuickEditBoardApplied
                )
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
                        selectedStickerID = nil
                        isPointsFlowPresented = false
                    }
                )
            }
            .fullScreenCover(isPresented: $isDiaryPresented) {
                BingoDiaryScreen()
            }
            .fullScreenCover(isPresented: $isPremiumPaywallPresented) {
                PremiumPaywallView(entrySource: premiumPaywallSource)
            }
            .fullScreenCover(isPresented: $isLimitedTimeDiscountPresented) {
                LimitedTimeDiscountView(entrySource: "home_limited_offer")
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
                    .submitLabel(.done)
                Button(L10n.cancel, role: .cancel) {
                    createBoardNameDraft = ""
                }
                Button(L10n.boardCreateAction) {
                    onCreateBoard()
                }
            }
            .alert(L10n.boardRenameTitle, isPresented: $isRenameBoardAlertPresented) {
                TextField(L10n.boardNamePlaceholder, text: $renameBoardNameDraft)
                    .submitLabel(.done)
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

// Sheet and cover declarations live together here; ContentView still owns the state transitions.
struct HomeSheetsModifier: ViewModifier {
    @Binding var isContactUsPresented: Bool
    @Binding var isContactUsCopyToastVisible: Bool
    @Binding var isTemplateImportPreviewPresented: Bool
    @Binding var isBoardCountdownPresented: Bool
    @Binding var isBoardRulesPresented: Bool
    @Binding var boardRulesTargetBoardID: UUID?
    @Binding var isGridSizeSheetPresented: Bool
    @Binding var isTemplateShareComposerPresented: Bool

    let boardTemplateImportPreviewDraft: BoardTemplatePayload?
    let boardTemplateShareDraft: BoardTemplatePayload?
    let shouldImportTemplateAsNewBoard: Bool
    let namedBoards: [BingoBoardStore.NamedBoard]
    let hasPremiumAccess: Bool
    let boardCountdownEndsAt: Date?
    let isPadLayout: Bool
    let onCopyEmail: () -> Void
    let onOpenFeedbackEmail: () -> Void
    let onApplyImportedTemplate: (BoardTemplatePayload) -> Void
    let onDismissTemplatePreview: () -> Void
    let onTemplateImportSheetHeight: (Int) -> CGFloat
    let onSaveBoardCountdown: (Int?) -> Void
    let onCancelBoardCountdown: () -> Void
    let onPresentPremiumPaywall: (String) -> Void
    let onApplyBoardRulesSettings: (UUID, Int?, BoardTaskResetMode, Int?) -> Void
    @ViewBuilder let gridSizeSheet: () -> AnyView

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isContactUsPresented) {
                ContactUsSheet(
                    isPresented: $isContactUsPresented,
                    isPadLayout: isPadLayout,
                    isCopyToastVisible: isContactUsCopyToastVisible,
                    onCopyEmail: onCopyEmail,
                    onOpenFeedbackEmail: onOpenFeedbackEmail
                )
            }
            .sheet(isPresented: $isTemplateImportPreviewPresented) {
                if let template = boardTemplateImportPreviewDraft {
                    BoardTemplateImportPreviewView(
                        template: template,
                        createsNewBoard: shouldImportTemplateAsNewBoard,
                        onImport: {
                            onApplyImportedTemplate(template)
                        },
                        onClose: onDismissTemplatePreview
                    )
                    .presentationDetents([.height(onTemplateImportSheetHeight(template.gridSize))])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $isBoardCountdownPresented) {
                BoardCountdownSheet(
                    countdownEndsAt: boardCountdownEndsAt,
                    onSave: { totalMinutes in
                        onSaveBoardCountdown(totalMinutes)
                    },
                    onCancel: onCancelBoardCountdown
                )
                .presentationDetents([.height(410)])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isBoardRulesPresented) {
                if let boardRulesTargetBoardID,
                   let board = namedBoards.first(where: { $0.id == boardRulesTargetBoardID }) {
                    BoardRulesSheet(
                        countdownEndsAt: board.countdownEndsAt,
                        initialResetMode: board.taskResetMode,
                        initialCustomResetMinutes: board.customResetMinutes,
                        onSave: { totalMinutes, resetMode, customResetMinutes in
                            if customResetMinutes != nil, !hasPremiumAccess {
                                isBoardRulesPresented = false
                                onPresentPremiumPaywall("board_rules_custom_reset_time")
                                return
                            }
                            onApplyBoardRulesSettings(board.id, totalMinutes, resetMode, customResetMinutes)
                            isBoardRulesPresented = false
                        },
                        onCancel: {
                            isBoardRulesPresented = false
                        }
                    )
                    .presentationDetents([.height(560)])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $isGridSizeSheetPresented) {
                gridSizeSheet()
                    .presentationDetents([.height(280)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(NeumorphicColors.background)
            }
            .fullScreenCover(isPresented: $isTemplateShareComposerPresented) {
                if let template = boardTemplateShareDraft {
                    BoardTemplateShareComposerView(template: template)
                }
            }
    }
}
