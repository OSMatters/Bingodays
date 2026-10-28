import SwiftUI

struct MacBingoLineOverlay: Shape {
    let lines: Set<BingoLine>
    let gridSize: Int
    func path(in rect: CGRect) -> Path {
        let gap: CGFloat = 10
        let cell = (rect.width - gap * CGFloat(gridSize - 1)) / CGFloat(gridSize)
        func center(_ index: Int) -> CGFloat { cell / 2 + CGFloat(index) * (cell + gap) }
        var path = Path()
        for line in lines {
            let first: CGPoint
            let last: CGPoint
            switch line {
            case .row(let row):
                first = CGPoint(x: center(0), y: center(row))
                last = CGPoint(x: center(gridSize - 1), y: center(row))
            case .column(let col):
                first = CGPoint(x: center(col), y: center(0))
                last = CGPoint(x: center(col), y: center(gridSize - 1))
            case .diagonalMain:
                first = CGPoint(x: center(0), y: center(0))
                last = CGPoint(x: center(gridSize - 1), y: center(gridSize - 1))
            case .diagonalAnti:
                first = CGPoint(x: center(gridSize - 1), y: center(0))
                last = CGPoint(x: center(0), y: center(gridSize - 1))
            }
            path.move(to: first); path.addLine(to: last)
        }
        return path
    }
}
