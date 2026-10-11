import Foundation
import Combine

@MainActor
final class AppOpenStreakStore: ObservableObject {
    static let shared = AppOpenStreakStore()

    @Published private(set) var currentStreak = 0
    @Published private(set) var bestStreak = 0
    @Published private(set) var acknowledgedMilestones: Set<Int> = []

    var pendingMilestones: [Int] {
        [10, 20, 30].filter { bestStreak >= $0 && !acknowledgedMilestones.contains($0) }
    }

    func acknowledgeMilestones(_ days: [Int]) {
        acknowledgedMilestones.formUnion(days)
        defaults.set(Array(acknowledgedMilestones).sorted(), forKey: storageKey + ".acknowledged")
    }

#if DEBUG
    private struct DebugSnapshot: Codable {
        var state: PersistedState
        var acknowledged: Set<Int>
    }

    var isDebugSimulationActive: Bool {
        defaults.data(forKey: storageKey + ".debugBackup") != nil
    }

    func debugSimulate(days: Int, interrupted: Bool = false) {
        if !isDebugSimulationActive,
           let backup = try? JSONEncoder().encode(DebugSnapshot(state: persistedState, acknowledged: acknowledgedMilestones)) {
            defaults.set(backup, forKey: storageKey + ".debugBackup")
        }
        let days = max(1, days)
        persistedState = PersistedState(
            lastOpenedDay: calendar.startOfDay(for: .now),
            currentStreak: interrupted ? 1 : days,
            bestStreak: interrupted ? 30 : days
        )
        // Each milestone preset previews only its own reminder.
        acknowledgedMilestones = Set([10, 20, 30].filter { interrupted || $0 < days })
        defaults.set(Array(acknowledgedMilestones).sorted(), forKey: storageKey + ".acknowledged")
        publishAndSave()
    }

    func debugResetReminders() {
        if !isDebugSimulationActive,
           let backup = try? JSONEncoder().encode(DebugSnapshot(state: persistedState, acknowledged: acknowledgedMilestones)) {
            defaults.set(backup, forKey: storageKey + ".debugBackup")
        }
        acknowledgedMilestones = []
        defaults.set([Int](), forKey: storageKey + ".acknowledged")
    }

    func debugRestoreRealProgress() {
        guard let data = defaults.data(forKey: storageKey + ".debugBackup"),
              let backup = try? JSONDecoder().decode(DebugSnapshot.self, from: data) else { return }
        persistedState = backup.state
        acknowledgedMilestones = backup.acknowledged
        defaults.set(Array(acknowledgedMilestones).sorted(), forKey: storageKey + ".acknowledged")
        defaults.removeObject(forKey: storageKey + ".debugBackup")
        publishAndSave()
        recordOpen()
    }
#endif

    private struct PersistedState: Codable {
        var lastOpenedDay: Date?
        var currentStreak: Int
        var bestStreak: Int
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private var persistedState: PersistedState
    private var calendar: Calendar

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "app_open_streak_state_v1",
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.calendar = calendar
        self.persistedState = PersistedState(lastOpenedDay: nil, currentStreak: 0, bestStreak: 0)
        load()
    }

    func recordOpen(at date: Date = .now) {
        let today = calendar.startOfDay(for: date)

        if let lastOpenedDay = persistedState.lastOpenedDay {
            let daysSinceLastOpen = calendar.dateComponents(
                [.day],
                from: lastOpenedDay,
                to: today
            ).day ?? 0

            // Opening several times on the same calendar day must not inflate the streak.
            guard daysSinceLastOpen != 0 else { return }
            persistedState.currentStreak = daysSinceLastOpen == 1
                ? persistedState.currentStreak + 1
                : 1
        } else {
            persistedState.currentStreak = 1
        }

        persistedState.lastOpenedDay = today
        persistedState.bestStreak = max(
            persistedState.bestStreak,
            persistedState.currentStreak
        )
        publishAndSave()
    }

    private func load() {
        acknowledgedMilestones = Set(defaults.array(forKey: storageKey + ".acknowledged") as? [Int] ?? [])
        guard let data = defaults.data(forKey: storageKey),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            publishAndSave()
            return
        }

        persistedState = state
        publish()
    }

    private func publishAndSave() {
        publish()
        guard let data = try? JSONEncoder().encode(persistedState) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func publish() {
        currentStreak = persistedState.currentStreak
        bestStreak = persistedState.bestStreak
    }
}
