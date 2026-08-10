import Combine
import Foundation

@MainActor
final class TaskStartReminderSyncStore: ObservableObject {
    private let scheduler: any TaskStartReminderScheduling
    private let debounceNanoseconds: UInt64
    private var syncTask: Task<Void, Never>?
    private var pendingSyncSignature: String?
    private var lastCompletedSyncSignature: String?

    init(
        scheduler: any TaskStartReminderScheduling = LiveTaskStartReminderScheduler(),
        debounceNanoseconds: UInt64 = 300_000_000
    ) {
        self.scheduler = scheduler
        self.debounceNanoseconds = debounceNanoseconds
    }

    @discardableResult
    func scheduleSync(
        namedBoards: [BingoBoardStore.NamedBoard],
        selectedBoardID: UUID?,
        activeBoard: SavedBoard?,
        now: Date = .now
    ) -> Task<Void, Never>? {
        let syncSignature = scheduler.syncSignature(
            namedBoards: namedBoards,
            selectedBoardID: selectedBoardID,
            activeBoard: activeBoard,
            now: now
        )

        guard syncSignature != pendingSyncSignature,
              syncSignature != lastCompletedSyncSignature else {
            return syncTask
        }

        syncTask?.cancel()
        pendingSyncSignature = syncSignature
        let task = Task { [scheduler, debounceNanoseconds, syncSignature] in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            await scheduler.syncReminders(
                namedBoards: namedBoards,
                selectedBoardID: selectedBoardID,
                activeBoard: activeBoard,
                now: now
            )
            await MainActor.run {
                guard pendingSyncSignature == syncSignature else { return }
                lastCompletedSyncSignature = syncSignature
                pendingSyncSignature = nil
                syncTask = nil
            }
        }
        syncTask = task
        return task
    }

    func cancelPendingSync() {
        syncTask?.cancel()
        syncTask = nil
        pendingSyncSignature = nil
    }
}
