import Foundation

struct NativeICloudSecondaryStateSnapshot: Codable, Equatable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let taskLibrary: MyTasksLibrary
    let taskHistory: [TaskHistoryRecord]
    let taskCompletionHistory: [TaskCompletionHistoryRecord]

    init(
        schemaVersion: Int = Self.schemaVersion,
        taskLibrary: MyTasksLibrary,
        taskHistory: [TaskHistoryRecord],
        taskCompletionHistory: [TaskCompletionHistoryRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.taskLibrary = taskLibrary
        self.taskHistory = taskHistory
        self.taskCompletionHistory = taskCompletionHistory
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case taskLibrary
        case taskHistory
        case taskCompletionHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.schemaVersion
        taskLibrary = try container.decode(MyTasksLibrary.self, forKey: .taskLibrary)
        taskHistory = try container.decodeIfPresent([TaskHistoryRecord].self, forKey: .taskHistory) ?? []
        taskCompletionHistory = try container.decodeIfPresent(
            [TaskCompletionHistoryRecord].self,
            forKey: .taskCompletionHistory
        ) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(taskLibrary, forKey: .taskLibrary)
        try container.encode(taskHistory, forKey: .taskHistory)
        try container.encode(taskCompletionHistory, forKey: .taskCompletionHistory)
    }

    static func captureLocal() -> NativeICloudSecondaryStateSnapshot {
        _ = TaskCompletionHistoryStore.ensureMigrated()
        return NativeICloudSecondaryStateSnapshot(
            taskLibrary: CommonTasksStore.loadLibrary(),
            taskHistory: TaskHistoryStore.load(),
            taskCompletionHistory: TaskCompletionHistoryStore.load()
        )
    }

    var hasMeaningfulUserData: Bool {
        !taskLibrary.tasks.isEmpty || !taskLibrary.groups.isEmpty || !taskHistory.isEmpty || !taskCompletionHistory.isEmpty
    }

    var lastUserModifiedAt: Date? {
        let taskDate = taskHistory.map(\.lastEditedAt).max()
        let completionDate = taskCompletionHistory.map(\.lastArchivedAt).max()
        return [taskDate, completionDate, NativeICloudPreferences.secondaryLocalModifiedAt]
            .compactMap { $0 }
            .max()
    }
}
