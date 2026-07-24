import Foundation

enum DiagnosticLogStore {
    struct PointsBaseline: Equatable {
        let totalPoints: Int
        let lifetimePoints: Int
    }

    enum Level: String, Codable {
        case info
        case warning
        case error
    }

    struct Entry: Codable {
        let timestamp: Date
        let level: Level
        let category: String
        let name: String
        let details: [String: String]
    }

    private static let storageKey = "diagnostic_log_entries_v1"
    private static let maxEntries = 160
    private static let maxDetailValueLength = 120
    private static let maxExportCharacters = 12_000
    private static let lock = NSLock()

    static func record(
        _ name: String,
        category: String,
        level: Level = .info,
        details: [String: String] = [:],
        now: Date = .now
    ) {
        let entry = Entry(
            timestamp: now,
            level: level,
            category: sanitizedKey(category),
            name: sanitizedKey(name),
            details: sanitizedDetails(details)
        )

        #if DEBUG
        if entry.name.hasPrefix("points.") {
            let detailsText = entry.details
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            print("[BingodaysPoints] \(entry.name) \(detailsText)")
        }
        #endif

        lock.lock()
        defer { lock.unlock() }

        var entries = loadEntries()
        entries.append(entry)
        if entries.count > maxEntries {
            entries = Array(entries.suffix(maxEntries))
        }
        saveEntries(entries)
    }

    static func recordUserAction(_ name: String, details: [String: String] = [:]) {
        record(name, category: "user_action", details: details)
    }

    static func recordStateChange(_ name: String, details: [String: String] = [:]) {
        record(name, category: "state_change", details: details)
    }

    static func recordWarning(_ name: String, details: [String: String] = [:]) {
        record(name, category: "warning", level: .warning, details: details)
    }

    static func exportText() -> String {
        let entries = snapshot()
        guard !entries.isEmpty else {
            return "No diagnostic events recorded."
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let text = entries.map { entry in
            let detailsText = entry.details
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            let suffix = detailsText.isEmpty ? "" : " \(detailsText)"
            return "\(formatter.string(from: entry.timestamp)) [\(entry.level.rawValue)] \(entry.category).\(entry.name)\(suffix)"
        }
        .joined(separator: "\n")

        guard text.count > maxExportCharacters else {
            return text
        }

        return "Diagnostic log truncated to latest \(maxExportCharacters) characters.\n"
            + String(text.suffix(maxExportCharacters))
    }

    static func snapshot() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return loadEntries()
    }

    /// Returns the durable points state immediately before the current run of
    /// failed task transactions. This is used only to retire the unshipped V1
    /// transaction journal that alternated old point snapshots on every tap.
    static func pointsBaselineBeforeLatestFailedTransactionEpisode() -> PointsBaseline? {
        let entries = snapshot()
        let lastSuccessfulToggleIndex = entries.lastIndex {
            $0.name == "points.task_toggle_persisted"
        }
        let episodeStart = lastSuccessfulToggleIndex.map { entries.index(after: $0) }
            ?? entries.startIndex
        let episode = entries[episodeStart...]
        guard episode.contains(where: {
            $0.name == "points.task_toggle_persistence_failed"
        }) else {
            return nil
        }
        guard let firstToggle = episode.first(where: {
            $0.name == "points.task_toggle_begin"
        }),
        let totalText = firstToggle.details["persisted_total"],
        let lifetimeText = firstToggle.details["persisted_lifetime"],
        let totalPoints = Int(totalText),
        let lifetimePoints = Int(lifetimeText) else {
            return nil
        }
        return PointsBaseline(
            totalPoints: totalPoints,
            lifetimePoints: lifetimePoints
        )
    }

    private static func sanitizedDetails(_ details: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in details {
            result[sanitizedKey(key)] = sanitizedValue(value)
        }
        return result
    }

    private static func sanitizedKey(_ key: String) -> String {
        let allowed = key.map { character -> Character in
            if character.isLetter || character.isNumber || character == "_" || character == "." || character == "-" {
                return character
            }
            return "_"
        }
        let result = String(allowed).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "unknown" : String(result.prefix(80))
    }

    private static func sanitizedValue(_ value: String) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(singleLine.prefix(maxDetailValueLength))
    }

    private static func loadEntries() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private static func saveEntries(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else {
            return
        }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
