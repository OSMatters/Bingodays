import Foundation

enum CommonTasksStore {
    static func load() -> [String] {
        loadLibrary().tasks.map(\.trimmedText)
    }

    static func loadLibrary() -> MyTasksLibrary {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: AppSettings.commonTasksKey),
           let saved = try? JSONDecoder().decode(MyTasksLibrary.self, from: data) {
            return sanitize(saved)
        }

        if let saved = defaults.array(forKey: AppSettings.commonTasksKey) as? [String] {
            let legacyTasks = saved.map { MyTaskItem(text: $0) }
            return MyTasksLibrary(tasks: sanitizeTasks(legacyTasks), groups: [])
        }
        return MyTasksLibrary()
    }

    static func loadGroups() -> [MyTaskGroup] {
        loadLibrary().groups
    }

    static func save(_ tasks: [String]) {
        var library = loadLibrary()
        library.tasks = tasks.map { MyTaskItem(text: $0) }
        saveLibrary(library)
    }

    @discardableResult
    static func saveLibrary(_ library: MyTasksLibrary) -> Bool {
        let sanitized = sanitize(library)
        guard let data = try? JSONEncoder().encode(sanitized) else { return false }
        UserDefaults.standard.set(data, forKey: AppSettings.commonTasksKey)
        let didSave = UserDefaults.standard.data(forKey: AppSettings.commonTasksKey) == data
        if didSave {
            NativeICloudLocalChangeReporter.secondaryStateDidChange()
        }
        return didSave
    }

    private static func sanitize(_ library: MyTasksLibrary) -> MyTasksLibrary {
        MyTasksLibrary(
            tasks: sanitizeTasks(library.tasks),
            groups: sanitizeGroups(library.groups)
        )
    }

    private static func sanitizeTasks(_ tasks: [MyTaskItem]) -> [MyTaskItem] {
        tasks
            .compactMap { task in
                var sanitized = task
                sanitized.text = String(task.text.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
                sanitized.normalizeStartDate()
                return sanitized.trimmedText.isEmpty ? nil : sanitized
            }
    }

    private static func sanitizeGroups(_ groups: [MyTaskGroup]) -> [MyTaskGroup] {
        groups
            .compactMap { group in
                let trimmedName = String(group.name.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
                let sanitizedTasks = sanitizeTasks(group.tasks)

                guard !trimmedName.isEmpty || !sanitizedTasks.isEmpty else { return nil }
                return MyTaskGroup(
                    id: group.id,
                    name: trimmedName.isEmpty ? L10n.groupDefaultName : trimmedName,
                    tasks: sanitizedTasks
                )
            }
    }
}

enum TaskHistoryStore {
    private static let maxHistoryCount = 600

    static func load() -> [TaskHistoryRecord] {
        guard let data = UserDefaults.standard.data(forKey: AppSettings.taskHistoryKey),
              let records = try? JSONDecoder().decode([TaskHistoryRecord].self, from: data) else {
            return []
        }
        return sanitize(records)
    }

    @discardableResult
    static func save(_ records: [TaskHistoryRecord]) -> Bool {
        let sanitized = sanitize(records)
        guard let data = try? JSONEncoder().encode(sanitized) else { return false }
        UserDefaults.standard.set(data, forKey: AppSettings.taskHistoryKey)
        let didSave = UserDefaults.standard.data(forKey: AppSettings.taskHistoryKey) == data
        if didSave {
            NativeICloudLocalChangeReporter.secondaryStateDidChange()
        }
        return didSave
    }

    static func deleteRecord(withKey key: String) {
        var records = load()
        records.removeAll { $0.key == key }
        save(records)
    }

    static func makeKey(for task: MyTaskItem, sourceTaskID: UUID? = nil) -> String {
        if let sourceTaskID {
            return "task:\(sourceTaskID.uuidString)"
        }

        let normalizedText = String(task.trimmedText.prefix(AppSettings.maxTaskLength)).lowercased()
        let startPart = task.startAt?.ISO8601Format() ?? "\(task.startMonth.map(String.init) ?? "nil")-\(task.startDay.map(String.init) ?? "nil")"
        let endPart = task.endAt?.ISO8601Format() ?? "nil"
        return "text:\(normalizedText)|\(startPart)|\(endPart)"
    }

    @discardableResult
    static func upsert(task: MyTaskItem, sourceTaskID: UUID? = nil, at date: Date = .now) -> Bool {
        var records = load()
        guard upsert(task: task, sourceTaskID: sourceTaskID, at: date, into: &records) else {
            return true
        }
        return save(records)
    }

    @discardableResult
    static func upsertBoardTasks(_ tasks: [MyTaskItem], at date: Date = .now) -> Bool {
        var records = load()
        var didChange = false
        for task in tasks {
            didChange = upsert(task: task, sourceTaskID: nil, at: date, into: &records) || didChange
        }
        return !didChange || save(records)
    }

    @discardableResult
    static func archive(board: SavedBoard, at date: Date = .now) -> Bool {
        save(archivedRecords(for: board, baseRecords: load(), at: date))
    }

    /// Builds an archive without writing it. Board import includes this value in
    /// its all-or-nothing local persistence transaction with the board snapshot.
    static func archivedRecords(
        for board: SavedBoard,
        baseRecords: [TaskHistoryRecord],
        at date: Date = .now
    ) -> [TaskHistoryRecord] {
        var records = baseRecords
        for task in archiveTasks(from: board) {
            _ = upsert(task: task, sourceTaskID: nil, at: date, into: &records)
        }
        return sanitize(records)
    }

    static func persistenceStep(replacing records: [TaskHistoryRecord]) -> PersistenceWriteStep? {
        guard let data = try? JSONEncoder().encode(sanitize(records)) else { return nil }
        return PersistenceWriteTransaction.userDefaultsStep(
            defaults: .standard,
            key: AppSettings.taskHistoryKey,
            newValue: data
        )
    }

    @discardableResult
    private static func upsert(
        task: MyTaskItem,
        sourceTaskID: UUID?,
        at date: Date,
        into records: inout [TaskHistoryRecord]
    ) -> Bool {
        var sanitizedTask = task
        sanitizedTask.text = String(task.text.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        sanitizedTask.normalizeVisibilityWindow()
        guard !sanitizedTask.trimmedText.isEmpty else { return false }

        let key = makeKey(for: sanitizedTask, sourceTaskID: sourceTaskID)

        if let index = records.firstIndex(where: { $0.key == key }) {
            records[index].text = sanitizedTask.trimmedText
            records[index].startAt = sanitizedTask.startAt
            records[index].endAt = sanitizedTask.endAt
            records[index].startMonth = sanitizedTask.startMonth
            records[index].startDay = sanitizedTask.startDay
            records[index].recurrenceRule = sanitizedTask.recurrenceRule
            records[index].sourceTaskID = sourceTaskID
            records[index].lastEditedAt = date
            records[index].normalizeVisibilityWindow()
        } else {
            records.append(
                TaskHistoryRecord(
                    key: key,
                    text: sanitizedTask.trimmedText,
                    startAt: sanitizedTask.startAt,
                    endAt: sanitizedTask.endAt,
                    startMonth: sanitizedTask.startMonth,
                    startDay: sanitizedTask.startDay,
                    recurrenceRule: sanitizedTask.recurrenceRule,
                    sourceTaskID: sourceTaskID,
                    lastEditedAt: date
                )
            )
        }
        return true
    }

    private static func archiveTasks(from board: SavedBoard) -> [MyTaskItem] {
        let boardCells = board.fullBoardCells ?? board.cells
        return boardCells.flatMap { $0 }.compactMap { cell -> MyTaskItem? in
            let text = cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return MyTaskItem(
                text: String(text.prefix(AppSettings.maxTaskLength)),
                startAt: cell.startVisibleAt,
                endAt: cell.endVisibleAt,
                startMonth: cell.startVisibleMonth,
                startDay: cell.startVisibleDay,
                recurrenceRule: cell.recurrenceRule
            )
        }
    }

    static func upsert(tasks: [MyTaskItem], at date: Date = .now) {
        for task in tasks {
            upsert(task: task, sourceTaskID: task.id, at: date)
        }
    }

    static func ensureLibrarySeeded(_ library: MyTasksLibrary, at date: Date = .now) {
        var records = load()
        var existingKeys = Set(records.map(\.key))

        for task in library.tasks {
            var sanitizedTask = task
            sanitizedTask.text = String(task.text.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
            sanitizedTask.normalizeVisibilityWindow()
            guard !sanitizedTask.trimmedText.isEmpty else { continue }

            let key = makeKey(for: sanitizedTask, sourceTaskID: task.id)
            guard !existingKeys.contains(key) else { continue }
            records.append(
                TaskHistoryRecord(
                    key: key,
                    text: sanitizedTask.trimmedText,
                    startAt: sanitizedTask.startAt,
                    endAt: sanitizedTask.endAt,
                    startMonth: sanitizedTask.startMonth,
                    startDay: sanitizedTask.startDay,
                    recurrenceRule: sanitizedTask.recurrenceRule,
                    sourceTaskID: task.id,
                    lastEditedAt: date
                )
            )
            existingKeys.insert(key)
        }

        for group in library.groups {
            for task in group.tasks {
                var sanitizedTask = task
                sanitizedTask.text = String(task.text.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
                sanitizedTask.normalizeVisibilityWindow()
                guard !sanitizedTask.trimmedText.isEmpty else { continue }

                let key = makeKey(for: sanitizedTask, sourceTaskID: task.id)
                guard !existingKeys.contains(key) else { continue }
                records.append(
                    TaskHistoryRecord(
                        key: key,
                        text: sanitizedTask.trimmedText,
                        startAt: sanitizedTask.startAt,
                        endAt: sanitizedTask.endAt,
                        startMonth: sanitizedTask.startMonth,
                        startDay: sanitizedTask.startDay,
                        recurrenceRule: sanitizedTask.recurrenceRule,
                        sourceTaskID: task.id,
                        lastEditedAt: date
                    )
                )
                existingKeys.insert(key)
            }
        }

        save(records)
    }

    private static func sanitize(_ records: [TaskHistoryRecord]) -> [TaskHistoryRecord] {
        var deduplicated: [String: TaskHistoryRecord] = [:]

        for rawRecord in records {
            var record = rawRecord
            record.text = String(record.text.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
            record.normalizeVisibilityWindow()
            guard !record.trimmedText.isEmpty else { continue }

            if let existing = deduplicated[record.key] {
                deduplicated[record.key] = existing.lastEditedAt >= record.lastEditedAt ? existing : record
            } else {
                deduplicated[record.key] = record
            }
        }

        return deduplicated.values
            .sorted { lhs, rhs in
                if lhs.lastEditedAt != rhs.lastEditedAt {
                    return lhs.lastEditedAt > rhs.lastEditedAt
                }
                return lhs.key < rhs.key
            }
            .prefix(maxHistoryCount)
            .map { $0 }
    }
}

/// Pure rules for completion-count inheritance. The matching key deliberately
/// contains only normalized task text: schedules, boards, task IDs, completion
/// state, timers, force mode, and rewards are not part of this history.
enum TaskCompletionHistoryRuleEngine {
    /// A first completion is already communicated by the task's completed
    /// state. The count badge becomes useful only once it represents a repeat.
    static func shouldDisplayCompletionHistoryBadge(count: Int) -> Bool {
        count >= 2
    }

    static func normalizedKey(for taskText: String, maxLength: Int = AppSettings.maxTaskLength) -> String? {
        let limited = String(taskText.prefix(maxLength))
        let collapsedWhitespace = limited
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let normalized = collapsedWhitespace
            .precomposedStringWithCompatibilityMapping
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
        return normalized.isEmpty ? nil : normalized
    }

    static func completionCount(for taskText: String, in records: [TaskCompletionHistoryRecord]) -> Int {
        guard let key = normalizedKey(for: taskText) else { return 0 }
        return records.first(where: { $0.key == key })?.completionCount ?? 0
    }

    /// Projects the name-scoped completion-history ledger onto one board. A
    /// board's stored count is only a display cache; the history ledger is the
    /// authority once migration has completed. This deliberately changes no
    /// task state other than `completionStreakCount`.
    static func boardByReconcilingCompletionHistory(
        _ board: SavedBoard,
        records: [TaskCompletionHistoryRecord]
    ) -> SavedBoard {
        let countsByKey = Dictionary(
            uniqueKeysWithValues: normalizedRecords(records).map { ($0.key, $0.completionCount) }
        )

        func reconciledCells(_ source: [[BingoCell]]) -> [[BingoCell]] {
            source.map { row in
                row.map { cell in
                    guard let key = normalizedKey(for: cell.storedTaskText) else {
                        return cell
                    }
                    var reconciled = cell
                    reconciled.completionStreakCount = countsByKey[key] ?? 0
                    return reconciled
                }
            }
        }

        return SavedBoard(
            gridSize: board.gridSize,
            cells: reconciledCells(board.cells),
            completedLines: board.completedLines,
            fullBoardCells: board.fullBoardCells.map(reconciledCells)
        )
    }

    /// Applies the same authoritative completion-history projection to every
    /// named board while preserving board identity, rules, timestamps, and the
    /// selected-board metadata. Keeping timestamps intact prevents a derived
    /// display-cache repair from winning an iCloud board-content conflict.
    static func namedBoardsSnapshotByReconcilingCompletionHistory(
        _ snapshot: BingoBoardStore.NamedBoardsSnapshot,
        records: [TaskCompletionHistoryRecord]
    ) -> BingoBoardStore.NamedBoardsSnapshot {
        var reconciled = snapshot
        reconciled.boards = snapshot.boards.map { namedBoard in
            var updatedBoard = namedBoard
            updatedBoard.board = boardByReconcilingCompletionHistory(
                namedBoard.board,
                records: records
            )
            return updatedBoard
        }
        return reconciled
    }

    /// Resolves the count a task should display after its name is edited. The
    /// caller owns persistence; this rule deliberately has no side effects so
    /// editors and quick-edit previews cannot accidentally create history.
    static func inheritedCompletionCount(
        previousTaskText: String,
        previousCompletionCount: Int,
        updatedTaskText: String,
        availableHistoryCount: Int
    ) -> Int {
        let previousKey = normalizedKey(for: previousTaskText)
        let updatedKey = normalizedKey(for: updatedTaskText)

        guard let updatedKey else { return 0 }
        guard previousKey != updatedKey else {
            return max(previousCompletionCount, 0)
        }
        return max(availableHistoryCount, 0)
    }

    static func recordsByArchiving(
        _ cells: [BingoCell],
        into records: [TaskCompletionHistoryRecord],
        at date: Date = .now
    ) -> [TaskCompletionHistoryRecord] {
        var totals = Dictionary(
            uniqueKeysWithValues: normalizedRecords(records).map { ($0.key, $0) }
        )
        for cell in cells {
            guard let key = normalizedKey(for: cell.storedTaskText),
                  cell.completionStreakCount > 0 else {
                continue
            }
            let existing = totals[key]
            totals[key] = TaskCompletionHistoryRecord(
                key: key,
                completionCount: max(existing?.completionCount ?? 0, cell.completionStreakCount),
                lastArchivedAt: max(existing?.lastArchivedAt ?? .distantPast, date)
            )
        }
        return normalizedRecords(Array(totals.values))
    }

    /// Applies a user initiated completion or undo to the name-scoped total.
    /// This is the sole mutation rule for live completion history; archiving is
    /// intentionally only a legacy/import safety net.
    static func recordsByApplyingCompletionDelta(
        taskText: String,
        delta: Int,
        to records: [TaskCompletionHistoryRecord],
        at date: Date = .now
    ) -> [TaskCompletionHistoryRecord] {
        guard delta != 0, let key = normalizedKey(for: taskText) else {
            return normalizedRecords(records)
        }

        var totals = Dictionary(
            uniqueKeysWithValues: normalizedRecords(records).map { ($0.key, $0) }
        )
        let existing = totals[key]
        let nextCount = max((existing?.completionCount ?? 0) + delta, 0)
        if nextCount == 0 {
            totals.removeValue(forKey: key)
        } else {
            totals[key] = TaskCompletionHistoryRecord(
                key: key,
                completionCount: nextCount,
                lastArchivedAt: date
            )
        }
        return normalizedRecords(Array(totals.values))
    }

    static func migratedRecords(
        existing: [TaskCompletionHistoryRecord],
        diaryEntries: [BingoDiaryEntry],
        currentBoards: [SavedBoard]
    ) -> [TaskCompletionHistoryRecord] {
        var diaryTotals: [String: Int] = [:]
        var snapshotMaximums: [String: Int] = [:]

        for entry in diaryEntries {
            for (taskText, count) in entry.completedTaskCounts where count > 0 {
                guard let key = normalizedKey(for: taskText) else { continue }
                diaryTotals[key, default: 0] += count
            }
            collectSnapshotMaximums(from: entry.board, into: &snapshotMaximums)
        }
        for board in currentBoards {
            collectSnapshotMaximums(from: board, into: &snapshotMaximums)
        }

        var merged = Dictionary(
            uniqueKeysWithValues: normalizedRecords(existing).map { ($0.key, $0) }
        )
        for key in Set(diaryTotals.keys).union(snapshotMaximums.keys) {
            let existingRecord = merged[key]
            let count = max(
                existingRecord?.completionCount ?? 0,
                diaryTotals[key] ?? 0,
                snapshotMaximums[key] ?? 0
            )
            guard count > 0 else { continue }
            merged[key] = TaskCompletionHistoryRecord(
                key: key,
                completionCount: count,
                lastArchivedAt: existingRecord?.lastArchivedAt ?? .now
            )
        }
        return normalizedRecords(Array(merged.values))
    }

    static func normalizedRecords(_ records: [TaskCompletionHistoryRecord]) -> [TaskCompletionHistoryRecord] {
        var merged: [String: TaskCompletionHistoryRecord] = [:]
        for record in records where !record.key.isEmpty && record.completionCount > 0 {
            let existing = merged[record.key]
            merged[record.key] = TaskCompletionHistoryRecord(
                key: record.key,
                completionCount: max(existing?.completionCount ?? 0, record.completionCount),
                lastArchivedAt: max(existing?.lastArchivedAt ?? .distantPast, record.lastArchivedAt)
            )
        }
        return merged.values.sorted { lhs, rhs in
            if lhs.lastArchivedAt != rhs.lastArchivedAt {
                return lhs.lastArchivedAt > rhs.lastArchivedAt
            }
            return lhs.key < rhs.key
        }
    }

    private static func collectSnapshotMaximums(
        from board: SavedBoard,
        into maximums: inout [String: Int]
    ) {
        let cells = (board.fullBoardCells ?? board.cells).flatMap { $0 }
        for cell in cells where cell.completionStreakCount > 0 {
            guard let key = normalizedKey(for: cell.storedTaskText) else { continue }
            maximums[key] = max(maximums[key] ?? 0, cell.completionStreakCount)
        }
    }
}

enum TaskCompletionHistoryStore {
    // V1 could mark migration complete before all shared-board sources had
    // arrived locally. V2 is deliberately idempotent and re-scans the durable
    // sources, so an earlier partial migration cannot permanently hide a count.
    // V3 promotes the diary-derived count to the durable, live total. This
    // repairs V2 installations where a completion updated a cell and diary but
    // did not update the history record subsequently inherited by new cells.
    private static let migrationVersion = 3

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: BingoBoardStore.appGroupID) ?? .standard
    }

    static func load() -> [TaskCompletionHistoryRecord] {
        let sources = [sharedDefaults, UserDefaults.standard]
        let records = sources.flatMap { defaults -> [TaskCompletionHistoryRecord] in
            guard let data = defaults.data(forKey: AppSettings.taskCompletionHistoryKey),
                  let records = try? JSONDecoder().decode([TaskCompletionHistoryRecord].self, from: data) else {
                return []
            }
            return records
        }
        return TaskCompletionHistoryRuleEngine.normalizedRecords(records)
    }

    @discardableResult
    static func save(_ records: [TaskCompletionHistoryRecord]) -> Bool {
        let normalized = TaskCompletionHistoryRuleEngine.normalizedRecords(records)
        guard let data = try? JSONEncoder().encode(normalized) else { return false }

        let defaults = [sharedDefaults, UserDefaults.standard]
        let steps = defaults.compactMap { defaults -> PersistenceWriteStep? in
            guard defaults.data(forKey: AppSettings.taskCompletionHistoryKey) != data else {
                return nil
            }
            return PersistenceWriteTransaction.userDefaultsStep(
                defaults: defaults,
                key: AppSettings.taskCompletionHistoryKey,
                newValue: data
            )
        }
        let didChange = !steps.isEmpty
        let didSave = PersistenceWriteTransaction.commit(steps) &&
            defaults.allSatisfy {
                $0.data(forKey: AppSettings.taskCompletionHistoryKey) == data
            }
        if didSave, didChange {
            NativeICloudLocalChangeReporter.secondaryStateDidChange()
        }
        return didSave
    }

    @discardableResult
    static func ensureMigrated() -> Bool {
        let defaults = [sharedDefaults, UserDefaults.standard]
        guard !defaults.allSatisfy({
            $0.integer(forKey: AppSettings.taskCompletionHistoryMigrationVersionKey) >= migrationVersion
        }) else {
            return true
        }
        let records = TaskCompletionHistoryRuleEngine.migratedRecords(
            existing: load(),
            diaryEntries: Array(BingoDiaryStore.loadAllEntriesDictionary().values),
            currentBoards: BingoBoardStore.loadNamedBoardsSnapshot().boards.map(\.board)
        )
        guard save(records) else { return false }
        let migrationSteps = defaults.compactMap { defaults -> PersistenceWriteStep? in
            guard defaults.integer(forKey: AppSettings.taskCompletionHistoryMigrationVersionKey) != migrationVersion else {
                return nil
            }
            return PersistenceWriteTransaction.userDefaultsStep(
                defaults: defaults,
                key: AppSettings.taskCompletionHistoryMigrationVersionKey,
                newValue: migrationVersion
            )
        }
        guard PersistenceWriteTransaction.commit(migrationSteps) else { return false }
        return defaults.allSatisfy {
            $0.integer(forKey: AppSettings.taskCompletionHistoryMigrationVersionKey) == migrationVersion
        }
    }

    static func completionCount(for taskText: String) -> Int {
        guard ensureMigrated() else { return 0 }
        return TaskCompletionHistoryRuleEngine.completionCount(for: taskText, in: load())
    }

    @discardableResult
    static func applyCompletionDelta(
        taskText: String,
        delta: Int,
        at date: Date = .now
    ) -> Bool {
        guard ensureMigrated() else { return false }
        let existing = load()
        let updated = TaskCompletionHistoryRuleEngine.recordsByApplyingCompletionDelta(
            taskText: taskText,
            delta: delta,
            to: existing,
            at: date
        )
        return updated == existing || save(updated)
    }

    @discardableResult
    static func archive(_ cell: BingoCell, at date: Date = .now) -> Bool {
        archive(cells: [cell], at: date)
    }

    @discardableResult
    static func archive(cells: [BingoCell], at date: Date = .now) -> Bool {
        guard ensureMigrated() else { return false }
        let existing = load()
        let archived = TaskCompletionHistoryRuleEngine.recordsByArchiving(cells, into: existing, at: date)
        return archived == existing || save(archived)
    }

    @discardableResult
    static func archive(board: SavedBoard, at date: Date = .now) -> Bool {
        archive(cells: (board.fullBoardCells ?? board.cells).flatMap { $0 }, at: date)
    }

    /// Used by both the app and widget reset paths before a board rule clears
    /// one-time tasks. Repeating tasks are deliberately excluded because reset
    /// only clears their current completion state, not the task itself.
    @discardableResult
    static func archiveTasksRemovedByReset(
        from board: BingoBoardStore.NamedBoard,
        at date: Date = .now
    ) -> Bool {
        let removedCells = BoardEngine.expandedBoardCache(from: board.board)
            .flatMap { $0 }
            .filter { cell in
                if case .remove = TaskLifecycleRuleEngine.dailySettlementAction(
                    for: cell,
                    mode: board.taskResetMode
                ) {
                    return true
                }
                return false
            }
        return archive(cells: removedCells, at: date)
    }

    static func mergedWithLocal(_ remoteRecords: [TaskCompletionHistoryRecord]) -> [TaskCompletionHistoryRecord] {
        TaskCompletionHistoryRuleEngine.normalizedRecords(load() + remoteRecords)
    }
}
