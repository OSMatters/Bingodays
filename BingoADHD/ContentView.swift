import SwiftUI
import AVFoundation
#if canImport(WidgetKit)
import WidgetKit
#endif

final class PointsSoundPlayer {
    static let shared = PointsSoundPlayer()

    private var player: AVAudioPlayer?

    func preload() {
        guard AppSettings.isSoundEffectsEnabled else { return }
        guard player == nil,
              let url = Bundle.main.url(forResource: "get1point", withExtension: "aiff") else { return }

        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.prepareToPlay()
            player = audioPlayer
        } catch {
            player = nil
        }
    }

    func play() {
        guard AppSettings.isSoundEffectsEnabled else { return }
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = BingoViewModel()
    @State private var isSidebarPresented = false
    @State private var isSettingsExpanded = true
    @State private var isWidgetGuideExpanded = false
    @State private var isThemePickerExpanded = false
    @State private var isPointsDetailsPresented = false
    @State private var isBoardCountdownPresented = false
    @State private var selectedStickerID: UUID?
    @State private var isDiaryPresented = false
    @State private var isCommonTasksEditorPresented = false
    @State private var pointsAnimationTrigger = 0
    @State private var floatingPointsDelta: Int?
    @State private var isFloatingPointsDeltaVisible = false
    @State private var stickerInventoryCounts = StickerStore.loadInventoryCounts()
    @State private var homeStickerPlacements = StickerStore.loadPlacements()
    @AppStorage(AppSettings.hapticsEnabledKey) private var isHapticsEnabled = true
    @AppStorage(AppSettings.soundEffectsEnabledKey) private var isSoundEffectsEnabled = true
    @AppStorage(AppSettings.themeKey) private var themeRawValue = AppTheme.sky.rawValue
    private let countdownTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var countdownNow = Date()
    private var bingoStreakDays: Int { BingoDiaryStore.consecutiveBingoDays() }
    private var streakGoals: [Int] { bingoStreakDays >= 60 ? [60, 180, 270, 365] : [7, 14, 30, 60] }
    private var activeTheme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .sky }
    private var activeThemeColor: Color { activeTheme.color }
    private var spentStickerPoints: Int {
        stickerInventoryCounts.reduce(0) { partial, entry in
            partial + (entry.key.requiredPoints * entry.value)
        }
    }
    private var availablePoints: Int { max(viewModel.totalPoints - spentStickerPoints, 0) }
    private var filledTaskCount: Int {
        viewModel.cells.flatMap(\.self).filter { !$0.isEmpty }.count
    }
    private var completedTaskCount: Int {
        viewModel.cells.flatMap(\.self).filter { !$0.isEmpty && $0.isCompleted }.count
    }
    private var completionProgress: Double {
        guard filledTaskCount > 0 else { return 0 }
        return Double(completedTaskCount) / Double(filledTaskCount)
    }
    private var completionPercent: Int {
        Int((completionProgress * 100).rounded())
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                NeumorphicColors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    VStack(spacing: 22) {
                        gridControls

                        BingoBoardView(viewModel: viewModel)
                            .padding(.horizontal, 8)

                        boardCountdownTrigger
                            .padding(.top, 14)
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                }

                homeStickerLayer(
                    canvasSize: geo.size,
                    topInset: geo.safeAreaInsets.top,
                    bottomInset: geo.safeAreaInsets.bottom
                )

                VStack {
                    headerView
                        .padding(.top, 75)
                    Spacer()
                }
                .ignoresSafeArea(edges: .top)

                if isSidebarPresented {
                    Color.black.opacity(0.16)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                isSidebarPresented = false
                            }
                        }
                }

                sidebarView(
                    width: min(geo.size.width * 0.8, 332),
                    topInset: geo.safeAreaInsets.top,
                    bottomInset: geo.safeAreaInsets.bottom
                )
                    .offset(x: isSidebarPresented ? 0 : -min(geo.size.width * 0.8, 320))
                    .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isSidebarPresented)

                if viewModel.showCelebration {
                    CelebrationView()
                }

                if viewModel.showBoardCompletionAnimation {
                    PAGCompletionView(resourceName: "cat_bmp") {
                        viewModel.dismissBoardCompletionAnimation()
                    }
                    .frame(width: min(geo.size.width * 0.5, 220), height: min(geo.size.width * 0.5, 220))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
        }
        .fullScreenCover(isPresented: $isCommonTasksEditorPresented) {
            CommonTasksEditorView()
        }
        .sheet(isPresented: $isPointsDetailsPresented) {
            PointsDetailSheet(
                points: availablePoints,
                inventoryCounts: stickerInventoryCounts,
                usedCounts: currentStickerUsageCounts,
                onRedeem: { kind in
                    redeemSticker(kind)
                },
                onAddToHome: { kind in
                    addStickerToHome(kind)
                }
            )
                .presentationDetents([.height(428)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isBoardCountdownPresented) {
            BoardCountdownSheet(
                countdownEndsAt: viewModel.boardCountdownEndsAt,
                onSave: { totalMinutes in
                    viewModel.setBoardCountdown(totalMinutes: totalMinutes)
                    isBoardCountdownPresented = false
                },
                onCancel: {
                    isBoardCountdownPresented = false
                }
            )
            .presentationDetents([.height(360)])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $isDiaryPresented) {
            BingoDiaryScreen()
        }
        .onAppear {
            countdownNow = Date()
            viewModel.processExpiredCountdowns(now: countdownNow)
            PAGCompletionView.preload(resourceName: "cat_bmp")
            PointsSoundPlayer.shared.preload()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            countdownNow = Date()
            viewModel.processExpiredCountdowns(now: countdownNow)
        }
        .onChange(of: availablePoints) { oldValue, newValue in
            let delta = newValue - oldValue
            guard delta != 0 else { return }

            pointsAnimationTrigger += 1
            floatingPointsDelta = delta

            if delta > 0 {
                PointsSoundPlayer.shared.play()
            }

            withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
                isFloatingPointsDeltaVisible = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) {
                withAnimation(.easeOut(duration: 0.32)) {
                    isFloatingPointsDeltaVisible = false
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.08) {
                if !isFloatingPointsDeltaVisible {
                    floatingPointsDelta = nil
                }
            }
        }
        .onReceive(countdownTicker) { _ in
            countdownNow = Date()
            viewModel.processExpiredCountdowns(now: countdownNow)
        }
        .alert(L10n.countdownEndedTitle, isPresented: Binding(
            get: { viewModel.expiredCountdownMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.clearExpiredCountdownMessage()
                }
            }
        )) {
            Button(L10n.ok) {
                viewModel.clearExpiredCountdownMessage()
            }
        } message: {
            Text(viewModel.expiredCountdownMessage ?? "")
        }
    }

    private var boardCountdownTrigger: some View {
        Button {
            isBoardCountdownPresented = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "timer")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(NeumorphicColors.accent)

                if let countdownText = boardCountdownText {
                    Text(countdownText)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(NeumorphicColors.accent)
                        .lineLimit(1)
                } else {
                    Text(L10n.setBoardCountdown)
                        .font(.system(.footnote, design: .rounded).weight(.medium))
                        .foregroundColor(NeumorphicColors.text.opacity(0.72))
                        .lineLimit(1)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(NeumorphicColors.text.opacity(0.58))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.clear.neumorphicConvex(radius: 16))
        }
        .buttonStyle(.plain)
    }

    private var boardCompletionProgressView: some View {
        HStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(NeumorphicColors.background)
                        .neumorphicConcave(radius: 10)
                        .overlay(
                            Capsule()
                                .stroke(NeumorphicColors.lightShadow.opacity(0.34), lineWidth: 0.8)
                        )

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    NeumorphicColors.accent.opacity(0.88),
                                    NeumorphicColors.accent
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: filledTaskCount == 0 ? 14 : max(14, proxy.size.width * completionProgress))
                        .shadow(color: NeumorphicColors.accent.opacity(0.28), radius: 10, x: 0, y: 4)
                        .opacity(filledTaskCount == 0 ? 0.28 : 1)
                }
            }
            .frame(height: 12)

            Text("\(completedTaskCount)/\(filledTaskCount)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(NeumorphicColors.accent)
        }
        .frame(height: 38)
        .frame(width: 180, alignment: .leading)
    }

    private var boardCountdownText: String? {
        guard let endsAt = viewModel.boardCountdownEndsAt, endsAt > countdownNow else {
            return nil
        }

        let remainingSeconds = max(Int(endsAt.timeIntervalSince(countdownNow)), 0)
        let hours = min(remainingSeconds / 3600, 99)
        let minutes = (remainingSeconds % 3600) / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func homeStickerLayer(canvasSize: CGSize, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        ZStack {
            if selectedStickerID != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            selectedStickerID = nil
                        }
                    }
            }

            ForEach(homeStickerPlacements) { placement in
                EditableHomeStickerView(
                    placement: placement,
                    canvasSize: canvasSize,
                    isEditing: selectedStickerID == placement.id,
                    onSelect: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            selectedStickerID = placement.id
                        }
                    },
                    onUpdate: { updatedPlacement in
                        updateStickerPlacement(updatedPlacement)
                    },
                    onDelete: {
                        deleteStickerPlacement(id: placement.id)
                    }
                )
            }
        }
    }

    private var headerView: some View {
        HStack {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    isSidebarPresented.toggle()
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.title2.weight(.bold))
                    .foregroundColor(NeumorphicColors.accent)
                    .frame(width: 44, height: 44)
                    .neumorphicConvex(radius: 22)
            }

            Spacer()

            ZStack(alignment: .topTrailing) {
                Button {
                    isPointsDetailsPresented = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(NeumorphicColors.accent)
                            .symbolEffect(.bounce, value: pointsAnimationTrigger)

                        Text("\(availablePoints)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(NeumorphicColors.text)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: availablePoints)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .neumorphicConvex(radius: 20)
                }
                .buttonStyle(.plain)

                if let floatingPointsDelta {
                    Text(floatingPointsDelta > 0 ? "+\(floatingPointsDelta)" : "\(floatingPointsDelta)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(floatingPointsDelta > 0 ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.72))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(NeumorphicColors.background.opacity(0.96))
                                .shadow(color: NeumorphicColors.darkShadow.opacity(0.16), radius: 5, x: 2, y: 2)
                                .shadow(color: Color.white.opacity(0.72), radius: 4, x: -2, y: -2)
                        )
                        .offset(x: -4, y: isFloatingPointsDeltaVisible ? -30 : -8)
                        .opacity(isFloatingPointsDeltaVisible ? 1 : 0)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func sidebarView(width: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        let sidebarShape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 28,
            topTrailingRadius: 28,
            style: .continuous
        )

        return VStack(alignment: .leading, spacing: 0) {
            List {
                Section {
                    sidebarStreakHero
                    sidebarStreakGoals

                    Button {
                        isSidebarPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isCommonTasksEditorPresented = true
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "star")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(NeumorphicColors.accent)
                                .frame(width: 40, height: 40)
                                .neumorphicConvex(radius: 20)

                            Text(L10n.myTasks)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(NeumorphicColors.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    Button {
                        isSidebarPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isDiaryPresented = true
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "calendar")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(NeumorphicColors.accent)
                                .frame(width: 40, height: 40)
                                .neumorphicConvex(radius: 20)

                            Text(L10n.bingoDiary)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(NeumorphicColors.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            isSettingsExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(NeumorphicColors.accent)
                                .frame(width: 40, height: 40)
                                .neumorphicConvex(radius: 20)

                            Text(L10n.setting)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)

                            Spacer()

                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(NeumorphicColors.accent)
                                .rotationEffect(.degrees(isSettingsExpanded ? 0 : -90))
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    if isSettingsExpanded {
                        sidebarToggleRow(title: L10n.haptics, isOn: $isHapticsEnabled)
                            .padding(.top, 6)

                        sidebarToggleRow(title: L10n.soundEffects, isOn: $isSoundEffectsEnabled)

                        widgetGuideRow

                        if isWidgetGuideExpanded {
                            widgetGuideTextRow
                        }

                        themePickerTriggerRow

                        if isThemePickerExpanded {
                            themePickerRow
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .environment(\.defaultMinListRowHeight, 72)
            .padding(.top, max(topInset, 22))
            .padding(.bottom, max(bottomInset, 12))
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background {
            sidebarShape
                .fill(NeumorphicColors.background)
                .shadow(color: NeumorphicColors.darkShadow.opacity(0.75), radius: 14, x: 10, y: 0)
                .shadow(color: NeumorphicColors.lightShadow.opacity(0.8), radius: 8, x: -2, y: 0)
        }
        .overlay {
            sidebarShape
                .stroke(NeumorphicColors.background.opacity(0.95), lineWidth: 1.5)
        }
        .clipShape(sidebarShape)
        .ignoresSafeArea(edges: .vertical)
    }

    private func sidebarRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(NeumorphicColors.accent)
                .frame(width: 40, height: 40)
                .neumorphicConvex(radius: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)

                Text(value)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.72))
            }

            Spacer()
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var sidebarStreakHero: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(bingoStreakDays)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                activeThemeColor.opacity(0.72),
                                activeThemeColor
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.top, 10)

                Text(L10n.dayStreak)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
            }

            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .fill(activeThemeColor.opacity(0.24))
                    .frame(width: 64, height: 64)
                    .blur(radius: 8)

                Image(systemName: "flame.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                activeThemeColor.opacity(0.42),
                                activeThemeColor.opacity(0.76),
                                activeThemeColor
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: activeThemeColor.opacity(0.34), radius: 10, x: 0, y: 6)
            }
            .frame(width: 78, height: 78)
        }
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets(top: 18, leading: 22, bottom: 10, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var sidebarStreakGoals: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.streakGoals)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            HStack(alignment: .center, spacing: 8) {
                ForEach(Array(streakGoals.enumerated()), id: \.offset) { index, goal in
                    streakGoalNode(goal: goal, previousGoal: index == 0 ? 0 : streakGoals[index - 1])

                    if index < streakGoals.count - 1 {
                        streakConnector(
                            from: goal,
                            to: streakGoals[index + 1]
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 10)
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(NeumorphicColors.background)
                .shadow(color: NeumorphicColors.darkShadow.opacity(0.22), radius: 8, x: 4, y: 4)
                .shadow(color: Color.white.opacity(0.65), radius: 8, x: -3, y: -3)
        )
        .listRowInsets(EdgeInsets(top: 6, leading: 22, bottom: 14, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func streakConnector(from startGoal: Int, to endGoal: Int) -> some View {
        let fillProgress = streakConnectorProgress(from: startGoal, to: endGoal)

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(NeumorphicColors.darkShadow.opacity(0.22))
                .frame(height: 8)

            GeometryReader { geo in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                activeThemeColor.opacity(0.45),
                                activeThemeColor
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 8)
                    .frame(width: geo.size.width * fillProgress)
            }
        }
    }

    private func streakGoalNode(goal: Int, previousGoal: Int) -> some View {
        let isAchieved = bingoStreakDays >= goal
        let isCurrent = !isAchieved && bingoStreakDays >= previousGoal

        return ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isAchieved
                    ? activeThemeColor.opacity(0.18)
                    : NeumorphicColors.background.opacity(isCurrent ? 0.99 : 0.98)
                )
                .frame(width: 44, height: 48)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isAchieved ? activeThemeColor.opacity(0.72) : NeumorphicColors.darkShadow.opacity(isCurrent ? 0.22 : 0.18))
                        .frame(width: 34, height: 10)
                        .padding(.top, 4)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isAchieved ? activeThemeColor.opacity(0.9) : NeumorphicColors.darkShadow.opacity(isCurrent ? 0.28 : 0.22), lineWidth: 1.2)
                }
                .overlay(alignment: .top) {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Color.white.opacity(0.75))
                            .frame(width: 4, height: 4)
                        Circle()
                            .fill(Color.white.opacity(0.75))
                            .frame(width: 4, height: 4)
                    }
                    .padding(.top, 7)
                }
                .overlay {
                    Rectangle()
                        .fill((isAchieved ? activeThemeColor : NeumorphicColors.darkShadow).opacity(isCurrent ? 0.2 : 0.16))
                        .frame(width: 28, height: 1)
                        .offset(y: -6)
                }
                .shadow(
                    color: isAchieved ? activeThemeColor.opacity(0.18) : NeumorphicColors.darkShadow.opacity(isCurrent ? 0.1 : 0.08),
                    radius: 3,
                    x: 1.5,
                    y: 1.5
                )
                .shadow(
                    color: Color.white.opacity(0.72),
                    radius: 3,
                    x: -1.5,
                    y: -1.5
                )

            Text("\(goal)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(isAchieved ? activeThemeColor : NeumorphicColors.text.opacity(isCurrent ? 0.86 : 0.78))
                .padding(.top, 10)
        }
        .frame(width: 44, height: 48)
    }

    private func streakConnectorProgress(from startGoal: Int, to endGoal: Int) -> CGFloat {
        if bingoStreakDays >= endGoal {
            return 1
        }
        if bingoStreakDays <= startGoal {
            return 0
        }

        let progress = CGFloat(bingoStreakDays - startGoal) / CGFloat(max(endGoal - startGoal, 1))
        return min(max(progress, 0), 1)
    }

    private func sidebarMetricRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(NeumorphicColors.accent)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)

                Text(value)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.72))
            }

            Spacer()
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func sidebarToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.78))

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(SidebarGlassToggleStyle())
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var widgetGuideRow: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                isWidgetGuideExpanded.toggle()
            }
        } label: {
            HStack(spacing: 14) {
                Text(L10n.homeWidget)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.78))

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(NeumorphicColors.accent)
                    .rotationEffect(.degrees(isWidgetGuideExpanded ? 0 : -90))
            }
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var widgetGuideTextRow: some View {
        Text(L10n.homeWidgetInstructions)
            .font(.system(size: 12.5, weight: .medium, design: .rounded))
            .foregroundColor(NeumorphicColors.text.opacity(0.6))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .listRowInsets(EdgeInsets(top: 2, leading: 22, bottom: 12, trailing: 22))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private var themePickerTriggerRow: some View {
        HStack(spacing: 14) {
            Text(L10n.themeColor)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.78))

            Spacer()

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    isThemePickerExpanded.toggle()
                }
            } label: {
                Image("PickerButton")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var themePickerRow: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 12), count: 5), spacing: 12) {
            ForEach(AppTheme.allCases) { theme in
                Button {
                    themeRawValue = theme.rawValue
                    UserDefaults(suiteName: BingoBoardStore.appGroupID)?.set(theme.rawValue, forKey: AppSettings.themeKey)
                    #if canImport(WidgetKit)
                    WidgetCenter.shared.reloadAllTimelines()
                    #endif
                } label: {
                    Circle()
                        .fill(theme.color)
                        .frame(width: 28, height: 28)
                        .overlay {
                            Circle()
                                .stroke(themeRawValue == theme.rawValue ? NeumorphicColors.text : .clear, lineWidth: 2)
                        }
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 4, leading: 76, bottom: 12, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var gridControls: some View {
        HStack {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.4)) {
                        viewModel.resizeGrid(to: viewModel.gridSize - 1)
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(NeumorphicColors.accent)
                        .frame(width: 34, height: 34)
                        .neumorphicConvex(radius: 17)
                }
                .disabled(viewModel.gridSize <= 2)

                Text("\(viewModel.gridSize) × \(viewModel.gridSize)")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(NeumorphicColors.text)
                    .frame(width: 50)
                    .multilineTextAlignment(.center)

                Button {
                    withAnimation(.spring(response: 0.4)) {
                        viewModel.resizeGrid(to: viewModel.gridSize + 1)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(NeumorphicColors.accent)
                        .frame(width: 34, height: 34)
                        .neumorphicConvex(radius: 17)
                }
                .disabled(viewModel.gridSize >= 5)
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    viewModel.shuffleBoard()
                }
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(NeumorphicColors.accent)
                    .frame(width: 38, height: 38)
                    .neumorphicConvex(radius: 19)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 26)
    }

    private func redeemSticker(_ kind: StickerKind) {
        guard availablePoints >= kind.requiredPoints else { return }
        guard stickerInventoryCounts[kind] != 1 else { return }
        stickerInventoryCounts[kind] = 1
        StickerStore.saveInventoryCounts(stickerInventoryCounts)
    }

    private func addStickerToHome(_ kind: StickerKind) {
        guard availableStickerCount(for: kind) > 0 else { return }

        let placement = HomeStickerPlacement(
            kind: kind,
            xRatio: kind == .cowCat ? 0.22 : 0.78,
            yRatio: kind == .cowCat ? 0.28 : 0.72
        )
        homeStickerPlacements.append(placement)
        StickerStore.savePlacements(homeStickerPlacements)
        isPointsDetailsPresented = false
        selectedStickerID = nil
    }

    private func updateStickerPlacement(_ placement: HomeStickerPlacement) {
        guard let index = homeStickerPlacements.firstIndex(where: { $0.id == placement.id }) else { return }
        homeStickerPlacements[index] = placement
        StickerStore.savePlacements(homeStickerPlacements)
    }

    private func deleteStickerPlacement(id: UUID) {
        homeStickerPlacements.removeAll { $0.id == id }
        StickerStore.savePlacements(homeStickerPlacements)
        if selectedStickerID == id {
            selectedStickerID = nil
        }
    }

    private var currentStickerUsageCounts: [StickerKind: Int] {
        homeStickerPlacements.reduce(into: [:]) { partial, placement in
            partial[placement.kind, default: 0] += 1
        }
    }

    private func availableStickerCount(for kind: StickerKind) -> Int {
        max((stickerInventoryCounts[kind] ?? 0) - (currentStickerUsageCounts[kind] ?? 0), 0)
    }
}

private struct PointsDetailSheet: View {
    let points: Int
    let inventoryCounts: [StickerKind: Int]
    let usedCounts: [StickerKind: Int]
    let onRedeem: (StickerKind) -> Void
    let onAddToHome: (StickerKind) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                NeumorphicColors.background
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .center, spacing: 14) {
                        Text(L10n.myPoints)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(NeumorphicColors.text.opacity(0.76))

                        HStack(spacing: 10) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(NeumorphicColors.accent)

                            Text("\(points)")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 14) {
                        Text(L10n.stickers)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(NeumorphicColors.text)

                        HStack(spacing: 16) {
                            ForEach(StickerKind.allCases) { kind in
                                stickerCard(kind)
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NeumorphicColors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.done) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(NeumorphicColors.accent)
                }
            }
        }
    }

    private func stickerCard(_ sticker: StickerKind) -> some View {
        let inventoryCount = inventoryCounts[sticker] ?? 0
        let usedCount = usedCounts[sticker] ?? 0
        let isPlacedOnHome = usedCount > 0
        let hasOwned = inventoryCount > 0
        let canRedeem = points >= sticker.requiredPoints

        return VStack(spacing: 12) {
            Image((hasOwned || canRedeem) ? sticker.unlockedImageName : sticker.lockedImageName)
                .resizable()
                .scaledToFit()
                .frame(height: 110)

            VStack(spacing: 4) {
                Text("\(sticker.requiredPoints) \(L10n.pointsUnit)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor((hasOwned || canRedeem) ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.58))

                if inventoryCount > 0 {
                    Text(L10n.ownedCount(inventoryCount))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.62))
                }
            }

            Button {
                if hasOwned {
                    onAddToHome(sticker)
                } else {
                    onRedeem(sticker)
                }
            } label: {
                Text(hasOwned ? (isPlacedOnHome ? L10n.onHome : L10n.addToHome) : L10n.redeem)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor((canRedeem || hasOwned) ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.42))
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(Color.clear.neumorphicConvex(radius: 17))
                    .opacity((canRedeem || hasOwned) ? 1 : 0.68)
            }
            .buttonStyle(.plain)
            .disabled((!canRedeem && !hasOwned) || isPlacedOnHome)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .background(Color.clear.neumorphicConvex(radius: 22))
        .opacity((hasOwned || canRedeem) ? 1 : 0.9)
    }
}

private struct EditableHomeStickerView: View {
    let placement: HomeStickerPlacement
    let canvasSize: CGSize
    let isEditing: Bool
    let onSelect: () -> Void
    let onUpdate: (HomeStickerPlacement) -> Void
    let onDelete: () -> Void

    @State private var dragStartPlacement: HomeStickerPlacement?
    @State private var magnifyStartScale: Double?

    private var baseStickerWidth: CGFloat {
        placement.kind == .cowCat ? 86 : 100
    }

    private var stickerWidth: CGFloat {
        baseStickerWidth * placement.scale
    }

    var body: some View {
        let position = CGPoint(
            x: canvasSize.width * placement.xRatio,
            y: canvasSize.height * placement.yRatio
        )

        ZStack(alignment: .topTrailing) {
            Image(placement.kind.unlockedImageName)
                .resizable()
                .scaledToFit()
                .frame(width: stickerWidth)
                .shadow(color: NeumorphicColors.darkShadow.opacity(0.16), radius: 6, x: 3, y: 4)
                .overlay {
                    if isEditing {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(NeumorphicColors.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .padding(2)
                    }
                }

            if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(NeumorphicColors.accent))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
        }
        .contentShape(Rectangle())
        .position(position)
        .onTapGesture {
            onSelect()
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard isEditing else { return }

                    let baseline = dragStartPlacement ?? placement
                    if dragStartPlacement == nil {
                        dragStartPlacement = placement
                    }

                    let newX = clamp(
                        baseline.xRatio + value.translation.width / max(canvasSize.width, 1),
                        min: 0.12,
                        max: 0.88
                    )
                    let newY = clamp(
                        baseline.yRatio + value.translation.height / max(canvasSize.height, 1),
                        min: 0.16,
                        max: 0.86
                    )

                    onUpdate(
                        HomeStickerPlacement(
                            id: placement.id,
                            kind: placement.kind,
                            xRatio: newX,
                            yRatio: newY,
                            scale: placement.scale
                        )
                    )
                }
                .onEnded { _ in
                    dragStartPlacement = nil
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    guard isEditing else { return }

                    let baseline = magnifyStartScale ?? placement.scale
                    if magnifyStartScale == nil {
                        magnifyStartScale = placement.scale
                    }

                    let newScale = clamp(baseline * value.magnification, min: 0.7, max: 1.8)
                    onUpdate(
                        HomeStickerPlacement(
                            id: placement.id,
                            kind: placement.kind,
                            xRatio: placement.xRatio,
                            yRatio: placement.yRatio,
                            scale: newScale
                        )
                    )
                }
                .onEnded { _ in
                    magnifyStartScale = nil
                }
        )
    }

    private func clamp(_ value: Double, min lowerBound: Double, max upperBound: Double) -> Double {
        Swift.max(lowerBound, Swift.min(value, upperBound))
    }
}

private struct CommonTasksEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var library = CommonTasksStore.loadLibrary()
    @FocusState private var focusedField: FocusedMyTaskField?

    private enum FocusedMyTaskField: Hashable {
        case task(Int)
        case groupName(UUID)
        case groupTask(UUID, Int)
    }

    var body: some View {
        NavigationView {
            ZStack {
                NeumorphicColors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(L10n.tasks)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 14)], spacing: 14) {
                                ForEach(library.tasks.indices, id: \.self) { index in
                                    taskCard(for: index)
                                }

                                if library.tasks.count < AppSettings.maxCommonTasks {
                                    addTaskCard
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(L10n.groups)
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(NeumorphicColors.text)
                                Spacer()
                                if library.groups.count < AppSettings.maxTaskGroups {
                                    addGroupButton
                                }
                            }

                            VStack(spacing: 14) {
                                ForEach(library.groups.indices, id: \.self) { index in
                                    groupCard(for: index)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 92)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(L10n.myTasksHint)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.66))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .background(NeumorphicColors.background)
            }
            .navigationTitle(L10n.myTasks)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NeumorphicColors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.done) {
                        finalizeLibrary()
                        dismiss()
                    }
                        .fontWeight(.semibold)
                        .foregroundColor(NeumorphicColors.accent)
                }
            }
        }
        .onDisappear {
            finalizeLibrary()
        }
    }

    private func taskCard(for index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()

                Button {
                    library.tasks.remove(at: index)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(NeumorphicColors.accent)
                        .frame(width: 18, height: 18)
                        .neumorphicConvex(radius: 9)
                }
                .buttonStyle(.plain)
            }

            TextField(L10n.taskNumber(index + 1), text: taskBinding(for: index), axis: .vertical)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text)
                .lineLimit(2)
                .focused($focusedField, equals: .task(index))

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(Color.clear.neumorphicConvex(radius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture {
            focusedField = .task(index)
        }
    }

    private var addTaskCard: some View {
        Button {
            library.tasks.append("")
            let newIndex = library.tasks.count - 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .task(newIndex)
            }
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(NeumorphicColors.accent)
                    .frame(width: 34, height: 34)
                    .neumorphicConvex(radius: 17)

                Text(L10n.addTask)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.78))
            }
            .frame(maxWidth: .infinity, minHeight: 104)
            .padding(14)
            .background(Color.clear.neumorphicConvex(radius: 20))
        }
        .buttonStyle(.plain)
    }

    private var addGroupButton: some View {
        Button {
            let newGroup = MyTaskGroup(name: "", tasks: [""])
            library.groups.append(newGroup)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .groupName(newGroup.id)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text(L10n.addGroup)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundColor(NeumorphicColors.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.clear.neumorphicConvex(radius: 14))
        }
        .buttonStyle(.plain)
    }

    private func groupCard(for index: Int) -> some View {
        let group = library.groups[index]

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                TextField(L10n.groupName, text: groupNameBinding(for: group.id))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .focused($focusedField, equals: .groupName(group.id))

                Spacer()

                Button {
                    guard let groupIndex = library.groups.firstIndex(where: { $0.id == group.id }) else { return }
                    library.groups.remove(at: groupIndex)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(NeumorphicColors.accent)
                        .frame(width: 18, height: 18)
                        .neumorphicConvex(radius: 9)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                ForEach(group.tasks.indices, id: \.self) { taskIndex in
                    groupTaskChip(groupID: group.id, index: taskIndex)
                }

                if group.tasks.count < AppSettings.maxTasksPerGroup {
                    addGroupTaskChip(groupID: group.id)
                }
            }
        }
        .padding(16)
        .background(Color.clear.neumorphicConvex(radius: 22))
    }

    private func groupTaskChip(groupID: UUID, index: Int) -> some View {
        HStack(spacing: 8) {
            TextField(L10n.task, text: groupTaskBinding(groupID: groupID, index: index))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text)
                .focused($focusedField, equals: .groupTask(groupID, index))

            Button {
                guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }),
                      library.groups[groupIndex].tasks.indices.contains(index) else { return }
                library.groups[groupIndex].tasks.remove(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(NeumorphicColors.accent.opacity(0.88))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(minHeight: 42)
        .background(Color.clear.neumorphicConvex(radius: 14))
    }

    private func addGroupTaskChip(groupID: UUID) -> some View {
        Button {
            guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }) else { return }
            library.groups[groupIndex].tasks.append("")
            let newIndex = library.groups[groupIndex].tasks.count - 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .groupTask(groupID, newIndex)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                Text(L10n.addTask)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundColor(NeumorphicColors.accent)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(Color.clear.neumorphicConvex(radius: 14))
        }
        .buttonStyle(.plain)
    }

    private func taskBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard library.tasks.indices.contains(index) else { return "" }
                return library.tasks[index]
            },
            set: { newValue in
                guard library.tasks.indices.contains(index) else { return }
                library.tasks[index] = String(newValue.prefix(AppSettings.maxTaskLength))
            }
        )
    }

    private func groupNameBinding(for groupID: UUID) -> Binding<String> {
        Binding(
            get: {
                library.groups.first(where: { $0.id == groupID })?.name ?? ""
            },
            set: { newValue in
                guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }) else { return }
                library.groups[groupIndex].name = String(newValue.prefix(AppSettings.maxTaskLength))
            }
        )
    }

    private func groupTaskBinding(groupID: UUID, index: Int) -> Binding<String> {
        Binding(
            get: {
                guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }),
                      library.groups[groupIndex].tasks.indices.contains(index) else { return "" }
                return library.groups[groupIndex].tasks[index]
            },
            set: { newValue in
                guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }),
                      library.groups[groupIndex].tasks.indices.contains(index) else { return }
                library.groups[groupIndex].tasks[index] = String(newValue.prefix(AppSettings.maxTaskLength))
            }
        )
    }

    private func finalizeLibrary() {
        CommonTasksStore.saveLibrary(library)
        library = CommonTasksStore.loadLibrary()
    }
}

private struct BingoDiaryScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayedMonth = Date()
    @State private var selectedEntry: BingoDiaryEntry?
    @State private var statsRange: BingoDiaryStatsRange = .week

    var body: some View {
        let calendar = Calendar.current
        let startDate = BingoBoardStore.firstSeenDate()
        let today = calendar.startOfDay(for: .now)
        let entries = BingoDiaryStore.entries(inMonthContaining: displayedMonth)
        let entriesByKey = Dictionary(uniqueKeysWithValues: entries.map { (dateKey(for: $0.date), $0) })
        let days = calendarDays(for: displayedMonth, startDate: startDate, endDate: today)
        let weeks = calendarWeeks(from: days)
        let taskCounts = BingoDiaryStore.completedTaskCounts(lastDays: statsRange.days, referenceDate: today)
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
        let canGoToPreviousMonth = calendar.compare(previousMonth, to: startDate, toGranularity: .month) != .orderedAscending
        let canGoToNextMonth = calendar.compare(nextMonth, to: today, toGranularity: .month) != .orderedDescending

        return NavigationView {
            ZStack {
                NeumorphicColors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        HStack {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    displayedMonth = previousMonth
                                }
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(canGoToPreviousMonth ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.28))
                                    .frame(width: 30, height: 30)
                                    .neumorphicConvex(radius: 15)
                            }
                            .buttonStyle(.plain)
                            .disabled(!canGoToPreviousMonth)

                            Spacer()

                            Text(monthTitle(for: displayedMonth))
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)

                            Spacer()

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    displayedMonth = nextMonth
                                }
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(canGoToNextMonth ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.28))
                                    .frame(width: 30, height: 30)
                                    .neumorphicConvex(radius: 15)
                            }
                            .buttonStyle(.plain)
                            .disabled(!canGoToNextMonth)
                        }

                        VStack(spacing: 10) {
                            HStack(spacing: 10) {
                                ForEach(weekdaySymbols(), id: \.self) { symbol in
                                    Text(symbol)
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(NeumorphicColors.text.opacity(0.52))
                                        .frame(maxWidth: .infinity)
                                }
                            }

                            VStack(spacing: 10) {
                                ForEach(weeks.indices, id: \.self) { weekIndex in
                                    HStack(spacing: 10) {
                                        ForEach(weeks[weekIndex].indices, id: \.self) { dayIndex in
                                            let day = weeks[weekIndex][dayIndex]
                                            let entry = entriesByKey[dateKey(for: day.date)]

                                            calendarDayCell(for: day, entry: entry)
                                        }
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(L10n.taskCompletions)
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundColor(NeumorphicColors.text)

                                Spacer()

                                statsRangePicker
                            }

                            if taskCounts.isEmpty {
                                Text(L10n.noTaskCompletions)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(NeumorphicColors.text.opacity(0.6))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(Array(taskCounts.prefix(8)), id: \.task) { item in
                                        HStack(spacing: 12) {
                                            Text(item.task)
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                .foregroundColor(NeumorphicColors.text)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.75)

                                            Text(L10n.completedTimes(item.count))
                                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                                .foregroundColor(NeumorphicColors.text.opacity(0.68))
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .neumorphicConvex(radius: 16)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 88)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(L10n.diaryHint)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.66))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .background(NeumorphicColors.background)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NeumorphicColors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.done) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(NeumorphicColors.accent)
                }

                ToolbarItem(placement: .principal) {
                    Text(L10n.bingoDiary)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                }
            }
        }
        .sheet(item: $selectedEntry) { entry in
            BingoDiaryDetailView(entry: entry)
                .presentationDetents([.height(480)])
                .presentationDragIndicator(.visible)
        }
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.displayLocale
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter.string(from: date)
    }

    private func weekdaySymbols() -> [String] {
        var calendar = Calendar.current
        calendar.locale = AppLanguage.displayLocale
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.displayLocale
        let symbols = formatter.shortStandaloneWeekdaySymbols ?? calendar.shortStandaloneWeekdaySymbols
        let firstWeekdayIndex = max(calendar.firstWeekday - 1, 0)
        let reordered = Array(symbols[firstWeekdayIndex...] + symbols[..<firstWeekdayIndex])

        if AppLanguage.current == .english {
            return reordered.map { $0.uppercased(with: AppLanguage.displayLocale) }
        }

        return reordered
    }

    private func calendarDays(for month: Date, startDate: Date, endDate: Date) -> [DiaryCalendarDay] {
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: startDate)
        let normalizedEnd = calendar.startOfDay(for: endDate)

        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let lastDayOfMonth = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
              let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: lastDayOfMonth) else {
            return []
        }

        let gridStart = firstWeek.start
        let gridEnd = calendar.date(byAdding: .day, value: 7, to: lastWeek.start) ?? lastWeek.end
        var days: [DiaryCalendarDay] = []
        var cursor = gridStart

        while cursor < gridEnd {
            let normalizedDate = calendar.startOfDay(for: cursor)
            days.append(
                DiaryCalendarDay(
                    date: normalizedDate,
                    isCurrentMonth: calendar.isDate(normalizedDate, equalTo: monthInterval.start, toGranularity: .month),
                    isWithinVisibleRange: normalizedDate >= normalizedStart && normalizedDate <= normalizedEnd
                )
            )
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? gridEnd
        }

        return days
    }

    private func calendarWeeks(from days: [DiaryCalendarDay]) -> [[DiaryCalendarDay]] {
        stride(from: 0, to: days.count, by: 7).map { index in
            Array(days[index..<min(index + 7, days.count)])
        }
    }

    private func dateKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private var statsRangePicker: some View {
        HStack(spacing: 8) {
            ForEach(BingoDiaryStatsRange.allCases, id: \.self) { range in
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                        statsRange = range
                    }
                } label: {
                    Text(range.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(statsRange == range ? .white : NeumorphicColors.text.opacity(0.66))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            Capsule()
                                .fill(statsRange == range ? NeumorphicColors.accent : NeumorphicColors.background)
                                .shadow(
                                    color: statsRange == range ? NeumorphicColors.accent.opacity(0.16) : NeumorphicColors.darkShadow.opacity(0.1),
                                    radius: 4,
                                    x: 2,
                                    y: 2
                                )
                                .shadow(
                                    color: Color.white.opacity(statsRange == range ? 0.08 : 0.72),
                                    radius: 4,
                                    x: -2,
                                    y: -2
                                )
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func calendarDayCell(for day: DiaryCalendarDay, entry: BingoDiaryEntry?) -> some View {
        if let entry {
            Button {
                selectedEntry = entry
            } label: {
                calendarDayLabel(for: day, entry: entry)
            }
            .buttonStyle(.plain)
        } else {
            calendarDayLabel(for: day, entry: nil)
        }
    }

    private func calendarDayLabel(for day: DiaryCalendarDay, entry: BingoDiaryEntry?) -> some View {
        let isCompleted = entry?.allTasksCompleted == true
        let hasEntry = entry != nil
        let dayNumber = Calendar.current.component(.day, from: day.date)

        return ZStack {
            if isCompleted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(NeumorphicColors.accent)
                    .frame(width: 40, height: 40)
                    .shadow(color: NeumorphicColors.accent.opacity(0.22), radius: 8, x: 0, y: 4)
                    .shadow(color: Color.white.opacity(0.28), radius: 3, x: 0, y: -1)
            }

            Text("\(dayNumber)")
                .font(.system(size: 14, weight: isCompleted ? .bold : .semibold, design: .rounded))
                .foregroundColor(calendarDayTextColor(for: day, hasEntry: hasEntry, isCompleted: isCompleted))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .contentShape(Rectangle())
    }

    private func calendarDayTextColor(for day: DiaryCalendarDay, hasEntry: Bool, isCompleted: Bool) -> Color {
        if isCompleted {
            return .white
        }

        if hasEntry {
            return NeumorphicColors.text
        }

        if day.isCurrentMonth && day.isWithinVisibleRange {
            return NeumorphicColors.text.opacity(0.34)
        }

        return NeumorphicColors.text.opacity(0.18)
    }
}

private struct DiaryCalendarDay: Identifiable {
    let date: Date
    let isCurrentMonth: Bool
    let isWithinVisibleRange: Bool

    var id: TimeInterval { date.timeIntervalSince1970 }
}

private enum BingoDiaryStatsRange: CaseIterable {
    case week
    case month

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        }
    }

    var title: String {
        switch self {
        case .week: return L10n.last7Days
        case .month: return L10n.last30Days
        }
    }
}

private struct BingoDiaryDetailView: View {
    let entry: BingoDiaryEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                NeumorphicColors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    BingoDiaryBoardView(board: entry.board)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)

                    Spacer()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NeumorphicColors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.done) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(NeumorphicColors.accent)
                }

                ToolbarItem(placement: .principal) {
                    Text(detailTitle)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                }
            }
        }
    }

    private var detailTitle: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.displayLocale
        formatter.dateStyle = .long
        return formatter.string(from: entry.date)
    }
}

private struct BingoDiaryBoardView: View {
    let board: SavedBoard

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 6
            let totalSpacing = spacing * CGFloat(max(board.gridSize - 1, 0))
            let cellSize = (geo.size.width - 24 - totalSpacing) / CGFloat(max(board.gridSize, 1))

            VStack(spacing: spacing) {
                ForEach(0..<board.gridSize, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<board.gridSize, id: \.self) { col in
                            if row < board.cells.count && col < board.cells[row].count {
                                BingoDiaryCellView(
                                    cell: board.cells[row][col],
                                    isInBingoLine: isInCompletedLine(row: row, col: col),
                                    isLocked: isLocked(row: row, col: col),
                                    cellSize: cellSize
                                )
                            }
                        }
                    }
                }
            }
            .padding(8)
            .padding(12)
            .neumorphicConvex(radius: 20)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func isInCompletedLine(row: Int, col: Int) -> Bool {
        for line in board.completedLines {
            switch line {
            case .row(let r): if r == row { return true }
            case .column(let c): if c == col { return true }
            case .diagonalMain: if row == col { return true }
            case .diagonalAnti: if row + col == board.gridSize - 1 { return true }
            }
        }
        return false
    }

    private func isLocked(row: Int, col: Int) -> Bool {
        let activeForced = activeForcedPositions
        guard !activeForced.isEmpty else { return false }
        return !activeForced.contains(DiaryPosition(row: row, col: col))
    }

    private var activeForcedPositions: Set<DiaryPosition> {
        var positions: Set<DiaryPosition> = []

        for row in board.cells.indices {
            for col in board.cells[row].indices {
                let cell = board.cells[row][col]
                if cell.isForced && !cell.isCompleted && !cell.isEmpty {
                    positions.insert(DiaryPosition(row: row, col: col))
                }
            }
        }

        return positions
    }

    private struct DiaryPosition: Hashable {
        let row: Int
        let col: Int
    }
}

private struct BingoDiaryCellView: View {
    let cell: BingoCell
    let isInBingoLine: Bool
    let isLocked: Bool
    let cellSize: CGFloat

    @AppStorage(AppSettings.themeKey) private var themeRawValue = AppTheme.sky.rawValue
    private var activeTheme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .sky }
    private var bingoSurfaceColor: Color { activeTheme.bingoSurfaceColor }
    private var bingoSurfaceShadowColor: Color { activeTheme.bingoSurfaceShadowColor }

    var body: some View {
        ZStack {
            backgroundSurface

            if isInBingoLine {
                bingoLineContent
            } else if !cell.isEmpty {
                VStack(spacing: 2) {
                    Text(cell.text)
                        .font(.system(size: dynamicFontSize, weight: .medium))
                        .foregroundColor(isLocked ? NeumorphicColors.text.opacity(0.35) : NeumorphicColors.text)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.5)
                        .padding(8)

                    if cell.isCompleted && !isLocked {
                        completionIcon(isLarge: false)
                    }
                }
            }

            if isLocked {
                lockOverlay
            }
        }
        .frame(width: cellSize, height: cellSize)
    }

    private var dynamicFontSize: CGFloat {
        let baseSize = min(cellSize * 0.22, 16.0)
        return cell.text.count > 6 ? max(baseSize * 0.8, 9) : baseSize
    }

    private var bingoLineContent: some View {
        VStack(spacing: 4) {
            Text(cell.text)
                .font(.system(size: dynamicFontSize, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            if !isLocked {
                completionIcon(isLarge: false, usesGoldSurface: true)
            }
        }
    }

    private var backgroundSurface: some View {
        Group {
            if isInBingoLine {
                RoundedRectangle(cornerRadius: 12)
                    .fill(bingoSurfaceColor)
                    .shadow(color: bingoSurfaceShadowColor.opacity(0.28), radius: 7, x: 4, y: 4)
                    .shadow(color: Color.white.opacity(0.42), radius: 7, x: -4, y: -4)
            } else if cell.isCompleted {
                Color.clear
                    .neumorphicConcave(radius: 12)
            } else {
                Color.clear
                    .neumorphicConvex(radius: 12)
            }
        }
        .overlay {
            if isLocked && !isInBingoLine {
                RoundedRectangle(cornerRadius: 12)
                    .fill(NeumorphicColors.background.opacity(0.62))
            }
        }
    }

    private func completionIcon(isLarge: Bool, usesGoldSurface: Bool = false) -> some View {
        let size = isLarge
            ? min(max(cellSize * 0.42, 34), 52)
            : min(max(cellSize * 0.16, 16), 22)

        return ZStack {
            Circle()
                .fill(isLarge || usesGoldSurface ? bingoSurfaceColor : NeumorphicColors.background)
                .shadow(
                    color: ((isLarge || usesGoldSurface) ? bingoSurfaceShadowColor : NeumorphicColors.darkShadow).opacity(0.3),
                    radius: isLarge ? 6 : 4,
                    x: isLarge ? 4 : 3,
                    y: isLarge ? 4 : 3
                )
                .shadow(
                    color: ((isLarge || usesGoldSurface) ? Color.white : NeumorphicColors.lightShadow).opacity(0.85),
                    radius: isLarge ? 6 : 4,
                    x: isLarge ? -4 : -3,
                    y: isLarge ? -4 : -3
                )

            Image(systemName: "checkmark")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor((isLarge || usesGoldSurface) ? .white : activeTheme.color)
        }
        .frame(width: size, height: size)
        .padding(.top, isLarge ? 0 : 6)
    }

    private var lockOverlay: some View {
        let size = min(max(cellSize * 0.22, 20), 28)

        return ZStack {
            Circle()
                .fill(NeumorphicColors.background)
                .shadow(color: NeumorphicColors.darkShadow.opacity(0.25), radius: 4, x: 2, y: 2)
                .shadow(color: NeumorphicColors.lightShadow.opacity(0.85), radius: 4, x: -2, y: -2)

            Image(systemName: "lock.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(NeumorphicColors.text.opacity(0.55))
        }
        .frame(width: size, height: size)
    }
}

private struct SidebarGlassToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.interpolatingSpring(stiffness: 210, damping: 18)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? NeumorphicColors.accent.opacity(0.78) : Color.white.opacity(0.18))
                    .frame(width: 42, height: 24)
                    .overlay {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(configuration.isOn ? 0.22 : 0.12),
                                        Color.white.opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.34), lineWidth: 0.8)
                    }
                    .shadow(color: NeumorphicColors.darkShadow.opacity(0.12), radius: 4, x: 1, y: 1)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.9), Color.white.opacity(0.68)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 18, height: 18)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.58), lineWidth: 0.6)
                    }
                    .shadow(color: NeumorphicColors.darkShadow.opacity(0.14), radius: 4, x: 1.5, y: 1.5)
                    .shadow(color: Color.white.opacity(0.28), radius: 1.5, x: -0.8, y: -0.8)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct BoardCountdownSheet: View {
    let countdownEndsAt: Date?
    let onSave: (Int?) -> Void
    let onCancel: () -> Void

    @State private var isCountdownEnabled: Bool
    @State private var countdownHours: Int
    @State private var countdownMinutes: Int
    private let initialCountdownTotalMinutes: Int?

    init(countdownEndsAt: Date?, onSave: @escaping (Int?) -> Void, onCancel: @escaping () -> Void) {
        let countdownTotalMinutes = Self.remainingMinutes(until: countdownEndsAt)
        self.countdownEndsAt = countdownEndsAt
        self.onSave = onSave
        self.onCancel = onCancel
        initialCountdownTotalMinutes = countdownTotalMinutes

        let initialTotalMinutes = countdownTotalMinutes ?? 60
        _isCountdownEnabled = State(initialValue: countdownTotalMinutes != nil)
        _countdownHours = State(initialValue: min(initialTotalMinutes / 60, 24))
        _countdownMinutes = State(initialValue: initialTotalMinutes % 60)
    }

    var body: some View {
        NavigationView {
            ZStack {
                NeumorphicColors.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.boardCountdownTitle)
                                    .font(.system(.headline, design: .rounded).weight(.bold))
                                    .foregroundColor(NeumorphicColors.text)

                                Text(L10n.boardCountdownDescription)
                                    .font(.caption)
                                    .foregroundColor(NeumorphicColors.text.opacity(0.6))
                            }

                            Spacer()

                            Toggle("", isOn: $isCountdownEnabled)
                                .labelsHidden()
                                .toggleStyle(NeumorphicSwitchToggleStyle())
                        }

                        if isCountdownEnabled {
                            HStack(spacing: 12) {
                                countdownValuePicker(title: L10n.hours, valueText: L10n.hourValue(countdownHours)) {
                                    ForEach(0...24, id: \.self) { hour in
                                        Button(L10n.hourValue(hour)) {
                                            countdownHours = hour
                                            if countdownHours == 24 {
                                                countdownMinutes = 0
                                            }
                                        }
                                    }
                                }

                                countdownValuePicker(title: L10n.minutes, valueText: L10n.minuteValue(countdownMinutes)) {
                                    ForEach(minuteOptions, id: \.self) { minute in
                                        Button(L10n.minuteValue(minute)) {
                                            countdownMinutes = minute
                                        }
                                        .disabled(countdownHours == 24 && minute != 0)
                                    }
                                }
                            }

                            Text(countdownSummaryText)
                                .font(.caption)
                                .foregroundColor(NeumorphicColors.text.opacity(0.62))
                        }
                    }

                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NeumorphicColors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { onCancel() }
                        .foregroundColor(NeumorphicColors.text.opacity(0.8))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.save) { onSave(resolvedTotalMinutes) }
                        .fontWeight(.semibold)
                        .foregroundColor(NeumorphicColors.accent)
                }
            }
            .onChange(of: countdownHours) { _, newHours in
                if newHours == 24 {
                    countdownMinutes = 0
                }
            }
        }
    }

    private var minuteOptions: [Int] {
        countdownHours == 24 ? [0] : Array(stride(from: 0, through: 55, by: 5))
    }

    private var totalMinutes: Int {
        min((countdownHours * 60) + countdownMinutes, BingoViewModel.maxCountdownMinutes)
    }

    private var resolvedTotalMinutes: Int? {
        guard isCountdownEnabled else { return nil }
        return max(totalMinutes, 1)
    }

    private var countdownSummaryText: String {
        if totalMinutes == BingoViewModel.maxCountdownMinutes {
            return L10n.boardWillClearIn24Hours
        }
        return L10n.boardWillClearIn(hours: countdownHours, minutes: countdownMinutes)
    }

    @ViewBuilder
    private func countdownValuePicker(title: String, valueText: String, @ViewBuilder content: () -> some View) -> some View {
        Menu {
            content()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(NeumorphicColors.text.opacity(0.66))

                HStack {
                    Text(valueText)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(NeumorphicColors.text)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(NeumorphicColors.accent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.clear.neumorphicConvex(radius: 12))
            }
        }
        .buttonStyle(.plain)
    }

    private static func remainingMinutes(until date: Date?) -> Int? {
        guard let date, date > Date() else { return nil }
        let seconds = date.timeIntervalSinceNow
        let totalMinutes = Int(ceil(seconds / 60))
        return min(max(totalMinutes, 1), BingoViewModel.maxCountdownMinutes)
    }
}

// MARK: - Celebration View
struct CelebrationView: View {
    @State private var confettiItems: [ConfettiItem] = []

    struct ConfettiItem: Identifiable {
        let id: Int
        let emoji: String
        let fontSize: CGFloat
        let startX: CGFloat
        let endX: CGFloat
        let duration: Double
        let delay: Double
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(confettiItems) { item in
                    ConfettiPiece(item: item, height: geo.size.height)
                }
            }
            .onAppear { generateConfetti(in: geo.size) }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func generateConfetti(in size: CGSize) {
        let emojis = ["🎉", "⭐️", "✨", "🎊", "💫", "🌟", "🎯", "🏆"]
        confettiItems = (0..<25).map { i in
            ConfettiItem(
                id: i,
                emoji: emojis[i % emojis.count],
                fontSize: CGFloat.random(in: 18...34),
                startX: CGFloat.random(in: 0...size.width),
                endX: CGFloat.random(in: -60...60),
                duration: Double.random(in: 1.2...2.2),
                delay: Double.random(in: 0...0.6)
            )
        }
    }
}

struct ConfettiPiece: View {
    let item: CelebrationView.ConfettiItem
    let height: CGFloat
    @State private var animate = false

    var body: some View {
        Text(item.emoji)
            .font(.system(size: item.fontSize))
            .offset(
                x: item.startX + (animate ? item.endX : 0),
                y: animate ? height + 50 : -50
            )
            .opacity(animate ? 0 : 1)
            .onAppear {
                withAnimation(.easeIn(duration: item.duration).delay(item.delay)) {
                    animate = true
                }
            }
    }
}
