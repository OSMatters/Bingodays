import SwiftUI

struct LockScreenCellOutline: Shape {
    let cornerRadius: CGFloat
    let variation: CGFloat
    let phase: Int

    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: 0.55, dy: 0.55)
        let radius = min(cornerRadius, min(bounds.width, bounds.height) / 2)
        let left = bounds.minX
        let right = bounds.maxX
        let top = bounds.minY
        let bottom = bounds.maxY

        var path = Path()
        path.move(to: point(x: left + radius, y: top, index: 0))

        path.addCurve(
            to: point(x: right - radius, y: top, index: 1),
            control1: point(x: left + radius + (right - left - 2 * radius) * 0.28, y: top, index: 2),
            control2: point(x: right - radius - (right - left - 2 * radius) * 0.24, y: top, index: 3)
        )
        path.addCurve(
            to: point(x: right, y: top + radius, index: 4),
            control1: point(x: right - radius * 0.36, y: top, index: 5),
            control2: point(x: right, y: top + radius * 0.38, index: 6)
        )
        path.addCurve(
            to: point(x: right, y: bottom - radius, index: 7),
            control1: point(x: right, y: top + radius + (bottom - top - 2 * radius) * 0.28, index: 8),
            control2: point(x: right, y: bottom - radius - (bottom - top - 2 * radius) * 0.26, index: 9)
        )
        path.addCurve(
            to: point(x: right - radius, y: bottom, index: 10),
            control1: point(x: right, y: bottom - radius * 0.36, index: 11),
            control2: point(x: right - radius * 0.38, y: bottom, index: 12)
        )
        path.addCurve(
            to: point(x: left + radius, y: bottom, index: 13),
            control1: point(x: right - radius - (right - left - 2 * radius) * 0.28, y: bottom, index: 14),
            control2: point(x: left + radius + (right - left - 2 * radius) * 0.25, y: bottom, index: 15)
        )
        path.addCurve(
            to: point(x: left, y: bottom - radius, index: 16),
            control1: point(x: left + radius * 0.36, y: bottom, index: 17),
            control2: point(x: left, y: bottom - radius * 0.38, index: 18)
        )
        path.addCurve(
            to: point(x: left, y: top + radius, index: 19),
            control1: point(x: left, y: bottom - radius - (bottom - top - 2 * radius) * 0.28, index: 20),
            control2: point(x: left, y: top + radius + (bottom - top - 2 * radius) * 0.25, index: 21)
        )
        path.addCurve(
            to: point(x: left + radius, y: top, index: 22),
            control1: point(x: left, y: top + radius * 0.36, index: 23),
            control2: point(x: left + radius * 0.38, y: top, index: 24)
        )
        path.closeSubpath()
        return path
    }

    private func point(x: CGFloat, y: CGFloat, index: Int) -> CGPoint {
        let offsets: [CGFloat] = [0.12, -0.28, 0.22, -0.16, 0.30, -0.18, 0.14, -0.24]
        let offset = offsets[(index + phase) % offsets.count] * variation
        return CGPoint(x: x + offset, y: y + offset * 0.72)
    }
}
