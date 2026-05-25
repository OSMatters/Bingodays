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

    static func saveLibrary(_ library: MyTasksLibrary) {
        let sanitized = sanitize(library)
        guard let data = try? JSONEncoder().encode(sanitized) else { return }
        UserDefaults.standard.set(data, forKey: AppSettings.commonTasksKey)
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

    static func save(_ records: [TaskHistoryRecord]) {
        let sanitized = sanitize(records)
        guard let data = try? JSONEncoder().encode(sanitized) else { return }
        UserDefaults.standard.set(data, forKey: AppSettings.taskHistoryKey)
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

    static func upsert(task: MyTaskItem, sourceTaskID: UUID? = nil, at date: Date = .now) {
        var sanitizedTask = task
        sanitizedTask.text = String(task.text.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        sanitizedTask.normalizeVisibilityWindow()
        guard !sanitizedTask.trimmedText.isEmpty else { return }

        let key = makeKey(for: sanitizedTask, sourceTaskID: sourceTaskID)
        var records = load()

        if let index = records.firstIndex(where: { $0.key == key }) {
            records[index].text = sanitizedTask.trimmedText
            records[index].startAt = sanitizedTask.startAt
            records[index].endAt = sanitizedTask.endAt
            records[index].startMonth = sanitizedTask.startMonth
            records[index].startDay = sanitizedTask.startDay
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
                    sourceTaskID: sourceTaskID,
                    lastEditedAt: date
                )
            )
        }

        save(records)
    }

    static func upsert(tasks: [MyTaskItem], at date: Date = .now) {
        for task in tasks {
            upsert(task: task, sourceTaskID: task.id, at: date)
        }
    }

    static func upsertBoardTasks(_ tasks: [MyTaskItem], at date: Date = .now) {
        for task in tasks {
            upsert(task: task, sourceTaskID: nil, at: date)
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
