import SwiftUI
import UIKit

enum BoardShareImportAction: String, Equatable {
    case createNewBoard = "create_new_board"
    case replaceCurrentBoard = "replace_current_board"
}

struct BoardShareFlowSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var store: BoardSharePresentationStore

    let boards: [BingoBoardStore.NamedBoard]
    let hasPremiumAccess: Bool
    let onImport: (BoardSharePayload, BoardShareImportAction) -> Bool
    let onUpgradeRequested: (BoardShareLookup) -> Void
    let onCopyCode: () -> Void
    let onReturnToActionMenu: () -> Void

    @State private var isReplacementConfirmationPresented = false
    @FocusState private var isShareCodeInputFocused: Bool
    @ScaledMetric(relativeTo: .body) private var shareCodeFontSize: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var publishedCodeFontSize: CGFloat = 31

    private var usesReflowedLayout: Bool {
        dynamicTypeSize == .xLarge ||
            dynamicTypeSize == .xxLarge ||
            dynamicTypeSize == .xxxLarge ||
            dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        NavigationStack {
            Group {
                switch store.page {
                case .menu:
                    adaptivePageContent(menu)
                case .selectBoard:
                    boardPicker
                case .shareResult(let result):
                    adaptivePageContent(shareResult(result))
                case .importCode:
                    adaptivePageContent(importCode)
                case .importPreview(let lookup):
                    importPreview(lookup)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .frame(maxWidth: 680, maxHeight: .infinity, alignment: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(navigationTitle)
                        .appDynamicFont(size: 18, weight: .semibold, design: .rounded)
                        .foregroundStyle(NeumorphicColors.text)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .topBarLeading) {
                    if canGoBack {
                        Button {
                            dismiss()
                            store.showMenu()
                            onReturnToActionMenu()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel(L10n.tr("Back", zhHans: "返回", zhHant: "返回", ja: "戻る"))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.tr("Close", zhHans: "关闭", zhHant: "關閉", ja: "閉じる"))
                }
            }
        }
        .presentationDetents(usesReflowedLayout ? [.large] : presentationDetents)
        .presentationContentInteraction(.scrolls)
        .alert(
            L10n.tr("Replace current board?", zhHans: "替换当前棋盘？", zhHant: "替換目前棋盤？"),
            isPresented: $isReplacementConfirmationPresented
        ) {
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.tr("Replace", zhHans: "替换", zhHant: "替換"), role: .destructive) {
                guard case let .importPreview(lookup) = store.page else { return }
                importBoard(lookup.payload, action: .replaceCurrentBoard)
            }
        } message: {
            Text(
                L10n.tr(
                    "Your current board's tasks will be archived and replaced. Your points and redeemed rewards will not change.",
                    zhHans: "当前棋盘的任务会归档并被替换；已有积分和已兑换奖励不会变化。",
                    zhHant: "目前棋盤的任務會歸檔並被替換；已有積分和已兌換獎勵不會變化。"
                )
            )
        }
    }

    private var navigationTitle: String {
        switch store.page {
        case .menu:
            return L10n.tr("Share Boards", zhHans: "棋盘分享", zhHant: "棋盤分享")
        case .selectBoard:
            return L10n.tr("Choose a board", zhHans: "选择棋盘", zhHant: "選擇棋盤")
        case .shareResult:
            return L10n.tr("Share code", zhHans: "分享码", zhHant: "分享碼")
        case .importCode:
            return L10n.tr("Import board", zhHans: "导入棋盘", zhHant: "匯入棋盤")
        case .importPreview:
            return L10n.tr("Preview board", zhHans: "预览棋盘", zhHant: "預覽棋盤")
        }
    }

    private var canGoBack: Bool {
        switch store.page {
        case .menu:
            return false
        case .selectBoard, .shareResult, .importCode, .importPreview:
            return true
        }
    }

    /// Compact pages fit their contents instead of inheriting a tall, empty
    /// sheet. The preview reserves room for a genuinely square grid.
    private var presentationDetents: Set<PresentationDetent> {
        switch store.page {
        case .menu:
            return [.height(260)]
        case .selectBoard:
            return [.fraction(0.58)]
        case .shareResult:
            return [.height(360)]
        case .importCode:
            return [.height(360)]
        case .importPreview:
            return [.fraction(0.78)]
        }
    }

    @ViewBuilder
    private func adaptivePageContent<Content: View>(_ content: Content) -> some View {
        if usesReflowedLayout {
            ScrollView(showsIndicators: false) {
                content
                    .padding(.bottom, 28)
            }
        } else {
            content
        }
    }

    private var menu: some View {
        VStack(spacing: 14) {
            menuButton(
                title: L10n.tr("Share board", zhHans: "分享棋盘", zhHant: "分享棋盤"),
                systemImage: "square.and.arrow.up"
            ) {
                store.showShareBoardPicker()
            }

            menuButton(
                title: L10n.tr("Import board", zhHans: "导入棋盘", zhHant: "匯入棋盤"),
                systemImage: "square.and.arrow.down"
            ) {
                store.showImportCodeEntry()
            }
        }
    }

    private var boardPicker: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if let errorMessage = store.errorMessage {
                    errorText(errorMessage)
                        .padding(.bottom, 4)
                }

                ForEach(boards) { board in
                    Button {
                        store.publish(board)
                    } label: {
                        Text(board.name)
                            .appDynamicFont(size: 17, weight: .medium, design: .rounded)
                            .foregroundStyle(NeumorphicColors.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(minHeight: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(BoardSharePayload.isShareable(board.board) ? 0.92 : 0.46))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!BoardSharePayload.isShareable(board.board) || store.isWorking)
                }
            }
            .padding(.bottom, 24)
        }
        .overlay(alignment: .bottom) {
            workingIndicator
        }
    }

    private func shareResult(_ result: BoardSharePublishResult) -> some View {
        VStack(spacing: 20) {
            Text(result.payload.boardName)
                .appDynamicFont(size: 18, weight: .semibold, design: .rounded)
                .foregroundStyle(NeumorphicColors.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(BoardShareCode.display(result.code))
                .font(.system(size: publishedCodeFontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(NeumorphicColors.text)
                .tracking(1.5)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                L10n.tr(
                    "Valid for 30 days",
                    zhHans: "有效期 30 天",
                    zhHant: "有效期 30 天"
                )
            )
            .appDynamicFont(size: 14, weight: .regular, design: .rounded)
            .foregroundStyle(NeumorphicColors.text.opacity(0.62))

            Group {
                if usesReflowedLayout {
                    VStack(spacing: 12) {
                        copyCodeButton(for: result)
                        systemShareButton(for: result)
                    }
                } else {
                    HStack(spacing: 12) {
                        copyCodeButton(for: result)
                        systemShareButton(for: result)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func copyCodeButton(for result: BoardSharePublishResult) -> some View {
        Button {
            UIPasteboard.general.string = result.code
            AnalyticsService.logBoardShareCodeCopied(payload: result.payload)
            onCopyCode()
        } label: {
            Label(L10n.tr("Copy", zhHans: "复制", zhHant: "複製"), systemImage: "doc.on.doc")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(BoardShareFilledButtonStyle())
    }

    private func systemShareButton(for result: BoardSharePublishResult) -> some View {
        ShareLink(
            item: shareText(for: result),
            subject: Text(L10n.tr("Bingodays board", zhHans: "Bingodays 棋盘", zhHant: "Bingodays 棋盤"))
        ) {
            Label(L10n.tr("Share", zhHans: "系统分享", zhHant: "系統分享"), systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(BoardShareFilledButtonStyle())
        .simultaneousGesture(TapGesture().onEnded {
            AnalyticsService.logBoardShareSystemShareTapped(payload: result.payload)
        })
    }

    private var importCode: some View {
        VStack(spacing: 18) {
            Text(
                L10n.tr(
                    "Enter the 10-digit share code.",
                    zhHans: "输入 10 位数字分享码",
                    zhHant: "輸入 10 位數字分享碼"
                )
            )
            .appDynamicFont(size: 16, weight: .regular, design: .rounded)
            .foregroundStyle(NeumorphicColors.text.opacity(0.75))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            TextField("000 000 000 0", text: $store.codeDraft)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(size: shareCodeFontSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(NeumorphicColors.text)
                .tint(NeumorphicColors.text)
                .accessibilityLabel(L10n.tr(
                    "10-digit share code",
                    zhHans: "10位数字分享码",
                    zhHant: "10位數字分享碼",
                    ja: "10桁の共有コード"
                ))
                .accessibilityHint(L10n.tr(
                    "Enter the code shared with you",
                    zhHans: "输入对方分享给你的代码",
                    zhHant: "輸入對方分享給你的代碼",
                    ja: "共有されたコードを入力します"
                ))
                .focused($isShareCodeInputFocused)
                .multilineTextAlignment(.center)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.92))
                )
                .onChange(of: store.codeDraft) { _, _ in
                    store.normalizeCodeDraft()
                }

            if let errorMessage = store.errorMessage {
                errorText(errorMessage)
            }

            Button {
                isShareCodeInputFocused = false
                store.lookupCode()
            } label: {
                if store.isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text(L10n.tr("Find board", zhHans: "查找棋盘", zhHant: "查找棋盤"))
                }
            }
            .buttonStyle(BoardShareFilledButtonStyle())
            .disabled(store.isWorking)
        }
    }

    private func importPreview(_ lookup: BoardShareLookup) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(lookup.payload.boardName)
                    .appDynamicFont(size: 20, weight: .bold, design: .rounded)
                    .foregroundStyle(NeumorphicColors.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                BoardSharePreviewGrid(payload: lookup.payload)

                importActions(for: lookup)
            }
            .padding(.bottom, 26)
        }
    }

    @ViewBuilder
    private func importActions(for lookup: BoardShareLookup) -> some View {
        if hasPremiumAccess {
            Button {
                importBoard(lookup.payload, action: .createNewBoard)
            } label: {
                Text(L10n.tr("Import board", zhHans: "导入棋盘", zhHant: "匯入棋盤"))
            }
            .buttonStyle(BoardShareFilledButtonStyle())
        } else if lookup.payload.gridSize == 5 {
            premiumGatedImportButton(for: lookup)
        } else {
            Group {
                if usesReflowedLayout {
                    VStack(spacing: 12) {
                        premiumImportAsNewBoardButton(for: lookup)
                        replaceCurrentBoardButton()
                    }
                } else {
                    HStack(spacing: 12) {
                        premiumImportAsNewBoardButton(for: lookup)
                        replaceCurrentBoardButton()
                    }
                }
            }
        }
    }

    private func premiumImportAsNewBoardButton(for lookup: BoardShareLookup) -> some View {
        Button {
            store.savePendingPremiumImport(lookup)
            onUpgradeRequested(lookup)
        } label: {
            Text(L10n.tr("Import as new board", zhHans: "导入为新棋盘", zhHant: "匯入為新棋盤"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(BoardShareFilledButtonStyle())
    }

    private func premiumGatedImportButton(for lookup: BoardShareLookup) -> some View {
        Button {
            store.savePendingPremiumImport(lookup)
            onUpgradeRequested(lookup)
        } label: {
            Text(L10n.tr("Import board", zhHans: "导入棋盘", zhHant: "匯入棋盤"))
        }
        .buttonStyle(BoardShareFilledButtonStyle())
    }

    private func replaceCurrentBoardButton() -> some View {
        Button {
            isReplacementConfirmationPresented = true
        } label: {
            Text(L10n.tr("Replace current board", zhHans: "替换当前棋盘", zhHant: "替換目前棋盤"))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(BoardShareFilledButtonStyle())
    }

    private func importBoard(_ payload: BoardSharePayload, action: BoardShareImportAction) {
        guard onImport(payload, action) else { return }
        store.clearPendingPremiumImport()
        dismiss()
    }

    private var workingIndicator: some View {
        Group {
            if store.isWorking {
                ProgressView()
                    .padding(12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityLabel(L10n.tr("Loading", zhHans: "正在加载", zhHant: "正在載入", ja: "読み込み中"))
            }
        }
    }

    private func errorText(_ text: String) -> some View {
        Text(text)
            .appDynamicFont(size: 13, weight: .regular, design: .rounded)
            .foregroundStyle(.red.opacity(0.85))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func menuButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .appDynamicFont(size: 17, weight: .semibold, design: .rounded)
                .frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(BoardShareFilledButtonStyle())
    }

    private func shareText(for result: BoardSharePublishResult) -> String {
        L10n.tr(
            "I shared a Bingodays board: \(result.payload.boardName)\nShare code: \(result.code)",
            zhHans: "我分享了一个 Bingodays 棋盘：\(result.payload.boardName)\n分享码：\(result.code)",
            zhHant: "我分享了一個 Bingodays 棋盤：\(result.payload.boardName)\n分享碼：\(result.code)"
        )
    }
}

private struct BoardSharePreviewGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let payload: BoardSharePayload

    private var usesReflowedLayout: Bool {
        dynamicTypeSize == .xLarge ||
            dynamicTypeSize == .xxLarge ||
            dynamicTypeSize == .xxxLarge ||
            dynamicTypeSize.isAccessibilitySize
    }

    private var cellsByCoordinate: [String: String] {
        Dictionary(
            payload.cells.map { ("\($0.row):\($0.column)", $0.text) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: payload.gridSize)
        LazyVGrid(columns: columns, spacing: 5) {
            ForEach(0..<(payload.gridSize * payload.gridSize), id: \.self) { index in
                let row = index / payload.gridSize
                let column = index % payload.gridSize
                let text = cellsByCoordinate["\(row):\(column)"] ?? ""
                Group {
                    if usesReflowedLayout {
                        previewCell(text, dynamicType: true)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        previewCell(text, dynamicType: false)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .frame(maxWidth: 440)
    }

    private func previewCell(_ text: String, dynamicType: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.86))

            if !text.isEmpty {
                Group {
                    if dynamicType {
                        Text(text)
                            .appDynamicFont(
                                size: payload.gridSize == 5 ? 10 : 12,
                                weight: .medium,
                                design: .rounded
                            )
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(text)
                            .font(.appSystem(
                                size: payload.gridSize == 5 ? 10 : 12,
                                weight: .medium,
                                design: .rounded
                            ))
                            .lineLimit(3)
                            .minimumScaleFactor(0.65)
                    }
                }
                .foregroundStyle(NeumorphicColors.text)
                .multilineTextAlignment(.center)
                .padding(5)
            }
        }
    }
}

/// Uses the same bottom action treatment as the board-name long-press menu.
/// The entry point is intentionally not a tall navigation sheet.
struct BoardShareActionOverlayView: View {
    let contentWidth: CGFloat
    let bottomInset: CGFloat
    let isPadLayout: Bool
    let onDismiss: () -> Void
    let onShareBoard: () -> Void
    let onImportBoard: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var backgroundColor: Color { Color(hex: "FAF9F3") }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                actionButton(
                    title: L10n.tr("Share board", zhHans: "分享棋盘", zhHant: "分享棋盤"),
                    action: onShareBoard
                )
                actionButton(
                    title: L10n.tr("Import board", zhHans: "导入棋盘", zhHant: "匯入棋盤"),
                    action: onImportBoard
                )
            }
            .frame(width: min(contentWidth, isPadLayout ? 460 : 353))
            .padding(.top, 14)
            .padding(.bottom, max(bottomInset, 14) + 12)
            .frame(maxWidth: .infinity)
            .background(
                backgroundColor
                    .ignoresSafeArea(edges: .bottom)
                    .onTapGesture(perform: onDismiss)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onDismiss)
    }

    private func actionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .appDynamicFont(size: isPadLayout ? 18 : 16, weight: .semibold, design: .rounded)
                .foregroundStyle(NeumorphicColors.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .frame(minHeight: isPadLayout ? 60 : 56)
                .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 10 : 0)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(backgroundColor)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct BoardShareFilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appDynamicFont(size: 16, weight: .semibold, design: .rounded)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(NeumorphicColors.modalAccent.opacity(configuration.isPressed ? 0.75 : 1))
            )
    }
}

private struct BoardShareOutlinedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appDynamicFont(size: 16, weight: .semibold, design: .rounded)
            .foregroundStyle(NeumorphicColors.text)
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(NeumorphicColors.text.opacity(configuration.isPressed ? 0.22 : 0.38), lineWidth: 1)
            )
    }
}
