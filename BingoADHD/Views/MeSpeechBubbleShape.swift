import SwiftUI

struct MeSpeechBubbleShape: Shape {
    let pointsUp: Bool

    static func tailHeight(for height: CGFloat) -> CGFloat {
        min(10, height * 0.16)
    }

    func path(in rect: CGRect) -> Path {
        // A continuous outline avoids an internal seam where the tail meets the pill.
        var path = Path()
        let tail = Self.tailHeight(for: rect.height)
        let body = CGRect(x: rect.minX, y: pointsUp ? rect.minY + tail : rect.minY,
                          width: rect.width, height: rect.height - tail)
        let radius = body.height / 2
        path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
        if pointsUp {
            path.addLine(to: CGPoint(x: body.maxX - radius - 17, y: body.minY))
            path.addLine(to: CGPoint(x: body.maxX - radius - 5, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: body.maxX - radius, y: body.minY),
                              control: CGPoint(x: body.maxX - radius, y: rect.minY))
        }
        path.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))
        path.addArc(center: CGPoint(x: body.maxX - radius, y: body.midY), radius: radius,
                    startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        if !pointsUp {
            path.addQuadCurve(to: CGPoint(x: body.maxX - radius + 13, y: rect.maxY),
                              control: CGPoint(x: body.maxX - radius + 13, y: body.maxY - 2))
            path.addLine(to: CGPoint(x: body.maxX - radius - 5, y: body.maxY))
        }
        path.addLine(to: CGPoint(x: body.minX + radius, y: body.maxY))
        path.addArc(center: CGPoint(x: body.minX + radius, y: body.midY), radius: radius,
                    startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}
