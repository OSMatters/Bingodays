import SwiftUI
import UIKit

private struct BoardCompletionPresentation: Identifiable {
    let id: UUID
}

struct HomePrimaryCoversModifier: ViewModifier {
    @Binding var isQuickEditPresented: Bool
    @Binding var isPointsFlowPresented: Bool
    @Binding var selectedStickerID: UUID?
    @Binding var isDiaryPresented: Bool
    @Binding var isPremiumPaywallPresented: Bool
    @Binding var isLimitedTimeDiscountPresented: Bool
    @Binding var limitedOfferState: LimitedOfferHomeState

    @ObservedObject var viewModel: BingoViewModel
    @ObservedObject var pointsFeatureStore: PointsFeatureStore

    let isPadLayout: Bool
    let availablePoints: Int
    let totalPoints: Int
    let premiumPaywallSource: String
    let limitedTimeOfferConfig: LimitedTimeOfferConfig
    let boardCompletionAnimationID: UUID?
    let boardCompletionBoardName: String
    let onQuickEditSuccess: (String) -> Void
    let onQuickEditBoardApplied: () -> Void
    let onPremiumPaywallDismiss: () -> Void
    let onBoardCompletionDismiss: (UUID) -> Void

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isQuickEditPresented) {
                QuickEditView(
                    viewModel: viewModel,
                    limitedOfferState: $limitedOfferState,
                    onSaveSuccess: onQuickEditSuccess,
                    onBoardApplied: onQuickEditBoardApplied
                )
            }
            .fullScreenCover(isPresented: $isPointsFlowPresented) {
                PointsFlowPresenter(
                    isPadLayout: isPadLayout,
                    points: availablePoints,
                    totalPoints: totalPoints,
                    pointsFeatureStore: pointsFeatureStore,
                    limitedOfferState: $limitedOfferState,
                    onAddStickerToHomeSuccess: {
                        selectedStickerID = nil
                        isPointsFlowPresented = false
                    }
                )
            }
            .fullScreenCover(isPresented: $isDiaryPresented) {
                BingoDiaryScreen()
            }
            .fullScreenCover(isPresented: $isPremiumPaywallPresented, onDismiss: onPremiumPaywallDismiss) {
                PremiumPaywallView(
                    entrySource: premiumPaywallSource,
                    limitedOfferState: $limitedOfferState
                )
            }
            .fullScreenCover(isPresented: $isLimitedTimeDiscountPresented) {
                LimitedTimeDiscountView(
                    entrySource: "home_limited_offer",
                    campaignID: limitedTimeOfferConfig.campaignID,
                    offerDuration: limitedTimeOfferConfig.offerDuration,
                    limitedOfferState: $limitedOfferState
                )
            }
            .fullScreenCover(item: boardCompletionPresentationBinding) { presentation in
                BoardAllBingoCompletionView(
                    animationID: presentation.id,
                    boardName: boardCompletionBoardName,
                    onContinue: onBoardCompletionDismiss
                )
            }
    }

    private var boardCompletionPresentationBinding: Binding<BoardCompletionPresentation?> {
        Binding(
            get: {
                boardCompletionAnimationID.map(BoardCompletionPresentation.init)
            },
            set: { presentation in
                guard presentation == nil,
                      let boardCompletionAnimationID else {
                    return
                }
                onBoardCompletionDismiss(boardCompletionAnimationID)
            }
        )
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
    @Binding var isBoardCountdownPresented: Bool
    @Binding var isBoardRulesPresented: Bool
    @Binding var boardRulesTargetBoardID: UUID?
    @Binding var isGridSizeSheetPresented: Bool

    let namedBoards: [BingoBoardStore.NamedBoard]
    let restoredBoardRulesDraft: BoardRulesDraft?
    let hasPremiumAccess: Bool
    let boardCountdownEndsAt: Date?
    let isPadLayout: Bool
    let onCopyEmail: () -> Void
    let onOpenBugReportEmail: () -> Void
    let onOpenFeatureSuggestionEmail: () -> Void
    let onSaveBoardCountdown: (Int?) -> Void
    let onCancelBoardCountdown: () -> Void
    let onBoardRulesPremiumRequired: (BoardRulesDraft) -> Void
    let onBoardRulesDismissed: () -> Void
    let onApplyBoardRulesSettings: (UUID, Int?, BoardTaskResetMode, Int?) -> Bool
    @ViewBuilder let gridSizeSheet: () -> AnyView

    private var usesPadBottomHalfSheets: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isContactUsPresented) {
                ContactUsSheet(
                    isPresented: $isContactUsPresented,
                    isPadLayout: isPadLayout,
                    isCopyToastVisible: isContactUsCopyToastVisible,
                    onCopyEmail: onCopyEmail,
                    onOpenBugReportEmail: onOpenBugReportEmail,
                    onOpenFeatureSuggestionEmail: onOpenFeatureSuggestionEmail
                )
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
            .adaptivePadBottomHalfSheet(
                isPresented: $isBoardRulesPresented,
                usePadPresentation: usesPadBottomHalfSheets,
                backgroundColor: Color(hex: "FAF9F3"),
                contentMaxWidth: 720,
                padHeightFraction: 0.9,
                onDismiss: onBoardRulesDismissed
            ) {
                if let boardRulesTargetBoardID,
                   let board = namedBoards.first(where: { $0.id == boardRulesTargetBoardID }) {
                    let matchingDraft = restoredBoardRulesDraft?.boardID == board.id
                        ? restoredBoardRulesDraft
                        : nil
                    BoardRulesSheet(
                        boardName: board.name,
                        countdownEndsAt: board.countdownEndsAt,
                        initialResetMode: board.taskResetMode,
                        initialCustomResetMinutes: board.customResetMinutes,
                        restoredDraft: matchingDraft,
                        onSave: { totalMinutes, resetMode, customResetMinutes in
                            let normalizedCustomResetMinutes = BoardResetRuleEngine.normalizedCustomResetMinutes(
                                customResetMinutes,
                                mode: resetMode
                            )
                            if normalizedCustomResetMinutes != nil, !hasPremiumAccess {
                                let draft = BoardRulesDraft(
                                    boardID: board.id,
                                    countdownMinutes: totalMinutes,
                                    resetMode: resetMode,
                                    customResetMinutes: normalizedCustomResetMinutes
                                )
                                isBoardRulesPresented = false
                                onBoardRulesPremiumRequired(draft)
                                return
                            }
                            if onApplyBoardRulesSettings(
                                board.id,
                                totalMinutes,
                                resetMode,
                                normalizedCustomResetMinutes
                            ) {
                                isBoardRulesPresented = false
                            }
                        },
                        onCancel: {
                            isBoardRulesPresented = false
                        }
                    )
                    .presentationDetents([.fraction(isPadLayout ? 0.72 : 0.88)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Color(hex: "FAF9F3"))
                }
            }
            .adaptivePadBottomHalfSheet(
                isPresented: $isGridSizeSheetPresented,
                usePadPresentation: usesPadBottomHalfSheets,
                backgroundColor: NeumorphicColors.background,
                contentMaxWidth: 720
            ) {
                gridSizeSheet()
                    .presentationDetents([.height(280)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(NeumorphicColors.background)
            }
    }
}
