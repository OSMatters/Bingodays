import SwiftUI

/// Keeps a complete feature composition together when a partial fold divides the window.
/// A fully open display retains its entire usable area.
struct DuoContentRegion<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            let region = Self.contentFrame(in: geometry)
            content()
                .frame(width: region.width, height: region.height)
                .position(x: region.midX, y: region.midY)
        }
    }

    static func contentFrame(in geometry: GeometryProxy) -> CGRect {
        let bounds = CGRect(origin: .zero, size: geometry.size)
        guard #available(iOS 27.1, *) else { return bounds }
        return geometry.reservedRegions(kind: .division)
            .filter(\.isActive)
            .reduce(bounds) { available, division in
                let fold = division.frame.intersection(available)
                guard !fold.isNull else { return available }
                let gap: CGFloat = 12
                let candidates: [CGRect]
                if fold.height > fold.width {
                    candidates = [
                        CGRect(x: available.minX, y: available.minY,
                               width: max(0, fold.minX - available.minX - gap), height: available.height),
                        CGRect(x: fold.maxX + gap, y: available.minY,
                               width: max(0, available.maxX - fold.maxX - gap), height: available.height)
                    ]
                } else {
                    candidates = [
                        CGRect(x: available.minX, y: available.minY,
                               width: available.width, height: max(0, fold.minY - available.minY - gap)),
                        CGRect(x: available.minX, y: fold.maxY + gap,
                               width: available.width, height: max(0, available.maxY - fold.maxY - gap))
                    ]
                }
                return candidates.max(by: { $0.width * $0.height < $1.width * $1.height }) ?? available
            }
    }
}
