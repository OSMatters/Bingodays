import Foundation
import os

enum DiagnosticLogStore {
    struct PointsBaseline: Equatable {
        let totalPoints: Int
        let lifetimePoints: Int
    }

    enum Level: String, Codable, Sendable {
        case info
        case warning
        case error
    }

    struct Entry: Codable, Equatable, Sendable {
        let timestamp: Date
        let level: Level
        let category: String
        let name: String
        let details: [String: String]
    }

    private static let storageKey = "diagnostic_log_entries_v1"
    private static let maxEntries = 160
    private static let maxCriticalEntries = 240
    private static let maxDetailValueLength = 120
    private static let maxExportCharacters = 32_000
    private static let criticalStorageKey = "diagnostic_critical_entries_v1"
    private static let ruleStorageKey = "diagnostic_task_rule_entries_v1"
    private static let maxRuleEntries = 240
    static let processSource = Bundle.main.bundleURL.pathExtension == "appex" ? "widget" : "app"
    private static var sharedLogURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BingoBoardStore.appGroupID)?
            .appendingPathComponent("diagnostic_\(processSource)_v2.json")
    }
    private static let persistenceQueue = DispatchQueue(
        label: "com.bingoday.diagnostic-log.persistence",
        qos: .utility
    )
    private struct CacheState: Sendable {
        var entries: [Entry]?
        var critical: [Entry]?
        var rules: [Entry]?
        var isPersistenceScheduled = false
    }
    private static let cache = OSAllocatedUnfairLock(initialState: CacheState())

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
            details: sanitizedDetails(details.merging([
                "process": processSource,
                "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                "app_build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            ]) { current, _ in current })
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

        cache.withLock { state in
            var entries = cachedEntries(state: &state)
            entries.append(entry)
            if entries.count > maxEntries {
                entries = Array(entries.suffix(maxEntries))
            }
            state.entries = entries
            var critical = cachedCriticalEntries(state: &state)
            var rules = cachedRuleEntries(state: &state)
            if isRuleTrace(entry) {
                rules.append(entry)
                rules = retainedRuleEntries(rules)
                state.rules = rules
            } else if isCritical(entry) {
                critical.append(entry)
                critical = Array(critical.suffix(maxCriticalEntries))
                state.critical = critical
            }
            schedulePersistenceLocked(state: &state)
        }
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
        let cached = cachedSnapshot()
        var entries = cached.entries
        for entry in cached.critical where !entries.contains(entry) {
            entries.append(entry)
        }
        for entry in cached.rules where !entries.contains(entry) {
            entries.append(entry)
        }
        if let ownURL = sharedLogURL {
            let otherSource = processSource == "app" ? "widget" : "app"
            let otherURL = ownURL.deletingLastPathComponent().appendingPathComponent("diagnostic_\(otherSource)_v2.json")
            if let data = try? Data(contentsOf: otherURL),
               let otherEntries = try? JSONDecoder().decode([Entry].self, from: data) {
                entries.append(contentsOf: otherEntries)
            }
        }
        return exportText(entries: entries)
    }

    static func isCritical(_ entry: Entry) -> Bool {
        isRuleTrace(entry) || entry.level != .info ||
            entry.name.hasPrefix("board.snapshot_") || entry.name.hasPrefix("board_reset.")
    }

    static func isRuleTrace(_ entry: Entry) -> Bool {
        entry.name.hasPrefix("task_edit.") || entry.name.hasPrefix("task_rule.") ||
            (entry.name == "board.snapshot_task_transition" && entry.details["after_rule"] != "removed")
    }

    static func retainedRuleEntries(_ entries: [Entry]) -> [Entry] {
        Array(entries.filter(isRuleTrace).sorted { $0.timestamp < $1.timestamp }.suffix(maxRuleEntries))
    }

    private static func loadRuleEntries() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: ruleStorageKey) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private static func loadCriticalEntries() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: criticalStorageKey) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    static func exportText(entries: [Entry]) -> String {
        guard !entries.isEmpty else {
            return "No diagnostic events recorded."
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func line(_ entry: Entry) -> String {
            let detailsText = entry.details
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            let suffix = detailsText.isEmpty ? "" : " \(detailsText)"
            return "\(formatter.string(from: entry.timestamp)) [\(entry.level.rawValue)] \(entry.category).\(entry.name)\(suffix)"
        }
        // Reserve most of the export for rule mutations; never truncate a line.
        func bounded(_ source: [Entry], budget: Int) -> [Entry] {
            var remaining = budget
            return source.sorted { $0.timestamp > $1.timestamp }.filter {
                let count = line($0).count + 1
                guard count <= remaining else { return false }
                remaining -= count
                return true
            }
        }
        let budget = maxExportCharacters - 200
        let rules = bounded(entries.filter(isRuleTrace), budget: budget / 2)
        let ruleCharacters = rules.reduce(0) { $0 + line($1).count + 1 }
        let critical = bounded(entries.filter { isCritical($0) && !isRuleTrace($0) }, budget: budget * 3 / 4 - ruleCharacters)
        let used = ruleCharacters + critical.reduce(0) { $0 + line($1).count + 1 }
        let recent = bounded(entries.filter { !isCritical($0) }, budget: budget - used)
        let selected = (rules + critical + recent).sorted { $0.timestamp < $1.timestamp }
        return "Diagnostic v3: selected=\(selected.count) available=\(entries.count); task-rule history reserved.\n" + selected.map(line).joined(separator: "\n")
    }

    static func snapshot() -> [Entry] {
        cache.withLock { state in cachedEntries(state: &state) }
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

    private static func cachedEntries(state: inout CacheState) -> [Entry] {
        if let entries = state.entries {
            return entries
        }
        let entries = loadEntries()
        state.entries = entries
        return entries
    }

    private static func cachedCriticalEntries(state: inout CacheState) -> [Entry] {
        if let entries = state.critical {
            return entries
        }
        let entries = loadCriticalEntries()
        state.critical = entries
        return entries
    }

    private static func cachedRuleEntries(state: inout CacheState) -> [Entry] {
        if let entries = state.rules {
            return entries
        }
        let entries = loadRuleEntries()
        state.rules = entries
        return entries
    }

    private static func cachedSnapshot() -> (
        entries: [Entry],
        critical: [Entry],
        rules: [Entry]
    ) {
        cache.withLock { state in
            (cachedEntries(state: &state), cachedCriticalEntries(state: &state), cachedRuleEntries(state: &state))
        }
    }

    private static func schedulePersistenceLocked(state: inout CacheState) {
        guard !state.isPersistenceScheduled else { return }
        let workItem = DispatchWorkItem {
            persistCachedEntries()
        }
        state.isPersistenceScheduled = true
        persistenceQueue.asyncAfter(deadline: .now() + .milliseconds(250), execute: workItem)
    }

    private static func persistCachedEntries() {
        let snapshot = takeCachedSnapshotForPersistence()

        saveEntries(snapshot.entries)
        if let data = try? JSONEncoder().encode(snapshot.rules) {
            UserDefaults.standard.set(data, forKey: ruleStorageKey)
        }
        if let data = try? JSONEncoder().encode(snapshot.critical) {
            UserDefaults.standard.set(data, forKey: criticalStorageKey)
        }
        if let url = sharedLogURL,
           let data = try? JSONEncoder().encode(
                snapshot.rules + snapshot.critical + snapshot.entries.filter { !isCritical($0) }
           ) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func takeCachedSnapshotForPersistence() -> (
        entries: [Entry],
        critical: [Entry],
        rules: [Entry]
    ) {
        cache.withLock { state in
            state.isPersistenceScheduled = false
            return (cachedEntries(state: &state), cachedCriticalEntries(state: &state), cachedRuleEntries(state: &state))
        }
    }

    private static func saveEntries(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else {
            return
        }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
