import SwiftUI

/// A cancellable visual clock. A nil time requests a static presentation.
/// Business deadlines and countdown clocks must not use this component.
struct DecorativeAnimationTimeline<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var startedAt = Date.now
    let isEnabled: Bool
    let content: (TimeInterval?) -> Content

    init(isEnabled: Bool = true, @ViewBuilder content: @escaping (TimeInterval?) -> Content) {
        self.isEnabled = isEnabled
        self.content = content
    }

    private var isRunning: Bool {
        isEnabled && isVisible && !reduceMotion && scenePhase == .active
    }

    var body: some View {
        TimelineView(.animation(paused: !isRunning)) { context in
            content(isRunning ? max(0, context.date.timeIntervalSince(startedAt)) : nil)
        }
        .onAppear { startedAt = .now; isVisible = true }
        .onDisappear { isVisible = false }
        .onChange(of: isRunning) { _, running in
            if running { startedAt = .now }
        }
    }
}

extension View {
    func decorativeWiggle(amplitude: CGFloat, duration: Double) -> some View {
        DecorativeAnimationTimeline { time in
            self.offset(x: time.map { amplitude * CGFloat(cos(.pi * $0 / duration)) } ?? 0)
        }
    }
}
