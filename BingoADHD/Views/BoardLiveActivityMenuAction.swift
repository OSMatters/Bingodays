import SwiftUI

/// The only App UI for this feature: an action in the existing board menu.
struct BoardLiveActivityMenuAction: View {
    let boardID: UUID
    let isPadLayout: Bool
    let onDismiss: () -> Void
    @AppStorage("lockScreenDiscovery.showTapCount") private var discoveryTapCount = 0
    @State private var showInstructions = false
    @State private var isWorking = false
    @State private var failure: String?

    var body: some View {
        Button {
            let isStarting = !BingoBoardLiveActivityController.isDisplaying(boardID)
            discoveryTapCount = min(discoveryTapCount + 1, 2)
            isWorking = true
            Task {
                do {
                    try await BingoBoardLiveActivityController.toggle(boardID: boardID)
                    if isStarting {
                        showInstructions = true
                    } else {
                        onDismiss()
                    }
                } catch {
                    failure = error.localizedDescription
                }
                isWorking = false
            }
        } label: {
            Text(BingoBoardLiveActivityController.isDisplaying(boardID)
                ? L10n.tr("Hide from\nLock Screen", zhHans: "停止锁屏展示", zhHant: "停止鎖屏展示", ja: "表示を終了")
                : L10n.tr("Show on\nLock Screen", zhHans: "显示在锁屏", zhHant: "顯示在鎖屏", ja: "ロック画面へ"))
                .foregroundStyle(NeumorphicColors.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .frame(minHeight: isPadLayout ? 42 : 40)
                .padding(.horizontal, isPadLayout ? 14 : 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if discoveryTapCount < 2 {
                FeatureNewBadge()
                    .padding(.trailing, 5)
                    .padding(.top, 2)
            }
        }
        .zIndex(1)
        .disabled(isWorking)
        .alert(L10n.tr("Board Ready", zhHans: "棋盘已开启", zhHant: "棋盤已開啟", ja: "表示の準備ができました"), isPresented: $showInstructions) {
            Button(L10n.tr("OK", zhHans: "好", zhHant: "好", ja: "OK")) { onDismiss() }
        } message: {
            Text(L10n.tr("Lock your iPhone, then wake the screen to see your board on the Lock Screen.", zhHans: "现在按下锁屏键，再点亮屏幕，就可以在锁屏页面看到棋盘了。", zhHant: "現在按下鎖屏鍵，再喚醒螢幕，就可以在鎖屏頁面看到棋盤了。", ja: "端末をロックしてから画面を点灯すると、ロック画面にボードが表示されます。"))
        }
        .alert(L10n.tr("Lock Screen Display", zhHans: "锁屏展示", zhHant: "鎖屏展示", ja: "ロック画面の表示"), isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } }
        )) {
            Button(L10n.tr("OK", zhHans: "好", zhHant: "好", ja: "OK"), role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }
}
