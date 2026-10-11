import Foundation

enum BingoTimeoutStore {
    private static let key = "bingo_timeout_unfinished_stats_v1"

    static func recordUnfinishedTimeout(task: String, on date: Date = .now) {
        let trimmedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTask.isEmpty else { return }

        var payload = loadPayload()
        let dayKey = dateKey(for: date)
        var dayStats = payload[dayKey] ?? [:]
        dayStats[trimmedTask, default: 0] += 1
        payload[dayKey] = dayStats
        persist(payload)
    }

    static func taskTimeoutStats(
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

        for (dayKey, taskCounts) in loadPayload() {
            guard let dayIndex = dayIndexByKey[dayKey] else { continue }
            for (task, count) in taskCounts where count > 0 {
                let trimmedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedTask.isEmpty else { continue }

                var counts = taskDailyCounts[trimmedTask] ?? emptyDailyCounts
                counts[dayIndex] += count
                taskDailyCounts[trimmedTask] = counts
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

    static func loadAllPayload(
        reading mode: PersistenceReadMode = .repairingMirrors
    ) -> [String: [String: Int]] {
        loadPayload(reading: mode)
    }

    static func totalTimedOutTasks() -> Int {
        loadPayload().values.reduce(0) { partialResult, taskCounts in
            partialResult + taskCounts.values.reduce(0, +)
        }
    }

    static func allTimeTimeoutTaskCounts() -> [(task: String, count: Int)] {
        let counts = loadPayload().reduce(into: [String: Int]()) { partial, entry in
            for (task, count) in entry.value where count > 0 {
                let trimmedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedTask.isEmpty else { continue }
                partial[trimmedTask, default: 0] += count
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

    @discardableResult
    static func replacePayload(_ payload: [String: [String: Int]]) -> Bool {
        persist(payload)
    }

    private static func loadPayload(
        reading mode: PersistenceReadMode = .repairingMirrors
    ) -> [String: [String: Int]] {
        if let data = sharedDefaults.data(forKey: key),
           let payload = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
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
            return payload
        }

        guard let data = UserDefaults.standard.data(forKey: key),
              let payload = try? JSONDecoder().decode([String: [String: Int]].self, from: data) else {
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
        return payload
    }

    @discardableResult
    private static func persist(_ payload: [String: [String: Int]]) -> Bool {
        guard let data = try? JSONEncoder().encode(payload) else { return false }
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

    private static func dateKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
