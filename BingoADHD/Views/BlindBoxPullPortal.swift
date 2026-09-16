import SwiftUI
import Lottie

private struct BlindBoxEntranceReadyKey: EnvironmentKey {
    static var defaultValue: Bool { true }
}

extension EnvironmentValues {
    var blindBoxEntranceReady: Bool {
        get { self[BlindBoxEntranceReadyKey.self] }
        set { self[BlindBoxEntranceReadyKey.self] = newValue }
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
    static let releaseDistance: CGFloat = 28

    static func ropeCenterY(circleBottom: CGFloat, size: CGSize, diameter: CGFloat) -> CGFloat {
        // The first rope bead is at x=13 in the 68px-wide animation,
        // displayed at 45pt inside a button centered at x=44.
        let ropeX: CGFloat = 44 - 45 / 2 + 13 * 45 / 68
        let radius = diameter / 2
        let distanceX = ropeX - size.width / 2
        let arcInset = radius - sqrt(max(0, radius * radius - distanceX * distanceX))
        let arcY = circleBottom - arcInset
        // The 99px animation fits to 45pt wide, giving a 65.51pt height.
        // Overlap its top with the arc by 2pt so no detached gap is visible.
        return max(38, arcY + (99 * 45 / 68) / 2 - 2)
    }

    static func canBegin(scrollTop: CGFloat, translation: CGSize) -> Bool {
        scrollTop >= -2 && translation.height > 0 && translation.height > abs(translation.width)
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
    let isRewardsSubpagePresented: Bool
    let onPresentationChange: (Bool) -> Void
    let onNavigationOpacityChange: (Double) -> Void
    @ViewBuilder let rewards: () -> Rewards
    @ViewBuilder let blindBox: (@escaping () -> Void) -> BlindBox

    private enum Phase { case idle, tutorial, hint, dragging, entering, open, returning }
    @AppStorage("blindBox.pullGuideCompleted.v1") private var guideCompleted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var tutorialStart = Date.now
    @State private var cutoutTopInset: CGFloat?
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
        isEnabled && scenePhase == .active && !mountsBlindBox &&
            !isRewardsSubpagePresented && (phase == .idle || phase == .hint)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let diameter = max(size.width * 3, size.height * 2.4)
            ZStack(alignment: .topLeading) {
                rewards()
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
                        BlindBoxLottie(name: "blinbox_la", loop: true, still: reduceMotion)
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
                    BlindBoxLottie(name: cutoutTopInset == nil ? "blindbox_shou" : "blindbox_shou_hand", still: reduceMotion)
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
                        BlindBoxLottie(name: "blinbox_box", loop: true, still: reduceMotion)
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
            .simultaneousGesture(pullGesture(size: size, diameter: diameter))
            .task(id: canScheduleHints) {
                guard canScheduleHints else { return }
                if enteredFromBottomTab && !guideCompleted {
                    tutorialStart = .now
                    phase = .tutorial
                    onNavigationOpacityChange(0.4)
                    return
                }
                // The rope loops independently. Only the hand has a quiet interval.
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
        .background {
            BlindBoxCutoutProbe { cutoutTopInset = $0 }
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
                onNavigationOpacityChange(1)
            }
        }
        .onDisappear {
            onNavigationOpacityChange(1)
            onPresentationChange(false)
        }
    }

    private func tutorial(size: CGSize) -> some View {
        TimelineView(.animation(paused: reduceMotion || scenePhase != .active)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(tutorialStart))
            let progress = elapsed.truncatingRemainder(dividingBy: 2.104) / 2.104
            // Match scroll_down.json: hand descends at frames 0–36,
            // returns at 36–72, then rests until the next loop (126.24 frames).
            let frame = progress * 126.24
            let pull = frame < 36 ? frame / 36 : max(0, (72 - frame) / 36)
            ZStack(alignment: .topLeading) {
                Button {
                    enter(size: size, diameter: max(size.width * 3, size.height * 2.4))
                } label: {
                    BlindBoxLottie(name: "blinbox_la", loop: true, still: reduceMotion)
                        .frame(width: 45, height: 66)
                        .frame(width: 60, height: 76)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .accessibilityLabel(openLabel)
                    .position(x: 44, y: 38 + (reduceMotion ? 0 : pull * 11.52 * 86 / 111))
                VStack(spacing: 14) {
            BlindBoxLottie(name: "scroll_down", still: reduceMotion, progress: progress)
                .frame(width: 90, height: 86)
            Text(L10n.tr("Swipe down to explore Blind Boxes", zhHans: "下滑探索盲盒游戏～", zhHant: "下滑探索盲盒遊戲～", ja: "下にスワイプしてボックスを探そう"))
                .font(.appSystem(size: 16, weight: .bold))
                .foregroundStyle(.white)
            Image(systemName: "chevron.down")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: size.width)
        .position(x: size.width / 2, y: size.height * 0.46)
        .allowsHitTesting(false)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private func dismissGuide() {
        guideCompleted = true
        phase = .idle
        onNavigationOpacityChange(1)
    }

    private func pullGesture(size: CGSize, diameter: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .local)
            .onChanged { value in
                guard isEnabled, !mountsBlindBox, !isRewardsSubpagePresented else { return }
                if gestureEligible == nil {
                    gestureEligible = BlindBoxPullInteraction.canBegin(scrollTop: scrollTop, translation: value.translation)
                    gestureOrigin = circleBottom
                }
                guard gestureEligible == true else { return }
                phase = .dragging
                circleBottom = gestureOrigin + max(0, value.translation.height) * 0.95
                rewardsOpacity = 1 - min(0.72, max(0, value.translation.height) / size.height)
                onNavigationOpacityChange(rewardsOpacity)
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
                        onNavigationOpacityChange(1)
                        phase = .idle
                    }
                }
            }
    }

    private func enter(size: CGSize, diameter: CGFloat) {
        guard !mountsBlindBox else { return }
        guideCompleted = true
        phase = .entering
        mountsBlindBox = true
        // The lower curved edge must pass the bottom corners, not just the center.
        withAnimation(reduceMotion ? nil : .timingCurve(0.32, 0.05, 0.18, 1, duration: 0.48)) {
            circleBottom = BlindBoxPullInteraction.coveredBottom(size: size, diameter: diameter)
            rewardsOpacity = 0
            onNavigationOpacityChange(0)
        }
        withAnimation(reduceMotion ? .linear(duration: 0.18) : .timingCurve(0.2, 0.65, 0.2, 1, duration: 0.42).delay(0.12), completionCriteria: .logicallyComplete) {
            cabinetOffset = 0
            cabinetOpacity = 1
        } completion: {
            guard phase == .entering else { return }
            phase = .open
            onPresentationChange(true)
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
            mountsBlindBox = false
            phase = .idle
            onPresentationChange(false)
            onNavigationOpacityChange(1)
        }
    }
}

/// Use the presenting window, not a hardcoded list of phone models. Extended
/// phone safe-area insets cover both notches and islands; iPads keep the artwork.
private struct BlindBoxCutoutProbe: UIViewRepresentable {
    let onChange: (CGFloat?) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onChange = onChange
    }

    final class ProbeView: UIView {
        var onChange: ((CGFloat?) -> Void)?
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
            let hasCutout = window.traitCollection.userInterfaceIdiom == .phone &&
                max(insets.top, max(insets.left, insets.right)) >= 44
            let top: CGFloat? = hasCutout ? insets.top : nil
            // Publish outside UIKit's layout pass to avoid mutating SwiftUI state
            // while the enclosing hierarchy is being laid out.
            Task { @MainActor [weak self] in
                guard let self, self.window != nil, self.lastInsets == insets else { return }
                self.onChange?(top)
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

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView(name: name, subdirectory: "BlindBoxMotion")
        view.contentMode = .scaleAspectFit
        view.backgroundBehavior = .pauseAndRestore
        view.isUserInteractionEnabled = false
        if let progress, !still {
            view.currentProgress = progress
        } else if still {
            view.currentProgress = 0.5
        } else {
            view.loopMode = loop ? .loop : .playOnce
            view.play()
        }
        return view
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {
        if still {
            uiView.pause()
            uiView.currentProgress = 0.5
        } else if let progress {
            uiView.currentProgress = progress
        }
    }

    static func dismantleUIView(_ uiView: LottieAnimationView, coordinator: ()) {
        uiView.stop()
    }
}
