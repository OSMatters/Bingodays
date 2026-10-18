import SwiftUI
import UIKit

struct AppIconSettingsSection: View {
    let isPadLayout: Bool
    let themeColor: Color
    let hasPremiumAccess: Bool
    let onOpenPremium: () -> Void

    @EnvironmentObject private var iconManager: AppIconManager
    @State private var iconErrorMessage: String?
    @StateObject private var streakStore = AppOpenStreakStore.shared
    @State private var lockedOption: AppIconOption?
    @State private var opensPremiumAfterDismiss = false

    var body: some View {
        VStack(alignment: .leading, spacing: scaled(10, pad: 12)) {
            Text(L10n.tr("App Icon", zhHans: "应用图标", zhHant: "應用程式圖標", ja: "アプリアイコン"))
                .font(.appSystem(size: scaled(15, pad: 17), weight: .bold, design: .rounded))
                .foregroundStyle(AppIconPalette.mutedText)
                .padding(.horizontal, scaled(4, pad: 6))

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: scaled(10, pad: 14)),
                    count: 3
                ),
                spacing: scaled(14, pad: 18)
            ) {
                ForEach(AppIconOption.allCases) { option in
                    iconButton(for: option)
                }
            }
            .padding(scaled(16, pad: 20))
            .background(
                RoundedRectangle(cornerRadius: scaled(18, pad: 22), style: .continuous)
                    .fill(Color.white.opacity(0.88))
            )

#if DEBUG
            debugStreakControls
#endif
        }
        .onAppear { iconManager.refresh() }
        .alert(
            L10n.tr("Couldn’t change app icon", zhHans: "无法更换应用图标", zhHant: "無法更換應用程式圖標", ja: "アプリアイコンを変更できません"),
            isPresented: Binding(
                get: { iconErrorMessage != nil },
                set: { if !$0 { iconErrorMessage = nil } }
            )
        ) {
            Button(L10n.ok, role: .cancel) { iconErrorMessage = nil }
        } message: {
            Text(iconErrorMessage ?? "")
        }
        .sheet(item: $lockedOption, onDismiss: {
            if opensPremiumAfterDismiss {
                opensPremiumAfterDismiss = false
                onOpenPremium()
            }
        }) { option in
            AppIconUnlockSheet(
                option: option,
                currentStreak: streakStore.currentStreak,
                themeColor: themeColor,
                onOpenPremium: { opensPremiumAfterDismiss = true }
            )
        }
    }

#if DEBUG
    private var debugStreakControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("DEBUG · 圖標解鎖測試", systemImage: "ladybug.fill")
                .font(.system(size: 14, weight: .bold))
            Text("選擇天數後返回首頁查看提醒。10／20／30 天只觸發對應獎勵；12 天查看剩餘進度。")
                .font(.system(size: 12))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                ForEach([1, 9, 10, 12, 20, 30], id: \.self) { day in
                    Button("第 \(day) 天") { streakStore.debugSimulate(days: day) }
                        .buttonStyle(.bordered)
                }
            }
            Button("模擬中斷：第 1 天，保留全部獎勵") {
                streakStore.debugSimulate(days: 1, interrupted: true)
            }
            Button("重設提醒紀錄（重新提醒已解鎖獎勵）") {
                streakStore.debugResetReminders()
            }
            Button("恢復真實進度") { streakStore.debugRestoreRealProgress() }
                .disabled(!streakStore.isDebugSimulationActive)
            Text(streakStore.isDebugSimulationActive ? "目前使用模擬進度，完成測試後請恢復真實進度。" : "目前使用真實進度；首次模擬會自動備份。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .tint(AppTheme.concise.color)
        .padding(16)
        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
    }
#endif

    private func iconButton(for option: AppIconOption) -> some View {
        let isUnlocked = option == .premium ? hasPremiumAccess : option.isUnlocked(bestStreak: streakStore.bestStreak)

        return Button {
            if isUnlocked {
                Task {
                    if case let .failed(message) = await iconManager.setIcon(option, source: .settings) {
                        iconErrorMessage = message
                    }
                }
            } else {
                lockedOption = option
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(option.previewAssetName)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: scaled(15, pad: 18), style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: scaled(15, pad: 18), style: .continuous)
                            .stroke(Color.white.opacity(0.82), lineWidth: 1)
                    }
                    .opacity(1)

                statusBadge(for: option, isUnlocked: isUnlocked)
                    .offset(x: scaled(3, pad: 4), y: -scaled(3, pad: 4))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(iconManager.isChanging)
        .accessibilityLabel(
            isUnlocked
                ? option.displayName
                : L10n.tr(
                    "Locked \(option.displayName) app icon",
                    zhHans: "已锁定的\(option.displayName)应用图标",
                    zhHant: "已鎖定的\(option.displayName)應用程式圖標",
                    ja: "ロック中の\(option.displayName)アプリアイコン"
                )
        )
    }

    private func statusBadge(for option: AppIconOption, isUnlocked: Bool) -> some View {
        let isCurrent = iconManager.isCurrent(option)

        return Group {
            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: scaled(11, pad: 13), weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: scaled(27, pad: 31), height: scaled(27, pad: 31))
                    .background(themeColor, in: Circle())
            } else if !isUnlocked {
                Image(systemName: option == .premium ? "crown.fill" : "lock.fill")
                    .font(.system(size: scaled(10, pad: 12), weight: .bold))
                    .foregroundStyle(AppIconPalette.text.opacity(0.82))
                    .frame(width: scaled(27, pad: 31), height: scaled(27, pad: 31))
                    .background(Color.white.opacity(0.94), in: Circle())
            }
        }
        .shadow(color: Color.black.opacity(0.14), radius: 4, y: 2)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.15) : base
    }
}

private struct AppIconUnlockSheet: View {
    let option: AppIconOption
    let currentStreak: Int
    let themeColor: Color
    let onOpenPremium: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var requiredDays: Int { option.requiredDays ?? 0 }

    var body: some View {
        ZStack {
            Image(option.previewAssetName)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .blur(radius: 28)

            GeometryReader { proxy in
                VStack(spacing: 20) {
                    Image(option.previewAssetName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 180, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .shadow(color: Color.black.opacity(0.2), radius: 18, y: 9)
                        .offset(y: -20)

                    VStack(spacing: 16) {
                        Text(option == .premium ? L10n.tr("Members-only app icon", zhHans: "会员专属应用图标", zhHant: "會員專屬應用程式圖標", ja: "会員限定アプリアイコン") : L10n.tr("Unlock this app icon", zhHans: "解锁这个应用图标", zhHant: "解鎖這個應用程式圖標", ja: "このアプリアイコンを解放"))
                            .font(.appSystem(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.center)

                        Text(option == .premium ? L10n.tr("Join Bingodays Pro to use this exclusive app icon", zhHans: "开通 Bingodays Pro 即可使用此专属图标", zhHant: "開通 Bingodays Pro 即可使用此專屬圖標", ja: "Bingodays Proに加入して限定アイコンを使おう") : L10n.tr(
                            "Keep Bingodays open for \(requiredDays) consecutive days",
                            zhHans: "连续开启 Bingodays \(requiredDays) 天",
                            zhHant: "連續開啟 Bingodays \(requiredDays) 天",
                            ja: "Bingodaysを\(requiredDays)日連続で開く"
                        ))
                        .font(.appSystem(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.68))
                        .multilineTextAlignment(.center)

                        if option != .premium { VStack(spacing: 5) {
                            artisticStreakText

                            Text(L10n.tr("Current consecutive days", zhHans: "当前连续开启天数", zhHant: "目前連續開啟天數", ja: "現在の連続起動日数"))
                                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.black.opacity(0.68))
                        } }

                        Button {
                            if option == .premium { onOpenPremium() }
                            dismiss()
                        } label: {
                            Text(option == .premium ? L10n.tr("Unlock with Pro", zhHans: "开通会员", zhHant: "開通會員", ja: "Proに加入") : L10n.tr("Got it!", zhHans: "明白了！", zhHant: "明白了！", ja: "わかった！"))
                                .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: min(proxy.size.width - 120, 220))
                                .padding(.vertical, 13)
                                .background(AppTheme.concise.color, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                    .padding(.bottom, 15)
                    .frame(maxWidth: min(proxy.size.width - 56, 352))
                    .background {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(Color.white.opacity(0.20))
                    }
                    .appLiquidGlass(
                        in: RoundedRectangle(cornerRadius: 32, style: .continuous),
                        interactive: false,
                        tint: Color.white.opacity(0.16),
                        fallbackWhiteOpacity: 0.15
                    )
                    .environment(\.colorScheme, .light)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
            }
        }
        .presentationDetents([.fraction(0.9)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
    }

    private var artisticStreakText: some View {
        let value = "\(min(currentStreak, requiredDays)) / \(requiredDays)"
        let outlineOffsets: [(CGFloat, CGFloat)] = [
            (-1.6, 0), (1.6, 0), (0, -1.6), (0, 1.6),
            (-1.2, -1.2), (1.2, -1.2), (-1.2, 1.2), (1.2, 1.2)
        ]

        return ZStack {
            ForEach(0..<outlineOffsets.count, id: \.self) { index in
                Text(value)
                    .font(.custom("Schoolbell", size: 64))
                    .kerning(-2)
                    .foregroundStyle(.white)
                    .offset(x: outlineOffsets[index].0, y: outlineOffsets[index].1)
            }

            Text(value)
                .font(.custom("Schoolbell", size: 64))
                .kerning(-2)
                .foregroundStyle(Color(hex: "734A37"))
        }
    }
}

struct AppIconStreakProgress: View {
    let currentStreak: Int
    let bestStreak: Int
    var celebrationStyle = false
    private let options: [AppIconOption] = [.days10, .days20, .days30]
    private var nextDay: Int? { [10, 20, 30].first { bestStreak < $0 } }

    var body: some View {
        if celebrationStyle {
            celebrationTimeline
        } else {
        VStack(spacing: 12) {
            Text(L10n.tr("\(currentStreak) consecutive days", zhHans: "已连续开启 \(currentStreak) 天", zhHant: "已連續開啟 \(currentStreak) 天", ja: "\(currentStreak)日連続で起動中"))
                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
            GeometryReader { geometry in
              ZStack {
                ForEach(options) { option in
                    VStack(spacing: 6) {
                        Image(option.previewAssetName)
                            .resizable().scaledToFit()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: option.isUnlocked(bestStreak: bestStreak) ? "checkmark" : "lock.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(option.isUnlocked(bestStreak: bestStreak) ? Color.white : Color(hex: "734A37"))
                                    .frame(width: 20, height: 20)
                                    .background(option.isUnlocked(bestStreak: bestStreak) ? AppTheme.concise.color : .white, in: Circle())
                                    .offset(x: 5, y: -5)
                            }
                        Text(L10n.tr("\(option.requiredDays ?? 0) days", zhHans: "\(option.requiredDays ?? 0) 天", zhHant: "\(option.requiredDays ?? 0) 天", ja: "\(option.requiredDays ?? 0)日"))
                            .font(.appSystem(size: 11, weight: .semibold, design: .rounded))
                    }
                    .position(x: geometry.size.width * CGFloat(option.requiredDays ?? 0) / 30, y: 34)
                }
              }
            }
            .frame(height: 72)
            .padding(.horizontal, 24)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.08))
                    Capsule().fill(AppTheme.concise.color)
                        .frame(width: geometry.size.width * CGFloat(min(max(currentStreak, 0), 30)) / 30)
                    HStack {
                        ForEach([10, 20, 30], id: \.self) { day in
                            Circle().fill(bestStreak >= day ? AppTheme.concise.color : Color.white)
                                .frame(width: 10, height: 10)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
            }
            .frame(height: 8)
            .padding(.horizontal, 24)
            Text(progressMessage)
                .font(.appSystem(size: 12, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.black.opacity(0.65))
        }
        .foregroundStyle(.black)
        .accessibilityElement(children: .combine)
        }
    }

    private var celebrationTimeline: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                let width = geometry.size.width - 50
                let accent = Color(hex: "DFAE81")
                let muted = Color(hex: "E7D5C4")
                ZStack(alignment: .topLeading) {
                    Capsule().fill(muted).frame(width: width, height: 7).offset(x: 25, y: 74)
                    Capsule().fill(accent)
                        .frame(width: width * CGFloat(min(max(currentStreak, 0), 30)) / 30, height: 7)
                        .offset(x: 25, y: 74)
                    ForEach([0, 10, 20, 30], id: \.self) { day in
                        let unlocked = day == 0 || bestStreak >= day
                        let x = 25 + width * CGFloat(day) / 30
                        Image(timelineAsset(for: day))
                            .resizable().scaledToFill()
                            .frame(width: unlocked ? 48 : 38, height: unlocked ? 48 : 38)
                            .clipShape(RoundedRectangle(cornerRadius: unlocked ? 8 : 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: unlocked ? 8 : 6)
                                    .stroke(.white, lineWidth: unlocked ? 2 : 1.5)
                            }
                            .shadow(color: unlocked ? accent.opacity(0.5) : .clear, radius: 12)
                            .position(x: x, y: 27)
                            .accessibilityLabel(L10n.tr("\(day) days", zhHans: "\(day) 天", zhHant: "\(day) 天", ja: "\(day)日"))
                            .accessibilityValue(unlocked ? L10n.tr("Unlocked", zhHans: "已解锁", zhHant: "已解鎖", ja: "解放済み") : L10n.tr("Locked", zhHans: "未解锁", zhHant: "未解鎖", ja: "未解放"))
                        Circle().fill(.white)
                            .overlay { Circle().stroke(unlocked ? accent : muted, lineWidth: 1.5) }
                            .frame(width: 14, height: 14).position(x: x, y: 77.5)
                        Text("\(day)")
                            .font(.appSystem(size: 13, weight: .regular))
                            .foregroundStyle(unlocked ? accent : muted)
                            .position(x: x, y: 98)
                    }
                }
            }
            .frame(height: 109)
            Text(progressMessage)
                .font(.appSystem(size: 14, weight: .regular))
                .foregroundStyle(Color(hex: "4A2F17"))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.24), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(.white, lineWidth: 2) }
    }

    private func timelineAsset(for day: Int) -> String {
        switch day {
        case 10: AppIconOption.days10.previewAssetName
        case 20: AppIconOption.days20.previewAssetName
        case 30: AppIconOption.days30.previewAssetName
        default: "AppIconPreviewDefault"
        }
    }

    private var progressMessage: String {
        guard let nextDay else {
            return L10n.tr("All streak rewards unlocked!", zhHans: "全部连续开启奖励已解锁！", zhHant: "全部連續開啟獎勵已解鎖！", ja: "連続起動の報酬をすべて解放しました！")
        }
        let remaining = max(0, nextDay - currentStreak)
        return L10n.tr("Open for \(remaining) more consecutive days to unlock the next icon", zhHans: "再连续开启 \(remaining) 天，即可解锁下一个图标", zhHant: "再連續開啟 \(remaining) 天，即可解鎖下一個圖標", ja: "あと\(remaining)日連続で開くと次のアイコンが解放されます")
    }
}

struct AppIconMilestoneSheet: View {
    let milestones: [Int]
    @ObservedObject var streakStore: AppOpenStreakStore
    @EnvironmentObject private var iconManager: AppIconManager
    @State private var iconErrorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var showsProgressOnly: Bool { milestones.isEmpty }
    private var option: AppIconOption {
        switch milestones.max() ?? 10 {
        case 30: .days30
        case 20: .days20
        default: .days10
        }
    }

    @ViewBuilder
    var body: some View {
        if showsProgressOnly {
            ViewThatFits(in: .vertical) {
                progressContent
                ScrollView { progressContent }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 16)
            .overlay(alignment: .topTrailing) { closeButton }
            .presentationDetents([.height(dynamicTypeSize.isAccessibilitySize ? 710 : 430)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(16)
            .presentationBackground(Color(hex: "FBF6F2"))
            .environment(\.colorScheme, .light)
        } else {
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.35)
                        .contentShape(Rectangle())
                        .onTapGesture { if !iconManager.isChanging { dismiss() } }
                        .accessibilityHidden(true)
                    popupContent
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom, 20))
                        .frame(
                            width: geometry.size.width,
                            height: min(dynamicTypeSize.isAccessibilitySize ? 710 : 574, geometry.size.height - 48),
                            alignment: .top
                        )
                        .background(Color(hex: "FBF6F2"))
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
                        .accessibilityAddTraits(.isModal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea()
            .presentationBackground(.clear)
            .environment(\.colorScheme, .light)
        }
    }

    private var popupContent: some View {
        ZStack(alignment: .top) {
            AppIconConfettiEffect()
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            ViewThatFits(in: .vertical) {
                sheetContent
                ScrollView { sheetContent }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) { closeButton }
        .environment(\.colorScheme, .light)
        .alert(L10n.tr("Couldn’t change app icon", zhHans: "无法更换应用图标", zhHant: "無法更換應用程式圖標", ja: "アプリアイコンを変更できません"), isPresented: Binding(get: { iconErrorMessage != nil }, set: { if !$0 { iconErrorMessage = nil } })) {
            Button(L10n.ok) { iconErrorMessage = nil }
        } message: { Text(iconErrorMessage ?? "") }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color(hex: "171717"))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(iconManager.isChanging)
        .accessibilityLabel(L10n.tr("Close", zhHans: "关闭", zhHant: "關閉", ja: "閉じる"))
        .padding(.top, 4)
        .padding(.trailing, 4)
    }

    @ViewBuilder
    private var sheetContent: some View {
        if showsProgressOnly {
            progressContent
        } else {
            milestoneContent
        }
    }

    private var progressContent: some View {
        VStack(spacing: 0) {
            Text(L10n.tr("App icon unlock progress", zhHans: "桌面图标解锁进度", zhHant: "桌面圖標解鎖進度", ja: "アプリアイコンの解放進捗"))
                .font(.appSystem(size: 20, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.top, 52)
            Text(L10n.tr("Opened Bingodays for \(streakStore.currentStreak) consecutive days", zhHans: "已连续开启 Bingodays \(streakStore.currentStreak) 天", zhHant: "已連續開啟 Bingodays \(streakStore.currentStreak) 天", ja: "Bingodaysを\(streakStore.currentStreak)日連続で起動中"))
                .font(.appSystem(size: 14, weight: .medium))
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.bottom, 24)
            AppIconStreakProgress(
                currentStreak: streakStore.currentStreak,
                bestStreak: streakStore.bestStreak,
                celebrationStyle: true
            )
            Button { dismiss() } label: {
                Text(L10n.tr("Done", zhHans: "完成", zhHant: "完成", ja: "完了"))
                    .font(.appSystem(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 300, minHeight: 52)
                    .background(LinearGradient(colors: [Color(hex: "D2A57E"), Color(hex: "D3A375")], startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
        }
        .foregroundStyle(Color(hex: "4A2F17"))
    }

    private var milestoneContent: some View {
        VStack(spacing: 0) {
            Image(option.previewAssetName).resizable().scaledToFill()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 23))
                .overlay { RoundedRectangle(cornerRadius: 23).strokeBorder(.white, lineWidth: 6) }
                .padding(.top, 40)
            Text(L10n.tr("You opened Bingodays for \(milestones.max() ?? 10) days in a row.\nA new app icon is unlocked!", zhHans: "你已连续开启\(milestones.max() ?? 10)天，\n新的桌面图标解锁了！", zhHant: "你已連續開啟\(milestones.max() ?? 10)天，\n新的桌面圖標解鎖了！", ja: "\(milestones.max() ?? 10)日連続で起動！\n新しいアイコンを解放しました！"))
                .font(.appSystem(size: 18, weight: .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 24)
                .padding(.bottom, 24)
            AppIconStreakProgress(currentStreak: streakStore.currentStreak, bestStreak: streakStore.bestStreak, celebrationStyle: true)
            Button {
                Task {
                    let result = await iconManager.setIcon(option, source: .milestone)
                    if result.succeeded { dismiss() }
                    if case let .failed(message) = result { iconErrorMessage = message }
                }
            } label: {
                Text(L10n.tr("Use this new icon!", zhHans: "使用这个新图标！", zhHant: "使用這個新圖標！", ja: "この新しいアイコンを使う！"))
                    .font(.appSystem(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 300, minHeight: 52)
                    .background(LinearGradient(colors: [Color(hex: "D2A57E"), Color(hex: "D3A375")], startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
            }
            .buttonStyle(.plain).disabled(iconManager.isChanging)
            .padding(.top, 19)
            .padding(.bottom, 0)
        }
        .foregroundStyle(Color(hex: "4A2F17"))
    }
}

/// Reuses individual pieces from the supplied artwork, without changing the asset.
private struct AppIconConfettiEffect: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var startedAt = Date()
    // The celebration deliberately unfolds slowly enough to see each paper piece.
    private static let burstDuration = 1.4
    private static let pieces: [UIImage] = {
        guard let source = UIImage(named: "AppIconCelebrationConfetti")?.cgImage else { return [] }
        // Pixel bounds of paper/ribbon pieces in the original 786 × 740 artwork.
        // Soft glow spots are deliberately excluded from the particle textures.
        let bounds: [CGRect] = [
            CGRect(x: 166, y: 76, width: 51, height: 66),
            CGRect(x: 99, y: 153, width: 62, height: 63),
            CGRect(x: 468, y: 139, width: 39, height: 40),
            CGRect(x: 532, y: 50, width: 21, height: 65),
            CGRect(x: 673, y: 111, width: 57, height: 74),
            CGRect(x: 498, y: 248, width: 45, height: 88),
            CGRect(x: 593, y: 257, width: 54, height: 37),
            CGRect(x: 322, y: 288, width: 48, height: 28),
            CGRect(x: 127, y: 303, width: 68, height: 53),
            CGRect(x: 257, y: 328, width: 39, height: 55),
            CGRect(x: 588, y: 378, width: 78, height: 53),
            CGRect(x: 80, y: 408, width: 100, height: 62),
            CGRect(x: 551, y: 475, width: 62, height: 39),
            CGRect(x: 223, y: 550, width: 65, height: 91)
        ]
        let scaleX = CGFloat(source.width) / 786
        let scaleY = CGFloat(source.height) / 740
        return bounds.compactMap { bounds in
            let rect = CGRect(x: bounds.minX * scaleX, y: bounds.minY * scaleY,
                              width: bounds.width * scaleX, height: bounds.height * scaleY).integral
            return source.cropping(to: rect).map { UIImage(cgImage: $0) }
        }
    }()

    var body: some View {
        Group {
            if reduceMotion || Self.pieces.isEmpty {
                Image("AppIconCelebrationConfetti")
                    .resizable().scaledToFit()
                    .offset(y: -22)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: scenePhase != .active)) { timeline in
                    Canvas { context, size in
                        let elapsed = max(0, timeline.date.timeIntervalSince(startedAt))
                        for index in 0..<(Self.pieces.count * 2) {
                            guard let symbol = context.resolveSymbol(id: index % Self.pieces.count) else { continue }
                            // Let the sheet finish entering before the burst begins.
                            let delay = 0.25 + Double(index % 3) * 0.08
                            let time = elapsed - delay
                            guard time >= 0 else { continue }
                            // Fixed seeds avoid particles jumping when SwiftUI recomputes the view.
                            let seed = Double((index * 37 + 17) % 101) / 100
                            let direction = index.isMultiple(of: 2) ? -1.0 : 1.0
                            let angle = Double(index) * 2 * .pi / Double(Self.pieces.count * 2)
                                + seed * 0.16
                            let progress = Self.burstProgress(min(1, time / Self.burstDuration))
                            let centerX = Double(size.width) / 2
                            let centerY = 100.0
                            let distanceLayer = Double(index % 3)
                            let horizontalRadius = Double(size.width) * (0.20 + distanceLayer * 0.07 + seed * 0.025)
                            var targetX = centerX + cos(angle) * horizontalRadius
                            let targetY = max(25, 110 + sin(angle) * (65 + distanceLayer * 20 + seed * 12))
                            // Keep the lower particles beside, not behind, the readable title.
                            if targetY > 175, abs(targetX - centerX) < Double(size.width) * 0.22 {
                                targetX = centerX + direction * Double(size.width) * (0.22 + distanceLayer * 0.055)
                            }
                            let idleTime = max(0, time - Self.burstDuration)
                            let idleBlend = min(1, idleTime / 0.3)
                            let x = centerX + (targetX - centerX) * progress
                                + sin(idleTime * 1.2 + Double(index)) * 2 * idleBlend
                            let y = centerY + (targetY - centerY) * progress
                                + sin(idleTime * (1.3 + seed * 0.4) + Double(index)) * (4 + seed * 3) * idleBlend
                            let fadeIn = min(1, time / 0.12)
                            var particle = context
                            particle.opacity = fadeIn * 0.95
                            particle.translateBy(x: x, y: y)
                            particle.rotate(by: .radians(Double(index) + direction * progress * .pi
                                + sin(idleTime * 1.1 + Double(index)) * 0.08 * idleBlend))
                            particle.scaleBy(x: 0.9 + progress * 0.1, y: 0.9 + progress * 0.1)
                            particle.draw(symbol, at: .zero)
                        }
                    } symbols: {
                        ForEach(Self.pieces.indices, id: \.self) { index in
                            let piece = Self.pieces[index]
                            Image(uiImage: piece)
                                .resizable().scaledToFit()
                                .frame(width: piece.size.width * 0.5, height: piece.size.height * 0.5)
                                .tag(index)
                        }
                    }
                }
                .clipped()
                .onAppear { startedAt = .now }
            }
        }
    }

    /// Evaluates the strong ease-out curve (0.23, 1, 0.32, 1).
    private static func burstProgress(_ progress: Double) -> Double {
        guard progress > 0, progress < 1 else { return progress }
        var lower = 0.0
        var upper = 1.0
        for _ in 0..<12 {
            let t = (lower + upper) / 2
            let x = 3 * (1 - t) * (1 - t) * t * 0.23
                + 3 * (1 - t) * t * t * 0.32 + t * t * t
            if x < progress { lower = t } else { upper = t }
        }
        let t = (lower + upper) / 2
        return 1 - pow(1 - t, 3)
    }
}

private enum AppIconPalette {
    static let text = Color(hex: "463C2E")
    static let mutedText = Color(hex: "8B7B68")
}
