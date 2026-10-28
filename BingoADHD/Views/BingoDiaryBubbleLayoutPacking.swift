import SwiftUI
import Foundation

extension BingoDiaryBubbleLayout {
    static func horizontalOverflowLayout(
        descriptors: [Descriptor],
        canvasWidth: CGFloat,
        viewportHeight: CGFloat
    ) -> (bubbles: [BingoDiaryBubble], width: CGFloat, height: CGFloat, isHorizontallyOverflowing: Bool) {
        guard !descriptors.isEmpty else { return ([], canvasWidth, 0, false) }

        let effectiveViewportHeight = viewportHeight.isFinite ? max(viewportHeight, 0) : 0
        let baseHeight = effectiveViewportHeight > 1 ? effectiveViewportHeight : 560
        let pageHeight = max(560, baseHeight + 140)
        let availableTop = topInset + initialTopGap
        let availableBottom = pageHeight - topInset
        let horizontalEdgeInset = sideInset
        let verticalEdgeInset = sideInset
        // Let the next group enter the viewport before the current one ends.
        // Its first bubble becomes a visible cue that the cloud scrolls sideways.
        let pageStride = max(1, canvasWidth - min(100, canvasWidth * 0.25))

        let sortedDescriptors = descriptors.sorted { lhs, rhs in
            if lhs.radius != rhs.radius { return lhs.radius > rhs.radius }
            return lhs.taskCount.count > rhs.taskCount.count
        }

        var placed: [Placement] = []
        var placedPageIndices: [Int] = []
        var requiredPageCount = 1
        let maxAttemptsPerPage = 800

        for (index, descriptor) in sortedDescriptors.enumerated() {
            var placement: Placement?
            var pageIndex = 0

            while placement == nil && pageIndex < 120 {
                let pageStartX = CGFloat(pageIndex) * pageStride
                let minX = pageStartX + descriptor.radius + horizontalEdgeInset
                let maxX = pageStartX + canvasWidth - descriptor.radius - horizontalEdgeInset
                let minY = availableTop + descriptor.radius + verticalEdgeInset
                let maxY = availableBottom - descriptor.radius - verticalEdgeInset
                let isXRangeValid = minX <= maxX
                let isYRangeValid = minY <= maxY

                var generator = SeededGenerator(
                    state: seed(for: descriptor.taskCount.task)
                    &+ UInt64(index * 131)
                    &+ UInt64(pageIndex * 9_973)
                    &+ 1
                )
                let pagePlaced = zip(placed, placedPageIndices)
                    .compactMap { placement, placedPageIndex in
                        placedPageIndex == pageIndex ? placement : nil
                    }
                var bestPlacementForPage: (placement: Placement, score: CGFloat)?

                let tangentAttempts = Int(CGFloat(maxAttemptsPerPage) * 0.9)
                for attempt in 0..<maxAttemptsPerPage {
                    let candidate: CGPoint
                    if pageIndex > 0, pagePlaced.isEmpty, attempt < tangentAttempts {
                        let yRange = safeRange(
                            lowerBound: minY,
                            upperBound: maxY,
                            fallback: (availableTop + availableBottom) * 0.5
                        )
                        candidate = CGPoint(x: minX, y: CGFloat.random(in: yRange, using: &generator))
                    } else if !pagePlaced.isEmpty,
                       attempt < tangentAttempts,
                       let base = pagePlaced.randomElement(using: &generator) {
                        let angle = CGFloat.random(in: 0...(2 * .pi), using: &generator)
                        // Keep edge spacing uniform regardless of bubble sizes.
                        let targetDistance = base.radius + descriptor.radius + minimumGap
                        candidate = CGPoint(
                            x: base.center.x + cos(angle) * targetDistance,
                            y: base.center.y + sin(angle) * targetDistance
                        )
                    } else {
                        let xRange = safeRange(
                            lowerBound: minX,
                            upperBound: maxX,
                            fallback: pageStartX + canvasWidth * 0.5
                        )
                        let yRange = safeRange(
                            lowerBound: minY,
                            upperBound: maxY,
                            fallback: (availableTop + availableBottom) * 0.5
                        )
                        candidate = CGPoint(
                            x: CGFloat.random(in: xRange, using: &generator),
                            y: CGFloat.random(in: yRange, using: &generator)
                        )
                    }

                    guard (!isXRangeValid || (candidate.x >= minX && candidate.x <= maxX)),
                          (!isYRangeValid || (candidate.y >= minY && candidate.y <= maxY)) else {
                        continue
                    }
                    if fits(candidate, radius: descriptor.radius, among: placed) {
                        let resolvedPlacement = Placement(
                            descriptor: descriptor,
                            center: candidate,
                            radius: descriptor.radius
                        )
                        let nearestEdgeDistance: CGFloat = placed.isEmpty
                            ? 0
                            : placed.reduce(CGFloat.greatestFiniteMagnitude) { current, other in
                                let centerDistance = hypot(candidate.x - other.center.x, candidate.y - other.center.y)
                                let edgeDistance = max(0, centerDistance - (descriptor.radius + other.radius))
                                return min(current, edgeDistance)
                            }
                        let pageCenter = CGPoint(
                            x: pageStartX + (canvasWidth / 2),
                            y: (availableTop + availableBottom) / 2
                        )
                        let centerDistance = hypot(candidate.x - pageCenter.x, candidate.y - pageCenter.y)
                        // Prefer candidates that keep the nearest edge gap close to minimumGap.
                        let leadingDistance = pageIndex > 0 && pagePlaced.isEmpty
                            ? candidate.x - minX
                            : 0
                        let score = nearestEdgeDistance * 8 + centerDistance * 0.02 + leadingDistance

                        if let best = bestPlacementForPage {
                            if score < best.score {
                                bestPlacementForPage = (resolvedPlacement, score)
                            }
                        } else {
                            bestPlacementForPage = (resolvedPlacement, score)
                        }
                    }
                }

                if let bestPlacementForPage {
                    placement = bestPlacementForPage.placement
                    requiredPageCount = max(requiredPageCount, pageIndex + 1)
                }

                if placement == nil {
                    pageIndex += 1
                }
            }

            if let placement {
                placed.append(placement)
                placedPageIndices.append(pageIndex)
            } else {
                let fallbackPage = requiredPageCount
                let fallbackCenter = CGPoint(
                    x: CGFloat(fallbackPage) * pageStride + canvasWidth * 0.5,
                    y: (availableTop + availableBottom) * 0.5
                )
                placed.append(
                    Placement(
                        descriptor: descriptor,
                        center: fallbackCenter,
                        radius: descriptor.radius
                    )
                )
                placedPageIndices.append(fallbackPage)
                requiredPageCount = fallbackPage + 1
            }
        }

        let bubbles = placed.map { placement in
            makeBubble(from: placement.descriptor, at: placement.center)
        }
        let totalCanvasWidth = canvasWidth + CGFloat(requiredPageCount - 1) * pageStride
        return (bubbles, totalCanvasWidth, pageHeight, requiredPageCount > 1)
    }

    private static func fits(_ candidate: CGPoint, radius: CGFloat, among placed: [Placement]) -> Bool {
        for other in placed {
            let distance = hypot(candidate.x - other.center.x, candidate.y - other.center.y)
            if distance < radius + other.radius + minimumGap {
                return false
            }
        }
        return true
    }

    private static func safeRange(
        lowerBound: CGFloat,
        upperBound: CGFloat,
        fallback: CGFloat
    ) -> ClosedRange<CGFloat> {
        guard lowerBound <= upperBound else { return fallback...fallback }
        return lowerBound...upperBound
    }

    static func makeBubble(from descriptor: Descriptor, at center: CGPoint) -> BingoDiaryBubble {
        BingoDiaryBubble(
            id: descriptor.taskCount.id,
            task: descriptor.taskCount.task,
            count: descriptor.taskCount.count,
            diameter: descriptor.diameter,
            contentScale: 1,
            position: center,
            gradientStart: descriptor.gradientStart,
            gradientEnd: descriptor.gradientEnd,
            motionFactor: descriptor.motionFactor
        )
    }

    private static func seed(for text: String) -> UInt64 {
        text.unicodeScalars.reduce(1469598103934665603) { partialResult, scalar in
            let mixed = partialResult ^ UInt64(scalar.value)
            return mixed &* 1099511628211
        }
    }

    static func colorIndex(for task: String) -> Int {
        abs(task.unicodeScalars.reduce(0) { partialResult, scalar in
            ((partialResult * 31) + Int(scalar.value)) % 100_000
        }) % palette.count
    }

    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }
}

extension BingoDiaryBubbleLayout {
    /// Packs every task into a fixed viewport with one shared scale factor.
    static func gravityLayout(
        taskCounts: [BingoDiaryTaskCount],
        width: CGFloat,
        height: CGFloat
    ) -> [BingoDiaryBubble] {
        guard width.isFinite, height.isFinite, width > 1, height > 1 else { return [] }
        let items = descriptors(for: taskCounts)
        guard !items.isEmpty else { return [] }
        let inset = min(12, min(width, height) * 0.025)
        let availableWidth = max(1, width - inset * 2)
        let availableHeight = max(1, height - inset * 2)
        let ordered = items.sorted { lhs, rhs in
            if lhs.diameter == rhs.diameter { return lhs.taskCount.id < rhs.taskCount.id }
            return lhs.diameter > rhs.diameter
        }

        func place(at scale: CGFloat) -> [(Descriptor, CGPoint)]? {
            let gap = 5 * scale
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            var placed: [(Descriptor, CGPoint)] = []
            placed.reserveCapacity(ordered.count)
            for item in ordered {
                let diameter = item.diameter * scale
                guard diameter <= availableWidth, diameter <= availableHeight else { return nil }
                if x > 0, x + diameter > availableWidth {
                    x = 0
                    y += rowHeight + gap
                    rowHeight = 0
                }
                guard y + diameter <= availableHeight else { return nil }
                placed.append((item, CGPoint(x: x + diameter / 2, y: y + diameter / 2)))
                x += diameter + gap
                rowHeight = max(rowHeight, diameter)
            }
            return placed
        }

        var low: CGFloat = 0
        var high: CGFloat = 1
        for _ in 0..<36 {
            let candidate = (low + high) / 2
            if place(at: candidate) != nil { low = candidate } else { high = candidate }
        }
        // A little unused area gives the bubbles room to roll after the phone tilts.
        let scale = low * 0.86
        guard let placements = place(at: scale) else { return [] }
        let usedWidth = placements.map { $0.1.x + $0.0.radius * scale }.max() ?? 0
        let usedHeight = placements.map { $0.1.y + $0.0.radius * scale }.max() ?? 0
        let offsetX = inset + (availableWidth - usedWidth) / 2
        let offsetY = inset + (availableHeight - usedHeight) / 2
        return placements.map { descriptor, center in
            let original = makeBubble(from: descriptor, at: center)
            return BingoDiaryBubble(
                id: original.id,
                task: original.task,
                count: original.count,
                diameter: original.diameter * scale,
                contentScale: scale,
                position: CGPoint(x: center.x + offsetX, y: center.y + offsetY),
                gradientStart: original.gradientStart,
                gradientEnd: original.gradientEnd,
                motionFactor: original.motionFactor
            )
        }
    }
}
