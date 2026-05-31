import Foundation
import AppIntents
import WidgetKit

enum WidgetPanelSelectionStore {
    static let selectedPanelKey = "widget_selected_panel_id_v1"

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: BingoBoardStore.appGroupID) ?? .standard
    }

    static func loadSelectedPanelID() -> UUID? {
        guard let raw = sharedDefaults.string(forKey: selectedPanelKey) else {
            return nil
        }
        return UUID(uuidString: raw)
    }

    static func saveSelectedPanelID(_ id: UUID?) {
        guard let id else {
            sharedDefaults.removeObject(forKey: selectedPanelKey)
            sharedDefaults.synchronize()
            return
        }
        sharedDefaults.set(id.uuidString, forKey: selectedPanelKey)
        sharedDefaults.synchronize()
    }
}

enum WidgetTaskSyncStore {
    private static let eventKey = "widget_task_sync_event_v1"
    private static let eventFileName = "widget_task_sync_event_v1.json"

    struct Event: Codable {
        let boardID: UUID
        let board: BingoBoardStore.NamedBoard
        let savedAt: Date
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: BingoBoardStore.appGroupID) ?? .standard
    }

    private static var eventFileURL: URL {
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BingoBoardStore.appGroupID) {
            let directory = containerURL.appendingPathComponent("Library/Application Support", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent(eventFileName)
        }

        #if targetEnvironment(simulator)
        let simulatorDirectory = URL(fileURLWithPath: "/tmp/\(BingoBoardStore.appGroupID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: simulatorDirectory, withIntermediateDirectories: true)
        return simulatorDirectory.appendingPathComponent(eventFileName)
        #else
        let fallbackDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: fallbackDirectory, withIntermediateDirectories: true)
        return fallbackDirectory.appendingPathComponent(eventFileName)
        #endif
    }

    static func save(board: BingoBoardStore.NamedBoard) {
        let event = Event(boardID: board.id, board: board, savedAt: board.updatedAt)
        guard let data = try? JSONEncoder().encode(event) else { return }

        try? data.write(to: eventFileURL, options: .atomic)
        sharedDefaults.set(data, forKey: eventKey)
        sharedDefaults.synchronize()
    }

    static func load() -> Event? {
        if let data = try? Data(contentsOf: eventFileURL),
           let event = try? JSONDecoder().decode(Event.self, from: data) {
            return event
        }

        guard let data = sharedDefaults.data(forKey: eventKey),
              let event = try? JSONDecoder().decode(Event.self, from: data) else {
            return nil
        }
        return event
    }

    static func loadBoard() -> SavedBoard? {
        load()?.board.board
    }

    static func loadCountdownEndsAt() -> Date? {
        load()?.board.countdownEndsAt
    }

    static func loadSavedAt() -> Date? {
        load()?.savedAt
    }

    static func clear() {
        try? FileManager.default.removeItem(at: eventFileURL)
        sharedDefaults.removeObject(forKey: eventKey)
        sharedDefaults.synchronize()
    }
}

struct SwitchBoardIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch Board"
    static var description = IntentDescription("Switches the current board shown in the large widget.")
    static var openAppWhenRun = false

    @Parameter(title: "Step")
    var step: Int

    init() {
        step = 1
    }

    init(step: Int) {
        self.step = step
    }

    func perform() async throws -> some IntentResult {
        let snapshot = BingoBoardStore.loadNamedBoardsSnapshot()
        guard snapshot.boards.count > 1 else {
            return .result()
        }

        let preferredPanelID = WidgetPanelSelectionStore.loadSelectedPanelID() ?? snapshot.selectedBoardID
        let currentIndex = snapshot.boards.firstIndex(where: { $0.id == preferredPanelID }) ?? 0
        let nextIndex = wrappedIndex(currentIndex + step, count: snapshot.boards.count)
        WidgetPanelSelectionStore.saveSelectedPanelID(snapshot.boards[nextIndex].id)

        WidgetCenter.shared.reloadTimelines(ofKind: "BingodaysLargeWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "BingodaysCountdownWidget")

        return .result()
    }

    private func wrappedIndex(_ value: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let remainder = value % count
        return remainder >= 0 ? remainder : remainder + count
    }
}

struct ToggleWidgetTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Task"
    static var description = IntentDescription("Marks a widget task complete or incomplete.")
    static var openAppWhenRun = false

    @Parameter(title: "Board ID")
    var boardID: String

    @Parameter(title: "Row")
    var row: Int

    @Parameter(title: "Column")
    var col: Int

    init() {
        boardID = ""
        row = 0
        col = 0
    }

    init(boardID: String, row: Int, col: Int) {
        self.boardID = boardID
        self.row = row
        self.col = col
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: boardID) else {
            return .result()
        }

        var snapshot = BingoBoardStore.loadNamedBoardsSnapshot()
        guard let index = snapshot.boards.firstIndex(where: { $0.id == id }) else {
            return .result()
        }

        guard let updatedBoard = WidgetTaskToggleService.toggled(
            board: snapshot.boards[index],
            row: row,
            col: col,
            now: .now
        ) else {
            return .result()
        }

        snapshot.boards[index] = updatedBoard
        snapshot.selectedBoardID = id
        WidgetTaskSyncStore.save(board: updatedBoard)
        BingoBoardStore.saveNamedBoardsSnapshot(snapshot)
        WidgetPanelSelectionStore.saveSelectedPanelID(id)

        BingoBoardStore.saveBoard(updatedBoard.board, savedAt: updatedBoard.updatedAt, associatedBoardID: id)
        BingoBoardStore.saveBoardCountdownEndsAt(updatedBoard.countdownEndsAt)

        WidgetCenter.shared.reloadTimelines(ofKind: "BingodaysLargeWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "BingodaysCountdownWidget")

        return .result()
    }
}

private enum WidgetTaskToggleService {
    private static let maxGridSize = BoardEngine.maxGridSize

    private struct Position: Hashable {
        let row: Int
        let col: Int
    }

    static func toggled(
        board namedBoard: BingoBoardStore.NamedBoard,
        row: Int,
        col: Int,
        now: Date
    ) -> BingoBoardStore.NamedBoard? {
        let preparedBoard = boardAfterApplyingPendingResetIfNeeded(namedBoard, now: now)
        let gridSize = min(max(preparedBoard.board.gridSize, 0), maxGridSize)
        guard row >= 0, col >= 0, row < gridSize, col < gridSize else {
            return nil
        }

        var fullBoard = BoardEngine.expandedBoardCache(from: preparedBoard.board)
        guard row < fullBoard.count, col < fullBoard[row].count else {
            return nil
        }

        let visibleCells = BoardEngine.projectVisibleCells(from: fullBoard, size: gridSize, referenceDate: now)
        guard row < visibleCells.count, col < visibleCells[row].count else {
            return nil
        }

        let visibleCell = visibleCells[row][col]
        guard !visibleCell.isEmpty else { return nil }
        guard !fullBoard[row][col].isVisibilityWindowInactive(on: now) else { return nil }
        guard !isLocked(row: row, col: col, in: visibleCells, referenceDate: now) else { return nil }

        let diaryTaskText = fullBoard[row][col].storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNowCompleted = !fullBoard[row][col].isCompleted

        fullBoard[row][col].isCompleted = isNowCompleted
        if isNowCompleted {
            if let deadline = fullBoard[row][col].countdownEndsAt {
                let remaining = max(Int(deadline.timeIntervalSince(now)), 0)
                fullBoard[row][col].countdownPausedRemainingSeconds = remaining > 0 ? remaining : nil
            } else {
                fullBoard[row][col].countdownPausedRemainingSeconds = nil
            }
            registerCompletionIfNeeded(cell: &fullBoard[row][col], now: now)
            fullBoard[row][col].isForced = false
            fullBoard[row][col].countdownEndsAt = nil
        } else {
            fullBoard[row][col].isTaskHidden = false
            fullBoard[row][col].completionStreakCount = max(fullBoard[row][col].completionStreakCount - 1, 0)
            if let paused = fullBoard[row][col].countdownPausedRemainingSeconds, paused > 0 {
                fullBoard[row][col].countdownEndsAt = now.addingTimeInterval(TimeInterval(paused))
            }
            fullBoard[row][col].countdownPausedRemainingSeconds = nil
            fullBoard[row][col].lastCompletedAt = nil
        }

        let updatedVisibleCells = BoardEngine.projectVisibleCells(from: fullBoard, size: gridSize, referenceDate: now)
        let completedLines = completedLines(in: updatedVisibleCells, gridSize: gridSize)
        let updatedSavedBoard = SavedBoard(
            gridSize: gridSize,
            cells: updatedVisibleCells,
            completedLines: completedLines,
            fullBoardCells: fullBoard
        )

        settleRewards(
            previousBoard: preparedBoard.board,
            updatedBoard: updatedSavedBoard,
            boardLastSavedAt: preparedBoard.updatedAt,
            now: now
        )
        BingoDiaryStore.applyExplicitTaskDelta(
            task: diaryTaskText,
            delta: isNowCompleted ? 1 : -1,
            board: updatedSavedBoard,
            on: now
        )

        var updatedNamedBoard = preparedBoard
        updatedNamedBoard.board = updatedSavedBoard
        updatedNamedBoard.lastTaskResetAppliedAt = now
        updatedNamedBoard.updatedAt = now
        return updatedNamedBoard
    }

    private static func boardAfterApplyingPendingResetIfNeeded(
        _ namedBoard: BingoBoardStore.NamedBoard,
        now: Date
    ) -> BingoBoardStore.NamedBoard {
        let calendar = Calendar.current
        let usesCustomResetTime = namedBoard.customResetMinutes != nil &&
            (namedBoard.taskResetMode == .resetStatusNextDay || namedBoard.taskResetMode == .customResetStatusTime)
        let customResetDue = usesCustomResetTime
            ? shouldApplyCustomReset(for: namedBoard, now: now, calendar: calendar)
            : false
        let alreadyAppliedToday: Bool = {
            guard let lastApplied = namedBoard.lastTaskResetAppliedAt else { return false }
            return calendar.isDate(lastApplied, inSameDayAs: now)
        }()
        let shouldApplyBySchedule: Bool = {
            if usesCustomResetTime {
                return customResetDue
            }
            switch namedBoard.taskResetMode {
            case .resetStatusNextDay, .clearTasksNextDay:
                return !alreadyAppliedToday
            case .customResetStatusTime:
                return customResetDue
            case .keepTaskStatus:
                return false
            }
        }()
        let shouldForceApplyForStaleCompletion =
            !usesCustomResetTime &&
            namedBoard.taskResetMode == .resetStatusNextDay &&
            boardHasStaleCompletedTasks(namedBoard, referenceDate: now, calendar: calendar)

        guard shouldApplyBySchedule || shouldForceApplyForStaleCompletion else {
            return namedBoard
        }

        var updatedBoard = namedBoard
        updatedBoard.board = transformedBoardSnapshotForResetMode(
            namedBoard.board,
            mode: namedBoard.taskResetMode,
            referenceDate: now
        )
        updatedBoard.lastTaskResetAppliedAt = now
        updatedBoard.updatedAt = now
        return updatedBoard
    }

    private static func shouldApplyCustomReset(
        for board: BingoBoardStore.NamedBoard,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        let clampedMinutes = min(max(board.customResetMinutes ?? 0, 0), 23 * 60 + 59)
        let startOfDay = calendar.startOfDay(for: now)
        guard let triggerTime = calendar.date(byAdding: .minute, value: clampedMinutes, to: startOfDay) else {
            return false
        }
        guard now >= triggerTime else { return false }
        guard let lastApplied = board.lastTaskResetAppliedAt else { return true }
        return lastApplied < triggerTime
    }

    private static func boardHasStaleCompletedTasks(
        _ board: BingoBoardStore.NamedBoard,
        referenceDate: Date,
        calendar: Calendar
    ) -> Bool {
        let fullBoard = BoardEngine.expandedBoardCache(from: board.board)

        for row in fullBoard {
            for cell in row {
                guard cell.isCompleted, cell.hasStoredTask else { continue }

                if let lastCompletedAt = cell.lastCompletedAt {
                    if !calendar.isDate(lastCompletedAt, inSameDayAs: referenceDate) {
                        return true
                    }
                } else if !calendar.isDate(board.updatedAt, inSameDayAs: referenceDate) {
                    return true
                }
            }
        }

        return false
    }

    private static func transformedBoardSnapshotForResetMode(
        _ board: SavedBoard,
        mode: BoardTaskResetMode,
        referenceDate: Date
    ) -> SavedBoard {
        var fullBoard: [[BingoCell]]

        switch mode {
        case .resetStatusNextDay, .customResetStatusTime:
            fullBoard = BoardEngine.expandedBoardCache(from: board)
            let calendar = Calendar.current
            for row in fullBoard.indices {
                for col in fullBoard[row].indices {
                    fullBoard[row][col] = normalizedBoardCellForNextDay(
                        fullBoard[row][col],
                        referenceDate: referenceDate,
                        calendar: calendar
                    )
                }
            }
            for row in fullBoard.indices {
                for col in fullBoard[row].indices {
                    guard !fullBoard[row][col].isEmpty else { continue }
                    fullBoard[row][col].isCompleted = false
                    fullBoard[row][col].isTaskHidden = false
                    fullBoard[row][col].countdownEndsAt = nil
                    fullBoard[row][col].countdownPausedRemainingSeconds = nil
                    fullBoard[row][col].estimatedDurationMinutes = nil
                }
            }
            normalizeForceFlagsForBoardReset(&fullBoard, referenceDate: referenceDate)
        case .clearTasksNextDay:
            fullBoard = BoardEngine.createEmptyGrid(size: maxGridSize)
        case .keepTaskStatus:
            fullBoard = BoardEngine.expandedBoardCache(from: board)
        }

        let gridSize = min(max(board.gridSize, 2), maxGridSize)
        let visibleCells: [[BingoCell]] = (0..<gridSize).map { row in
            (0..<gridSize).map { col in
                fullBoard[row][col].projectedForDisplay(on: referenceDate)
            }
        }

        return SavedBoard(
            gridSize: gridSize,
            cells: visibleCells,
            completedLines: [],
            fullBoardCells: fullBoard
        )
    }

    private static func normalizedBoardCellForNextDay(
        _ cell: BingoCell,
        referenceDate: Date,
        calendar: Calendar
    ) -> BingoCell {
        var updated = cell

        if updated.isForced, updated.isCompleted {
            updated.isForced = false
        }

        if updated.isOneTimeTask,
           let oneTimeVisibleDate = updated.oneTimeVisibleDate,
           !calendar.isDate(oneTimeVisibleDate, inSameDayAs: referenceDate) {
            updated.text = ""
            updated.residentTaskText = nil
            updated.residentWeekdays = []
            updated.oneTimeVisibleDate = nil
            updated.isTaskHidden = false
            updated.isForced = false
            updated.countdownEndsAt = nil
            updated.countdownPausedRemainingSeconds = nil
            updated.estimatedDurationMinutes = nil
            updated.completionStreakCount = 0
            updated.lastCompletedAt = nil
            updated.isCompleted = false
        }

        return updated
    }

    private static func normalizeForceFlagsForBoardReset(
        _ fullBoard: inout [[BingoCell]],
        referenceDate: Date
    ) {
        var forcedPositions: [(row: Int, col: Int)] = []

        for row in fullBoard.indices {
            for col in fullBoard[row].indices {
                guard fullBoard[row][col].isForced else { continue }

                if !fullBoard[row][col].hasStoredTask || fullBoard[row][col].isCompleted {
                    fullBoard[row][col].isForced = false
                    continue
                }

                forcedPositions.append((row, col))
            }
        }

        guard forcedPositions.count > 1 else { return }

        let keepPosition = forcedPositions.first {
            let projected = fullBoard[$0.row][$0.col].projectedForDisplay(on: referenceDate)
            return !projected.isEmpty
        } ?? forcedPositions[0]

        for position in forcedPositions where !(position.row == keepPosition.row && position.col == keepPosition.col) {
            fullBoard[position.row][position.col].isForced = false
        }
    }

    private static func isLocked(
        row: Int,
        col: Int,
        in cells: [[BingoCell]],
        referenceDate: Date
    ) -> Bool {
        let activeForcedPositions = activeForcedPositions(in: cells, referenceDate: referenceDate)
        guard !activeForcedPositions.isEmpty else { return false }
        return !activeForcedPositions.contains(Position(row: row, col: col))
    }

    private static func activeForcedPositions(
        in cells: [[BingoCell]],
        referenceDate: Date
    ) -> Set<Position> {
        var positions: Set<Position> = []

        for row in cells.indices {
            for col in cells[row].indices {
                let cell = cells[row][col]
                if cell.isForced && !cell.isCompleted && !cell.isEmpty && !cell.isVisibilityWindowInactive(on: referenceDate) {
                    positions.insert(Position(row: row, col: col))
                }
            }
        }

        return positions
    }

    private static func registerCompletionIfNeeded(cell: inout BingoCell, now: Date) {
        let calendar = Calendar.current
        if let lastCompletedAt = cell.lastCompletedAt,
           calendar.isDate(lastCompletedAt, inSameDayAs: now) {
            cell.lastCompletedAt = now
            return
        }

        cell.completionStreakCount += 1
        cell.lastCompletedAt = now
    }

    private static func completedLines(in cells: [[BingoCell]], gridSize: Int) -> Set<BingoLine> {
        var currentLines: Set<BingoLine> = []

        for row in 0..<gridSize where row < cells.count {
            let rowCells = Array(cells[row].prefix(gridSize))
            if rowCells.count == gridSize && rowCells.allSatisfy({ $0.isCompleted && !$0.isEmpty }) {
                currentLines.insert(.row(row))
            }
        }

        for col in 0..<gridSize {
            var allCompleted = true
            for row in 0..<gridSize {
                guard row < cells.count, col < cells[row].count,
                      cells[row][col].isCompleted, !cells[row][col].isEmpty else {
                    allCompleted = false
                    break
                }
            }
            if allCompleted {
                currentLines.insert(.column(col))
            }
        }

        var mainDiagonalCompleted = true
        for index in 0..<gridSize {
            guard index < cells.count, index < cells[index].count,
                  cells[index][index].isCompleted, !cells[index][index].isEmpty else {
                mainDiagonalCompleted = false
                break
            }
        }
        if mainDiagonalCompleted {
            currentLines.insert(.diagonalMain)
        }

        var antiDiagonalCompleted = true
        for index in 0..<gridSize {
            let col = gridSize - 1 - index
            guard index < cells.count, col < cells[index].count,
                  cells[index][col].isCompleted, !cells[index][col].isEmpty else {
                antiDiagonalCompleted = false
                break
            }
        }
        if antiDiagonalCompleted {
            currentLines.insert(.diagonalAnti)
        }

        return currentLines
    }

    private static func settleRewards(
        previousBoard: SavedBoard,
        updatedBoard: SavedBoard,
        boardLastSavedAt: Date,
        now: Date
    ) {
        let previousCells = previousBoard.cells
        let previousCompletedLines = previousBoard.completedLines
        let initialTotalPoints = PointsStore.loadTotalPoints() ?? boardScore(
            cells: previousCells,
            completedLines: previousCompletedLines
        )
        let initialLifetimePoints = PointsStore.loadLifetimePoints() ?? initialTotalPoints
        let initialDailyRewardState = PointsStore.loadDailyRewardState() ?? BingoRewardSettlement.initialDailyRewardState(
            referenceDate: now,
            boardLastSavedAt: boardLastSavedAt,
            currentCells: previousCells,
            currentCompletedLines: previousCompletedLines,
            isBoardFullyCompleted: isBoardFullyCompleted(previousCells)
        )

        let output = BingoRewardSettlement.settle(
            input: BingoRewardSettlementInput(
                date: now,
                cells: updatedBoard.cells,
                completedLines: updatedBoard.completedLines,
                isBoardFullyCompleted: isBoardFullyCompleted(updatedBoard.cells),
                totalPoints: initialTotalPoints,
                lifetimePoints: initialLifetimePoints,
                dailyRewardState: initialDailyRewardState,
                nonRevocableConsumedPoints: BingoRewardSettlement.nonRevocableConsumedPointsTotal()
            ),
            mode: .normal
        )

        PointsStore.saveTotalPoints(output.totalPoints)
        PointsStore.saveLifetimePoints(output.lifetimePoints)
        PointsStore.saveDailyRewardState(output.dailyRewardState)
    }

    private static func boardScore(cells: [[BingoCell]], completedLines: Set<BingoLine>) -> Int {
        let completedTaskCount = cells
            .flatMap { $0 }
            .filter { $0.isCompleted && !$0.isEmpty }
            .count
        let allTasksCompletedBonus = isBoardFullyCompleted(cells) ? 10 : 0
        return completedTaskCount + (completedLines.count * 5) + allTasksCompletedBonus
    }

    private static func isBoardFullyCompleted(_ cells: [[BingoCell]]) -> Bool {
        let allCells = cells.flatMap { $0 }
        return !allCells.isEmpty && allCells.allSatisfy { !$0.isEmpty && $0.isCompleted }
    }
}
