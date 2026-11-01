import SwiftUI

struct NativeICloudSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var coordinator: NativeICloudSyncCoordinator

    let isPadLayout: Bool
    let themeColor: Color

    @State private var requestedEnabled = NativeICloudPreferences.isEnabled
    @State private var isChangingSetting = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: scaled(18, pad: 22)) {
                    deviceCloudCard
                    syncControlCard
                }
                .frame(maxWidth: isPadLayout ? 560 : .infinity)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, scaled(18, pad: 26))
                .padding(.top, scaled(18, pad: 24))
                .padding(.bottom, scaled(28, pad: 36))
            }
            .background(NeumorphicColors.background.ignoresSafeArea())
            .navigationTitle(L10n.tr("iCloud Sync", zhHans: "iCloud 同步", zhHant: "iCloud 同步", ja: "iCloud同期"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.tr("Done", zhHans: "完成", zhHant: "完成", ja: "完了")) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            requestedEnabled = NativeICloudPreferences.isEnabled
        }
        .onChange(of: coordinator.state) { _, _ in
            requestedEnabled = NativeICloudPreferences.isEnabled
        }
        .alert(
            L10n.tr(
                "iCloud account changed",
                zhHans: "iCloud 账号已切换",
                zhHant: "iCloud 帳號已切換",
                ja: "iCloudアカウントが変更されました"
            ),
            isPresented: accountChangeAlertPresented
        ) {
            if let change = coordinator.pendingAccountChange {
                if change.remoteDataAvailability == .present {
                    Button(L10n.tr(
                        "Use this iCloud data",
                        zhHans: "使用当前 iCloud 数据",
                        zhHant: "使用目前 iCloud 資料",
                        ja: "このiCloudデータを使う"
                    )) {
                        Task {
                            await coordinator.resolveAccountChange(.useCurrentAccountCloud)
                        }
                    }
                }

                if change.remoteDataAvailability == .empty && change.localHasMeaningfulData {
                    Button(L10n.tr(
                        "Copy this device to iCloud",
                        zhHans: "将本机数据复制到 iCloud",
                        zhHant: "將本機資料複製到 iCloud",
                        ja: "この端末のデータをiCloudへコピー"
                    )) {
                        Task {
                            await coordinator.resolveAccountChange(.copyLocalDataToEmptyCurrentAccount)
                        }
                    }
                }
            }

            Button(L10n.tr("Not now", zhHans: "暂不处理", zhHant: "暫不處理", ja: "今はしない"), role: .cancel) {
                Task {
                    await coordinator.resolveAccountChange(.keepLocalOnly)
                }
            }
        } message: {
            Text(accountChangeMessage)
        }
    }

    private var deviceCloudCard: some View {
        VStack(spacing: scaled(16, pad: 20)) {
            ZStack {
                Capsule()
                    .fill(themeColor.opacity(0.18))
                    .frame(width: scaled(210, pad: 245), height: scaled(66, pad: 76))

                HStack(spacing: scaled(24, pad: 30)) {
                    deviceIcon("iphone")

                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.94))
                        Image(systemName: cloudSymbol)
                            .font(.appSystem(size: scaled(28, pad: 32), weight: .semibold))
                            .foregroundStyle(statusColor)
                    }
                    .frame(width: scaled(58, pad: 66), height: scaled(58, pad: 66))
                    .shadow(color: statusColor.opacity(0.18), radius: 12, x: 0, y: 6)

                    deviceIcon("ipad")
                }
            }

            VStack(spacing: 6) {
                Text(statusTitle)
                    .appDynamicFont(size: scaled(19, pad: 22), weight: .bold, design: .rounded)
                    .foregroundStyle(NeumorphicColors.text)
                    .multilineTextAlignment(.center)

                Text(statusDetail)
                    .appDynamicFont(size: scaled(13, pad: 15), weight: .medium, design: .rounded)
                    .foregroundStyle(NeumorphicColors.text.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, scaled(18, pad: 24))
        .padding(.vertical, scaled(24, pad: 30))
        .background(cardBackground(accent: statusColor))
    }

    private var syncControlCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: enabledBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("Sync with iCloud", zhHans: "使用 iCloud 同步", zhHant: "使用 iCloud 同步", ja: "iCloudで同期"))
                        .appDynamicFont(size: scaled(15, pad: 17), weight: .bold, design: .rounded)
                        .foregroundStyle(NeumorphicColors.text)
                    Text(L10n.tr(
                        "Your local data stays on this device when sync is off.",
                        zhHans: "关闭后，本地数据仍保留在这台设备上。",
                        zhHant: "關閉後，本機資料仍保留在這台裝置上。",
                        ja: "オフにしても、この端末のデータは残ります。"
                    ))
                    .appDynamicFont(size: scaled(11.5, pad: 13), weight: .medium, design: .rounded)
                    .foregroundStyle(NeumorphicColors.text.opacity(0.54))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(themeColor)
            .disabled(isChangingSetting)

            if requestedEnabled {
                Divider()
                    .padding(.vertical, scaled(14, pad: 17))

                Button {
                    Task {
                        await coordinator.syncNow()
                    }
                } label: {
                    HStack {
                        Label(
                            L10n.tr("Sync now", zhHans: "立即同步", zhHant: "立即同步", ja: "今すぐ同期"),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        Spacer()
                        if isBusy {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                        }
                    }
                    .appDynamicFont(size: scaled(14, pad: 16), weight: .semibold, design: .rounded)
                    .foregroundStyle(themeColor)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        }
        .padding(scaled(18, pad: 22))
        .background(cardBackground(accent: themeColor.opacity(0.55)))
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { requestedEnabled },
            set: { newValue in
                requestedEnabled = newValue
                isChangingSetting = true
                Task {
                    await coordinator.setEnabled(newValue)
                    await MainActor.run {
                        requestedEnabled = NativeICloudPreferences.isEnabled
                        isChangingSetting = false
                    }
                }
            }
        )
    }

    private var isBusy: Bool {
        if isChangingSetting { return true }
        switch coordinator.state {
        case .preparing, .syncing:
            return true
        default:
            return false
        }
    }

    private var accountChangeAlertPresented: Binding<Bool> {
        Binding(
            get: { coordinator.pendingAccountChange != nil },
            // The explicit actions above own dismissal. Ignoring a system-driven
            // false value prevents a tap outside the alert from accidentally
            // choosing a data source.
            set: { _ in }
        )
    }

    private var accountChangeMessage: String {
        guard let change = coordinator.pendingAccountChange else { return "" }
        switch change.remoteDataAvailability {
        case .present:
            return L10n.tr(
                "This device still has data from the previous iCloud account. Choose the current account's data to replace this device, or keep sync off. Data is never merged automatically across accounts.",
                zhHans: "这台设备仍保留上一个 iCloud 账号的数据。你可以使用当前账号的数据替换本机，或保持同步关闭。不同账号的数据绝不会自动合并。",
                zhHant: "這台裝置仍保留上一個 iCloud 帳號的資料。你可以使用目前帳號的資料取代本機，或保持同步關閉。不同帳號的資料絕不會自動合併。",
                ja: "この端末には前のiCloudアカウントのデータが残っています。現在のアカウントのデータで置き換えるか、同期をオフのままにしてください。アカウント間でデータが自動結合されることはありません。"
            )
        case .empty:
            return L10n.tr(
                "The current iCloud account has no Bingodays data. You may explicitly copy this device's data to it, or keep sync off. This never changes the previous account's cloud data.",
                zhHans: "当前 iCloud 账号没有 Bingodays 数据。你可以明确选择将本机数据复制到该账号，或保持同步关闭。这不会改动上一个账号的云端数据。",
                zhHant: "目前 iCloud 帳號沒有 Bingodays 資料。你可以明確選擇將本機資料複製到該帳號，或保持同步關閉。這不會更動上一個帳號的雲端資料。",
                ja: "現在のiCloudアカウントにはBingodaysデータがありません。この端末のデータを明示的にコピーするか、同期をオフのままにしてください。以前のアカウントのクラウドデータは変更されません。"
            )
        case .unknown:
            return L10n.tr(
                "Bingodays could not confirm the current iCloud account's data yet. Sync stays off until you try again, so neither account can be overwritten.",
                zhHans: "暂时无法确认当前 iCloud 账号的数据。同步会保持关闭，直到你稍后重试，因此不会覆盖任一账号的数据。",
                zhHant: "暫時無法確認目前 iCloud 帳號的資料。同步會保持關閉，直到你稍後重試，因此不會覆蓋任一帳號的資料。",
                ja: "現在のiCloudアカウントのデータをまだ確認できません。後でもう一度試すまで同期はオフのままなので、どちらのアカウントのデータも上書きされません。"
            )
        }
    }

    private var cloudSymbol: String {
        switch coordinator.state {
        case .ready:
            return "checkmark.icloud.fill"
        case .waitingForCloud:
            return "icloud.and.arrow.down.fill"
        case .accountChangeRequiresDecision:
            return "person.crop.circle.badge.exclamationmark"
        case .failed, .unavailable:
            return "exclamationmark.icloud.fill"
        default:
            return "icloud.fill"
        }
    }

    private var statusColor: Color {
        switch coordinator.state {
        case .ready:
            return themeColor
        case .waitingForCloud:
            return themeColor
        case .accountChangeRequiresDecision:
            return themeColor
        case .failed, .unavailable:
            return Color(hex: "D26A5C")
        default:
            return themeColor
        }
    }

    private var statusTitle: String {
        switch coordinator.state {
        case .disabled:
            return L10n.tr("Your cloud is waiting", zhHans: "你的云端还在等待", zhHant: "你的雲端還在等待", ja: "クラウドは待機中")
        case .preparing:
            return L10n.tr("Connecting to iCloud…", zhHans: "正在连接 iCloud…", zhHant: "正在連接 iCloud…", ja: "iCloudに接続中…")
        case .syncing:
            return L10n.tr("Keeping everything in step…", zhHans: "正在让设备保持一致…", zhHant: "正在讓裝置保持一致…", ja: "データをそろえています…")
        case .waitingForCloud:
            return L10n.tr("Waiting for iCloud…", zhHans: "正在等待 iCloud…", zhHant: "正在等待 iCloud…", ja: "iCloudを待機中…")
        case .ready:
            return L10n.tr("Your devices are connected", zhHans: "你的设备已连接", zhHant: "你的裝置已連接", ja: "デバイスが接続されました")
        case .accountChangeRequiresDecision:
            return L10n.tr("Choose data for this iCloud account", zhHans: "请选择当前 iCloud 账号的数据", zhHant: "請選擇目前 iCloud 帳號的資料", ja: "このiCloudアカウントのデータを選択")
        case .unavailable:
            return L10n.tr("iCloud is unavailable", zhHans: "iCloud 暂不可用", zhHant: "iCloud 暫不可用", ja: "iCloudを利用できません")
        case .failed:
            return L10n.tr("Sync needs attention", zhHans: "同步需要检查", zhHant: "同步需要檢查", ja: "同期を確認してください")
        }
    }

    private var statusDetail: String {
        switch coordinator.state {
        case .disabled:
            return L10n.tr("Turn on sync when you want this device to join.", zhHans: "准备好后开启同步，让这台设备加入。", zhHant: "準備好後開啟同步，讓這台裝置加入。", ja: "同期をオンにすると、この端末が参加します。")
        case .preparing, .syncing:
            return L10n.tr("This can take a moment the first time.", zhHans: "首次同步可能需要一点时间。", zhHant: "首次同步可能需要一點時間。", ja: "初回は少し時間がかかることがあります。")
        case .waitingForCloud(let lastCheckedAt):
            let time = lastCheckedAt.formatted(.dateTime.hour().minute().locale(AppLanguage.displayLocale))
            return L10n.tr(
                "Checked at \(time). iOS has not delivered a new iCloud update yet; automatic sync will keep trying.",
                zhHans: "已于 \(time) 检查，本机尚未收到新的 iCloud 数据；系统会继续自动同步。",
                zhHant: "已於 \(time) 檢查，本機尚未收到新的 iCloud 資料；系統會繼續自動同步。",
                ja: "\(time) に確認しました。新しいiCloudデータはまだ届いていません。自動同期を継続します。"
            )
        case .ready(let lastSyncAt):
            guard let lastSyncAt else {
                return L10n.tr("Automatic sync is on.", zhHans: "自动同步已开启。", zhHant: "自動同步已開啟。", ja: "自動同期がオンです。")
            }
            return L10n.tr(
                "Last checked \(lastSyncAt.formatted(.dateTime.hour().minute().locale(AppLanguage.displayLocale)))",
                zhHans: "最近检查：\(lastSyncAt.formatted(.dateTime.hour().minute().locale(AppLanguage.displayLocale)))",
                zhHant: "最近檢查：\(lastSyncAt.formatted(.dateTime.hour().minute().locale(AppLanguage.displayLocale)))",
                ja: "最終確認：\(lastSyncAt.formatted(.dateTime.hour().minute().locale(AppLanguage.displayLocale)))"
            )
        case .accountChangeRequiresDecision:
            return L10n.tr(
                "Sync is paused to keep two iCloud accounts separate.",
                zhHans: "同步已暂停，避免两个 iCloud 账号的数据混在一起。",
                zhHant: "同步已暫停，避免兩個 iCloud 帳號的資料混在一起。",
                ja: "2つのiCloudアカウントのデータを分けるため、同期は一時停止しています。"
            )
        case .unavailable(let message), .failed(let message):
            return message
        }
    }

    private func deviceIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.appSystem(size: scaled(23, pad: 27), weight: .semibold))
            .foregroundStyle(themeColor.opacity(0.76))
            .frame(width: scaled(34, pad: 40), height: scaled(44, pad: 50))
    }

    private func cardBackground(accent: Color) -> some View {
        RoundedRectangle(cornerRadius: scaled(22, pad: 26), style: .continuous)
            .fill(Color.white.opacity(0.88))
            .overlay {
                RoundedRectangle(cornerRadius: scaled(22, pad: 26), style: .continuous)
                    .stroke(accent.opacity(0.38), lineWidth: 1)
            }
            .shadow(color: NeumorphicColors.darkShadow.opacity(0.1), radius: 12, x: 0, y: 7)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}
