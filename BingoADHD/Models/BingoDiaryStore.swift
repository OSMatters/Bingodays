import Foundation

enum BingoDiaryStore {
    private static let key = "bingo_diary_v1"

    static func save(board: SavedBoard, on date: Date = .now) {
        persist(entriesBySaving(board: board, on: date, entries: loadEntriesDictionary()))
    }

    static func entriesBySaving(
        board: SavedBoard,
        on date: Date,
        entries existingEntries: [String: BingoDiaryEntry]
    ) -> [String: BingoDiaryEntry] {
        var entries = existingEntries
        let entryID = dateKey(for: date)
        let existingEntry = entries[entryID]
        let transitions = completedTaskTransitions(
            previousBoard: existingEntry?.board,
            currentBoard: board
        )
        let mergedCounts = applyTaskCountDelta(
            base: existingTaskCounts(from: existingEntry),
            increments: transitions.increments,
            decrements: transitions.decrements
        )
        let entry = BingoDiaryEntry(
            id: entryID,
            date: Calendar.current.startOfDay(for: date),
            board: board,
            allTasksCompleted: (existingEntry?.allTasksCompleted ?? false) || boardHasAllTasksCompleted(board),
            completedTaskCounts: mergedCounts
        )
        entries[entry.id] = entry
        return entries
    }

    @discardableResult
    static func applyExplicitTaskDelta(
        task: String,
        delta: Int,
        board: SavedBoard,
        on date: Date = .now
    ) -> Bool {
        persist(entriesByApplyingExplicitTaskDelta(
            task: task,
            delta: delta,
            board: board,
            on: date,
            entries: loadEntriesDictionary()
        ))
    }

    static func entriesByApplyingExplicitTaskDelta(
        task: String,
        delta: Int,
        board: SavedBoard,
        on date: Date,
        entries existingEntries: [String: BingoDiaryEntry]
    ) -> [String: BingoDiaryEntry] {
        let entryID = dateKey(for: date)
        let existingEntry = existingEntries[entryID]
        let normalizedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTask.isEmpty else {
            return entriesBySyncingBoardSnapshotWithoutCounting(
                board: board,
                on: date,
                entries: existingEntries
            )
        }

        var entries = existingEntries
        var mergedCounts = existingTaskCounts(from: existingEntry)

        if delta > 0 {
            mergedCounts[normalizedTask, default: 0] += delta
        } else if delta < 0 {
            let current = mergedCounts[normalizedTask, default: 0]
            let next = max(0, current + delta)
            if next == 0 {
                mergedCounts.removeValue(forKey: normalizedTask)
            } else {
                mergedCounts[normalizedTask] = next
            }
        }

        let entry = BingoDiaryEntry(
            id: entryID,
            date: Calendar.current.startOfDay(for: date),
            board: board,
            allTasksCompleted: (existingEntry?.allTasksCompleted ?? false) || boardHasAllTasksCompleted(board),
            completedTaskCounts: mergedCounts
        )
        entries[entry.id] = entry
        return entries
    }

    // Keep today's baseline board snapshot in sync even when diary counting is skipped.
    // This prevents stale snapshot diffs from causing large decrement/increment jumps later.
    static func syncBoardSnapshotWithoutCounting(board: SavedBoard, on date: Date = .now) {
        persist(entriesBySyncingBoardSnapshotWithoutCounting(
            board: board,
            on: date,
            entries: loadEntriesDictionary()
        ))
    }

    static func entriesBySyncingBoardSnapshotWithoutCounting(
        board: SavedBoard,
        on date: Date,
        entries existingEntries: [String: BingoDiaryEntry]
    ) -> [String: BingoDiaryEntry] {
        var entries = existingEntries
        let entryID = dateKey(for: date)
        guard let existingEntry = entries[entryID] else { return entries }

        let updatedEntry = BingoDiaryEntry(
            id: existingEntry.id,
            date: existingEntry.date,
            board: board,
            allTasksCompleted: existingEntry.allTasksCompleted || boardHasAllTasksCompleted(board),
            completedTaskCounts: existingEntry.completedTaskCounts
        )
        entries[entryID] = updatedEntry
        return entries
    }

    static func entry(for date: Date) -> BingoDiaryEntry? {
        loadEntriesDictionary()[dateKey(for: date)]
    }

    static func entries(inMonthContaining date: Date) -> [BingoDiaryEntry] {
        let calendar = Calendar.current
        let monthInterval = calendar.dateInterval(of: .month, for: date)

        return loadEntriesDictionary().values
            .filter { entry in
                guard let interval = monthInterval else { return false }
                return interval.contains(entry.date)
            }
            .sorted { $0.date < $1.date }
    }

    static func consecutiveBingoDays(referenceDate: Date = .now) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        let entries = loadEntriesDictionary()

        var streak = 0
        var cursor = today

        while let entry = entries[dateKey(for: cursor)], entry.allTasksCompleted {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }

        return streak
    }

    static func consecutiveTaskCompletionDays(referenceDate: Date = .now) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        let entries = loadEntriesDictionary()

        var streak = 0
        var cursor = today

        while let entry = entries[dateKey(for: cursor)],
              existingTaskCounts(from: entry).values.contains(where: { $0 > 0 }) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }

        return streak
    }

    static func totalCompletedTasks() -> Int {
        allTimeCompletedTaskCounts().reduce(0) { $0 + $1.count }
    }

    static func allTimeCompletedTaskCounts() -> [(task: String, count: Int)] {
        let stats = allTimeCompletedTaskStats()

        return stats.map { (task: $0.task, count: $0.count) }
    }

    static func allTimeCompletedTaskStats() -> [(task: String, count: Int, firstCompletedAt: Date)] {
        struct TaskAggregate {
            var count: Int
            var firstCompletedAt: Date
        }

        let entries = loadEntriesDictionary()

        let stats = entries.values.reduce(into: [String: TaskAggregate]()) { partial, entry in
            let day = Calendar.current.startOfDay(for: entry.date)
            for (task, count) in existingTaskCounts(from: entry) {
                guard !task.isEmpty, count > 0 else { continue }
                if let existing = partial[task] {
                    partial[task] = TaskAggregate(
                        count: existing.count + count,
                        firstCompletedAt: min(existing.firstCompletedAt, day)
                    )
                } else {
                    partial[task] = TaskAggregate(count: count, firstCompletedAt: day)
                }
            }
        }

        return stats
            .map { (task: $0.key, count: $0.value.count, firstCompletedAt: $0.value.firstCompletedAt) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    if lhs.firstCompletedAt == rhs.firstCompletedAt {
                        return lhs.task.localizedCaseInsensitiveCompare(rhs.task) == .orderedAscending
                    }
                    return lhs.firstCompletedAt < rhs.firstCompletedAt
                }
                return lhs.count > rhs.count
            }
    }

    static func taskDailyCompletions(
        task: String,
        limit: Int = 30,
        referenceDate: Date = .now
    ) -> [(date: Date, count: Int)] {
        let normalizedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTask.isEmpty else { return [] }

        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: referenceDate)
        let rows = loadEntriesDictionary().values.compactMap { entry -> (date: Date, count: Int)? in
            let day = calendar.startOfDay(for: entry.date)
            guard day <= endDate else { return nil }
            let count = existingTaskCounts(from: entry)[normalizedTask] ?? 0
            guard count > 0 else { return nil }
            return (date: day, count: count)
        }
        .sorted { $0.date > $1.date }

        guard limit > 0 else { return rows }
        return Array(rows.prefix(limit))
    }

    static func taskCompletionsThisWeek(
        task: String,
        referenceDate: Date = .now
    ) -> Int {
        let normalizedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTask.isEmpty else { return 0 }
        let calendar = Calendar.current
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else { return 0 }

        return loadEntriesDictionary().values.reduce(0) { partial, entry in
            let day = calendar.startOfDay(for: entry.date)
            guard weekInterval.contains(day) else { return partial }
            return partial + (existingTaskCounts(from: entry)[normalizedTask] ?? 0)
        }
    }

    static func completedTaskCounts(lastDays: Int, referenceDate: Date = .now) -> [(task: String, count: Int)] {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: referenceDate)
        guard let startDate = calendar.date(byAdding: .day, value: -(max(lastDays, 1) - 1), to: endDate) else {
            return []
        }

        let counts = loadEntriesDictionary().values.reduce(into: [String: Int]()) { partial, entry in
            let day = calendar.startOfDay(for: entry.date)
            guard day >= startDate && day <= endDate else { return }

            for (task, count) in existingTaskCounts(from: entry) {
                guard !task.isEmpty, count > 0 else { continue }
                partial[task, default: 0] += count
            }
        }

        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
                }
                return lhs.value > rhs.value
            }
            .map { (task: $0.key, count: $0.value) }
    }

    static func taskCompletionStats(
        lastDays: Int,
        referenceDate: Date = .now
    ) -> [(task: String, totalCount: Int, activeDays: Int, completionRate: Double, dailyCounts: [Int])] {
        let calendar = Calendar.current
        let days = max(lastDays, 1)
        let endDate = calendar.startOfDay(for: referenceDate)
        guard let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: endDate) else {
            return []
        }

        var dayIndexByKey: [String: Int] = [:]
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDate) else { continue }
            dayIndexByKey[dateKey(for: day)] = offset
        }

        let emptyDailyCounts = Array(repeating: 0, count: days)
        var taskDailyCounts: [String: [Int]] = [:]

        for entry in loadEntriesDictionary().values {
            let entryKey = dateKey(for: entry.date)
            guard let dayIndex = dayIndexByKey[entryKey] else { continue }

            for (task, count) in existingTaskCounts(from: entry) {
                guard !task.isEmpty, count > 0 else { continue }
                var counts = taskDailyCounts[task] ?? emptyDailyCounts
                counts[dayIndex] += count
                taskDailyCounts[task] = counts
            }
        }

        return taskDailyCounts
            .map { task, dailyCounts in
                let totalCount = dailyCounts.reduce(0, +)
                let activeDays = dailyCounts.reduce(0) { $0 + ($1 > 0 ? 1 : 0) }
                let completionRate = Double(activeDays) / Double(days)
                return (task: task, totalCount: totalCount, activeDays: activeDays, completionRate: completionRate, dailyCounts: dailyCounts)
            }
            .sorted { lhs, rhs in
                if lhs.totalCount == rhs.totalCount {
                    return lhs.task.localizedCaseInsensitiveCompare(rhs.task) == .orderedAscending
                }
                return lhs.totalCount > rhs.totalCount
            }
    }

    static func loadAllEntriesDictionary(
        reading mode: PersistenceReadMode = .repairingMirrors
    ) -> [String: BingoDiaryEntry] {
        loadEntriesDictionary(reading: mode)
    }

    @discardableResult
    static func replaceAllEntriesDictionary(_ entries: [String: BingoDiaryEntry]) -> Bool {
        persist(entries)
    }

    private static func loadEntriesDictionary(
        reading mode: PersistenceReadMode = .repairingMirrors
    ) -> [String: BingoDiaryEntry] {
        if let data = sharedDefaults.data(forKey: key),
           let entries = try? JSONDecoder().decode([String: BingoDiaryEntry].self, from: data) {
            if mode == .repairingMirrors,
               UserDefaults.standard.data(forKey: key) != data {
                _ = PersistenceWriteTransaction.commit([
                    PersistenceWriteTransaction.userDefaultsStep(
                        defaults: .standard,
                        key: key,
                        newValue: data
                    )
                ])
            }
            return entries
        }

        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([String: BingoDiaryEntry].self, from: data) else {
            return [:]
        }
        if mode == .repairingMirrors {
            _ = PersistenceWriteTransaction.commit([
                PersistenceWriteTransaction.userDefaultsStep(
                    defaults: sharedDefaults,
                    key: key,
                    newValue: data
                )
            ])
        }
        return entries
    }

    @discardableResult
    private static func persist(_ entries: [String: BingoDiaryEntry]) -> Bool {
        guard let data = try? JSONEncoder().encode(entries) else { return false }
        return PersistenceWriteTransaction.commit([
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: key,
                newValue: data
            ),
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: .standard,
                key: key,
                newValue: data
            )
        ])
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: BingoBoardStore.appGroupID) ?? .standard
    }

    private static func boardHasAllTasksCompleted(_ board: SavedBoard) -> Bool {
        let taskCells = board.cells.flatMap { $0 }.filter { !$0.isEmpty }
        guard !taskCells.isEmpty else { return false }
        return taskCells.allSatisfy(\.isCompleted)
    }

    private static func completedTaskCounts(from board: SavedBoard) -> [String: Int] {
        board.cells
            .flatMap { $0 }
            .reduce(into: [String: Int]()) { partial, cell in
                guard cell.isCompleted, !cell.isEmpty else { return }
                let task = cell.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !task.isEmpty else { return }
                partial[task, default: 0] += 1
            }
    }

    // Count only completion transitions from previous snapshot -> current snapshot.
    // This avoids undercounting repeated completions (old max-merge logic) and
    // avoids double counting on frequent saves when no state changed.
    private static func completedTaskTransitions(
        previousBoard: SavedBoard?, currentBoard: SavedBoard
    ) -> (increments: [String: Int], decrements: [String: Int]) {
        let previousCells = flattenedVisibleCells(from: previousBoard)
        let currentCells = flattenedVisibleCells(from: currentBoard)
        var duplicateIDs = Set<UUID>()
        func indexedCells(_ cells: [BingoCell]) -> [UUID: BingoCell] {
            var result: [UUID: BingoCell] = [:]
            for cell in cells {
                if result.updateValue(cell, forKey: cell.id) != nil {
                    duplicateIDs.insert(cell.id)
                }
            }
            return result
        }
        let previousByID = indexedCells(previousCells)
        let currentByID = indexedCells(currentCells)
        if !duplicateIDs.isEmpty {
            DiagnosticLogStore.recordWarning("diary.ambiguous_cell_identity", details: [
                "duplicate_id_count": String(duplicateIDs.count)
            ])
        }

        // An ambiguous identity cannot establish a completion transition. Keep
        // existing counts and still process unaffected cells; never guess which
        // duplicate is authoritative or count the same identity twice.
        let increments = currentCells.reduce(into: [String: Int]()) { partial, cell in
            guard !duplicateIDs.contains(cell.id) else { return }
            guard !cell.isEmpty, cell.isCompleted else { return }
            let task = cell.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !task.isEmpty else { return }

            // First save of the day: existing entry may not exist yet.
            let wasCompleted = previousByID[cell.id]?.isCompleted ?? false
            guard !wasCompleted else { return }

            partial[task, default: 0] += 1
        }
        let decrements = previousCells.reduce(into: [String: Int]()) { partial, previousCell in
            guard !duplicateIDs.contains(previousCell.id) else { return }
            guard !previousCell.isEmpty, previousCell.isCompleted else { return }
            let task = previousCell.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !task.isEmpty else { return }

            // Only explicit same-cell uncheck should decrement diary count.
            // If a cell was replaced/rebuilt (ID missing), do not treat it as a cancel.
            guard let currentCell = currentByID[previousCell.id] else { return }
            guard !currentCell.isCompleted else { return }

            partial[task, default: 0] += 1
        }
        return (increments, decrements)
    }

    private static func flattenedVisibleCells(from board: SavedBoard?) -> [BingoCell] {
        guard let board else { return [] }

        let resolvedGridSize = max(0, min(board.gridSize, 5))
        if let fullBoardCells = board.fullBoardCells, !fullBoardCells.isEmpty, resolvedGridSize > 0 {
            var flattened: [BingoCell] = []
            flattened.reserveCapacity(resolvedGridSize * resolvedGridSize)

            let rowUpperBound = min(resolvedGridSize, fullBoardCells.count)
            for row in 0..<rowUpperBound {
                let colUpperBound = min(resolvedGridSize, fullBoardCells[row].count)
                guard colUpperBound > 0 else { continue }
                flattened.append(contentsOf: fullBoardCells[row].prefix(colUpperBound))
            }

            if !flattened.isEmpty {
                return flattened
            }
        }
        return board.cells.flatMap { $0 }
    }

    private static func existingTaskCounts(from entry: BingoDiaryEntry?) -> [String: Int] {
        guard let entry else { return [:] }
        if !entry.completedTaskCounts.isEmpty {
            return entry.completedTaskCounts
        }
        return completedTaskCounts(from: entry.board)
    }

    private static func applyTaskCountDelta(
        base: [String: Int],
        increments: [String: Int],
        decrements: [String: Int]
    ) -> [String: Int] {
        var merged = base

        for (task, count) in increments where count > 0 {
            merged[task, default: 0] += count
        }

        for (task, count) in decrements where count > 0 {
            let current = merged[task, default: 0]
            let next = max(0, current - count)
            if next == 0 {
                merged.removeValue(forKey: task)
            } else {
                merged[task] = next
            }
        }

        return merged
    }

    private struct TaskStreakBound {
        var maxStreak: Int
        var firstCompletedAt: Date
    }

    private static func completionStreakLowerBounds(
        from entries: [String: BingoDiaryEntry],
        calendar: Calendar
    ) -> [String: TaskStreakBound] {
        var result: [String: TaskStreakBound] = [:]

        for entry in entries.values {
            let sourceCells: [[BingoCell]] = {
                if let fullBoard = entry.board.fullBoardCells, !fullBoard.isEmpty {
                    return fullBoard
                }
                return entry.board.cells
            }()

            for cell in sourceCells.flatMap({ $0 }) {
                let task = cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
                // Keep same-day complete -> cancel reversible, while preserving
                // historical fallback for previous-day completions.
                guard !task.isEmpty, cell.completionStreakCount > 0 else { continue }
                let completionDate = calendar.startOfDay(for: cell.lastCompletedAt ?? entry.date)
                let isHistoricalCompletion = completionDate < calendar.startOfDay(for: Date())
                guard cell.isCompleted || isHistoricalCompletion else { continue }

                if let existing = result[task] {
                    result[task] = TaskStreakBound(
                        maxStreak: max(existing.maxStreak, cell.completionStreakCount),
                        firstCompletedAt: min(existing.firstCompletedAt, completionDate)
                    )
                } else {
                    result[task] = TaskStreakBound(
                        maxStreak: cell.completionStreakCount,
                        firstCompletedAt: completionDate
                    )
                }
            }
        }

        return result
    }

    private static func dateKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
