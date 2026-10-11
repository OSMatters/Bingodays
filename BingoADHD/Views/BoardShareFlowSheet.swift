import SwiftUI
import UIKit

enum BoardShareImportAction: String, Equatable {
    case createNewBoard = "create_new_board"
    case replaceCurrentBoard = "replace_current_board"
}

struct BoardShareFlowSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: BoardSharePresentationStore

    let boards: [BingoBoardStore.NamedBoard]
    let hasPremiumAccess: Bool
    let onImport: (BoardSharePayload, BoardShareImportAction) -> Bool
    let onUpgradeRequested: (BoardShareLookup) -> Void
    let onCopyCode: () -> Void
    let onReturnToActionMenu: () -> Void

    @State private var isReplacementConfirmationPresented = false
    @FocusState private var isShareCodeInputFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                switch store.page {
                case .menu:
                    menu
                case .selectBoard:
                    boardPicker
                case .shareResult(let result):
                    shareResult(result)
                case .importCode:
                    importCode
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
                        .font(.appSystem(size: 18, weight: .semibold, design: .rounded))
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
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .presentationDetents(presentationDetents)
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
                            .font(.appSystem(size: 17, weight: .medium, design: .rounded))
                            .foregroundColor(NeumorphicColors.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .frame(height: 54)
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
                .font(.appSystem(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)
                .lineLimit(1)

            Text(BoardShareCode.display(result.code))
                .font(.system(size: 31, weight: .bold, design: .monospaced))
                .foregroundColor(NeumorphicColors.text)
                .tracking(1.5)
                .multilineTextAlignment(.center)

            Text(
                L10n.tr(
                    "Valid for 30 days",
                    zhHans: "有效期 30 天",
                    zhHant: "有效期 30 天"
                )
            )
            .font(.appSystem(size: 14, weight: .regular, design: .rounded))
            .foregroundColor(NeumorphicColors.text.opacity(0.62))

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = result.code
                    AnalyticsService.logBoardShareCodeCopied(payload: result.payload)
                    onCopyCode()
                } label: {
                    Label(L10n.tr("Copy", zhHans: "复制", zhHant: "複製"), systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BoardShareFilledButtonStyle())

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
        }
        .frame(maxWidth: .infinity)
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
            .font(.appSystem(size: 16, weight: .regular, design: .rounded))
            .foregroundColor(NeumorphicColors.text.opacity(0.75))

            TextField("000 000 000 0", text: $store.codeDraft)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .foregroundColor(NeumorphicColors.text)
                .tint(NeumorphicColors.text)
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
                    .font(.appSystem(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)

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
            HStack(spacing: 12) {
                premiumImportAsNewBoardButton(for: lookup)

                Button {
                    isReplacementConfirmationPresented = true
                } label: {
                    Text(L10n.tr("Replace current board", zhHans: "替换当前棋盘", zhHant: "替換目前棋盤"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BoardShareFilledButtonStyle())
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
            }
        }
    }

    private func errorText(_ text: String) -> some View {
        Text(text)
            .font(.appSystem(size: 13, weight: .regular, design: .rounded))
            .foregroundColor(.red.opacity(0.85))
            .multilineTextAlignment(.center)
    }

    private func menuButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.appSystem(size: 17, weight: .semibold, design: .rounded))
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
    let payload: BoardSharePayload

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
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.86))

                    Text(cellsByCoordinate["\(row):\(column)"] ?? "")
                        .font(.appSystem(size: payload.gridSize == 5 ? 10 : 12, weight: .medium, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.65)
                        .padding(5)
                }
                .aspectRatio(1, contentMode: .fit)
            }
        }
        .frame(maxWidth: 440)
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

    private var backgroundColor: Color { Color(hex: "FAF9F3") }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

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
    }

    private func actionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appSystem(size: isPadLayout ? 18 : 16, weight: .semibold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)
                .frame(maxWidth: .infinity)
                .frame(height: isPadLayout ? 60 : 56)
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
            .font(.appSystem(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
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
            .font(.appSystem(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(NeumorphicColors.text)
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(NeumorphicColors.text.opacity(configuration.isPressed ? 0.22 : 0.38), lineWidth: 1)
            )
    }
}
