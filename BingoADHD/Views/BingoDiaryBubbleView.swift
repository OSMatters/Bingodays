import SwiftUI
import Foundation
import UIKit

struct BingoDiaryBubbleView: View {
    let bubble: BingoDiaryBubble
    var usesCompactLabel = false

    private var showsInitial: Bool {
        usesCompactLabel && bubble.diameter < 90
    }

    private var initial: String {
        String(bubble.task.trimmingCharacters(in: .whitespacesAndNewlines).first ?? "•")
    }

    private var labelWidth: CGFloat {
        bubble.diameter * (bubble.diameter <= 70 ? 0.72 : 0.78)
    }

    private var labelHeight: CGFloat {
        bubble.diameter * 0.56
    }

    private var contentScale: CGFloat {
        usesCompactLabel ? max(bubble.contentScale, 0.0001) : 1
    }

    private var sourceDiameter: CGFloat {
        bubble.diameter / contentScale
    }

    private var backgroundNumberFontSize: CGFloat {
        // radius 40~140 -> font 40~150
        let radius = sourceDiameter / 2
        let normalized = max(0, min(1, (radius - 40) / 100))
        return (40 + normalized * 110) * contentScale
    }

    private var taskFontSize: CGFloat {
        let baseSize: CGFloat
        switch sourceDiameter {
        case ..<90:
            baseSize = 13
        case ..<150:
            baseSize = 16
        case ..<210:
            baseSize = 19
        default:
            baseSize = 22
        }
        let lengthPenalty = CGFloat(max(0, bubble.task.count - 8)) * 0.22
        return max(10, baseSize - lengthPenalty) * contentScale
    }

    private var bubbleTextColor: Color {
        let mixed = mix(colorA: bubble.gradientStart, colorB: bubble.gradientEnd, ratio: 0.56)
        return deepenedColor(from: mixed)
    }

    private func mix(colorA: Color, colorB: Color, ratio: CGFloat) -> UIColor {
        let left = UIColor(colorA)
        let right = UIColor(colorB)
        var lr: CGFloat = 0
        var lg: CGFloat = 0
        var lb: CGFloat = 0
        var la: CGFloat = 0
        var rr: CGFloat = 0
        var rg: CGFloat = 0
        var rb: CGFloat = 0
        var ra: CGFloat = 0
        let leftOK = left.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        let rightOK = right.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)
        guard leftOK, rightOK else { return left }
        let clamped = min(max(ratio, 0), 1)
        let inv = 1 - clamped
        return UIColor(
            red: lr * clamped + rr * inv,
            green: lg * clamped + rg * inv,
            blue: lb * clamped + rb * inv,
            alpha: la * clamped + ra * inv
        )
    }

    private func deepenedColor(from color: UIColor) -> Color {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        if color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            let deeper = UIColor(
                hue: hue,
                saturation: min(1.0, saturation * 1.12 + 0.04),
                brightness: max(0.08, brightness * 0.38),
                alpha: 1
            )
            return Color(uiColor: deeper)
        }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var rgbaAlpha: CGFloat = 0
        if color.getRed(&red, green: &green, blue: &blue, alpha: &rgbaAlpha) {
            return Color(
                red: max(0, red * 0.42),
                green: max(0, green * 0.42),
                blue: max(0, blue * 0.42)
            )
        }
        return Color(hex: "2B1A0D")
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [bubble.gradientStart, bubble.gradientEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if bubble.diameter >= 34 && !showsInitial {
                Text("\(bubble.count)")
                    .appDynamicFont(size: backgroundNumberFontSize, weight: .bold, design: .rounded)
                    .foregroundStyle(.white.opacity(0.2))
                    .minimumScaleFactor(0.4)
            }

            if showsInitial {
                Text(initial)
                    .font(.system(size: max(3, taskFontSize * 1.35), weight: .bold, design: .rounded))
                    .foregroundStyle(bubbleTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: bubble.diameter * 0.82, height: bubble.diameter * 0.82)
            } else {
                Text(bubble.task)
                    .appDynamicFont(size: taskFontSize, weight: .bold, design: .rounded)
                    .foregroundStyle(bubbleTextColor)
                    .frame(width: labelWidth, height: labelHeight, alignment: .center)
                    .lineLimit(nil)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.55)
                    .allowsTightening(true)
            }
        }
        .frame(width: bubble.diameter, height: bubble.diameter)
        .clipShape(Circle())
    }
}
