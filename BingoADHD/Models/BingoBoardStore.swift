import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum BoardTaskResetMode: String, Codable, CaseIterable {
    case resetStatusNextDay
    case clearTasksNextDay
    case customResetStatusTime
    case keepTaskStatus
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
        var customResetMinutes: Int?
        var lastTaskResetAppliedAt: Date?
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case board
            case countdownEndsAt
            case taskResetMode
            case customResetMinutes
            case lastTaskResetAppliedAt
            case updatedAt
        }

        init(
            id: UUID = UUID(),
            name: String,
            board: SavedBoard,
            countdownEndsAt: Date? = nil,
            taskResetMode: BoardTaskResetMode = .resetStatusNextDay,
            customResetMinutes: Int? = nil,
            lastTaskResetAppliedAt: Date? = .now,
            updatedAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.board = board
            self.countdownEndsAt = countdownEndsAt
            self.taskResetMode = taskResetMode
            self.customResetMinutes = NamedBoard.clampedCustomResetMinutes(customResetMinutes)
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
            customResetMinutes = NamedBoard.clampedCustomResetMinutes(try container.decodeIfPresent(Int.self, forKey: .customResetMinutes))
            updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
            // Migration-safe anchor: if historical data doesn't have this field,
            // use updatedAt to avoid immediate same-day reset on first launch.
            lastTaskResetAppliedAt = try container.decodeIfPresent(Date.self, forKey: .lastTaskResetAppliedAt) ?? updatedAt
        }

        private static func clampedCustomResetMinutes(_ value: Int?) -> Int? {
            guard let value else { return nil }
            return min(max(value, 0), 23 * 60 + 59)
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
        #if DEBUG
        let previousSnapshot = loadPersistedNamedBoardsSnapshotForIntegrityCheck()
        debugValidateNamedBoardsTransition(from: previousSnapshot, to: sanitized)
        #endif
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
                    customResetMinutes: board.customResetMinutes,
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

    #if DEBUG
    private struct DebugBoardSignature {
        let id: UUID
        let name: String
        let hasContent: Bool
        let signature: String
    }

    private static func loadPersistedNamedBoardsSnapshotForIntegrityCheck() -> NamedBoardsSnapshot? {
        if let data = try? Data(contentsOf: namedBoardsFileURL),
           let decoded = try? JSONDecoder().decode(NamedBoardsSnapshot.self, from: data) {
            return sanitizeNamedBoardsSnapshot(decoded)
        }

        if let data = sharedDefaults.data(forKey: boardsSaveKey),
           let decoded = try? JSONDecoder().decode(NamedBoardsSnapshot.self, from: data) {
            return sanitizeNamedBoardsSnapshot(decoded)
        }

        if let data = UserDefaults.standard.data(forKey: boardsSaveKey),
           let decoded = try? JSONDecoder().decode(NamedBoardsSnapshot.self, from: data) {
            return sanitizeNamedBoardsSnapshot(decoded)
        }

        return nil
    }

    private static func debugValidateNamedBoardsTransition(
        from previousSnapshot: NamedBoardsSnapshot?,
        to nextSnapshot: NamedBoardsSnapshot
    ) {
        debugAssertNoCrossBoardCellIDReuse(in: nextSnapshot)
        guard let previousSnapshot,
              previousSnapshot.boards.count > 1,
              nextSnapshot.boards.count > 1 else {
            return
        }

        let previousSignatures = previousSnapshot.boards.map(debugBoardSignature)
        let nextSignatures = nextSnapshot.boards.map(debugBoardSignature)
        let previousByID = Dictionary(uniqueKeysWithValues: previousSignatures.map { ($0.id, $0) })

        for nextBoard in nextSignatures {
            guard nextBoard.hasContent,
                  let previousBoard = previousByID[nextBoard.id],
                  previousBoard.hasContent,
                  previousBoard.signature != nextBoard.signature else {
                continue
            }

            let matchingPreviousBoard = previousSignatures.first {
                $0.id != nextBoard.id &&
                $0.hasContent &&
                $0.signature == nextBoard.signature &&
                $0.signature != previousBoard.signature
            }
            let matchingNextBoard = nextSignatures.first {
                $0.id != nextBoard.id &&
                $0.hasContent &&
                $0.signature == nextBoard.signature &&
                $0.signature != previousBoard.signature
            }

            guard let sourceBoard = matchingPreviousBoard ?? matchingNextBoard else {
                continue
            }

            debugReportNamedBoardsIntegrityFailure(
                """
                [BoardIntegrity] Possible cross-board overwrite detected. Board "\(nextBoard.name)" (\(nextBoard.id)) changed from its previous content to match "\(sourceBoard.name)" (\(sourceBoard.id)). Check recent board persistence, widget sync, and lifecycle reload paths.
                """
            )
        }
    }

    private static func debugAssertNoCrossBoardCellIDReuse(in snapshot: NamedBoardsSnapshot) {
        guard snapshot.boards.count > 1 else { return }

        var ownerByCellID: [UUID: (boardID: UUID, boardName: String)] = [:]
        for namedBoard in snapshot.boards {
            for cell in debugCanonicalCells(in: namedBoard.board) {
                if let owner = ownerByCellID[cell.id], owner.boardID != namedBoard.id {
                    debugReportNamedBoardsIntegrityFailure(
                        """
                        [BoardIntegrity] Cell ID \(cell.id) appears in both "\(owner.boardName)" (\(owner.boardID)) and "\(namedBoard.name)" (\(namedBoard.id)). This usually means one board snapshot was copied into another without regenerating cell identities.
                        """
                    )
                } else {
                    ownerByCellID[cell.id] = (namedBoard.id, namedBoard.name)
                }
            }
        }
    }

    private static func debugReportNamedBoardsIntegrityFailure(_ message: String) {
        print(message)
        assertionFailure(message)
    }

    private static func debugBoardSignature(_ namedBoard: NamedBoard) -> DebugBoardSignature {
        DebugBoardSignature(
            id: namedBoard.id,
            name: namedBoard.name,
            hasContent: debugBoardHasContent(namedBoard.board),
            signature: debugBoardContentSignature(namedBoard.board)
        )
    }

    private static func debugBoardHasContent(_ board: SavedBoard) -> Bool {
        debugCanonicalCells(in: board).contains { $0.hasStoredTask || $0.isCompleted }
    }

    private static func debugBoardContentSignature(_ board: SavedBoard) -> String {
        [
            "grid=\(board.gridSize)",
            "lines=\(board.completedLines.map(debugLineSignature).sorted().joined(separator: ","))",
            "visible=\(debugCellMatrixSignature(board.cells))",
            "full=\(debugCellMatrixSignature(board.fullBoardCells ?? []))"
        ].joined(separator: "\n")
    }

    private static func debugCanonicalCells(in board: SavedBoard) -> [BingoCell] {
        let source = board.fullBoardCells ?? board.cells
        return source.flatMap { $0 }
    }

    private static func debugCellMatrixSignature(_ cells: [[BingoCell]]) -> String {
        cells.enumerated().map { row, rowCells in
            rowCells.enumerated().map { col, cell in
                "r\(row)c\(col):\(debugCellSignature(cell))"
            }.joined(separator: ";")
        }.joined(separator: "/")
    }

    private static func debugCellSignature(_ cell: BingoCell) -> String {
        let residentTaskText = cell.residentTaskText ?? "nil"
        let residentWeekdays = cell.residentWeekdays.sorted().map { String($0) }.joined(separator: ",")
        let startVisibleMonth = cell.startVisibleMonth.map { String($0) } ?? "nil"
        let startVisibleDay = cell.startVisibleDay.map { String($0) } ?? "nil"
        let countdownPausedRemainingSeconds = cell.countdownPausedRemainingSeconds.map { String($0) } ?? "nil"
        let estimatedDurationMinutes = cell.estimatedDurationMinutes.map { String($0) } ?? "nil"

        let parts: [String] = [
            cell.id.uuidString,
            cell.text,
            residentTaskText,
            residentWeekdays,
            debugDateSignature(cell.oneTimeVisibleDate),
            debugDateSignature(cell.startVisibleAt),
            debugDateSignature(cell.endVisibleAt),
            startVisibleMonth,
            startVisibleDay,
            cell.isTaskHidden ? "hidden" : "shown",
            cell.isCompleted ? "done" : "open",
            cell.isForced ? "forced" : "normal",
            debugDateSignature(cell.countdownEndsAt),
            countdownPausedRemainingSeconds,
            estimatedDurationMinutes,
            String(cell.completionStreakCount),
            debugDateSignature(cell.lastCompletedAt),
            debugDateSignature(cell.lastVisibilityWindowTimeoutAt)
        ]
        return parts.joined(separator: "|")
    }

    private static func debugDateSignature(_ date: Date?) -> String {
        guard let date else { return "nil" }
        return String(date.timeIntervalSinceReferenceDate)
    }

    private static func debugLineSignature(_ line: BingoLine) -> String {
        switch line {
        case .row(let row):
            return "row:\(row)"
        case .column(let column):
            return "column:\(column)"
        case .diagonalMain:
            return "diagonalMain"
        case .diagonalAnti:
            return "diagonalAnti"
        }
    }
    #endif

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
