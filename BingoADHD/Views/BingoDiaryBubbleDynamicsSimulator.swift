import SwiftUI
import Foundation

@MainActor
final class BingoDiaryBubbleMotionState: ObservableObject {
    static let zero = BingoDiaryBubbleMotionState()

    @Published var offset: CGSize = .zero
}

@MainActor
final class BingoDiaryBubbleDynamicsSimulator: ObservableObject {
    @Published private(set) var motionStates: [String: BingoDiaryBubbleMotionState] = [:]

    private var velocities: [String: CGVector] = [:]
    private var impulses: [String: CGVector] = [:]
    private var motionFactors: [String: CGFloat] = [:]
    private var diameters: [String: CGFloat] = [:]
    private var baseCenters: [String: CGPoint] = [:]
    private var radii: [String: CGFloat] = [:]
    private var canvasSize: CGSize = .zero
    private var gravity: CGSize = .zero
    private var timer: Timer?
    private var isPaused = false

    func start() {
        guard timer == nil else { return }
        let interval: CGFloat = 1.0 / 30.0
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // This timer is installed exclusively on RunLoop.main.
            MainActor.assumeIsolated { self?.step(deltaTime: interval) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for state in motionStates.values {
            state.offset = .zero
        }
        motionStates.removeAll()
        velocities.removeAll()
        impulses.removeAll()
        motionFactors.removeAll()
        diameters.removeAll()
        baseCenters.removeAll()
        radii.removeAll()
        canvasSize = .zero
        gravity = .zero
        isPaused = false
    }

    func updateBubbles(_ bubbles: [BingoDiaryBubble], canvasSize: CGSize) {
        self.canvasSize = canvasSize
        let activeIDs = Set(bubbles.map(\.id))
        var updatedStates = motionStates.filter { activeIDs.contains($0.key) }
        velocities = velocities.filter { activeIDs.contains($0.key) }
        impulses = impulses.filter { activeIDs.contains($0.key) }
        motionFactors = motionFactors.filter { activeIDs.contains($0.key) }
        diameters = diameters.filter { activeIDs.contains($0.key) }
        baseCenters = baseCenters.filter { activeIDs.contains($0.key) }
        radii = radii.filter { activeIDs.contains($0.key) }

        for bubble in bubbles {
            motionFactors[bubble.id] = bubble.motionFactor
            diameters[bubble.id] = bubble.diameter
            let radius = bubble.diameter / 2
            radii[bubble.id] = radius
            baseCenters[bubble.id] = bubble.position
            if updatedStates[bubble.id] == nil {
                updatedStates[bubble.id] = BingoDiaryBubbleMotionState()
            }
            if velocities[bubble.id] == nil {
                velocities[bubble.id] = .zero
            }
            if impulses[bubble.id] == nil {
                impulses[bubble.id] = .zero
            }
        }

        motionStates = updatedStates
    }

    func updateGravity(_ value: CGSize) {
        gravity = value
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
    }

    func motionState(for id: String) -> BingoDiaryBubbleMotionState {
        motionStates[id] ?? .zero
    }

    private func step(deltaTime: CGFloat) {
        guard !isPaused, !motionStates.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else { return }

        var updatedOffsets: [String: CGSize] = [:]
        let gravityX = activeGravityComponent(gravity.width)
        let gravityY = activeGravityComponent(gravity.height)
        let smoothing = min(max(deltaTime * 14, 0.10), 0.36)
        let maxOffsetDistance: CGFloat = 15
        var maxDelta: CGFloat = 0
        let unifiedTargetOffset = clampedOffset(
            CGSize(
                width: gravityX * maxOffsetDistance,
                height: gravityY * maxOffsetDistance
            ),
            maxDistance: maxOffsetDistance
        )

        for (id, state) in motionStates {
            let currentOffset = state.offset
            let nextOffset = clampedOffset(
                CGSize(
                    width: currentOffset.width + (unifiedTargetOffset.width - currentOffset.width) * smoothing,
                    height: currentOffset.height + (unifiedTargetOffset.height - currentOffset.height) * smoothing
                ),
                maxDistance: maxOffsetDistance
            )
            maxDelta = max(maxDelta, hypot(nextOffset.width - currentOffset.width, nextOffset.height - currentOffset.height))
            updatedOffsets[id] = nextOffset
        }
        // Each bubble publishes only its own offset, so the whole cloud doesn't rebuild
        // whenever one animation frame advances.
        if maxDelta > 0.03 {
            for (id, nextOffset) in updatedOffsets {
                if let state = motionStates[id] {
                    state.offset = nextOffset
                }
            }
        }
    }

    private func clampedOffset(_ offset: CGSize, maxDistance: CGFloat) -> CGSize {
        let distance = hypot(offset.width, offset.height)
        guard distance > maxDistance, distance > 0 else { return offset }
        let scale = maxDistance / distance
        return CGSize(width: offset.width * scale, height: offset.height * scale)
    }

    private func activeGravityComponent(_ rawValue: CGFloat) -> CGFloat {
        let deadZone: CGFloat = 0.03
        let magnitude = abs(rawValue)
        guard magnitude > deadZone else { return 0 }
        let normalized = min(1.0, (magnitude - deadZone) / max(0.0001, 1.0 - deadZone))
        let curved = pow(normalized, 0.92)
        return rawValue.sign == .minus ? -curved : curved
    }
}
