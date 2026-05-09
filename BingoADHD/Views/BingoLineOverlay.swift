import SwiftUI

struct BingoLineOverlay: View {
    let completedLines: Set<BingoLine>
    let gridSize: Int
    let cellSize: CGFloat
    let spacing: CGFloat

    var body: some View {
        Canvas { context, size in
            for line in completedLines {
                let (start, end) = linePoints(for: line, in: size)
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)

                context.stroke(
                    path,
                    with: .color(NeumorphicColors.pencilStroke.opacity(0.95)),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                )
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.6), value: completedLines.count)
    }

    private func linePoints(for line: BingoLine, in size: CGSize) -> (CGPoint, CGPoint) {
        let step = cellSize + spacing
        let halfCell = cellSize / 2
        let textLineOffset = cellSize * 0.44

        switch line {
        case .row(let r):
            let y = CGFloat(r) * step + textLineOffset
            return (CGPoint(x: halfCell, y: y), CGPoint(x: CGFloat(gridSize - 1) * step + halfCell, y: y))

        case .column(let c):
            let x = CGFloat(c) * step + halfCell
            return (CGPoint(x: x, y: textLineOffset), CGPoint(x: x, y: CGFloat(gridSize - 1) * step + textLineOffset))

        case .diagonalMain:
            return (CGPoint(x: halfCell, y: textLineOffset),
                    CGPoint(x: CGFloat(gridSize - 1) * step + halfCell, y: CGFloat(gridSize - 1) * step + textLineOffset))

        case .diagonalAnti:
            return (CGPoint(x: CGFloat(gridSize - 1) * step + halfCell, y: textLineOffset),
                    CGPoint(x: halfCell, y: CGFloat(gridSize - 1) * step + textLineOffset))
        }
    }
}
