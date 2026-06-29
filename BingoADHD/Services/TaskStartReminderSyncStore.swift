import Combine
import Foundation

@MainActor
final class TaskStartReminderSyncStore: ObservableObject {
    private let scheduler: any TaskStartReminderScheduling
    private let debounceNanoseconds: UInt64
    private var syncTask: Task<Void, Never>?
    private var lastSyncSignature: String?

    init(
        scheduler: any TaskStartReminderScheduling = LiveTaskStartReminderScheduler(),
        debounceNanoseconds: UInt64 = 300_000_000
    ) {
        self.scheduler = scheduler
        self.debounceNanoseconds = debounceNanoseconds
    }

    func scheduleSync(
        namedBoards: [BingoBoardStore.NamedBoard],
        selectedBoardID: UUID?,
        activeBoard: SavedBoard?,
        now: Date = .now
    ) {
        let syncSignature = scheduler.syncSignature(
            namedBoards: namedBoards,
            selectedBoardID: selectedBoardID,
            activeBoard: activeBoard,
            now: now
        )

        guard syncSignature != lastSyncSignature else { return }
        lastSyncSignature = syncSignature

        syncTask?.cancel()
        syncTask = Task { [scheduler, debounceNanoseconds] in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            await scheduler.syncReminders(
                namedBoards: namedBoards,
                selectedBoardID: selectedBoardID,
                activeBoard: activeBoard,
                now: now
            )
        }
    }

    func cancelPendingSync() {
        syncTask?.cancel()
        syncTask = nil
    }
}
