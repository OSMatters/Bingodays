import CoreHaptics
import UIKit

enum AppHaptics {
    @MainActor private static let completionGenerator = UIImpactFeedbackGenerator(style: .medium)
    @MainActor private static let controlGenerator = UIImpactFeedbackGenerator(style: .light)
    @MainActor private static let emphasisGenerator = UIImpactFeedbackGenerator(style: .heavy)

    private static func perform(_ work: @escaping @MainActor @Sendable () -> Void) {
        guard AppSettings.isHapticsEnabled else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    static func prepareForInteraction() {
        perform {
            completionGenerator.prepare()
            controlGenerator.prepare()
            emphasisGenerator.prepare()
        }
    }

    static func completion() {
        perform {
            completionGenerator.impactOccurred(intensity: 1.0)
            completionGenerator.prepare()
        }
    }

    static func control() {
        perform {
            controlGenerator.impactOccurred(intensity: 0.85)
            controlGenerator.prepare()
        }
    }

    static func emphasis() {
        perform {
            emphasisGenerator.impactOccurred(intensity: 1.0)
            emphasisGenerator.prepare()
        }
    }
}

/// A single, sustained haptic whose intensity ramps up with a celebration animation.
/// Core Haptics avoids the staccato feel of repeatedly firing impact generators.
@MainActor
final class AppHapticContinuousPlayer {
    // The main-actor owner controls playback. Resource teardown stays in a plain
    // holder so destruction does not read actor-isolated properties on older iOS.
    private final class Resources {
        var engine: CHHapticEngine?
        var player: CHHapticAdvancedPatternPlayer?

        deinit {
            try? player?.stop(atTime: 0)
            engine?.stop()
        }
    }

    private let resources = Resources()
    private var engine: CHHapticEngine? {
        get { resources.engine }
        set { resources.engine = newValue }
    }
    private var player: CHHapticAdvancedPatternPlayer? {
        get { resources.player }
        set { resources.player = newValue }
    }

    func start(
        initialIntensity: CGFloat = 0.10,
        peakIntensity: CGFloat = 0.55,
        rampDuration: TimeInterval = 1.8,
        sharpness: CGFloat = 0.08
    ) {

        stop()
        guard AppSettings.isHapticsEnabled,
              CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            return
        }

        do {
            let effectivePeak = min(max(peakIntensity, 0), 1)
            let effectiveInitial = min(max(initialIntensity, 0), effectivePeak)
            let effectiveSharpness = min(max(sharpness, 0), 1)
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(effectivePeak)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(effectiveSharpness))
                ],
                relativeTime: 0,
                duration: 10
            )
            // Intensity control is relative to the event's peak intensity. Start near silence,
            // then smoothly reach its authored maximum and hold until the animation stops it.
            let openingControl = Float((effectiveInitial / max(effectivePeak, 0.001)) - 1)
            let intensityCurve = CHHapticParameterCurve(
                parameterID: .hapticIntensityControl,
                controlPoints: [
                    .init(relativeTime: 0, value: openingControl),
                    .init(relativeTime: max(rampDuration, 0.01), value: 0)
                ],
                relativeTime: 0
            )
            let pattern = try CHHapticPattern(events: [event], parameterCurves: [intensityCurve])
            let engine = try CHHapticEngine()
            let player = try engine.makeAdvancedPlayer(with: pattern)

            self.engine = engine
            self.player = player
            try engine.start()
            try player.start(atTime: 0)
        } catch {
            player = nil
            engine = nil
        }
    }

    func stop() {

        try? player?.stop(atTime: 0)
        engine?.stop()
        player = nil
        engine = nil
    }

}
