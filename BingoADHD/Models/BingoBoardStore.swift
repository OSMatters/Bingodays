import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum BoardTaskResetMode: String, Codable, CaseIterable {
    case resetStatusNextDay
    case clearTasksNextDay
}

enum BingoBoardStore {
    static let appGroupID = "group.com.bingoday.app"
    private static let saveKey = "bingo_board_v1"
    private static let lastSavedAtKey = "bingo_board_last_saved_at_v1"
    private static let sharedFileName = "bingo_board_v1.json"
    private static let metricsFileName = "bingo_metrics_v1.json"
    private static let boardsSaveKey = "bingo_boards_v1"
    private static let boardsFileName = "bingo_boards_v1.json"
    private static let maxBoardNameLength = 20

    struct NamedBoard: Identifiable, Codable, Equatable {
        let id: UUID
        var name: String
        var board: SavedBoard
        var countdownEndsAt: Date?
        var taskResetMode: BoardTaskResetMode
        var lastTaskResetAppliedAt: Date?
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case board
            case countdownEndsAt
            case taskResetMode
            case lastTaskResetAppliedAt
            case updatedAt
        }

        init(
            id: UUID = UUID(),
            name: String,
            board: SavedBoard,
            countdownEndsAt: Date? = nil,
            taskResetMode: BoardTaskResetMode = .resetStatusNextDay,
            lastTaskResetAppliedAt: Date? = .now,
            updatedAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.board = board
            self.countdownEndsAt = countdownEndsAt
            self.taskResetMode = taskResetMode
            self.lastTaskResetAppliedAt = lastTaskResetAppliedAt
            self.updatedAt = updatedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            name = try container.decode(String.self, forKey: .name)
            board = try container.decode(SavedBoard.self, forKey: .board)
            countdownEndsAt = try container.decodeIfPresent(Date.self, forKey: .countdownEndsAt)
            taskResetMode = try container.decodeIfPresent(BoardTaskResetMode.self, forKey: .taskResetMode) ?? .resetStatusNextDay
            updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
            // Migration-safe anchor: if historical data doesn't have this field,
            // use updatedAt to avoid immediate same-day reset on first launch.
            lastTaskResetAppliedAt = try container.decodeIfPresent(Date.self, forKey: .lastTaskResetAppliedAt) ?? updatedAt
        }
    }

    struct NamedBoardsSnapshot: Codable, Equatable {
        var selectedBoardID: UUID?
        var boards: [NamedBoard]

        init(selectedBoardID: UUID?, boards: [NamedBoard]) {
            self.selectedBoardID = selectedBoardID
            self.boards = boards
        }
    }

    private struct WidgetMetrics: Codable {
        let firstSeenAt: Date
    }

    static func loadBoard() -> SavedBoard? {
        if let data = try? Data(contentsOf: sharedFileURL),
           let saved = try? JSONDecoder().decode(SavedBoard.self, from: data) {
            return saved
        }

        if let data = sharedDefaults.data(forKey: saveKey),
           let saved = try? JSONDecoder().decode(SavedBoard.self, from: data) {
            persistSharedFile(data)
            return saved
        }

        if let data = UserDefaults.standard.data(forKey: saveKey),
           let saved = try? JSONDecoder().decode(SavedBoard.self, from: data) {
            persistSharedFile(data)
            return saved
        }

        return nil
    }

    static func saveBoard(_ board: SavedBoard, savedAt: Date = .now) {
        guard let data = try? JSONEncoder().encode(board) else { return }

        persistSharedFile(data)
        sharedDefaults.set(data, forKey: saveKey)
        UserDefaults.standard.set(data, forKey: saveKey)
        saveBoardLastSavedAt(savedAt)

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func clearBoard() {
        try? FileManager.default.removeItem(at: sharedFileURL)
        sharedDefaults.removeObject(forKey: saveKey)
        UserDefaults.standard.removeObject(forKey: saveKey)
        sharedDefaults.removeObject(forKey: lastSavedAtKey)
        UserDefaults.standard.removeObject(forKey: lastSavedAtKey)
        saveBoardCountdownEndsAt(nil)

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func loadNamedBoardsSnapshot() -> NamedBoardsSnapshot {
        if let data = try? Data(contentsOf: namedBoardsFileURL),
           let decoded = try? JSONDecoder().decode(NamedBoardsSnapshot.self, from: data) {
            let sanitized = sanitizeNamedBoardsSnapshot(decoded)
            if sanitized != decoded {
                saveNamedBoardsSnapshot(sanitized)
            }
            return sanitized
        }

        if let data = sharedDefaults.data(forKey: boardsSaveKey),
           let decoded = try? JSONDecoder().decode(NamedBoardsSnapshot.self, from: data) {
            let sanitized = sanitizeNamedBoardsSnapshot(decoded)
            saveNamedBoardsSnapshot(sanitized)
            return sanitized
        }

        if let data = UserDefaults.standard.data(forKey: boardsSaveKey),
           let decoded = try? JSONDecoder().decode(NamedBoardsSnapshot.self, from: data) {
            let sanitized = sanitizeNamedBoardsSnapshot(decoded)
            saveNamedBoardsSnapshot(sanitized)
            return sanitized
        }

        if let legacyBoard = loadBoard() {
            let migratedBoard = NamedBoard(
                name: L10n.boardDefaultName(1),
                board: legacyBoard,
                countdownEndsAt: loadBoardCountdownEndsAt(),
                updatedAt: loadBoardLastSavedAt() ?? .now
            )
            let snapshot = NamedBoardsSnapshot(selectedBoardID: migratedBoard.id, boards: [migratedBoard])
            saveNamedBoardsSnapshot(snapshot)
            return snapshot
        }

        return NamedBoardsSnapshot(selectedBoardID: nil, boards: [])
    }

    static func saveNamedBoardsSnapshot(_ snapshot: NamedBoardsSnapshot) {
        let sanitized = sanitizeNamedBoardsSnapshot(snapshot)
        guard let data = try? JSONEncoder().encode(sanitized) else { return }

        persistNamedBoardsFile(data)
        sharedDefaults.set(data, forKey: boardsSaveKey)
        UserDefaults.standard.set(data, forKey: boardsSaveKey)

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func loadBoardLastSavedAt() -> Date? {
        if let date = sharedDefaults.object(forKey: lastSavedAtKey) as? Date {
            return date
        }

        if let date = UserDefaults.standard.object(forKey: lastSavedAtKey) as? Date {
            sharedDefaults.set(date, forKey: lastSavedAtKey)
            return date
        }

        if let values = try? sharedFileURL.resourceValues(forKeys: [.contentModificationDateKey]),
           let modificationDate = values.contentModificationDate {
            saveBoardLastSavedAt(modificationDate)
            return modificationDate
        }

        return nil
    }

    static func saveBoardLastSavedAt(_ date: Date) {
        sharedDefaults.set(date, forKey: lastSavedAtKey)
        UserDefaults.standard.set(date, forKey: lastSavedAtKey)
    }

    static func loadBoardCountdownEndsAt() -> Date? {
        if let countdown = sharedDefaults.object(forKey: AppSettings.boardCountdownKey) as? Date {
            return countdown
        }

        if let countdown = UserDefaults.standard.object(forKey: AppSettings.boardCountdownKey) as? Date {
            sharedDefaults.set(countdown, forKey: AppSettings.boardCountdownKey)
            return countdown
        }

        return nil
    }

    static func saveBoardCountdownEndsAt(_ date: Date?) {
        sharedDefaults.set(date, forKey: AppSettings.boardCountdownKey)
        UserDefaults.standard.set(date, forKey: AppSettings.boardCountdownKey)
    }

    static func usageDays(referenceDate: Date = .now) -> Int {
        let metrics = loadOrCreateMetrics(referenceDate: referenceDate)
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: metrics.firstSeenAt)
        let end = calendar.startOfDay(for: referenceDate)
        let dayCount = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(dayCount + 1, 1)
    }

    static func firstSeenDate(referenceDate: Date = .now) -> Date {
        Calendar.current.startOfDay(for: loadOrCreateMetrics(referenceDate: referenceDate).firstSeenAt)
    }

    static func setFirstSeenDate(_ date: Date) {
        persistMetrics(WidgetMetrics(firstSeenAt: date))
    }

    static func clearFirstSeenDate() {
        try? FileManager.default.removeItem(at: metricsFileURL)
    }

    private static func sanitizeNamedBoardsSnapshot(_ snapshot: NamedBoardsSnapshot) -> NamedBoardsSnapshot {
        var seenIDs = Set<UUID>()
        var sanitizedBoards: [NamedBoard] = []
        sanitizedBoards.reserveCapacity(snapshot.boards.count)

        for board in snapshot.boards {
            guard seenIDs.insert(board.id).inserted else { continue }
            sanitizedBoards.append(
                NamedBoard(
                    id: board.id,
                    name: board.name,
                    board: board.board,
                    countdownEndsAt: board.countdownEndsAt,
                    taskResetMode: board.taskResetMode,
                    lastTaskResetAppliedAt: board.lastTaskResetAppliedAt,
                    updatedAt: board.updatedAt
                )
            )
        }

        for index in sanitizedBoards.indices {
            let fallbackIndex = index + 1
            let trimmed = sanitizedBoards[index].name
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let limited = String(trimmed.prefix(maxBoardNameLength))
            sanitizedBoards[index].name = limited.isEmpty ? L10n.boardDefaultName(fallbackIndex) : limited
        }

        let selectedBoardID: UUID?
        if let existingSelected = snapshot.selectedBoardID,
           sanitizedBoards.contains(where: { $0.id == existingSelected }) {
            selectedBoardID = existingSelected
        } else {
            selectedBoardID = sanitizedBoards.first?.id
        }

        return NamedBoardsSnapshot(selectedBoardID: selectedBoardID, boards: sanitizedBoards)
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    private static var sharedFileURL: URL {
        sharedURL(for: sharedFileName)
    }

    private static var namedBoardsFileURL: URL {
        sharedURL(for: boardsFileName)
    }

    private static func persistSharedFile(_ data: Data) {
        try? data.write(to: sharedFileURL, options: .atomic)
    }

    private static func persistNamedBoardsFile(_ data: Data) {
        try? data.write(to: namedBoardsFileURL, options: .atomic)
    }

    private static var metricsFileURL: URL {
        sharedURL(for: metricsFileName)
    }

    private static func loadOrCreateMetrics(referenceDate: Date) -> WidgetMetrics {
        if let data = try? Data(contentsOf: metricsFileURL),
           let metrics = try? JSONDecoder().decode(WidgetMetrics.self, from: data) {
            return metrics
        }

        let metrics = WidgetMetrics(firstSeenAt: referenceDate)
        persistMetrics(metrics)
        return metrics
    }

    private static func persistMetrics(_ metrics: WidgetMetrics) {
        guard let data = try? JSONEncoder().encode(metrics) else { return }
        try? data.write(to: metricsFileURL, options: .atomic)
    }

    private static func sharedURL(for fileName: String) -> URL {
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            let directory = containerURL.appendingPathComponent("Library/Application Support", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent(fileName)
        }

        #if targetEnvironment(simulator)
        let simulatorDirectory = URL(fileURLWithPath: "/tmp/\(appGroupID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: simulatorDirectory, withIntermediateDirectories: true)
        return simulatorDirectory.appendingPathComponent(fileName)
        #else
        let fallbackDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: fallbackDirectory, withIntermediateDirectories: true)
        return fallbackDirectory.appendingPathComponent(fileName)
        #endif
    }
}
