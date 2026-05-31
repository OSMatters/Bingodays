
import Foundation
import UIKit
import Compression

struct BingoCell: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var residentTaskText: String?
    var residentWeekdays: Set<Int>
    var oneTimeVisibleDate: Date?
    var startVisibleAt: Date?
    var endVisibleAt: Date?
    var startReminderEnabled: Bool
    var startReminderOffsetMinutes: Int
    var startVisibleMonth: Int?
    var startVisibleDay: Int?
    var isTaskHidden: Bool
    var isCompleted: Bool
    var isForced: Bool
    var countdownEndsAt: Date?
    var countdownPausedRemainingSeconds: Int?
    var estimatedDurationMinutes: Int?
    var completionStreakCount: Int
    var lastCompletedAt: Date?
    var lastVisibilityWindowTimeoutAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case residentTaskText
        case residentWeekdays
        case oneTimeVisibleDate
        case startVisibleAt
        case endVisibleAt
        case startReminderEnabled
        case startReminderOffsetMinutes
        case startVisibleMonth
        case startVisibleDay
        case isTaskHidden
        case isCompleted
        case isForced
        case countdownEndsAt
        case countdownPausedRemainingSeconds
        case estimatedDurationMinutes
        case completionStreakCount
        case lastCompletedAt
        case lastVisibilityWindowTimeoutAt
    }

    init(
        id: UUID = UUID(),
        text: String = "",
        residentTaskText: String? = nil,
        residentWeekdays: Set<Int> = [],
        oneTimeVisibleDate: Date? = nil,
        startVisibleAt: Date? = nil,
        endVisibleAt: Date? = nil,
        startReminderEnabled: Bool = false,
        startReminderOffsetMinutes: Int = Self.defaultStartReminderOffsetMinutes,
        startVisibleMonth: Int? = nil,
        startVisibleDay: Int? = nil,
        isTaskHidden: Bool = false,
        isCompleted: Bool = false,
        isForced: Bool = false,
        countdownEndsAt: Date? = nil,
        countdownPausedRemainingSeconds: Int? = nil,
        estimatedDurationMinutes: Int? = nil,
        completionStreakCount: Int = 0,
        lastCompletedAt: Date? = nil,
        lastVisibilityWindowTimeoutAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.residentTaskText = residentTaskText
        self.residentWeekdays = residentWeekdays
        self.oneTimeVisibleDate = oneTimeVisibleDate
        self.startVisibleAt = startVisibleAt
        self.endVisibleAt = endVisibleAt
        self.startReminderEnabled = startReminderEnabled
        self.startReminderOffsetMinutes = Self.normalizedStartReminderOffsetMinutes(startReminderOffsetMinutes)
        self.startVisibleMonth = startVisibleMonth
        self.startVisibleDay = startVisibleDay
        self.isTaskHidden = isTaskHidden
        self.isCompleted = isCompleted
        self.isForced = isForced
        self.countdownEndsAt = countdownEndsAt
        self.countdownPausedRemainingSeconds = countdownPausedRemainingSeconds
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.completionStreakCount = max(completionStreakCount, 0)
        self.lastCompletedAt = lastCompletedAt
        self.lastVisibilityWindowTimeoutAt = lastVisibilityWindowTimeoutAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        residentTaskText = try container.decodeIfPresent(String.self, forKey: .residentTaskText)
        residentWeekdays = try container.decodeIfPresent(Set<Int>.self, forKey: .residentWeekdays) ?? []
        oneTimeVisibleDate = try container.decodeIfPresent(Date.self, forKey: .oneTimeVisibleDate)
        startVisibleAt = try container.decodeIfPresent(Date.self, forKey: .startVisibleAt)
        endVisibleAt = try container.decodeIfPresent(Date.self, forKey: .endVisibleAt)
        startReminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .startReminderEnabled) ?? false
        startReminderOffsetMinutes = Self.normalizedStartReminderOffsetMinutes(
            try container.decodeIfPresent(Int.self, forKey: .startReminderOffsetMinutes)
        )
        startVisibleMonth = try container.decodeIfPresent(Int.self, forKey: .startVisibleMonth)
        startVisibleDay = try container.decodeIfPresent(Int.self, forKey: .startVisibleDay)
        isTaskHidden = try container.decodeIfPresent(Bool.self, forKey: .isTaskHidden) ?? false
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        isForced = try container.decodeIfPresent(Bool.self, forKey: .isForced) ?? false
        countdownEndsAt = try container.decodeIfPresent(Date.self, forKey: .countdownEndsAt)
        countdownPausedRemainingSeconds = try container.decodeIfPresent(Int.self, forKey: .countdownPausedRemainingSeconds)
        estimatedDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedDurationMinutes)
        completionStreakCount = try container.decodeIfPresent(Int.self, forKey: .completionStreakCount) ?? 0
        lastCompletedAt = try container.decodeIfPresent(Date.self, forKey: .lastCompletedAt)
        lastVisibilityWindowTimeoutAt = try container.decodeIfPresent(Date.self, forKey: .lastVisibilityWindowTimeoutAt)
    }

    var hasVisibilityWindow: Bool {
        hasStartVisibilityDate || hasEndVisibilityDate
    }

    static let defaultStartReminderOffsetMinutes = 5
    static let allowedStartReminderOffsetMinutes = [5, 10, 30]

    static func normalizedStartReminderOffsetMinutes(_ value: Int?) -> Int {
        guard let value else { return defaultStartReminderOffsetMinutes }
        return allowedStartReminderOffsetMinutes.contains(value) ? value : defaultStartReminderOffsetMinutes
    }

    func isVisibilityWindowActive(on date: Date, calendar: Calendar = .current) -> Bool {
        isStartVisibilityReached(on: date, calendar: calendar) && !isEndVisibilityReached(on: date)
    }

    func isVisibilityWindowInactive(on date: Date, calendar: Calendar = .current) -> Bool {
        // UX rule: only "before start" should be grey/inactive.
        // After end time, task enters timeout flow instead of staying grey.
        hasVisibilityWindow && !isStartVisibilityReached(on: date, calendar: calendar)
    }

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasStoredTask: Bool {
        !storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var storedTaskText: String {
        let recurring = residentTaskText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !recurring.isEmpty {
            return recurring
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasResidentSchedule: Bool {
        !residentWeekdays.isEmpty && !(residentTaskText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var isOneTimeTask: Bool {
        oneTimeVisibleDate != nil && !(residentTaskText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var hasStartVisibilityDate: Bool {
        startVisibleAt != nil || (startVisibleMonth != nil && startVisibleDay != nil)
    }

    func isStartVisibilityReached(on date: Date, calendar: Calendar = .current) -> Bool {
        if let startVisibleAt {
            return date >= startVisibleAt
        }
        guard let startVisibleMonth, let startVisibleDay else { return true }
        guard (1...12).contains(startVisibleMonth), (1...31).contains(startVisibleDay) else { return true }

        let currentYear = calendar.component(.year, from: date)
        var components = DateComponents()
        components.year = currentYear
        components.month = startVisibleMonth
        components.day = startVisibleDay
        guard let threshold = calendar.date(from: components) else { return true }

        return date >= calendar.startOfDay(for: threshold)
    }

    var hasEndVisibilityDate: Bool {
        endVisibleAt != nil
    }

    func isEndVisibilityReached(on date: Date) -> Bool {
        guard let endVisibleAt else { return false }
        return date >= endVisibleAt
    }

    func isResidentActive(on date: Date, calendar: Calendar = .current) -> Bool {
        guard hasResidentSchedule else { return true }
        let weekday = calendar.component(.weekday, from: date)
        return residentWeekdays.contains(weekday)
    }

    func projectedForDisplay(on date: Date, calendar: Calendar = .current) -> BingoCell {
        var projected = self
        if isVisibilityWindowInactive(on: date, calendar: calendar) {
            projected.text = storedTaskText
            projected.isCompleted = false
            projected.isTaskHidden = false
            projected.isForced = false
            projected.countdownEndsAt = nil
            return projected
        }

        let activeToday: Bool
        if isOneTimeTask, let oneTimeVisibleDate {
            activeToday = calendar.isDate(oneTimeVisibleDate, inSameDayAs: date)
        } else if hasResidentSchedule {
            activeToday = isResidentActive(on: date, calendar: calendar)
        } else {
            projected.text = storedTaskText
            // Keep countdown visible/active for regular tasks.
            return projected
        }
        projected.text = activeToday ? storedTaskText : ""
        projected.isCompleted = activeToday ? isCompleted : false
        projected.isTaskHidden = activeToday ? isTaskHidden : false
        // Only hide countdown when this task is not active today.
        projected.countdownEndsAt = activeToday ? countdownEndsAt : nil
        return projected
    }
}

enum BingoLine: Hashable, Codable {
    case row(Int)
    case column(Int)
    case diagonalMain
    case diagonalAnti
}

struct SavedBoard: Codable, Equatable {
    let gridSize: Int
    let cells: [[BingoCell]]
    let completedLines: Set<BingoLine>
    let fullBoardCells: [[BingoCell]]?

    init(gridSize: Int, cells: [[BingoCell]], completedLines: Set<BingoLine>, fullBoardCells: [[BingoCell]]? = nil) {
        self.gridSize = gridSize
        self.cells = cells
        self.completedLines = completedLines
        self.fullBoardCells = fullBoardCells
    }
}

struct BoardTemplateTile: Codable, Equatable {
    var text: String
    var residentWeekdays: [Int]
    var startVisibleMonth: Int?
    var startVisibleDay: Int?
    var isForced: Bool

    init(
        text: String,
        residentWeekdays: [Int] = [],
        startVisibleMonth: Int? = nil,
        startVisibleDay: Int? = nil,
        isForced: Bool = false
    ) {
        self.text = String(text.prefix(AppSettings.maxTaskLength))
        self.residentWeekdays = residentWeekdays.sorted()
        self.startVisibleMonth = startVisibleMonth
        self.startVisibleDay = startVisibleDay
        self.isForced = isForced
    }

    init(cell: BingoCell) {
        self.init(
            text: cell.storedTaskText,
            residentWeekdays: Array(cell.residentWeekdays),
            startVisibleMonth: cell.startVisibleMonth,
            startVisibleDay: cell.startVisibleDay,
            // Template sharing/import should not implicitly carry force flag.
            isForced: false
        )
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasContent: Bool {
        !trimmedText.isEmpty
    }
}

struct BoardTemplatePayload: Codable, Equatable, Identifiable {
    private static let minGridSize = 2
    private static let maxGridSize = 5
    static let urlScheme = "bingodays"
    static let urlHost = "template"
    static let universalHost = "dashbingo.xyz"
    static let universalPath = "/t"
    static let payloadQueryItem = "payload"
    private static let compressedPayloadPrefix = "z."
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6760203837")!

    let version: Int
    var title: String
    let gridSize: Int
    let tiles: [BoardTemplateTile]
    let createdAt: Date

    init(title: String, gridSize: Int, tiles: [BoardTemplateTile], createdAt: Date = .now) {
        self.version = 1
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.gridSize = min(max(gridSize, Self.minGridSize), Self.maxGridSize)
        self.tiles = Array(tiles.prefix(self.gridSize * self.gridSize))
        self.createdAt = createdAt
    }

    init(title: String, gridSize: Int, cells: [[BingoCell]], createdAt: Date = .now) {
        let normalizedGridSize = min(max(gridSize, Self.minGridSize), Self.maxGridSize)
        let normalizedTiles = (0..<normalizedGridSize).flatMap { row in
            (0..<normalizedGridSize).map { col in
                BoardTemplateTile(cell: cells[row][col])
            }
        }
        self.init(title: title, gridSize: normalizedGridSize, tiles: normalizedTiles, createdAt: createdAt)
    }

    var id: String {
        encodedPayloadToken ?? UUID().uuidString
    }

    var normalizedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(trimmed.prefix(20))
        return limited.isEmpty ? L10n.templateShareNamePlaceholder : limited
    }

    var filledTileCount: Int {
        tiles.filter(\.hasContent).count
    }

    var hasShareableContent: Bool {
        filledTileCount > 0
    }

    var qrCodeURL: URL {
        // Prefer direct template import for installed users.
        importURL ?? Self.appStoreURL
    }

    var importURL: URL? {
        guard let encodedPayloadToken else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.universalHost
        components.path = Self.universalPath
        components.queryItems = [
            URLQueryItem(name: Self.payloadQueryItem, value: encodedPayloadToken)
        ]
        return components.url
    }

    var nativeImportURL: URL? {
        guard let encodedPayloadToken else { return nil }
        var components = URLComponents()
        components.scheme = Self.urlScheme
        components.host = Self.urlHost
        components.queryItems = [
            URLQueryItem(name: Self.payloadQueryItem, value: encodedPayloadToken)
        ]
        return components.url
    }

    func shareMessage() -> String {
        let deepLink = importURL?.absoluteString ?? (nativeImportURL?.absoluteString ?? "")
        return L10n.templateShareMessage(
            deepLink: deepLink,
            appStoreLink: Self.appStoreURL.absoluteString
        )
    }

    func makeSavedBoard(referenceDate: Date = .now) -> SavedBoard {
        let normalizedGridSize = min(max(gridSize, Self.minGridSize), Self.maxGridSize)
        let requiredTiles = normalizedGridSize * normalizedGridSize
        let normalizedTiles = Array(tiles.prefix(requiredTiles)) + Array(
            repeating: BoardTemplateTile(text: ""),
            count: max(requiredTiles - tiles.count, 0)
        )

        var fullBoardCells = Self.createEmptyGrid(size: Self.maxGridSize)
        for index in 0..<requiredTiles {
            let row = index / normalizedGridSize
            let col = index % normalizedGridSize
            let tile = normalizedTiles[index]
            let trimmedText = tile.trimmedText

            guard !trimmedText.isEmpty else {
                fullBoardCells[row][col] = BingoCell()
                continue
            }

            let weekdaySet = Set(tile.residentWeekdays.filter { (1...7).contains($0) })
            var cell = BingoCell(
                text: trimmedText,
                residentTaskText: weekdaySet.isEmpty ? nil : trimmedText,
                residentWeekdays: weekdaySet,
                oneTimeVisibleDate: nil,
                startVisibleMonth: tile.startVisibleMonth,
                startVisibleDay: tile.startVisibleDay,
                isTaskHidden: false,
                isCompleted: false,
                // Import path should not implicitly inherit force flag.
                isForced: false,
                countdownEndsAt: nil,
                completionStreakCount: 0,
                lastCompletedAt: nil
            )
            cell = cell.projectedForDisplay(on: referenceDate)
            fullBoardCells[row][col] = cell
        }

        let visibleCells = (0..<normalizedGridSize).map { row in
            (0..<normalizedGridSize).map { col in
                fullBoardCells[row][col].projectedForDisplay(on: referenceDate)
            }
        }

        return SavedBoard(
            gridSize: normalizedGridSize,
            cells: visibleCells,
            completedLines: [],
            fullBoardCells: fullBoardCells
        )
    }

    static func decode(from url: URL) -> BoardTemplatePayload? {
        guard let token = payloadToken(from: url),
              let data = payloadData(from: token),
              let payload = try? JSONDecoder().decode(BoardTemplatePayload.self, from: data) else {
            return nil
        }

        return payload.hasShareableContent ? payload : nil
    }

    private static func payloadToken(from url: URL) -> String? {
        let scheme = url.scheme?.lowercased()
        let host = url.host?.lowercased()
        let isNativeTemplateLink = scheme == urlScheme && host == urlHost

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        if let token = components.queryItems?.first(where: { $0.name == payloadQueryItem })?.value,
           !token.isEmpty {
            return token
        }

        if let fragment = components.fragment,
           let fragmentComponents = URLComponents(string: "placeholder://placeholder?\(fragment)"),
           let token = fragmentComponents.queryItems?.first(where: { $0.name == payloadQueryItem })?.value,
           !token.isEmpty {
            return token
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        if let payloadIndex = pathComponents.lastIndex(of: payloadQueryItem),
           payloadIndex + 1 < pathComponents.count {
            let token = pathComponents[payloadIndex + 1]
            return token.isEmpty ? nil : token
        }

        if isNativeTemplateLink, pathComponents.count == 1 {
            let token = pathComponents[0]
            return token.isEmpty ? nil : token
        }

        return nil
    }

    private var encodedPayloadToken: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        if let compressedData = data.zlibCompressedData(),
           compressedData.count < data.count {
            return Self.compressedPayloadPrefix + compressedData.base64URLToken
        }
        return data.base64URLToken
    }

    private static func payloadData(from token: String) -> Data? {
        if token.hasPrefix(compressedPayloadPrefix) {
            let compressedToken = String(token.dropFirst(compressedPayloadPrefix.count))
            guard let compressedData = Data(base64URLToken: compressedToken) else { return nil }
            return compressedData.zlibDecompressedData()
        }
        return Data(base64URLToken: token)
    }

    private static func createEmptyGrid(size: Int) -> [[BingoCell]] {
        (0..<size).map { _ in
            (0..<size).map { _ in BingoCell() }
        }
    }
}

@MainActor
final class BoardTemplateImportCoordinator: ObservableObject {
    static let shared = BoardTemplateImportCoordinator()

    @Published var pendingTemplate: BoardTemplatePayload?
    @Published var pendingTemplateSource: String = "unknown"

    func handleIncomingURL(_ url: URL) -> Bool {
        guard let template = BoardTemplatePayload.decode(from: url) else { return false }
        pendingTemplateSource = "qr_scan"
        pendingTemplate = template
        return true
    }

    func dismissPendingTemplate() {
        pendingTemplate = nil
        pendingTemplateSource = "unknown"
    }
}

struct BingoDiaryEntry: Identifiable, Codable {
    let id: String
    let date: Date
    let board: SavedBoard
    let allTasksCompleted: Bool
    let completedTaskCounts: [String: Int]

    init(
        id: String,
        date: Date,
        board: SavedBoard,
        allTasksCompleted: Bool,
        completedTaskCounts: [String: Int] = [:]
    ) {
        self.id = id
        self.date = date
        self.board = board
        self.allTasksCompleted = allTasksCompleted
        self.completedTaskCounts = completedTaskCounts
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case board
        case allTasksCompleted
        case completedTaskCounts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        board = try container.decode(SavedBoard.self, forKey: .board)
        allTasksCompleted = try container.decode(Bool.self, forKey: .allTasksCompleted)
        completedTaskCounts = try container.decodeIfPresent([String: Int].self, forKey: .completedTaskCounts) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(board, forKey: .board)
        try container.encode(allTasksCompleted, forKey: .allTasksCompleted)
        try container.encode(completedTaskCounts, forKey: .completedTaskCounts)
    }
}

struct DailyRewardState: Codable, Equatable {
    var dateKey: String
    var rewardedCellIDs: Set<UUID>
    var peakCompletedLineCount: Int
    var fullBoardRewardGranted: Bool

    init(
        dateKey: String,
        rewardedCellIDs: Set<UUID> = [],
        peakCompletedLineCount: Int = 0,
        fullBoardRewardGranted: Bool = false
    ) {
        self.dateKey = dateKey
        self.rewardedCellIDs = rewardedCellIDs
        self.peakCompletedLineCount = peakCompletedLineCount
        self.fullBoardRewardGranted = fullBoardRewardGranted
    }
}

struct MyTaskItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var startAt: Date?
    var endAt: Date?
    var startMonth: Int?
    var startDay: Int?

    init(
        id: UUID = UUID(),
        text: String = "",
        startAt: Date? = nil,
        endAt: Date? = nil,
        startMonth: Int? = nil,
        startDay: Int? = nil
    ) {
        self.id = id
        self.text = text
        self.startAt = startAt
        self.endAt = endAt
        self.startMonth = startMonth
        self.startDay = startDay
        normalizeVisibilityWindow()
    }

    init(from decoder: Decoder) throws {
        if let singleValueContainer = try? decoder.singleValueContainer(),
           let legacyText = try? singleValueContainer.decode(String.self) {
            id = UUID()
            text = legacyText
            startAt = nil
            endAt = nil
            startMonth = nil
            startDay = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        startAt = try container.decodeIfPresent(Date.self, forKey: .startAt)
        endAt = try container.decodeIfPresent(Date.self, forKey: .endAt)
        startMonth = try container.decodeIfPresent(Int.self, forKey: .startMonth)
        startDay = try container.decodeIfPresent(Int.self, forKey: .startDay)
        normalizeVisibilityWindow()
    }

    mutating func normalizeStartDate() {
        normalizeVisibilityWindow()
    }

    mutating func normalizeVisibilityWindow() {
        if let startAt {
            let components = Calendar.current.dateComponents([.month, .day], from: startAt)
            startMonth = components.month
            startDay = components.day
        } else {
            guard let startMonth, let startDay else {
                self.startMonth = nil
                self.startDay = nil
                return
            }

            guard (1...12).contains(startMonth), (1...31).contains(startDay) else {
                self.startMonth = nil
                self.startDay = nil
                return
            }
        }

        if let startAt, let endAt, endAt <= startAt {
            self.endAt = nil
        }
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasStartDate: Bool {
        startAt != nil || (startMonth != nil && startDay != nil)
    }

    var hasEndDate: Bool {
        endAt != nil
    }

    func isStartDateReached(on date: Date = .now, calendar: Calendar = .current) -> Bool {
        if let startAt {
            return date >= startAt
        }
        guard let startMonth, let startDay else { return true }
        guard (1...12).contains(startMonth), (1...31).contains(startDay) else { return true }

        let currentYear = calendar.component(.year, from: date)
        var components = DateComponents()
        components.year = currentYear
        components.month = startMonth
        components.day = startDay
        guard let threshold = calendar.date(from: components) else { return true }

        return date >= calendar.startOfDay(for: threshold)
    }

    func isEndDateReached(on date: Date = .now) -> Bool {
        guard let endAt else { return false }
        return date >= endAt
    }
}

struct MyTaskGroup: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var tasks: [MyTaskItem]

    init(id: UUID = UUID(), name: String = "", tasks: [MyTaskItem] = []) {
        self.id = id
        self.name = name
        self.tasks = tasks
    }
}

struct MyTasksLibrary: Codable, Equatable {
    var tasks: [MyTaskItem]
    var groups: [MyTaskGroup]

    init(tasks: [MyTaskItem] = [], groups: [MyTaskGroup] = []) {
        self.tasks = tasks
        self.groups = groups
    }
}

struct TaskHistoryRecord: Identifiable, Codable, Equatable {
    let key: String
    var text: String
    var startAt: Date?
    var endAt: Date?
    var startMonth: Int?
    var startDay: Int?
    var sourceTaskID: UUID?
    var lastEditedAt: Date

    var id: String { key }

    init(
        key: String,
        text: String,
        startAt: Date? = nil,
        endAt: Date? = nil,
        startMonth: Int? = nil,
        startDay: Int? = nil,
        sourceTaskID: UUID? = nil,
        lastEditedAt: Date = .now
    ) {
        self.key = key
        self.text = text
        self.startAt = startAt
        self.endAt = endAt
        self.startMonth = startMonth
        self.startDay = startDay
        self.sourceTaskID = sourceTaskID
        self.lastEditedAt = lastEditedAt
        normalizeVisibilityWindow()
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func normalizeStartDate() {
        normalizeVisibilityWindow()
    }

    mutating func normalizeVisibilityWindow() {
        if let startAt {
            let components = Calendar.current.dateComponents([.month, .day], from: startAt)
            startMonth = components.month
            startDay = components.day
        } else {
            guard let startMonth, let startDay else {
                self.startMonth = nil
                self.startDay = nil
                return
            }

            guard (1...12).contains(startMonth), (1...31).contains(startDay) else {
                self.startMonth = nil
                self.startDay = nil
                return
            }

            var components = DateComponents()
            components.year = 2000
            components.month = startMonth
            components.day = startDay
            guard Calendar.current.date(from: components) != nil else {
                self.startMonth = nil
                self.startDay = nil
                return
            }
        }

        if let startAt, let endAt, endAt <= startAt {
            self.endAt = nil
        }
    }
}

struct CustomReward: Identifiable, Codable, Equatable {
    static let currentCardStyleVersion = 2

    let id: UUID
    var title: String
    var requiredPoints: Int
    var emoji: String
    var themeImageName: String?
    var cardStyleVersion: Int
    var redemptionCount: Int
    var totalSpentPoints: Int
    var isArchived: Bool

    var isLegacyCardStyle: Bool {
        cardStyleVersion < Self.currentCardStyleVersion
    }

    var displayEmoji: String {
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedEmoji.first.map(String.init) ?? "😊"
    }

    init(
        id: UUID = UUID(),
        title: String,
        requiredPoints: Int,
        emoji: String = "😊",
        themeImageName: String? = nil,
        cardStyleVersion: Int = CustomReward.currentCardStyleVersion,
        redemptionCount: Int = 0,
        totalSpentPoints: Int = 0,
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.requiredPoints = requiredPoints
        self.emoji = emoji
        self.themeImageName = themeImageName
        self.cardStyleVersion = cardStyleVersion
        self.redemptionCount = redemptionCount
        self.totalSpentPoints = totalSpentPoints
        self.isArchived = isArchived
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case requiredPoints
        case emoji
        case themeImageName
        case cardStyleVersion
        case redemptionCount
        case totalSpentPoints
        case isArchived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        requiredPoints = try container.decode(Int.self, forKey: .requiredPoints)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji) ?? "😊"
        themeImageName = try container.decodeIfPresent(String.self, forKey: .themeImageName)
        cardStyleVersion = try container.decodeIfPresent(Int.self, forKey: .cardStyleVersion) ?? 1
        redemptionCount = try container.decodeIfPresent(Int.self, forKey: .redemptionCount) ?? 0
        totalSpentPoints = try container.decodeIfPresent(Int.self, forKey: .totalSpentPoints) ?? 0
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }
}

struct PointRedemptionRecord: Identifiable, Codable, Equatable {
    enum ItemKind: String, Codable {
        case sticker
        case customReward
    }

    let id: UUID
    let itemKind: ItemKind
    let title: String
    let points: Int
    let redeemedAt: Date
    let imageName: String?
    let emoji: String?

    init(
        id: UUID = UUID(),
        itemKind: ItemKind,
        title: String,
        points: Int,
        redeemedAt: Date = .now,
        imageName: String? = nil,
        emoji: String? = nil
    ) {
        self.id = id
        self.itemKind = itemKind
        self.title = title
        self.points = points
        self.redeemedAt = redeemedAt
        self.imageName = imageName
        self.emoji = emoji
    }
}

enum StickerKind: String, CaseIterable, Codable, Identifiable {
    case cowCat
    case cowCatStar
    case orangeCat
    case pomeranian
    case dachshund
    case toyPoodle
    case yorkshire
    case akita
    case goldenRetriever
    case ragdollCat
    case ragdollCatStar
    case maineCoon
    case alaskanMalamute
    case chineseVillageDog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cowCat: return L10n.tr("Cow Cat", zhHans: "奶牛猫", ja: "白黒猫")
        case .cowCatStar: return L10n.tr("Cow Cat (Star)", zhHans: "奶牛猫（星星）", zhHant: "奶牛貓（星星）", ja: "白黒猫（スター）")
        case .orangeCat: return L10n.tr("Orange Cat", zhHans: "橘猫", ja: "茶トラ猫")
        case .pomeranian: return L10n.tr("Pomeranian", zhHans: "博美", ja: "ポメラニアン")
        case .dachshund: return L10n.tr("Dachshund", zhHans: "腊肠狗", ja: "ダックスフンド")
        case .toyPoodle: return L10n.tr("Toy Poodle", zhHans: "泰迪", ja: "トイプードル")
        case .yorkshire: return L10n.tr("Yorkshire", zhHans: "约克夏", ja: "ヨークシャー")
        case .akita: return L10n.tr("Akita", zhHans: "秋田", ja: "秋田犬")
        case .goldenRetriever: return L10n.tr("Golden Retriever", zhHans: "金毛", ja: "ゴールデンレトリバー")
        case .ragdollCat: return L10n.tr("Ragdoll Cat", zhHans: "布偶猫", ja: "ラグドール")
        case .ragdollCatStar: return L10n.tr("Ragdoll Cat (Star)", zhHans: "布偶猫（星星）", zhHant: "布偶貓（星星）", ja: "ラグドール（スター）")
        case .maineCoon: return L10n.tr("Maine Coon", zhHans: "缅因猫", ja: "メインクーン")
        case .alaskanMalamute: return L10n.tr("Alaskan Malamute", zhHans: "阿拉斯加", ja: "アラスカンマラミュート")
        case .chineseVillageDog: return L10n.tr("Chinese Village Dog", zhHans: "中华田园犬", ja: "中華田園犬")
        }
    }

    var redemptionHistoryTitle: String {
        switch self {
        case .cowCatStar:
            return StickerKind.cowCat.title
        case .ragdollCatStar:
            return StickerKind.ragdollCat.title
        default:
            return title
        }
    }

    var unlockedImageName: String {
        switch self {
        case .cowCat: return "CowCatSticker"
        case .cowCatStar: return "CowCatStarSticker"
        case .orangeCat: return "OrangeCatSticker"
        case .pomeranian: return "PomeranianSticker"
        case .dachshund: return "DachshundSticker"
        case .toyPoodle: return "ToyPoodleSticker"
        case .yorkshire: return "YorkshireSticker"
        case .akita: return "AkitaSticker"
        case .goldenRetriever: return "GoldenRetrieverSticker"
        case .ragdollCat: return "RagdollCatSticker"
        case .ragdollCatStar: return "RagdollCatStarSticker"
        case .maineCoon: return "MaineCoonSticker"
        case .alaskanMalamute: return "AlaskanMalamuteSticker"
        case .chineseVillageDog: return "ChineseVillageDogSticker"
        }
    }

    var lockedImageName: String {
        switch self {
        case .cowCat: return "AkitaStickerLocked"
        case .cowCatStar: return "CowCatStarStickerLocked"
        case .orangeCat: return "OrangeCatStickerLocked"
        case .pomeranian: return "PomeranianStickerLocked"
        case .dachshund: return "DachshundStickerLocked"
        case .toyPoodle: return "ToyPoodleStickerLocked"
        case .yorkshire: return "YorkshireStickerLocked"
        case .akita: return "AkitaStickerLocked"
        case .goldenRetriever: return "GoldenRetrieverStickerLocked"
        case .ragdollCat: return "MaineCoonStickerLocked"
        case .ragdollCatStar: return "RagdollCatStarStickerLocked"
        case .maineCoon: return "MaineCoonStickerLocked"
        case .alaskanMalamute: return "AlaskanMalamuteStickerLocked"
        case .chineseVillageDog: return "ChineseVillageDogStickerLocked"
        }
    }

    var requiredPoints: Int {
        15
    }

    var homeDisplayWidth: CGFloat {
        switch self {
        case .cowCat:
            return 86
        case .cowCatStar:
            return 94
        case .ragdollCat, .maineCoon, .alaskanMalamute, .goldenRetriever, .chineseVillageDog:
            return 100
        case .ragdollCatStar:
            return 102
        default:
            return 92
        }
    }

    var defaultPlacement: (xRatio: Double, yRatio: Double) {
        switch self {
        case .cowCat:
            return (0.22, 0.24)
        case .cowCatStar:
            return (0.34, 0.84)
        case .orangeCat:
            return (0.48, 0.18)
        case .pomeranian:
            return (0.78, 0.24)
        case .dachshund:
            return (0.18, 0.46)
        case .toyPoodle:
            return (0.82, 0.48)
        case .yorkshire:
            return (0.22, 0.70)
        case .akita:
            return (0.50, 0.74)
        case .goldenRetriever:
            return (0.78, 0.70)
        case .ragdollCat:
            return (0.50, 0.30)
        case .ragdollCatStar:
            return (0.66, 0.84)
        case .maineCoon:
            return (0.34, 0.56)
        case .alaskanMalamute:
            return (0.66, 0.56)
        case .chineseVillageDog:
            return (0.50, 0.88)
        }
    }
}

struct HomeStickerPlacement: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: StickerKind
    var xRatio: Double
    var yRatio: Double
    var scale: Double

    init(id: UUID = UUID(), kind: StickerKind, xRatio: Double, yRatio: Double, scale: Double = 1.0) {
        self.id = id
        self.kind = kind
        self.xRatio = xRatio
        self.yRatio = yRatio
        self.scale = scale
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case xRatio
        case yRatio
        case scale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(StickerKind.self, forKey: .kind)
        xRatio = try container.decode(Double.self, forKey: .xRatio)
        yRatio = try container.decode(Double.self, forKey: .yRatio)
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(xRatio, forKey: .xRatio)
        try container.encode(yRatio, forKey: .yRatio)
        try container.encode(scale, forKey: .scale)
    }

    func normalized() -> HomeStickerPlacement {
        HomeStickerPlacement(
            id: id,
            kind: kind,
            xRatio: Self.clamp(xRatio, min: 0.02, max: 0.98, fallback: 0.5),
            yRatio: Self.clamp(yRatio, min: 0.02, max: 1.08, fallback: 0.5),
            scale: Self.clamp(scale, min: 0.5, max: 1.6, fallback: 1.0)
        )
    }

    private static func clamp(_ value: Double, min lowerBound: Double, max upperBound: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return Swift.max(lowerBound, Swift.min(value, upperBound))
    }
}

enum AppSettings {
    static let hapticsEnabledKey = "haptics_enabled"
    static let soundEffectsEnabledKey = "sound_effects_enabled"
    static let themeKey = "theme_color"
    static let hasSeenOnboardingKey = "has_seen_onboarding_v2"
    static let commonTasksKey = "common_tasks"
    static let boardCountdownKey = "board_countdown_v1"
    static let totalPointsKey = "total_points_v2"
    static let lifetimePointsKey = "lifetime_points_v1"
    static let dailyRewardStateKey = "daily_reward_state_v1"
    static let redeemedStickersKey = "redeemed_stickers_v1"
    static let redeemedStickerOrderKey = "redeemed_sticker_order_v1"
    static let stickerInventoryCountsKey = "sticker_inventory_counts_v1"
    static let homeStickerPlacementsKey = "home_sticker_placements_v1"
    static let customRewardsKey = "custom_rewards_v1"
    static let pointRedemptionHistoryKey = "point_redemption_history_v1"
    static let rewardEmojiHistoryKey = "reward_emoji_history_v1"
    static let taskHistoryKey = "task_history_v1"
    static let lastAppUpdateCheckAtKey = "last_app_update_check_at_v1"
    static let lastPromptedUpdateVersionKey = "last_prompted_update_version_v1"
    static let skippedUpdateVersionKey = "skipped_update_version_v1"
    static let cachedUpdateInfoKey = "cached_app_update_info_v1"
    static let hasRatedAppReviewPromptKey = "has_rated_app_review_prompt_v1"
    static let appReviewPromptStageKey = "app_review_prompt_stage_v1"
    static let appReviewPromptCooldownUntilKey = "app_review_prompt_cooldown_until_v1"
    static let appReviewPromptLifetimeShownCountKey = "app_review_prompt_lifetime_shown_count_v1"
    static let appReviewPromptLastShownDayKey = "app_review_prompt_last_shown_day_v1"
    static let firstStepGuideStateKey = "first_step_guide_state_v1"
    static let firstStepGuideMilestoneKey = "first_step_guide_milestone_v1"
    static let hasAcknowledgedBoardEditHintKey = "has_acknowledged_board_edit_hint_v1"
    static let hasInteractedWithBoardPanelKey = "has_interacted_with_board_panel_v1"
    static let hasVisitedPremiumPaywallWithoutPurchaseKey = "has_visited_premium_paywall_without_purchase_v1"
    static let limitedTimeDiscountStartedAtKey = "limited_time_discount_started_at_v1"
    static let limitedTimeDiscountCampaignIDKey = "limited_time_discount_campaign_id_v1"
    static let maxCommonTasks = 8
    static let maxTaskGroups = 3
    static let maxTasksPerGroup = 5
    static let maxTaskLength = 20
    static let maxRewardTitleLength = 16
    static let maxFreeCustomRewards = 3
    static let freeHistoryTasksVisibleCount = 10

    static var isHapticsEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: hapticsEnabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: hapticsEnabledKey)
    }

    static var isSoundEffectsEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: soundEffectsEnabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: soundEffectsEnabledKey)
    }
}

enum AppHaptics {
    private static let completionGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let controlGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let emphasisGenerator = UIImpactFeedbackGenerator(style: .heavy)

    private static func perform(_ work: @escaping () -> Void) {
        guard AppSettings.isHapticsEnabled else { return }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    static func prepareForInteraction() {
        perform {
            completionGenerator.prepare()
            controlGenerator.prepare()
            emphasisGenerator.prepare()
        }
    }

    static func completion() {
        perform {
            completionGenerator.impactOccurred(intensity: 1.0)
            completionGenerator.prepare()
        }
    }

    static func control() {
        perform {
            controlGenerator.impactOccurred(intensity: 0.85)
            controlGenerator.prepare()
        }
    }

    static func emphasis() {
        perform {
            emphasisGenerator.impactOccurred(intensity: 1.0)
            emphasisGenerator.prepare()
        }
    }
}

enum BingoDiaryStore {
    private static let key = "bingo_diary_v1"

    static func save(board: SavedBoard, on date: Date = .now) {
        var entries = loadEntriesDictionary()
        let entryID = dateKey(for: date)
        let existingEntry = entries[entryID]
        let completionIncrements = completedTaskIncrements(
            previousBoard: existingEntry?.board,
            currentBoard: board
        )
        let completionDecrements = completedTaskDecrements(
            previousBoard: existingEntry?.board,
            currentBoard: board
        )
        let mergedCounts = applyTaskCountDelta(
            base: existingTaskCounts(from: existingEntry),
            increments: completionIncrements,
            decrements: completionDecrements
        )
        let entry = BingoDiaryEntry(
            id: entryID,
            date: Calendar.current.startOfDay(for: date),
            board: board,
            allTasksCompleted: (existingEntry?.allTasksCompleted ?? false) || boardHasAllTasksCompleted(board),
            completedTaskCounts: mergedCounts
        )
        entries[entry.id] = entry
        persist(entries)
    }

    static func applyExplicitTaskDelta(
        task: String,
        delta: Int,
        board: SavedBoard,
        on date: Date = .now
    ) {
        let normalizedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTask.isEmpty else {
            syncBoardSnapshotWithoutCounting(board: board, on: date)
            return
        }

        var entries = loadEntriesDictionary()
        let entryID = dateKey(for: date)
        let existingEntry = entries[entryID]
        var mergedCounts = existingTaskCounts(from: existingEntry)

        if delta > 0 {
            mergedCounts[normalizedTask, default: 0] += delta
        } else if delta < 0 {
            let current = mergedCounts[normalizedTask, default: 0]
            let next = max(0, current + delta)
            if next == 0 {
                mergedCounts.removeValue(forKey: normalizedTask)
            } else {
                mergedCounts[normalizedTask] = next
            }
        }

        let entry = BingoDiaryEntry(
            id: entryID,
            date: Calendar.current.startOfDay(for: date),
            board: board,
            allTasksCompleted: (existingEntry?.allTasksCompleted ?? false) || boardHasAllTasksCompleted(board),
            completedTaskCounts: mergedCounts
        )
        entries[entry.id] = entry
        persist(entries)
    }

    // Keep today's baseline board snapshot in sync even when diary counting is skipped.
    // This prevents stale snapshot diffs from causing large decrement/increment jumps later.
    static func syncBoardSnapshotWithoutCounting(board: SavedBoard, on date: Date = .now) {
        var entries = loadEntriesDictionary()
        let entryID = dateKey(for: date)
        guard let existingEntry = entries[entryID] else { return }

        let updatedEntry = BingoDiaryEntry(
            id: existingEntry.id,
            date: existingEntry.date,
            board: board,
            allTasksCompleted: existingEntry.allTasksCompleted || boardHasAllTasksCompleted(board),
            completedTaskCounts: existingEntry.completedTaskCounts
        )
        entries[entryID] = updatedEntry
        persist(entries)
    }

    static func entry(for date: Date) -> BingoDiaryEntry? {
        loadEntriesDictionary()[dateKey(for: date)]
    }

    static func entries(inMonthContaining date: Date) -> [BingoDiaryEntry] {
        let calendar = Calendar.current
        let monthInterval = calendar.dateInterval(of: .month, for: date)

        return loadEntriesDictionary().values
            .filter { entry in
                guard let interval = monthInterval else { return false }
                return interval.contains(entry.date)
            }
            .sorted { $0.date < $1.date }
    }

    static func consecutiveBingoDays(referenceDate: Date = .now) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        let entries = loadEntriesDictionary()

        var streak = 0
        var cursor = today

        while let entry = entries[dateKey(for: cursor)], entry.allTasksCompleted {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }

        return streak
    }

    static func consecutiveTaskCompletionDays(referenceDate: Date = .now) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        let entries = loadEntriesDictionary()

        var streak = 0
        var cursor = today

        while let entry = entries[dateKey(for: cursor)],
              existingTaskCounts(from: entry).values.contains(where: { $0 > 0 }) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }

        return streak
    }

    static func totalCompletedTasks() -> Int {
        allTimeCompletedTaskCounts().reduce(0) { $0 + $1.count }
    }

    static func allTimeCompletedTaskCounts() -> [(task: String, count: Int)] {
        let stats = allTimeCompletedTaskStats()

        return stats.map { (task: $0.task, count: $0.count) }
    }

    static func allTimeCompletedTaskStats() -> [(task: String, count: Int, firstCompletedAt: Date)] {
        struct TaskAggregate {
            var count: Int
            var firstCompletedAt: Date
        }

        let entries = loadEntriesDictionary()

        let stats = entries.values.reduce(into: [String: TaskAggregate]()) { partial, entry in
            let day = Calendar.current.startOfDay(for: entry.date)
            for (task, count) in existingTaskCounts(from: entry) {
                guard !task.isEmpty, count > 0 else { continue }
                if let existing = partial[task] {
                    partial[task] = TaskAggregate(
                        count: existing.count + count,
                        firstCompletedAt: min(existing.firstCompletedAt, day)
                    )
                } else {
                    partial[task] = TaskAggregate(count: count, firstCompletedAt: day)
                }
            }
        }

        return stats
            .map { (task: $0.key, count: $0.value.count, firstCompletedAt: $0.value.firstCompletedAt) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    if lhs.firstCompletedAt == rhs.firstCompletedAt {
                        return lhs.task.localizedCaseInsensitiveCompare(rhs.task) == .orderedAscending
                    }
                    return lhs.firstCompletedAt < rhs.firstCompletedAt
                }
                return lhs.count > rhs.count
            }
    }

    static func taskDailyCompletions(
        task: String,
        limit: Int = 30,
        referenceDate: Date = .now
    ) -> [(date: Date, count: Int)] {
        let normalizedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTask.isEmpty else { return [] }

        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: referenceDate)
        let rows = loadEntriesDictionary().values.compactMap { entry -> (date: Date, count: Int)? in
            let day = calendar.startOfDay(for: entry.date)
            guard day <= endDate else { return nil }
            let count = existingTaskCounts(from: entry)[normalizedTask] ?? 0
            guard count > 0 else { return nil }
            return (date: day, count: count)
        }
        .sorted { $0.date > $1.date }

        guard limit > 0 else { return rows }
        return Array(rows.prefix(limit))
    }

    static func taskCompletionsThisWeek(
        task: String,
        referenceDate: Date = .now
    ) -> Int {
        let normalizedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTask.isEmpty else { return 0 }
        let calendar = Calendar.current
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else { return 0 }

        return loadEntriesDictionary().values.reduce(0) { partial, entry in
            let day = calendar.startOfDay(for: entry.date)
            guard weekInterval.contains(day) else { return partial }
            return partial + (existingTaskCounts(from: entry)[normalizedTask] ?? 0)
        }
    }

    static func completedTaskCounts(lastDays: Int, referenceDate: Date = .now) -> [(task: String, count: Int)] {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: referenceDate)
        guard let startDate = calendar.date(byAdding: .day, value: -(max(lastDays, 1) - 1), to: endDate) else {
            return []
        }

        let counts = loadEntriesDictionary().values.reduce(into: [String: Int]()) { partial, entry in
            let day = calendar.startOfDay(for: entry.date)
            guard day >= startDate && day <= endDate else { return }

            for (task, count) in existingTaskCounts(from: entry) {
                guard !task.isEmpty, count > 0 else { continue }
                partial[task, default: 0] += count
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

    static func taskCompletionStats(
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

        for entry in loadEntriesDictionary().values {
            let entryKey = dateKey(for: entry.date)
            guard let dayIndex = dayIndexByKey[entryKey] else { continue }

            for (task, count) in existingTaskCounts(from: entry) {
                guard !task.isEmpty, count > 0 else { continue }
                var counts = taskDailyCounts[task] ?? emptyDailyCounts
                counts[dayIndex] += count
                taskDailyCounts[task] = counts
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

    static func loadAllEntriesDictionary() -> [String: BingoDiaryEntry] {
        loadEntriesDictionary()
    }

    static func replaceAllEntriesDictionary(_ entries: [String: BingoDiaryEntry]) {
        persist(entries)
    }

    private static func loadEntriesDictionary() -> [String: BingoDiaryEntry] {
        if let data = sharedDefaults.data(forKey: key),
           let entries = try? JSONDecoder().decode([String: BingoDiaryEntry].self, from: data) {
            return entries
        }

        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([String: BingoDiaryEntry].self, from: data) else {
            return [:]
        }
        sharedDefaults.set(data, forKey: key)
        return entries
    }

    private static func persist(_ entries: [String: BingoDiaryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        sharedDefaults.set(data, forKey: key)
        UserDefaults.standard.set(data, forKey: key)
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: BingoBoardStore.appGroupID) ?? .standard
    }

    private static func boardHasAllTasksCompleted(_ board: SavedBoard) -> Bool {
        let taskCells = board.cells.flatMap { $0 }.filter { !$0.isEmpty }
        guard !taskCells.isEmpty else { return false }
        return taskCells.allSatisfy(\.isCompleted)
    }

    private static func completedTaskCounts(from board: SavedBoard) -> [String: Int] {
        board.cells
            .flatMap { $0 }
            .reduce(into: [String: Int]()) { partial, cell in
                guard cell.isCompleted, !cell.isEmpty else { return }
                let task = cell.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !task.isEmpty else { return }
                partial[task, default: 0] += 1
            }
    }

    // Count only completion transitions from previous snapshot -> current snapshot.
    // This avoids undercounting repeated completions (old max-merge logic) and
    // avoids double counting on frequent saves when no state changed.
    private static func completedTaskIncrements(previousBoard: SavedBoard?, currentBoard: SavedBoard) -> [String: Int] {
        let previousCells = flattenedVisibleCells(from: previousBoard)
        let currentCells = flattenedVisibleCells(from: currentBoard)
        let previousByID = Dictionary(uniqueKeysWithValues: previousCells.map { ($0.id, $0) })

        return currentCells.reduce(into: [String: Int]()) { partial, cell in
            guard !cell.isEmpty, cell.isCompleted else { return }
            let task = cell.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !task.isEmpty else { return }

            // First save of the day: existing entry may not exist yet.
            let wasCompleted = previousByID[cell.id]?.isCompleted ?? false
            guard !wasCompleted else { return }

            partial[task, default: 0] += 1
        }
    }

    // Count un-completion transitions from previous snapshot -> current snapshot.
    // This keeps same-day diary counts accurate when users cancel completed tasks.
    private static func completedTaskDecrements(previousBoard: SavedBoard?, currentBoard: SavedBoard) -> [String: Int] {
        let previousCells = flattenedVisibleCells(from: previousBoard)
        let currentCells = flattenedVisibleCells(from: currentBoard)
        let currentByID = Dictionary(uniqueKeysWithValues: currentCells.map { ($0.id, $0) })

        return previousCells.reduce(into: [String: Int]()) { partial, previousCell in
            guard !previousCell.isEmpty, previousCell.isCompleted else { return }
            let task = previousCell.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !task.isEmpty else { return }

            // Only explicit same-cell uncheck should decrement diary count.
            // If a cell was replaced/rebuilt (ID missing), do not treat it as a cancel.
            guard let currentCell = currentByID[previousCell.id] else { return }
            guard !currentCell.isCompleted else { return }

            partial[task, default: 0] += 1
        }
    }

    private static func flattenedVisibleCells(from board: SavedBoard?) -> [BingoCell] {
        guard let board else { return [] }

        let resolvedGridSize = max(0, min(board.gridSize, 5))
        if let fullBoardCells = board.fullBoardCells, !fullBoardCells.isEmpty, resolvedGridSize > 0 {
            var flattened: [BingoCell] = []
            flattened.reserveCapacity(resolvedGridSize * resolvedGridSize)

            let rowUpperBound = min(resolvedGridSize, fullBoardCells.count)
            for row in 0..<rowUpperBound {
                let colUpperBound = min(resolvedGridSize, fullBoardCells[row].count)
                guard colUpperBound > 0 else { continue }
                flattened.append(contentsOf: fullBoardCells[row].prefix(colUpperBound))
            }

            if !flattened.isEmpty {
                return flattened
            }
        }
        return board.cells.flatMap { $0 }
    }

    private static func existingTaskCounts(from entry: BingoDiaryEntry?) -> [String: Int] {
        guard let entry else { return [:] }
        if !entry.completedTaskCounts.isEmpty {
            return entry.completedTaskCounts
        }
        return completedTaskCounts(from: entry.board)
    }

    private static func applyTaskCountDelta(
        base: [String: Int],
        increments: [String: Int],
        decrements: [String: Int]
    ) -> [String: Int] {
        var merged = base

        for (task, count) in increments where count > 0 {
            merged[task, default: 0] += count
        }

        for (task, count) in decrements where count > 0 {
            let current = merged[task, default: 0]
            let next = max(0, current - count)
            if next == 0 {
                merged.removeValue(forKey: task)
            } else {
                merged[task] = next
            }
        }

        return merged
    }

    private struct TaskStreakBound {
        var maxStreak: Int
        var firstCompletedAt: Date
    }

    private static func completionStreakLowerBounds(
        from entries: [String: BingoDiaryEntry],
        calendar: Calendar
    ) -> [String: TaskStreakBound] {
        var result: [String: TaskStreakBound] = [:]

        for entry in entries.values {
            let sourceCells: [[BingoCell]] = {
                if let fullBoard = entry.board.fullBoardCells, !fullBoard.isEmpty {
                    return fullBoard
                }
                return entry.board.cells
            }()

            for cell in sourceCells.flatMap({ $0 }) {
                let task = cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
                // Keep same-day complete -> cancel reversible, while preserving
                // historical fallback for previous-day completions.
                guard !task.isEmpty, cell.completionStreakCount > 0 else { continue }
                let completionDate = calendar.startOfDay(for: cell.lastCompletedAt ?? entry.date)
                let isHistoricalCompletion = completionDate < calendar.startOfDay(for: Date())
                guard cell.isCompleted || isHistoricalCompletion else { continue }

                if let existing = result[task] {
                    result[task] = TaskStreakBound(
                        maxStreak: max(existing.maxStreak, cell.completionStreakCount),
                        firstCompletedAt: min(existing.firstCompletedAt, completionDate)
                    )
                } else {
                    result[task] = TaskStreakBound(
                        maxStreak: cell.completionStreakCount,
                        firstCompletedAt: completionDate
                    )
                }
            }
        }

        return result
    }

    private static func dateKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

private extension Data {
    var base64URLToken: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLToken: String) {
        var base64 = base64URLToken
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: base64)
    }

    func zlibCompressedData() -> Data? {
        processedWithZlib(operation: COMPRESSION_STREAM_ENCODE)
    }

    func zlibDecompressedData() -> Data? {
        processedWithZlib(operation: COMPRESSION_STREAM_DECODE)
    }

    private func processedWithZlib(operation: compression_stream_operation) -> Data? {
        guard !isEmpty else { return Data() }

        return withUnsafeBytes { rawBuffer -> Data? in
            guard let sourceBase = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return nil }

            let initialDstPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
            let initialSrcMutablePointer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
            initialDstPointer.initialize(to: 0)
            initialSrcMutablePointer.initialize(to: 0)
            defer {
                initialDstPointer.deallocate()
                initialSrcMutablePointer.deallocate()
            }

            var stream = compression_stream(
                dst_ptr: initialDstPointer,
                dst_size: 0,
                src_ptr: UnsafePointer(initialSrcMutablePointer),
                src_size: 0,
                state: nil
            )
            guard compression_stream_init(&stream, operation, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR else {
                return nil
            }
            defer { compression_stream_destroy(&stream) }

            let destinationCapacity = 64 * 1024
            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationCapacity)
            defer { destinationBuffer.deallocate() }

            stream.src_ptr = sourceBase
            stream.src_size = count
            stream.dst_ptr = destinationBuffer
            stream.dst_size = destinationCapacity

            var outputData = Data()
            let flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)

            while true {
                let status = compression_stream_process(&stream, flags)
                let producedBytes = destinationCapacity - stream.dst_size
                if producedBytes > 0 {
                    outputData.append(destinationBuffer, count: producedBytes)
                }

                if status == COMPRESSION_STATUS_END {
                    return outputData
                }
                if status != COMPRESSION_STATUS_OK {
                    return nil
                }

                stream.dst_ptr = destinationBuffer
                stream.dst_size = destinationCapacity
            }
        }
    }
}

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

    static func loadAllPayload() -> [String: [String: Int]] {
        loadPayload()
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

    static func replacePayload(_ payload: [String: [String: Int]]) {
        persist(payload)
    }

    private static func loadPayload() -> [String: [String: Int]] {
        if let data = sharedDefaults.data(forKey: key),
           let payload = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            return payload
        }

        guard let data = UserDefaults.standard.data(forKey: key),
              let payload = try? JSONDecoder().decode([String: [String: Int]].self, from: data) else {
            return [:]
        }

        sharedDefaults.set(data, forKey: key)
        return payload
    }

    private static func persist(_ payload: [String: [String: Int]]) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        sharedDefaults.set(data, forKey: key)
        UserDefaults.standard.set(data, forKey: key)
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
