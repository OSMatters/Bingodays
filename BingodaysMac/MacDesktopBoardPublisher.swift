import SwiftUI
import AppKit
import WidgetKit

@MainActor
extension MacWorkspaceStore {
    func publishDesktopBoard() {
        guard let container = BingoBoardStore.sharedContainerURL else { return }
        let theme = AppTheme.current
        let skinRaw = UserDefaults.standard.string(forKey: AppSettings.homeBackgroundKey) ?? HomeBackgroundOption.none.rawValue
        var snapshot = MacDesktopBoardSnapshot(
            boardID: boards.selectedBoardID,
            gridSize: model.gridSize,
            cells: model.cells.enumerated().flatMap { row, cells in
                cells.enumerated().map { col, cell in
                    MacDesktopBoardSnapshot.Cell(text: cell.isEmpty ? "" : cell.text,
                                                 completed: cell.isCompleted,
                                                 inBingo: model.isInCompletedLine(row: row, col: col))
                }
            },
            accent: desktopColor(theme.color), surface: desktopColor(theme.bingoSurfaceColor),
            outline: desktopColor(theme.bingoCellOutlineColor),
            backgroundImage: HomeBackgroundOption(rawValue: skinRaw)?.imageName,
            updatedAt: .now
        )
        snapshot.futureStates = desktopFutureStates()
        do {
            let url = MacDesktopBoardSnapshot.fileURL(in: container)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            WidgetCenter.shared.reloadTimelines(ofKind: MacDesktopBoardSnapshot.widgetKind)
        } catch {
            DiagnosticLogStore.recordWarning("mac.desktop_board_publish_failed")
        }
    }
    private func desktopFutureStates() -> [MacDesktopBoardSnapshot.FutureState] {
        guard var board = boards.selectedBoardSnapshot else { return [] }
        board.board = model.makeSavedBoardSnapshot()
        let now = Date()
        let calendar = Calendar.current
        let horizon = calendar.date(byAdding: .day, value: 14, to: now) ?? now
        var dates: Set<Date> = []
        for offset in 1...14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            dates.insert(day)
            if let reset = BoardResetRuleEngine.nextScheduledResetTime(for: board, after: day.addingTimeInterval(-1)) {
                dates.insert(reset)
            }
        }
        for cell in BoardEngine.expandedBoardCache(from: board.board).flatMap({ $0 }) {
            for date in [cell.startVisibleAt, cell.endVisibleAt, cell.countdownEndsAt].compactMap({ $0 }) where date > now && date <= horizon {
                dates.insert(date)
            }
        }
        return dates.filter { $0 > now && $0 <= horizon }.sorted().map { date in
            board = BoardResetRuleEngine.boardAfterApplyingPendingResetIfNeeded(board, now: date)
            let visible = BoardEngine.projectVisibleCells(from: BoardEngine.expandedBoardCache(from: board.board), size: board.board.gridSize, referenceDate: date)
            let lines = BoardEngine.completedLines(in: visible, size: board.board.gridSize)
            let size = board.board.gridSize
            let cells = visible.enumerated().flatMap { row, cells in
                cells.enumerated().map { col, cell in
                    let inLine = lines.contains(.row(row)) || lines.contains(.column(col)) ||
                        (row == col && lines.contains(.diagonalMain)) ||
                        (row + col == size - 1 && lines.contains(.diagonalAnti))
                    return MacDesktopBoardSnapshot.Cell(text: cell.isEmpty ? "" : cell.text, completed: cell.isCompleted, inBingo: inLine)
                }
            }
            return MacDesktopBoardSnapshot.FutureState(date: date, cells: cells)
        }
    }
    private func desktopColor(_ color: SwiftUI.Color) -> MacDesktopBoardSnapshot.PaletteColor {
        let resolved = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor.brown
        return MacDesktopBoardSnapshot.PaletteColor(red: resolved.redComponent, green: resolved.greenComponent, blue: resolved.blueComponent)
    }
}
