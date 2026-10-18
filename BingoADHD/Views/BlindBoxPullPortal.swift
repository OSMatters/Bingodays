import SwiftUI
import Lottie

private struct BlindBoxEntranceReadyKey: EnvironmentKey {
    static var defaultValue: Bool { true }
}

private struct BlindBoxWindowSafeAreaInsetsKey: EnvironmentKey {
    static var defaultValue: EdgeInsets { EdgeInsets() }
}

extension EnvironmentValues {
    var blindBoxEntranceReady: Bool {
        get { self[BlindBoxEntranceReadyKey.self] }
        set { self[BlindBoxEntranceReadyKey.self] = newValue }
    }

    var blindBoxWindowSafeAreaInsets: EdgeInsets {
        get { self[BlindBoxWindowSafeAreaInsetsKey.self] }
        set { self[BlindBoxWindowSafeAreaInsetsKey.self] = newValue }
    }
}

/// The scroll view reports its resting top, so scrolling back through rewards
/// never accidentally becomes a blind-box navigation gesture.
struct RewardsScrollTopPreference: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

enum BlindBoxPullInteraction {
    /// Navigation is deliberately more intentional than ordinary list scrolling.
    /// The rope remains directly tappable; a drag must start from its top area.
    static let releaseDistance: CGFloat = 84
    static let topActivationHeight: CGFloat = 154

    static func ropeCenterY(circleBottom: CGFloat, size: CGSize, diameter: CGFloat) -> CGFloat {
        // The first rope bead is at x=13 in the 68px-wide animation,
        // displayed at 45pt inside a button centered at x=44.
        let artworkScale: CGFloat = 45.0 / 68.0
        let ropeX: CGFloat = 21.5 + 13.0 * artworkScale
        let radius = diameter / 2
        let distanceX = ropeX - size.width / 2
        let arcInset = radius - sqrt(max(0, radius * radius - distanceX * distanceX))
        let arcY = circleBottom - arcInset
        // The 99px animation fits to 45pt wide, giving a 65.51pt height.
        // Overlap its top with the arc by 2pt so no detached gap is visible.
        let halfArtworkHeight = 49.5 * artworkScale
        return max(38, arcY + halfArtworkHeight - 2)
    }

    static func canBegin(
        scrollTop: CGFloat,
        startLocation: CGPoint,
        translation: CGSize
    ) -> Bool {
        scrollTop >= -2 && startLocation.y <= topActivationHeight &&
            translation.height > 0 && translation.height > abs(translation.width)
    }

    static func shouldEnter(translation: CGSize) -> Bool {
        translation.height >= releaseDistance
    }

    static func coveredBottom(size: CGSize, diameter: CGFloat) -> CGFloat {
        let radius = diameter / 2
        let sagitta = radius - sqrt(max(0, radius * radius - size.width * size.width / 4))
        return size.height + sagitta + 24
    }
}

struct BlindBoxPullPortal<Rewards: View, BlindBox: View>: View {
    let enteredFromBottomTab: Bool
    var isEnabled = true
    var isActive = true
    let isRewardsSubpagePresented: Bool
    let onPresentationChange: (Bool) -> Void
    @ViewBuilder let rewards: () -> Rewards
    @ViewBuilder let blindBox: (@escaping () -> Void) -> BlindBox

    private enum Phase { case idle, tutorial, hint, dragging, entering, open, returning }
    // v2 intentionally starts clean at the feature launch so existing users
    // receive the same first-entry instruction as newly registered users.
    @AppStorage("blindBox.pullGuideCompleted.v2") private var guideCompleted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var tutorialStart = Date.now
    @State private var cutoutTopInset: CGFloat?
    @State private var windowSafeAreaInsets = EdgeInsets()
    @State private var phase: Phase = .idle
    @State private var scrollTop: CGFloat = 0
    @State private var circleBottom: CGFloat = -30
    @State private var rewardsOpacity: Double = 1
    @State private var cabinetOpacity: Double = 0
    @State private var cabinetOffset: CGFloat = 100
    @State private var mountsBlindBox = false
    @State private var gestureEligible: Bool?
    @State private var gestureOrigin: CGFloat = 0

    private var openLabel: String {
        L10n.tr("Explore Blind Boxes", zhHans: "探索盲盒", zhHant: "探索盲盒", ja: "ブラインドボックスへ")
    }

    private var canScheduleHints: Bool {
        isActive && isEnabled && scenePhase == .active && !mountsBlindBox &&
            !isRewardsSubpagePresented && (phase == .idle || phase == .hint)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let diameter = max(size.width * 3, size.height * 2.4)
            ZStack(alignment: .topLeading) {
                // Keep a stable backdrop while the rewards content fades.
                PointsRewardBackground()
                    .ignoresSafeArea()
                rewards()
                    .environment(\.blindBoxWindowSafeAreaInsets, windowSafeAreaInsets)
                    .opacity(rewardsOpacity)
                    .allowsHitTesting(!mountsBlindBox && phase != .tutorial)
                    .accessibilityHidden(mountsBlindBox || phase == .tutorial)
                    .onPreferenceChange(RewardsScrollTopPreference.self) { scrollTop = $0 }

                if phase == .tutorial {
                    Color.black.opacity(0.6)
                        .contentShape(Rectangle())
                        .onTapGesture { dismissGuide() }
                    tutorial(size: size)
                }

                Image("BlindBoxPullCircle")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: diameter, height: diameter)
                    .position(x: size.width / 2, y: circleBottom - diameter / 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                if isEnabled && (phase == .idle || phase == .hint || phase == .dragging) {
                    Button { enter(size: size, diameter: diameter) } label: {
                        BlindBoxLottie(name: "blinbox_la", loop: true, still: reduceMotion || !isActive || isRewardsSubpagePresented)
                            .frame(width: 45, height: 66)
                            .frame(width: 60, height: 76)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(openLabel)
                    .position(x: 44, y: BlindBoxPullInteraction.ropeCenterY(
                        circleBottom: circleBottom, size: size, diameter: diameter
                    ))
                    .opacity(isRewardsSubpagePresented ? 0 : 1)
                    .allowsHitTesting(!isRewardsSubpagePresented)
                }

                if phase == .hint {
                    BlindBoxLottie(name: cutoutTopInset == nil ? "blindbox_shou" : "blindbox_shou_hand", still: reduceMotion || !isActive || isRewardsSubpagePresented)
                        .id(cutoutTopInset == nil)
                        .frame(width: 108, height: 100)
                        // The hand matte begins about 46pt into this 100pt view.
                        // Anchor that edge to the window's top safe-area boundary.
                        .position(x: size.width / 2, y: cutoutTopInset.map { $0 + 4 } ?? max(16, circleBottom + 8))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                if phase == .dragging {
                    VStack(spacing: 8) {
                        BlindBoxLottie(name: "blinbox_box", loop: true, still: reduceMotion || !isActive || isRewardsSubpagePresented)
                            .frame(width: 60, height: 60)
                        Text(L10n.tr("Release to enter Blind Boxes", zhHans: "下拉后松手，进入盲盒页", zhHant: "下拉後鬆手，進入盲盒頁", ja: "指を離してブラインドボックスへ"))
                            .font(.appSystem(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                        Image(systemName: "chevron.down")
                            .foregroundStyle(.white)
                    }
                    .frame(width: size.width)
                    .position(x: size.width / 2, y: max(90, circleBottom - 75))
                    .opacity(min(1, max(0, circleBottom / 140)))
                    .allowsHitTesting(false)
                }

                if mountsBlindBox {
                    blindBox { close() }
                        .environment(\.blindBoxEntranceReady, phase == .open)
                        .opacity(cabinetOpacity)
                        .offset(y: reduceMotion ? 0 : cabinetOffset)
                        .allowsHitTesting(phase == .open)
                        .accessibilityHidden(phase != .open)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .contentShape(Rectangle())
            // The rewards grid owns ordinary vertical drags. The parent only
            // observes a deliberate pull that starts around the rope at top.
            .simultaneousGesture(pullGesture(size: size, diameter: diameter))
            .task(id: canScheduleHints && !reduceMotion) {
                guard canScheduleHints else { return }
                if !guideCompleted {
                    tutorialStart = .now
                    phase = .tutorial
                    return
                }
                // The rope loops independently. Only the hand has a quiet interval.
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    guard canScheduleHints else { return }
                    phase = .hint
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { circleBottom = 52 }
                    do { try await Task.sleep(for: .seconds(2.806)) } catch { return }
                    guard canScheduleHints, phase == .hint else { return }
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { circleBottom = -30 }
                    phase = .idle
                }
            }
        }
        .ignoresSafeArea()
        .onChange(of: reduceMotion) { _, reduced in
            guard reduced, phase == .hint else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                circleBottom = -30
                phase = .idle
            }
        }
        .background {
            BlindBoxCutoutProbe { insets in
                let hasCutout = UIDevice.current.userInterfaceIdiom == .phone &&
                    max(insets.top, max(insets.left, insets.right)) >= 44
                cutoutTopInset = hasCutout ? insets.top : nil
                windowSafeAreaInsets = EdgeInsets(
                    top: insets.top,
                    leading: insets.left,
                    bottom: insets.bottom,
                    trailing: insets.right
                )
            }
                .allowsHitTesting(false)
        }
        .onChange(of: scenePhase) { _, scene in
            if scene != .active && phase == .hint {
                phase = .idle
                circleBottom = -30
            }
        }
        .onChange(of: isRewardsSubpagePresented) { _, presented in
            if presented && !mountsBlindBox {
                phase = .idle
                circleBottom = -30
            }
        }
        .onChange(of: suppressesTabBar, initial: true) { _, value in
            onPresentationChange(value)
        }
        .onChange(of: "\(isActive):\(phase):\(mountsBlindBox)", initial: true) { _, state in
            if AppDebugFlags.tabGlassTrace {
                print("[TabGlass] portal active:phase:mounted=\(state)")
            }
        }
        .onChange(of: isActive) { _, active in
            guard !active else { return }
            phase = .idle
            mountsBlindBox = false
            circleBottom = -30
            rewardsOpacity = 1
            cabinetOpacity = 0
            cabinetOffset = 100
            gestureEligible = nil
        }
    }

    private var suppressesTabBar: Bool {
        isActive && (mountsBlindBox || phase == .tutorial || phase == .dragging)
    }

    private func tutorial(size: CGSize) -> some View {
        TimelineView(.animation(paused: reduceMotion || scenePhase != .active)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(tutorialStart))
            let progress = elapsed.truncatingRemainder(dividingBy: 2.104) / 2.104
            let dividerY = min(max(142, size.height * 0.18), 166)
            // Match scroll_down.json: hand descends at frames 0–36,
            // returns at 36–72, then rests until the next loop (126.24 frames).
            let frame = progress * 126.24
            let pull = frame < 36 ? frame / 36 : max(0, (72 - frame) / 36)
            ZStack(alignment: .topLeading) {
                Button {
                    enter(size: size, diameter: max(size.width * 3, size.height * 2.4))
                } label: {
                    BlindBoxLottie(name: "blinbox_la", loop: true, still: reduceMotion || !isActive || isRewardsSubpagePresented)
                        .frame(width: 45, height: 66)
                        .frame(width: 60, height: 76)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .accessibilityLabel(openLabel)
                    .position(x: 44, y: 38 + (reduceMotion ? 0 : pull * 11.52 * 86 / 111))

                // The hand demonstrates the gesture above the boundary; the
                // caption keeps the exact eligible pull area unambiguous.
                BlindBoxLottie(name: "scroll_down", still: reduceMotion || !isActive || isRewardsSubpagePresented, progress: progress)
                    .frame(width: 98, height: 92)
                    .position(x: size.width / 2, y: dividerY - 61)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                Image(systemName: "chevron.down")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .position(x: size.width / 2, y: dividerY - 15)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                Rectangle()
                    .stroke(
                        Color.white.opacity(0.92),
                        style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
                    )
                    .frame(width: max(0, size.width - 12), height: 1.5)
                    .position(x: size.width / 2, y: dividerY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                Text(L10n.tr(
                    "Swipe down in this area to explore Blind Boxes",
                    zhHans: "此区域下滑探索盲盒游戏～",
                    zhHant: "此區域下滑探索盲盒遊戲～",
                    ja: "このエリアを下にスワイプしてブラインドボックスへ"
                ))
                .font(.appSystem(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: size.width - 32)
                .position(x: size.width / 2, y: dividerY + 32)
                .allowsHitTesting(false)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private func dismissGuide() {
        guideCompleted = true
        phase = .idle
    }

    private func pullGesture(size: CGSize, diameter: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard isActive, isEnabled, !mountsBlindBox, !isRewardsSubpagePresented else { return }
                if gestureEligible == nil {
                    gestureEligible = BlindBoxPullInteraction.canBegin(
                        scrollTop: scrollTop,
                        startLocation: value.startLocation,
                        translation: value.translation
                    )
                    gestureOrigin = circleBottom
                }
                guard gestureEligible == true else { return }
                phase = .dragging
                circleBottom = gestureOrigin + max(0, value.translation.height) * 0.95
                rewardsOpacity = 1 - min(0.72, max(0, value.translation.height) / size.height)
                if value.location.y >= size.height - 24 && BlindBoxPullInteraction.shouldEnter(translation: value.translation) {
                    enter(size: size, diameter: diameter)
                }
            }
            .onEnded { value in
                defer { gestureEligible = nil }
                guard gestureEligible == true, phase == .dragging else { return }
                if BlindBoxPullInteraction.shouldEnter(translation: value.translation) {
                    enter(size: size, diameter: diameter)
                } else {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0)) {
                        circleBottom = -30
                        rewardsOpacity = 1
                        phase = .idle
                    }
                }
            }
    }

    private func enter(size: CGSize, diameter: CGFloat) {
        guard isActive, !mountsBlindBox else { return }
        guideCompleted = true
        phase = .entering
        mountsBlindBox = true
        // The lower curved edge must pass the bottom corners, not just the center.
        withAnimation(reduceMotion ? nil : .timingCurve(0.32, 0.05, 0.18, 1, duration: 0.48)) {
            circleBottom = BlindBoxPullInteraction.coveredBottom(size: size, diameter: diameter)
            rewardsOpacity = 0
        }
        withAnimation(reduceMotion ? .linear(duration: 0.18) : .timingCurve(0.2, 0.65, 0.2, 1, duration: 0.42).delay(0.12), completionCriteria: .logicallyComplete) {
            cabinetOffset = 0
            cabinetOpacity = 1
        } completion: {
            guard phase == .entering else { return }
            phase = .open
        }
    }

    private func close() {
        guard phase == .open else { return }
        phase = .returning
        withAnimation(reduceMotion ? .linear(duration: 0.18) : .smooth(duration: 0.3), completionCriteria: .logicallyComplete) {
            cabinetOpacity = 0
            cabinetOffset = 100
            circleBottom = -30
            rewardsOpacity = 1
        } completion: {
            guard phase == .returning else { return }
            mountsBlindBox = false
            phase = .idle
        }
    }
}

/// Use the presenting window, not a hardcoded list of phone models. Extended
/// phone safe-area insets cover both notches and islands; iPads keep the artwork.
private struct BlindBoxCutoutProbe: UIViewRepresentable {
    let onChange: (UIEdgeInsets) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onChange = onChange
    }

    final class ProbeView: UIView {
        var onChange: ((UIEdgeInsets) -> Void)?
        private var lastInsets: UIEdgeInsets?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            reportInsets()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            reportInsets()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            reportInsets()
        }

        private func reportInsets() {
            guard let window, lastInsets != window.safeAreaInsets else { return }
            let insets = window.safeAreaInsets
            lastInsets = insets
            // Publish outside UIKit's layout pass to avoid mutating SwiftUI state
            // while the enclosing hierarchy is being laid out.
            Task { @MainActor [weak self] in
                guard let self, self.window != nil, self.lastInsets == insets else { return }
                self.onChange?(insets)
            }
        }
    }
}

/// One UIKit animation view per asset; SwiftUI drag updates do not restart playback.
private struct BlindBoxLottie: UIViewRepresentable {
    let name: String
    var loop = false
    var still = false
    var progress: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    final class Coordinator {
        var wasPaused = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private var shouldPause: Bool { still || reduceMotion || scenePhase != .active }

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView(name: name, subdirectory: "BlindBoxMotion")
        view.contentMode = .scaleAspectFit
        view.backgroundBehavior = .pause
        view.isUserInteractionEnabled = false
        view.loopMode = loop ? .loop : .playOnce
        context.coordinator.wasPaused = shouldPause
        if shouldPause {
            view.currentProgress = 0.5
        } else if let progress {
            view.currentProgress = progress
        } else {
            view.play()
        }
        return view
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {
        if shouldPause {
            uiView.pause()
            if still || reduceMotion { uiView.currentProgress = 0.5 }
        } else if let progress {
            uiView.currentProgress = progress
        } else if context.coordinator.wasPaused {
            uiView.play()
        }
        context.coordinator.wasPaused = shouldPause
    }

    static func dismantleUIView(_ uiView: LottieAnimationView, coordinator: Coordinator) {
        uiView.stop()
    }
}
