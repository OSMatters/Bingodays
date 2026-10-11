import SwiftUI

struct BingoBoardLiveActivityCell: View {
    let boardID: UUID
    let cell: BingoBoardActivitySnapshot.Cell
    let theme: AppTheme
    let size: CGSize

    let scale: CGFloat

    private var inset: CGFloat { max(1, (size.width / scale < 72 ? 5 : 10) * scale) }
    private var textSize: CGSize {
        CGSize(width: max(1, size.width - inset * 2), height: max(1, size.height - inset * 2))
    }
    private var fill: Color {
        cell.inBingo ? theme.color : (cell.completed ? theme.bingoSurfaceColor : .white)
    }
    private var border: Color {
        cell.inBingo ? theme.color : (cell.completed ? theme.bingoSurfaceColor : theme.bingoCellOutlineColor)
    }
    private var cornerRadius: CGFloat { 12 * scale }

    private var outline: some View {
        ZStack {
            LockScreenCellOutline(cornerRadius: cornerRadius, variation: 0.9 * scale, phase: 0)
                .stroke(border.opacity(0.78), style: StrokeStyle(lineWidth: 1.15 * scale, lineCap: .round, lineJoin: .round))
            LockScreenCellOutline(cornerRadius: cornerRadius + 0.35 * scale, variation: 1.2 * scale, phase: 3)
                .stroke(border.opacity(0.24), style: StrokeStyle(lineWidth: 0.7 * scale, lineCap: .round, lineJoin: .round))
        }
    }

    var body: some View {
        Button(intent: ToggleLiveActivityTaskIntent(boardID: boardID, cell: cell)) {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius).fill(fill)
                if cell.completed {
                    Image(cell.inBingo ? "CellBingo" : "CellComplete")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: size.width * 0.76, height: size.height * 0.76)
                }
                BingoBoardLiveActivityText(text: cell.text, size: textSize, inBingo: cell.inBingo, maximumFontSize: max(11, min(size.width / scale * 0.19, 18)) * scale)
                outline
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!cell.enabled)
        .accessibilityLabel(cell.text)
        .accessibilityValue(cell.completed ? L10n.tr("Completed", zhHans: "已完成", zhHant: "已完成", ja: "完了") : L10n.tr("Incomplete", zhHans: "未完成", zhHant: "未完成", ja: "未完了"))
    }
}

/// Uses the same measured character wrapping for the rendered text.
struct BingoBoardLiveActivityText: View {
    let text: String
    let size: CGSize
    let inBingo: Bool
    let maximumFontSize: CGFloat

    var body: some View {
        Image(uiImage: BingoBoardTextFitter.image(for: text, in: size, maximumFontSize: maximumFontSize, color: inBingo ? .white : UIColor(red: 41 / 255, green: 30 / 255, blue: 10 / 255, alpha: 1)))
            .resizable()
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)
    }
}
