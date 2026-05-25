import SwiftUI
import Foundation

struct BingoDiaryBubble: Identifiable, Equatable {
    let id: String
    let task: String
    let count: Int
    let diameter: CGFloat
    let position: CGPoint
    let gradientStart: Color
    let gradientEnd: Color
    let motionFactor: CGFloat
}

private enum BingoDiaryBubbleTier {
    case round1
    case round2
    case round3
    case round4

    var diameter: CGFloat {
        switch self {
        case .round1: return 237
        case .round2: return 200
        case .round3: return 130
        case .round4: return 70
        }
    }

}

enum BingoDiaryBubbleLayout {
    struct Descriptor {
        let taskCount: BingoDiaryTaskCount
        let radius: CGFloat
        let gradientStart: Color
        let gradientEnd: Color
        let motionFactor: CGFloat

        var diameter: CGFloat { radius * 2 }
    }

    struct Placement {
        let descriptor: Descriptor
        let center: CGPoint
        let radius: CGFloat
    }

    static let minimumGap: CGFloat = 8
    static let sideInset: CGFloat = 16
    static let topInset: CGFloat = 0
    static let initialTopGap: CGFloat = 0
    static let bottomVisibilityReserve: CGFloat = 28
    static let palette: [(Color, Color)] = [
        (Color(hex: "F1C397"), Color(hex: "F7E3CF")),
        (Color(hex: "F1A0A0"), Color(hex: "FFDBDB")),
        (Color(hex: "99DAC0"), Color(hex: "CCF4D0")),
        (Color(hex: "7DC5E2"), Color(hex: "D6F3FF")),
        (Color(hex: "BF9CD6"), Color(hex: "FDE4FC")),
        (Color(hex: "EBA1CA"), Color(hex: "FDD7EC"))
    ]

    static func layout(
        taskCounts: [BingoDiaryTaskCount],
        width: CGFloat,
        viewportHeight: CGFloat,
        maximumBubbleCount: Int
    ) -> (bubbles: [BingoDiaryBubble], width: CGFloat, height: CGFloat, isHorizontallyOverflowing: Bool) {
        let visibleItems = Array(taskCounts.prefix(maximumBubbleCount))
        let usableWidth = width.isFinite ? max(width, 0) : 0
        guard !visibleItems.isEmpty else { return ([], usableWidth, 0, false) }
        // Wait for a real measured width instead of using a synthetic fallback.
        // This avoids first-entry transient vertical stacks caused by early narrow passes.
        guard usableWidth > 1 else { return ([], 0, 0, false) }

        let sortedItems = visibleItems.sorted { lhs, rhs in
            if lhs.count == rhs.count {
                switch (lhs.firstCompletedAt, rhs.firstCompletedAt) {
                case let (l?, r?) where l != r:
                    return l < r
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                default:
                    return lhs.task.localizedCaseInsensitiveCompare(rhs.task) == .orderedAscending
                }
            }
            return lhs.count > rhs.count
        }

        let minimumCount = sortedItems.map(\.count).min() ?? 0
        let maximumCount = sortedItems.map(\.count).max() ?? 0
        let countSpread = maximumCount - minimumCount
        let uniqueCountsAscending = Array(Set(sortedItems.map(\.count))).sorted()
        let shouldUseAdjacentTierSizing = sortedItems.count < 4 || countSpread < 2

        let adjacentTierByCount: [Int: BingoDiaryBubbleTier] = {
            guard shouldUseAdjacentTierSizing, !uniqueCountsAscending.isEmpty else { return [:] }
            let tiersAscending: [BingoDiaryBubbleTier] = [.round4, .round3, .round2, .round1] // small -> large
            let requiredTierCount = min(max(uniqueCountsAscending.count, 1), tiersAscending.count)
            let preferredStart = adjacentTierStartIndex(maxCount: maximumCount, requiredTierCount: requiredTierCount)
            let maxStart = tiersAscending.count - requiredTierCount
            let startIndex = min(max(preferredStart, 0), maxStart)
            var mapping: [Int: BingoDiaryBubbleTier] = [:]
            for (index, count) in uniqueCountsAscending.enumerated() {
                let tierOffset = min(index, requiredTierCount - 1)
                mapping[count] = tiersAscending[startIndex + tierOffset]
            }
            return mapping
        }()

        func radius(for value: Int) -> CGFloat {
            if shouldUseAdjacentTierSizing, let tier = adjacentTierByCount[value] {
                return tier.diameter / 2
            }
            guard maximumCount > minimumCount else { return 90 }
            let normalized = CGFloat(value - minimumCount) / CGFloat(maximumCount - minimumCount)
            return 40 + normalized * 100
        }

        let descriptors: [Descriptor] = sortedItems.enumerated().map { index, item in
            let resolvedRadius = radius(for: item.count)
            let paletteItem = palette[colorIndex(for: item.task)]
            let normalizedRadius = max(0, min(1, (resolvedRadius - 40) / 100))
            let tierMotionBase: CGFloat = 1.12 - normalizedRadius * 0.16
            let colorJitter = CGFloat(colorIndex(for: item.task) % 4) * 0.04
            let motionFactor = min(1.25, tierMotionBase + colorJitter)
            return Descriptor(
                taskCount: item,
                radius: resolvedRadius,
                gradientStart: paletteItem.0,
                gradientEnd: paletteItem.1,
                motionFactor: motionFactor
            )
        }

        if descriptors.count == 1 {
            let descriptor = descriptors[0]
            let canvasHeight = max(360, descriptor.radius * 2 + 160) + bottomVisibilityReserve
            let center = CGPoint(
                x: usableWidth / 2,
                y: canvasHeight / 2
            )
            let bubbles = [makeBubble(from: descriptor, at: center)]
            return (
                bubbles,
                usableWidth,
                canvasHeight,
                false
            )
        }

        return horizontalOverflowLayout(
            descriptors: descriptors,
            canvasWidth: usableWidth,
            viewportHeight: viewportHeight
        )
    }

    private static func adjacentTierStartIndex(maxCount: Int, requiredTierCount: Int) -> Int {
        let preferredStart: Int
        switch maxCount {
        case ...2:
            preferredStart = 0
        case ...5:
            preferredStart = 1
        case ...24:
            preferredStart = 2
        default:
            preferredStart = 2
        }
        return min(max(preferredStart, 0), max(0, 4 - requiredTierCount))
    }

}
