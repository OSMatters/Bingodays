import SwiftUI
import Foundation
import CoreMotion

@MainActor
final class BingoDiaryGravityMonitor: ObservableObject {
    private let motionManager = CMMotionManager()
    private var sessionID = UUID()
    private var referenceTilt: CGSize?
    private var lastPublishedOffset: CGSize = .zero
    private var offset: CGSize = .zero
    var onOffsetChange: (@MainActor (CGSize) -> Void)?

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        guard !motionManager.isDeviceMotionActive else { return }
        let currentSessionID = UUID()
        sessionID = currentSessionID
        referenceTilt = nil
        lastPublishedOffset = .zero
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            // Core Motion delivers this handler on OperationQueue.main.
            MainActor.assumeIsolated {
                guard let self, self.sessionID == currentSessionID, let gravity = motion?.gravity else { return }
                let userAcceleration = motion?.userAcceleration
                let accelX = CGFloat(userAcceleration?.x ?? 0)
                let accelY = CGFloat(userAcceleration?.y ?? 0)

                // 以当前拿起手机的姿态作为“零重力位”，避免默认持续下坠。
                let currentTilt = CGSize(width: CGFloat(gravity.x), height: CGFloat(-gravity.y))
                if self.referenceTilt == nil {
                    self.referenceTilt = currentTilt
                } else if abs(accelX) < 0.035 && abs(accelY) < 0.035 {
                    // 慢速重基线：消除静置状态下的长期偏航，防止圆群持续单向漂移。
                    let old = self.referenceTilt ?? .zero
                    self.referenceTilt = CGSize(
                        width: old.width * 0.985 + currentTilt.width * 0.015,
                        height: old.height * 0.985 + currentTilt.height * 0.015
                    )
                }
                let reference = self.referenceTilt ?? .zero

                // 归一化输入：相对倾斜 + 抖动冲量，范围控制在可模拟区间。
                var tiltX = (currentTilt.width - reference.width) * 3.4
                var tiltY = (currentTilt.height - reference.height) * 3.4
                if abs(tiltX) < 0.04 { tiltX = 0 }
                if abs(tiltY) < 0.04 { tiltY = 0 }
                let jerkX = accelX * 2.8
                let jerkY = CGFloat(-accelY) * 2.8
                let rawX = max(min(tiltX + jerkX, 2.35), -2.35)
                let rawY = max(min(tiltY + jerkY, 2.35), -2.35)
                // 保留足够响应性，避免重力信号被过度抹平。
                let nextOffset = CGSize(
                    width: self.offset.width * 0.10 + rawX * 0.90,
                    height: self.offset.height * 0.10 + rawY * 0.90
                )
                guard hypot(
                    nextOffset.width - self.lastPublishedOffset.width,
                    nextOffset.height - self.lastPublishedOffset.height
                ) > 0.01 else { return }
                self.lastPublishedOffset = nextOffset
                self.offset = nextOffset
                self.onOffsetChange?(nextOffset)
            }
        }
    }

    func stop() {
        sessionID = UUID()
        motionManager.stopDeviceMotionUpdates()
        referenceTilt = nil
        lastPublishedOffset = .zero
        offset = .zero
        onOffsetChange?(.zero)
    }
}
