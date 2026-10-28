import SwiftUI
import CoreMotion
import UIKit

struct BingoDiaryGravityBubbleCloud: View {
    let bubbles: [BingoDiaryBubble]
    let width: CGFloat
    let height: CGFloat
    let isActive: Bool
    let onBubbleTap: (BingoDiaryBubble) -> Void

    @StateObject private var simulator = BingoDiaryGravityPhysicsSimulator()
    @StateObject private var motionMonitor = BingoDiaryGravityMotionMonitor()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(bubbles) { bubble in
                BingoDiaryGravityBubbleItem(
                    bubble: bubble,
                    motionState: simulator.motionState(for: bubble.id),
                    onTap: { onBubbleTap(bubble) }
                )
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
        .onAppear {
            isVisible = true
            configureMotion()
        }
        .onDisappear {
            isVisible = false
            motionMonitor.stop()
            simulator.stop()
        }
        .onChange(of: layoutSignature) { _, _ in configureMotion() }
        .onChange(of: isActive) { _, _ in configureMotion() }
        .onChange(of: reduceMotion) { _, _ in configureMotion() }
        .onChange(of: scenePhase) { _, _ in configureMotion() }
    }

    private var layoutSignature: String {
        "\(width)x\(height)#" + bubbles.map { "\($0.id):\($0.diameter):\($0.position.x):\($0.position.y)" }.joined(separator: "|")
    }

    private func configureMotion() {
        guard isVisible, isActive, !reduceMotion, scenePhase == .active else {
            motionMonitor.stop()
            simulator.stop()
            return
        }
        guard motionMonitor.isAvailable else {
            simulator.stop()
            return
        }
        simulator.updateBubbles(bubbles, canvasSize: CGSize(width: width, height: height))
        motionMonitor.onGravityChange = { [weak simulator] gravity in
            simulator?.updateGravity(gravity)
        }
        motionMonitor.start()
        simulator.start()
    }
}

private struct BingoDiaryGravityBubbleItem: View {
    let bubble: BingoDiaryBubble
    @ObservedObject var motionState: BingoDiaryBubbleMotionState
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            BingoDiaryBubbleView(bubble: bubble, usesCompactLabel: true)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(bubble.task)
        .accessibilityValue(
            L10n.tr(
                "Completed \(bubble.count) times",
                zhHans: "已完成 \(bubble.count) 次",
                zhHant: "已完成 \(bubble.count) 次",
                ja: "\(bubble.count) 回完了"
            )
        )
        .accessibilityHint(L10n.tr("Opens task details", zhHans: "打开任务详情", zhHant: "開啟任務詳細資料", ja: "タスクの詳細を開きます"))
        .offset(
            x: bubble.position.x - bubble.diameter / 2 + motionState.offset.width,
            y: bubble.position.y - bubble.diameter / 2 + motionState.offset.height
        )
    }
}

@MainActor
final class BingoDiaryGravityMotionMonitor: ObservableObject {
    private let manager = CMMotionManager()
    private var sessionID = UUID()
    private var filtered: CGSize = .zero
    var onGravityChange: (@MainActor (CGSize) -> Void)?
    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        let session = UUID()
        sessionID = session
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            MainActor.assumeIsolated {
                guard let self, self.sessionID == session, let gravity = motion?.gravity else { return }
                let orientation = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first(where: { $0.activationState == .foregroundActive })?.interfaceOrientation ?? .portrait
                let x = CGFloat(gravity.x)
                let y = CGFloat(gravity.y)
                let screenGravity: CGSize
                switch orientation {
                case .landscapeLeft:
                    screenGravity = CGSize(width: y, height: x)
                case .landscapeRight:
                    screenGravity = CGSize(width: -y, height: -x)
                case .portraitUpsideDown:
                    screenGravity = CGSize(width: -x, height: y)
                default:
                    screenGravity = CGSize(width: x, height: -y)
                }
                self.filtered = CGSize(
                    width: self.filtered.width * 0.75 + screenGravity.width * 0.25,
                    height: self.filtered.height * 0.75 + screenGravity.height * 0.25
                )
                self.onGravityChange?(self.filtered)
            }
        }
    }

    func stop() {
        sessionID = UUID()
        manager.stopDeviceMotionUpdates()
        filtered = .zero
    }
}

@MainActor
final class BingoDiaryGravityPhysicsSimulator: ObservableObject {
    private struct Body {
        let id: String
        let base: CGPoint
        let radius: CGFloat
        var center: CGPoint
        var velocity: CGVector = .zero
    }

    @Published private var motionStates: [String: BingoDiaryBubbleMotionState] = [:]
    private var bodies: [Body] = []
    private var canvasSize: CGSize = .zero
    private var gravity: CGSize = .zero
    private var timer: Timer?
    private var layoutKey = ""

    func motionState(for id: String) -> BingoDiaryBubbleMotionState {
        motionStates[id] ?? .zero
    }

    func updateBubbles(_ bubbles: [BingoDiaryBubble], canvasSize: CGSize) {
        let key = "\(canvasSize.width)x\(canvasSize.height)#" + bubbles.map {
            "\($0.id):\($0.diameter):\($0.position.x):\($0.position.y)"
        }.joined(separator: "|")
        guard key != layoutKey else { return }
        layoutKey = key
        self.canvasSize = canvasSize
        bodies = bubbles.map {
            Body(id: $0.id, base: $0.position, radius: $0.diameter / 2, center: $0.position)
        }
        motionStates = Dictionary(uniqueKeysWithValues: bubbles.map {
            ($0.id, BingoDiaryBubbleMotionState())
        })
    }

    func updateGravity(_ value: CGSize) { gravity = value }

    func start() {
        guard timer == nil else { return }
        let interval: CGFloat = 1.0 / 30.0
        let timer = Timer(timeInterval: TimeInterval(interval), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step(dt: interval) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        gravity = .zero
        layoutKey = ""
        bodies.removeAll()
        motionStates.removeAll()
    }

    func step(dt: CGFloat) {
        guard !bodies.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else { return }
        let acceleration: CGFloat = 900
        let damping = exp(-1.5 * dt)
        let maxSpeed: CGFloat = 520
        let previousCenters = bodies.map(\.center)
        for index in bodies.indices {
            bodies[index].velocity.dx = (bodies[index].velocity.dx + gravity.width * acceleration * dt) * damping
            bodies[index].velocity.dy = (bodies[index].velocity.dy + gravity.height * acceleration * dt) * damping
            let speed = hypot(bodies[index].velocity.dx, bodies[index].velocity.dy)
            if speed > maxSpeed {
                bodies[index].velocity.dx *= maxSpeed / speed
                bodies[index].velocity.dy *= maxSpeed / speed
            }
            bodies[index].center.x += bodies[index].velocity.dx * dt
            bodies[index].center.y += bodies[index].velocity.dy * dt
            confine(index)
        }

        let maxDiameter = bodies.map { $0.radius * 2 }.max() ?? 0
        for _ in 0..<48 {
            var largestOverlap: CGFloat = 0
            // Sorting makes most pair checks exit once circles are too far apart.
            let order = bodies.indices.sorted { bodies[$0].center.x < bodies[$1].center.x }
            for a in order.indices {
                let first = order[a]
                for b in (a + 1)..<order.count {
                    let second = order[b]
                    if bodies[second].center.x - bodies[first].center.x > maxDiameter + 0.5 { break }
                    largestOverlap = max(largestOverlap, separate(first, second))
                }
            }
            for index in bodies.indices { confine(index) }
            if largestOverlap < 0.05 { break }
        }

        // Derive velocity from the resolved position so a resting pile does not
        // keep trying to move through the floor on every frame.
        for index in bodies.indices {
            let dx = (bodies[index].center.x - previousCenters[index].x) / dt
            let dy = (bodies[index].center.y - previousCenters[index].y) / dt
            bodies[index].velocity.dx = abs(dx) < 3 ? 0 : max(-maxSpeed, min(maxSpeed, dx)) * 0.94
            bodies[index].velocity.dy = abs(dy) < 3 ? 0 : max(-maxSpeed, min(maxSpeed, dy)) * 0.94
        }

        for body in bodies {
            let offset = CGSize(width: body.center.x - body.base.x, height: body.center.y - body.base.y)
            if let state = motionStates[body.id], hypot(state.offset.width - offset.width, state.offset.height - offset.height) > 0.001 {
                state.offset = offset
            }
        }
    }

    private func confine(_ index: Int) {
        let radius = bodies[index].radius
        let minX = radius
        let maxX = max(radius, canvasSize.width - radius)
        let minY = radius
        let maxY = max(radius, canvasSize.height - radius)
        bodies[index].center.x = min(max(bodies[index].center.x, minX), maxX)
        bodies[index].center.y = min(max(bodies[index].center.y, minY), maxY)
    }

    private func separate(_ first: Int, _ second: Int) -> CGFloat {
        let dx = bodies[second].center.x - bodies[first].center.x
        let dy = bodies[second].center.y - bodies[first].center.y
        let minDistance = bodies[first].radius + bodies[second].radius + 0.5
        let distance = hypot(dx, dy)
        guard distance < minDistance else { return 0 }
        let nx: CGFloat = distance > 0.0001 ? dx / distance : 1
        let ny: CGFloat = distance > 0.0001 ? dy / distance : 0
        let overlap = minDistance - distance
        let firstWeight = max(1, bodies[first].radius * bodies[first].radius)
        let secondWeight = max(1, bodies[second].radius * bodies[second].radius)
        // A bubble against the right wall can still move vertically, while a
        // bubble on the floor can still move horizontally. Resolve each axis
        // independently so a corner pair never becomes artificially immovable.
        let firstX = canMove(first, dx: -nx, dy: 0) ? nx : 0
        let firstY = canMove(first, dx: 0, dy: -ny) ? ny : 0
        let secondX = canMove(second, dx: nx, dy: 0) ? nx : 0
        let secondY = canMove(second, dx: 0, dy: ny) ? ny : 0
        let firstMobility = 1 / firstWeight
        let secondMobility = 1 / secondWeight
        let effectiveMobility = firstMobility * (firstX * firstX + firstY * firstY)
            + secondMobility * (secondX * secondX + secondY * secondY)
        guard effectiveMobility > 0 else { return overlap }
        let correction = overlap / effectiveMobility
        bodies[first].center.x -= firstX * firstMobility * correction
        bodies[first].center.y -= firstY * firstMobility * correction
        bodies[second].center.x += secondX * secondMobility * correction
        bodies[second].center.y += secondY * secondMobility * correction
        return overlap
    }

    private func canMove(_ index: Int, dx: CGFloat, dy: CGFloat) -> Bool {
        let body = bodies[index]
        let edgeTolerance: CGFloat = 0.05
        if dx < 0, body.center.x <= body.radius + edgeTolerance { return false }
        if dx > 0, body.center.x >= canvasSize.width - body.radius - edgeTolerance { return false }
        if dy < 0, body.center.y <= body.radius + edgeTolerance { return false }
        if dy > 0, body.center.y >= canvasSize.height - body.radius - edgeTolerance { return false }
        return true
    }
}
