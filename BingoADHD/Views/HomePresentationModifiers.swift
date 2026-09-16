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
    @Binding var isBoardOrderPresented: Bool

    let namedBoards: [BingoBoardStore.NamedBoard]
    let selectedBoardID: UUID?
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
    let onSaveBoardOrder: ([UUID]) -> Bool
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
            .adaptivePadBottomHalfSheet(
                isPresented: $isBoardOrderPresented,
                usePadPresentation: usesPadBottomHalfSheets,
                backgroundColor: Color(hex: "FAF9F3"),
                contentMaxWidth: 720,
                padHeightFraction: 0.7
            ) {
                BoardOrderSheet(
                    boards: namedBoards,
                    selectedBoardID: selectedBoardID,
                    isPadLayout: isPadLayout,
                    onSave: onSaveBoardOrder,
                    onCancel: { isBoardOrderPresented = false }
                )
                .presentationDetents([.fraction(isPadLayout ? 0.62 : 0.72)])
                .presentationDragIndicator(.visible)
            }
    }
}

enum BoardOrderDragIndexCalculator {
    static func targetIndex(
        startIndex: Int,
        translationInRows: Double,
        boardCount: Int
    ) -> Int {
        guard boardCount > 1 else { return 0 }

        let rowOffset = Int(translationInRows.rounded(.toNearestOrAwayFromZero))
        return min(max(startIndex + rowOffset, 1), boardCount - 1)
    }

    static func displacement(
        for index: Int,
        sourceIndex: Int,
        targetIndex: Int
    ) -> Int {
        if sourceIndex < targetIndex,
           index > sourceIndex,
           index <= targetIndex {
            return -1
        }
        if targetIndex < sourceIndex,
           index >= targetIndex,
           index < sourceIndex {
            return 1
        }
        return 0
    }
}

private struct BoardOrderSheet: View {
    let boards: [BingoBoardStore.NamedBoard]
    let selectedBoardID: UUID?
    let isPadLayout: Bool
    let onSave: ([UUID]) -> Bool
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draftBoards: [BingoBoardStore.NamedBoard]
    @State private var draggingBoardID: UUID?
    @State private var dragStartIndex: Int?
    @State private var dragTargetIndex: Int?
    @State private var dragTranslation: CGFloat = 0
    @State private var saveErrorMessage: String?

    init(
        boards: [BingoBoardStore.NamedBoard],
        selectedBoardID: UUID?,
        isPadLayout: Bool,
        onSave: @escaping ([UUID]) -> Bool,
        onCancel: @escaping () -> Void
    ) {
        self.boards = boards
        self.selectedBoardID = selectedBoardID
        self.isPadLayout = isPadLayout
        self.onSave = onSave
        self.onCancel = onCancel
        _draftBoards = State(initialValue: boards)
    }

    private var didChangeOrder: Bool {
        draftBoards.map(\.id) != boards.map(\.id)
    }

    private var lockedBoardID: UUID? {
        boards.first?.id
    }

    private var sheetBackground: Color {
        Color(hex: "FAF9F3")
    }

    private var rowHeight: CGFloat {
        isPadLayout ? 56 : 52
    }

    private var reorderAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.18, extraBounce: 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(draftBoards) { board in
                        HStack(spacing: 12) {
                            Text(board.name)
                                .font(.appSystem(size: scaled(16, pad: 18), weight: .regular, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer(minLength: 8)

                            if board.id == lockedBoardID {
                                Image(systemName: "lock.fill")
                                    .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold))
                                    .foregroundColor(NeumorphicColors.accent)
                                    .accessibilityLabel(L10n.tr("Locked board", zhHans: "已锁定棋盘", zhHant: "已鎖定棋盤"))
                            } else if board.id == selectedBoardID {
                                Image(systemName: "checkmark")
                                    .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold))
                                    .foregroundColor(NeumorphicColors.accent)
                                    .accessibilityLabel(L10n.tr("Current board", zhHans: "当前棋盘", zhHant: "目前棋盤"))
                            }

                            if board.id != lockedBoardID {
                                Image(systemName: "line.3.horizontal")
                                    .font(.appSystem(size: scaled(18, pad: 20), weight: .medium))
                                    .foregroundColor(NeumorphicColors.accent)
                                    .accessibilityLabel(L10n.tr("Drag to reorder", zhHans: "长按拖动排序", zhHant: "長按拖動排序"))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                                    .gesture(boardReorderGesture(for: board.id))
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(height: rowHeight)
                        .contentShape(Rectangle())
                        .background(sheetBackground)
                        .overlay(alignment: .bottom) {
                            if board.id != lockedBoardID {
                                Rectangle()
                                    .fill(Color(hex: "E7E1D8"))
                                    .frame(height: 0.5)
                                    .padding(.horizontal, 16)
                            }
                        }
                        .offset(y: verticalOffset(for: board.id))
                        .zIndex(draggingBoardID == board.id ? 1 : 0)
                    }
                }
                .padding(.top, 8)
            }
            .scrollDisabled(draggingBoardID != nil)
            .background(sheetBackground)
            .coordinateSpace(name: "board-order-list")
            .navigationTitle(L10n.tr("Board Order", zhHans: "棋盘顺序", zhHant: "棋盤順序"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(sheetBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.cancel, action: cancel)
                        .font(.appSystem(size: scaled(16, pad: 18), weight: .regular, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.save, action: save)
                        .font(.appSystem(size: scaled(16, pad: 18), weight: .medium, design: .rounded))
                        .foregroundColor(NeumorphicColors.accent)
                        .disabled(!didChangeOrder)
                }
            }
            .alert(
                L10n.tr("Couldn't save board order", zhHans: "棋盘顺序保存失败", zhHant: "棋盤順序儲存失敗"),
                isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented { saveErrorMessage = nil }
                    }
                )
            ) {
                Button(L10n.ok, role: .cancel) {
                    saveErrorMessage = nil
                }
            } message: {
                Text(saveErrorMessage ?? "")
            }
        }
        .presentationBackground(sheetBackground)
    }

    private func save() {
        guard didChangeOrder else { return }
        guard onSave(draftBoards.map(\.id)) else {
            saveErrorMessage = L10n.tr(
                "Please try again.",
                zhHans: "请稍后重试。",
                zhHant: "請稍後再試。"
            )
            return
        }
        dismiss()
    }

    private func cancel() {
        onCancel()
        dismiss()
    }

    private func boardReorderGesture(for boardID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("board-order-list"))
            .onChanged { value in
                guard boardID != lockedBoardID else { return }
                if draggingBoardID == nil {
                    draggingBoardID = boardID
                    dragStartIndex = draftBoards.firstIndex(where: { $0.id == boardID })
                    dragTargetIndex = dragStartIndex
                }
                guard draggingBoardID == boardID,
                      let dragStartIndex else {
                    return
                }

                dragTranslation = value.translation.height
                let targetIndex = BoardOrderDragIndexCalculator.targetIndex(
                    startIndex: dragStartIndex,
                    translationInRows: Double(value.translation.height / rowHeight),
                    boardCount: draftBoards.count
                )
                if targetIndex != dragTargetIndex {
                    withAnimation(reorderAnimation) {
                        dragTargetIndex = targetIndex
                    }
                }
            }
            .onEnded { _ in
                finishDragging()
            }
    }

    private func verticalOffset(for boardID: UUID) -> CGFloat {
        guard let boardIndex = draftBoards.firstIndex(where: { $0.id == boardID }),
              let dragStartIndex,
              let dragTargetIndex else {
            return 0
        }
        if boardID == draggingBoardID {
            return dragTranslation
        }
        let displacement = BoardOrderDragIndexCalculator.displacement(
            for: boardIndex,
            sourceIndex: dragStartIndex,
            targetIndex: dragTargetIndex
        )
        return CGFloat(displacement) * rowHeight
    }

    private func finishDragging() {
        guard let dragStartIndex,
              let dragTargetIndex else {
            resetDragState()
            return
        }

        withAnimation(reorderAnimation, completionCriteria: .logicallyComplete) {
            dragTranslation = CGFloat(dragTargetIndex - dragStartIndex) * rowHeight
        } completion: {
            commitDrag(from: dragStartIndex, to: dragTargetIndex)
        }
    }

    private func commitDrag(from sourceIndex: Int, to targetIndex: Int) {
        var reorderedBoards = draftBoards
        if sourceIndex != targetIndex {
            reorderedBoards.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            )
        }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            draftBoards = reorderedBoards
            resetDragState()
        }
    }

    private func resetDragState() {
        draggingBoardID = nil
        dragStartIndex = nil
        dragTargetIndex = nil
        dragTranslation = 0
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}
