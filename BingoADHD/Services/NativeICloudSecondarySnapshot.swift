import Foundation

struct NativeICloudSecondaryStateSnapshot: Codable, Equatable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let taskLibrary: MyTasksLibrary
    let taskHistory: [TaskHistoryRecord]

    init(
        schemaVersion: Int = Self.schemaVersion,
        taskLibrary: MyTasksLibrary,
        taskHistory: [TaskHistoryRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.taskLibrary = taskLibrary
        self.taskHistory = taskHistory
    }

    static func captureLocal() -> NativeICloudSecondaryStateSnapshot {
        NativeICloudSecondaryStateSnapshot(
            taskLibrary: CommonTasksStore.loadLibrary(),
            taskHistory: TaskHistoryStore.load()
        )
    }

    var hasMeaningfulUserData: Bool {
        !taskLibrary.tasks.isEmpty || !taskLibrary.groups.isEmpty || !taskHistory.isEmpty
    }

    var lastUserModifiedAt: Date? {
        let taskDate = taskHistory.map(\.lastEditedAt).max()
        return [taskDate, NativeICloudPreferences.secondaryLocalModifiedAt]
            .compactMap { $0 }
            .max()
    }
}
