import SwiftUI

/// The only App UI for this feature: an action in the existing board menu.
struct BoardLiveActivityMenuAction: View {
    let boardID: UUID
    let isPadLayout: Bool
    let onDismiss: () -> Void
    @State private var isWorking = false
    @State private var failure: String?

    var body: some View {
        Button {
            isWorking = true
            Task {
                do {
                    try await BingoBoardLiveActivityController.toggle(boardID: boardID)
                    onDismiss()
                } catch {
                    failure = error.localizedDescription
                }
                isWorking = false
            }
        } label: {
            Text(BingoBoardLiveActivityController.isDisplaying(boardID)
                ? L10n.tr("Stop Lock Screen Display", zhHans: "停止锁屏展示", zhHant: "停止鎖屏展示", ja: "ロック画面の表示を停止")
                : L10n.tr("Show on Lock Screen", zhHans: "显示在锁屏", zhHant: "顯示在鎖屏", ja: "ロック画面に表示"))
                .font(.appSystem(size: isPadLayout ? 18 : 16, weight: .regular, design: .rounded))
                .foregroundStyle(NeumorphicColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, isPadLayout ? 14 : 12)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .alert(L10n.tr("Lock Screen Display", zhHans: "锁屏展示", zhHant: "鎖屏展示", ja: "ロック画面の表示"), isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } }
        )) {
            Button(L10n.tr("OK", zhHans: "好", zhHant: "好", ja: "OK"), role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }
}
