import SwiftUI
import WidgetKit

struct MacDesktopBoardView: View {
    let snapshot: MacDesktopBoardSnapshot
    let referenceDate: Date
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let gap = side < 200 ? 4.0 : 8.0
            let inset = side < 200 ? 8.0 : 14.0
            let cellSide = (side - 2 * inset - gap * Double(snapshot.gridSize - 1)) / Double(snapshot.gridSize)
            Grid(horizontalSpacing: gap, verticalSpacing: gap) {
                ForEach(0..<snapshot.gridSize, id: \.self) { row in
                    GridRow {
                        ForEach(0..<snapshot.gridSize, id: \.self) { col in
                            let cell = snapshot.cells(at: referenceDate)[row * snapshot.gridSize + col]
                            ZStack {
                                RoundedRectangle(cornerRadius: cellSide * 0.15)
                                    .fill(cell.completed ? color(snapshot.surface) : Color.white.opacity(0.93))
                                RoundedRectangle(cornerRadius: cellSide * 0.15)
                                    .strokeBorder(color(cell.inBingo ? snapshot.accent : snapshot.outline), lineWidth: cell.inBingo ? 2.5 : 1.5)
                                VStack(spacing: 3) {
                                    if cell.completed {
                                        Image(systemName: "checkmark").font(.system(size: max(8, cellSide * 0.16), weight: .bold)).foregroundStyle(color(snapshot.accent))
                                    }
                                    Text(cell.text)
                                        .font(.system(size: min(16, max(9, cellSide * 0.19)), weight: .medium, design: .rounded))
                                        .foregroundStyle(Color(red: 0.29, green: 0.27, blue: 0.25))
                                        .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.65)
                                }.padding(max(3, cellSide * 0.07))
                            }
                            .frame(width: cellSide, height: cellSide)
                            .accessibilityLabel(cell.text.isEmpty ? "空白格" : cell.text)
                            .accessibilityValue(cell.completed ? "已完成" : "未完成")
                        }
                    }
                }
            }
            .padding(inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .containerBackground(for: .widget) {
            if let image = snapshot.backgroundImage {
                Image(image).resizable().scaledToFill()
            } else { Color(red: 0.98, green: 0.97, blue: 0.95) }
        }
        .widgetURL(snapshot.destination)
    }
    private func color(_ value: MacDesktopBoardSnapshot.PaletteColor) -> Color {
        Color(red: value.red, green: value.green, blue: value.blue)
    }
}
