import SwiftUI

/// A single horizontally scrolling surface with three stable, independently sized rows.
struct QuickEditThreeRowLayout: Layout {
    var spacing: CGFloat = 12
    var minimumRowHeight: CGFloat = 44

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rowHeight = max(minimumRowHeight, sizes.map(\.height).max() ?? 0)
        var widths = Array(repeating: CGFloat.zero, count: 3)
        for (index, size) in sizes.enumerated() {
            let row = index % 3
            widths[row] += (widths[row] > 0 ? spacing : 0) + size.width
        }
        return CGSize(width: widths.max() ?? 0, height: rowHeight * 3 + spacing * 2)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rowHeight = (bounds.height - spacing * 2) / 3
        var offsets = Array(repeating: CGFloat.zero, count: 3)
        for (index, subview) in subviews.enumerated() {
            let row = index % 3
            let size = subview.sizeThatFits(.unspecified)
            subview.place(
                at: CGPoint(x: bounds.minX + offsets[row], y: bounds.minY + CGFloat(row) * (rowHeight + spacing)),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: rowHeight)
            )
            offsets[row] += size.width + spacing
        }
    }
}
