import SwiftUI
import CoreText
import CloudKit
import BackgroundTasks
import FirebaseCore
import UserNotifications
import os

@MainActor
enum AppFontRegistrar {
    private static var hasRegisteredFonts = false

    static func registerIfNeeded() {
        guard !hasRegisteredFonts else { return }

        let fontFileNames = [
            "ArchivoBlack-Regular.ttf",
            "Outfit-wght.ttf",
            "Schoolbell-Regular.ttf"
        ]

        for fileName in fontFileNames {
            guard let url = Bundle.main.url(forResource: fileName, withExtension: nil) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }

        hasRegisteredFonts = true
    }
}

enum TaskStartReminderService {
    private struct PendingReminder {
        let identifier: String
        let title: String
        let body: String
        let date: Date
        let boardID: UUID
        let cellID: UUID
    }

    private static let notificationIDPrefix = "task_start_reminder."

    static var allowedOffsetMinutes: [Int] {
        BingoCell.allowedStartReminderOffsetMinutes
    }

    static var defaultOffsetMinutes: Int {
        BingoCell.defaultStartReminderOffsetMinutes
    }

    static func normalizedOffsetMinutes(_ value: Int) -> Int {
        BingoCell.normalizedStartReminderOffsetMinutes(value)
    }

    static func nextReminderDate(
        for cell: BingoCell,
        now: Date,
        calendar _: Calendar = .current
    ) -> Date? {
        guard !cell.hasRepeatingSchedule,
              let startDate = cell.startVisibleAt,
              cell.endVisibleAt != nil else {
            return nil
        }

        let offset = TimeInterval(normalizedOffsetMinutes(cell.startReminderOffsetMinutes) * 60)
        let reminderDate = startDate.addingTimeInterval(-offset)
        return reminderDate > now ? reminderDate : nil
    }

    static func offsetTitle(minutes: Int) -> String {
        switch normalizedOffsetMinutes(minutes) {
        case 5:
            return L10n.tr("5 min before", zhHans: "5分钟前", zhHant: "5分鐘前", ja: "5分前")
        case 10:
            return L10n.tr("10 min before", zhHans: "10分钟前", zhHant: "10分鐘前", ja: "10分前")
        case 30:
            return L10n.tr("30 min before", zhHans: "30分钟前", zhHant: "30分鐘前", ja: "30分前")
        default:
            return L10n.tr("5 min before", zhHans: "5分钟前", zhHant: "5分鐘前", ja: "5分前")
        }
    }

    static func isManagedNotificationID(_ identifier: String) -> Bool {
        identifier.hasPrefix(notificationIDPrefix)
    }

    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await notificationSettings(center: center)
        switch settings {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    static func syncReminders(
        namedBoards: [BingoBoardStore.NamedBoard],
        selectedBoardID: UUID?,
        activeBoard: SavedBoard?,
        now: Date = .now
    ) async {
        let boards = resolvedBoards(
            namedBoards: namedBoards,
            selectedBoardID: selectedBoardID,
            activeBoard: activeBoard
        )
        let desiredReminders = ReminderPreferences.load().enabled
            ? desiredReminders(from: boards, now: now) : []
        let desiredIDs = Set(desiredReminders.map(\.identifier))
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await pendingNotificationRequests(center: center)
        let managedPendingRequests = pendingRequests.filter { isManagedNotificationID($0.identifier) }
        let managedPendingIDs = Set(managedPendingRequests.map(\.identifier))
        let pendingRequestsByID = Dictionary(
            managedPendingRequests.map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let stalePendingIDs = managedPendingIDs.subtracting(desiredIDs)
        let changedPendingIDs = Set(desiredReminders.compactMap { reminder -> String? in
            guard let request = pendingRequestsByID[reminder.identifier] else { return nil }
            return pendingRequest(request, matches: reminder) ? nil : reminder.identifier
        })
        let pendingIDsToRemove = Array(stalePendingIDs.union(changedPendingIDs))

        if !pendingIDsToRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: pendingIDsToRemove)
        }

        let deliveredIDs = await deliveredNotificationIDs(center: center)
        let staleDeliveredIDs = deliveredIDs
            .filter { isManagedNotificationID($0) && !desiredIDs.contains($0) }
        if !staleDeliveredIDs.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: staleDeliveredIDs)
        }

        guard await hasNotificationAuthorization(center: center) else { return }

        for reminder in desiredReminders {
            guard pendingRequestsByID[reminder.identifier] == nil || changedPendingIDs.contains(reminder.identifier) else {
                continue
            }
            schedule(reminder, center: center)
        }
    }

    static func syncSignature(
        namedBoards: [BingoBoardStore.NamedBoard],
        selectedBoardID: UUID?,
        activeBoard: SavedBoard?,
        now: Date
    ) -> String {
        let boards = resolvedBoards(
            namedBoards: namedBoards,
            selectedBoardID: selectedBoardID,
            activeBoard: activeBoard
        )
        let preferences = ReminderPreferences.load()
        return (preferences.enabled ? "on|" : "off|") + desiredReminders(from: boards, now: now)
            .map { reminder in
                [
                    reminder.identifier,
                    reminder.title,
                    reminder.body,
                    String(Int(reminder.date.timeIntervalSince1970))
                ].joined(separator: "|")
            }
            .sorted()
            .joined(separator: "\n")
    }

    private static func resolvedBoards(
        namedBoards: [BingoBoardStore.NamedBoard],
        selectedBoardID: UUID?,
        activeBoard: SavedBoard?
    ) -> [BingoBoardStore.NamedBoard] {
        var boards = namedBoards
        if let selectedBoardID,
           let activeBoard,
           let selectedIndex = boards.firstIndex(where: { $0.id == selectedBoardID }) {
            boards[selectedIndex].board = activeBoard
        }
        return boards
    }

    private static func desiredReminders(
        from boards: [BingoBoardStore.NamedBoard],
        now: Date
    ) -> [PendingReminder] {
        boards.flatMap { board in
            let sourceCells = board.board.fullBoardCells ?? board.board.cells
            return sourceCells.flatMap { row in
                row.compactMap { cell in
                    desiredReminder(for: cell, boardID: board.id, boardName: board.name, now: now)
                }
            }
        }
    }

    private static func desiredReminder(
        for cell: BingoCell,
        boardID: UUID,
        boardName: String,
        now: Date
    ) -> PendingReminder? {
        let taskText = cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cell.startReminderEnabled,
              !taskText.isEmpty,
              !cell.isCompleted,
              let reminderDate = nextReminderDate(for: cell, now: now) else {
            return nil
        }

        let offsetMinutes = normalizedOffsetMinutes(cell.startReminderOffsetMinutes)
        let message = ReminderCopyVariant.forDate(reminderDate)
            .taskStartMessage(taskText: taskText, offsetMinutes: offsetMinutes)

        return PendingReminder(
            identifier: notificationID(boardID: boardID, cellID: cell.id),
            title: message.title,
            body: "\(boardName): \(message.body)",
            date: reminderDate,
            boardID: boardID,
            cellID: cell.id
        )
    }

    private static func notificationID(boardID: UUID, cellID: UUID) -> String {
        "\(notificationIDPrefix)\(boardID.uuidString).\(cellID.uuidString)"
    }

    private static func schedule(_ reminder: PendingReminder, center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.userInfo = [
            "type": "task_start_reminder",
            "board_id": reminder.boardID.uuidString,
            "cell_id": reminder.cellID.uuidString
        ]

        let triggerDate = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: reminder.date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        let request = UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
        center.add(request)
    }

    // Copy only the fields used for reconciliation before leaving the SDK callback.
    private struct PendingRequestSnapshot: Sendable {
        let identifier: String
        let title: String
        let body: String
        let type: String?
        let boardID: String?
        let cellID: String?
        let dateComponents: DateComponents?

        init(_ request: UNNotificationRequest) {
            identifier = request.identifier
            title = request.content.title
            body = request.content.body
            type = request.content.userInfo["type"] as? String
            boardID = request.content.userInfo["board_id"] as? String
            cellID = request.content.userInfo["cell_id"] as? String
            dateComponents = (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents
        }
    }

    private static func pendingRequest(_ request: PendingRequestSnapshot, matches reminder: PendingReminder) -> Bool {
        guard request.title == reminder.title,
              request.body == reminder.body,
              request.type == "task_start_reminder",
              request.boardID == reminder.boardID.uuidString,
              request.cellID == reminder.cellID.uuidString,
              let dateComponents = request.dateComponents else {
            return false
        }

        let expectedDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: reminder.date
        )
        return dateComponents.year == expectedDateComponents.year &&
            dateComponents.month == expectedDateComponents.month &&
            dateComponents.day == expectedDateComponents.day &&
            dateComponents.hour == expectedDateComponents.hour &&
            dateComponents.minute == expectedDateComponents.minute &&
            dateComponents.second == expectedDateComponents.second
    }

    private static func hasNotificationAuthorization(center: UNUserNotificationCenter) async -> Bool {
        let settings = await notificationSettings(center: center)
        switch settings {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    private static func notificationSettings(center: UNUserNotificationCenter) async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private static func pendingNotificationRequests(
        center: UNUserNotificationCenter
    ) async -> [PendingRequestSnapshot] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(PendingRequestSnapshot.init))
            }
        }
    }

    private static func deliveredNotificationIDs(center: UNUserNotificationCenter) async -> [String] {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications.map { $0.request.identifier })
            }
        }
    }
}

struct ReminderCopyVariant: Equatable {
    private let value: UInt64

    // Keep the existing seed so a user's daily choice stays stable across app updates.
    private static let seedKey = "reminder_daily_tone_seed_v1"

    static func forDate(
        _ date: Date,
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> Self {
        let seed: UInt64
        if let stored = defaults.string(forKey: seedKey), let value = UInt64(stored) {
            seed = value
        } else {
            seed = UInt64.random(in: UInt64.min...UInt64.max)
            defaults.set(String(seed), forKey: seedKey)
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = UInt64((parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0))
        var value = (seed ^ day) &+ 0x9E3779B97F4A7C15
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Self(value: value)
    }

    enum Kind { case boardReset, ticket, streak }

    func message(for kind: Kind) -> (title: String, body: String) {
        let copies: [(title: String, body: String)]
        switch kind {
        case .boardReset:
            copies = [
                (L10n.tr("Wait, how is there only an hour left?", zhHans: "不是，怎么就剩一小时了", zhHant: "不是，怎麼就剩一小時了"),
                 L10n.tr("The board resets soon. I thought today was longer.", zhHans: "棋盘快重置了，我还以为今天很长呢。", zhHant: "棋盤快重置了，我還以為今天很長呢。")),
                (L10n.tr("The board refreshes already?", zhHans: "棋盘待会儿就刷新？", zhHant: "棋盤待會兒就刷新？"),
                 L10n.tr("One hour left. If there's anything you want to finish, there's still time.", zhHans: "还有 1 小时。想补点什么，现在还来得及。", zhHant: "還有 1 小時。想補點什麼，現在還來得及。")),
                (L10n.tr("How did reset time get here so fast?", zhHans: "救命，重置时间这么快到", zhHant: "救命，重置時間這麼快到"),
                 L10n.tr("The board refreshes in one hour. Don't say I didn't warn you.", zhHans: "再过 1 小时就刷新，别说我没提醒你。", zhHant: "再過 1 小時就刷新，別說我沒提醒你。")),
                (L10n.tr("The reset countdown is on", zhHans: "重置倒计时开始了喂", zhHant: "重置倒數計時開始了喂"),
                 L10n.tr("One hour left. If you want to wrap anything up, now's the time.", zhHans: "就剩 1 小时，要收尾的话趁现在。", zhHant: "就剩 1 小時，要收尾的話趁現在。"))
            ]
        case .ticket:
            copies = [
                (L10n.tr("Wait, more blind-box tickets?", zhHans: "不是，盲盒券又来了？", zhHant: "不是，盲盒券又來了？"),
                 L10n.tr("Today's tickets refreshed. Are you tempted?", zhHans: "今天的券更新了，手痒了没。", zhHant: "今天的券更新了，手癢了沒。")),
                (L10n.tr("Tickets updated. Just saying.", zhHans: "券更新啦，我先说", zhHant: "券更新啦，我先說"),
                 L10n.tr("Whether you open a box or not, today's tickets are ready.", zhHans: "开不开盒先不管，今天的券可以看了。", zhHant: "開不開盒先不管，今天的券可以看了。")),
                (L10n.tr("New tickets. Who could resist?", zhHans: "新券来了，这谁忍得住", zhHant: "新券來了，這誰忍得住"),
                 L10n.tr("The blind boxes are back for today.", zhHans: "盲盒今天又开张了。", zhHant: "盲盒今天又開張了。")),
                (L10n.tr("Tickets refreshed. For real.", zhHans: "盲盒券已刷新，真的", zhHant: "盲盒券已刷新，真的"),
                 L10n.tr("See which box you can open today.", zhHans: "看看今天能开哪盒。", zhHant: "看看今天能開哪盒。")),
                (L10n.tr("The tickets just showed up like that", zhHans: "这券怎么说来就来", zhHant: "這券怎麼說來就來"),
                 L10n.tr("The new round is here. Go see.", zhHans: "新一期已经更新了，去看看。", zhHant: "新一期已經更新了，去看看。"))
            ]
        case .streak:
            copies = [
                (L10n.tr("Wait, you haven't opened today?", zhHans: "不是，今天还没打开？", zhHant: "不是，今天還沒打開？"),
                 L10n.tr("Your streak hasn't been renewed yet. There's still time.", zhHans: "连续记录还没续上，今天还来得及。", zhHant: "連續紀錄還沒續上，今天還來得及。")),
                (L10n.tr("I almost forgot to remind you", zhHans: "我差点忘了提醒你", zhHant: "我差點忘了提醒你"),
                 L10n.tr("You haven't opened Bingodays today. Don't miss it tonight.", zhHans: "今天还没打开 Bingodays，晚上别错过。", zhHant: "今天還沒打開 Bingodays，晚上別錯過。")),
                (L10n.tr("Your streak is waiting around", zhHans: "连续记录等你等到发呆", zhHant: "連續紀錄等你等到發呆"),
                 L10n.tr("Open the app now and you're still in time.", zhHans: "现在打开还来得及。", zhHant: "現在打開還來得及。")),
                (L10n.tr("Does today feel like it's missing something?", zhHans: "今天是不是少了点什么", zhHant: "今天是不是少了點什麼"),
                 L10n.tr("Yep, you haven't opened Bingodays yet.", zhHans: "对，Bingodays 还没打开。", zhHant: "對，Bingodays 還沒打開。")),
                (L10n.tr("Wait, your streak is slipping away", zhHans: "等等，连续记录要溜了", zhHant: "等等，連續紀錄要溜了"),
                 L10n.tr("You haven't dropped by today. Come check in.", zhHans: "今天还没来，过来报个到。", zhHant: "今天還沒來，過來報個到。"))
            ]
        }
        return copies[Int(value % UInt64(copies.count))]
    }

    func taskStartMessage(taskText: String, offsetMinutes: Int) -> (title: String, body: String) {
        let copies: [(title: String, body: String)] = [
            (L10n.tr("Wait, it's almost starting?", zhHans: "不是，这就快开始了？", zhHant: "不是，這就快開始了？"),
             L10n.tr("\(taskText) is in \(offsetMinutes) minutes. I just realized too.", zhHans: "\(taskText) 还有 \(offsetMinutes) 分钟，我也刚反应过来。", zhHant: "\(taskText) 還有 \(offsetMinutes) 分鐘，我也剛反應過來。")),
            (L10n.tr("Time runs faster than I do", zhHans: "时间跑得比我还快", zhHant: "時間跑得比我還快"),
             L10n.tr("\(taskText) starts in \(offsetMinutes) minutes.", zhHans: "\(taskText) 还有 \(offsetMinutes) 分钟开始。", zhHant: "\(taskText) 還有 \(offsetMinutes) 分鐘開始。")),
            (L10n.tr("How is it almost time already?", zhHans: "等下，怎么快到点了", zhHant: "等下，怎麼快到點了"),
             L10n.tr("\(taskText) starts in \(offsetMinutes) minutes. Don't let time sneak up on you.", zhHans: "\(taskText) 再过 \(offsetMinutes) 分钟开始，别被时间偷袭。", zhHant: "\(taskText) 再過 \(offsetMinutes) 分鐘開始，別被時間偷襲。")),
            (L10n.tr("Easy, it hasn't started yet", zhHans: "别慌，还没到点", zhHant: "別慌，還沒到點"),
             L10n.tr("\(taskText) is in \(offsetMinutes) minutes. Want to get ready?", zhHans: "\(taskText) 还有 \(offsetMinutes) 分钟，准备一下？", zhHant: "\(taskText) 還有 \(offsetMinutes) 分鐘，準備一下？")),
            (L10n.tr("It's time... wait, not yet", zhHans: "时间到了……啊还没", zhHant: "時間到了……啊還沒"),
             L10n.tr("\(taskText) starts in \(offsetMinutes) minutes. That gave me a scare.", zhHans: "\(taskText) 还有 \(offsetMinutes) 分钟开始，吓我一跳。", zhHant: "\(taskText) 還有 \(offsetMinutes) 分鐘開始，嚇我一跳。"))
        ]
        return copies[Int(value % UInt64(copies.count))]
    }

}

struct ReminderPreferences {
    static let enabledKey = "reminder_master_enabled_v1"
    static let resetKey = "reminder_board_reset_enabled_v1"
    static let ticketKey = "reminder_ticket_enabled_v1"
    static let streakKey = "reminder_streak_enabled_v1"
    static let ticketTimeMinutes = 600
    static let streakTimeMinutes = 1200

    let enabled: Bool
    let resetEnabled: Bool
    let ticketEnabled: Bool
    let streakEnabled: Bool

    static func selectAllChoices(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: resetKey)
        defaults.set(true, forKey: ticketKey)
        defaults.set(true, forKey: streakKey)
    }

    static func load(_ defaults: UserDefaults = .standard) -> Self {
        return Self(
            enabled: defaults.bool(forKey: enabledKey),
            resetEnabled: defaults.bool(forKey: resetKey),
            ticketEnabled: defaults.bool(forKey: ticketKey),
            streakEnabled: defaults.bool(forKey: streakKey)
        )
    }
}

@MainActor
enum DailyReminderService {
    private static let prefix = "bingoday.reminder."
    private static var syncGeneration = 0

    struct PlannedReminder {
        let id: String
        let date: Date
        let kind: ReminderCopyVariant.Kind
    }

    nonisolated static func isManagedNotificationID(_ id: String) -> Bool { id.hasPrefix("bingoday.reminder.") }

    static func plan(
        boards: [BingoBoardStore.NamedBoard],
        preferences: ReminderPreferences,
        lastOpenedDay: Date?,
        ticketBalance: Int,
        lastTicketGrantDayIdentifier: String? = nil,
        now: Date,
        calendar: Calendar = .current,
        ticketGrantCalendar: Calendar? = nil
    ) -> [PlannedReminder] {
        guard preferences.enabled else { return [] }
        var result: [PlannedReminder] = []

        if preferences.resetEnabled {
            // One generic reminder per calendar day, even if several boards reset.
            var earliestByDay: [Date: Date] = [:]
            for board in boards where board.taskResetMode != .keepTaskStatus {
                let cells = (board.board.fullBoardCells ?? board.board.cells).flatMap { $0 }
                guard cells.contains(where: { $0.hasStoredTask && !$0.isCompleted }) else { continue }
                let horizon = board.taskResetMode == .clearTasksNextDay ? 1 : 7
                for day in 0..<horizon {
                    guard let anchor = calendar.date(byAdding: .day, value: day, to: now),
                          let reset = BoardResetRuleEngine.nextScheduledResetTime(for: board, after: anchor, calendar: calendar) else { continue }
                    let alert = reset.addingTimeInterval(-3_600)
                    guard alert > now else { continue }
                    let key = calendar.startOfDay(for: alert)
                    earliestByDay[key] = min(earliestByDay[key] ?? alert, alert)
                }
            }
            result += earliestByDay.map { day, date in
                PlannedReminder(id: "\(prefix)reset.\(dayID(day, calendar: calendar))", date: date, kind: .boardReset)
            }
        }

        if preferences.ticketEnabled && ticketBalance < BlindBoxRuleConfiguration.maximumTicketBalance {
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                      let date = calendar.date(byAdding: .minute, value: ReminderPreferences.ticketTimeMinutes, to: day),
                      date > now,
                      BlindBoxGrantDay.identifier(for: date, calendar: ticketGrantCalendar ?? calendar) != lastTicketGrantDayIdentifier else { continue }
                result.append(PlannedReminder(id: "\(prefix)ticket.\(dayID(day, calendar: calendar))", date: date, kind: .ticket))
            }
        }

        if preferences.streakEnabled, let lastOpenedDay {
            let openedDay = calendar.startOfDay(for: lastOpenedDay)
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: openedDay),
               let date = calendar.date(byAdding: .minute, value: ReminderPreferences.streakTimeMinutes, to: nextDay),
               date > now {
                result.append(PlannedReminder(id: "\(prefix)streak.\(dayID(nextDay, calendar: calendar))", date: date, kind: .streak))
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    static func sync(
        namedBoards: [BingoBoardStore.NamedBoard],
        selectedBoardID: UUID?,
        activeBoard: SavedBoard?,
        now: Date = .now
    ) async {
        var boards = namedBoards
        if let selectedBoardID, let activeBoard,
           let index = boards.firstIndex(where: { $0.id == selectedBoardID }) {
            boards[index].board = activeBoard
        }
        let preferences = ReminderPreferences.load()
        let ticketState = BlindBoxLocalStateStore.load()
        let reminders = plan(
            boards: boards,
            preferences: preferences,
            lastOpenedDay: AppOpenStreakStore.shared.lastOpenedDay,
            ticketBalance: ticketState.ticketBalance,
            lastTicketGrantDayIdentifier: ticketState.lastTicketGrantDayIdentifier,
            now: now,
            ticketGrantCalendar: BlindBoxGrantDay.calendar(for: ticketState, fallback: .current)
        )
        syncGeneration += 1
        let generation = syncGeneration
        let center = UNUserNotificationCenter.current()
        let pending: [UNNotificationRequest] = await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { continuation.resume(returning: $0) }
        }
        guard generation == syncGeneration else { return }
        let desiredIDs = Set(reminders.map(\.id))
        let managed = pending.filter { isManagedNotificationID($0.identifier) }
        let existing = Dictionary(managed.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        let obsolete = managed.map(\.identifier).filter { !desiredIDs.contains($0) }
        if !obsolete.isEmpty { center.removePendingNotificationRequests(withIdentifiers: obsolete) }
        if !preferences.enabled {
            let delivered: [UNNotification] = await withCheckedContinuation { continuation in
                center.getDeliveredNotifications { continuation.resume(returning: $0) }
            }
            guard generation == syncGeneration else { return }
            let deliveredIDs = delivered.map { $0.request.identifier }.filter(isManagedNotificationID)
            if !deliveredIDs.isEmpty { center.removeDeliveredNotifications(withIdentifiers: deliveredIDs) }
        }
        guard preferences.enabled else { return }
        let authorized: Bool = await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus))
            }
        }
        guard authorized, generation == syncGeneration else { return }
        for reminder in reminders {
            guard generation == syncGeneration else { return }
            let message = ReminderCopyVariant.forDate(reminder.date).message(for: reminder.kind)
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            if let request = existing[reminder.id],
               request.content.title == message.title,
               request.content.body == message.body,
               (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents == components { continue }
            if existing[reminder.id] != nil { center.removePendingNotificationRequests(withIdentifiers: [reminder.id]) }
            let content = UNMutableNotificationContent()
            content.title = message.title
            content.body = message.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }

    private static func dayID(_ day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}

protocol TaskStartReminderScheduling: Sendable {
    func syncReminders(
        namedBoards: [BingoBoardStore.NamedBoard],
        selectedBoardID: UUID?,
        activeBoard: SavedBoard?,
        now: Date
    ) async

    func syncSignature(
        namedBoards: [BingoBoardStore.NamedBoard],
        selectedBoardID: UUID?,
        activeBoard: SavedBoard?,
        now: Date
    ) -> String
}

struct LiveTaskStartReminderScheduler: TaskStartReminderScheduling {
    func syncReminders(
        namedBoards: [BingoBoardStore.NamedBoard],
        selectedBoardID: UUID?,
        activeBoard: SavedBoard?,
        now: Date
    ) async {
        await TaskStartReminderService.syncReminders(
            namedBoards: namedBoards,
            selectedBoardID: selectedBoardID,
            activeBoard: activeBoard,
            now: now
        )
    }

    func syncSignature(
        namedBoards: [BingoBoardStore.NamedBoard],
        selectedBoardID: UUID?,
        activeBoard: SavedBoard?,
        now: Date
    ) -> String {
        TaskStartReminderService.syncSignature(
            namedBoards: namedBoards,
            selectedBoardID: selectedBoardID,
            activeBoard: activeBoard,
            now: now
        )
    }
}

enum NativeICloudWidgetRefreshScheduler {
    static let taskIdentifier = "com.bingoday.app.icloud-widget-refresh"

    /// A background refresh is deliberately only a fallback. CloudKit silent
    /// pushes are still the fast path; iOS decides when this task can run.
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    static func scheduleFallback(after delay: TimeInterval = 15 * 60) {
        guard NativeICloudPreferences.isEnabled else { return }

        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(max(delay, 0))
        do {
            try BGTaskScheduler.shared.submit(request)
            DiagnosticLogStore.recordStateChange(
                "icloud.widget_refresh_fallback_scheduled",
                details: ["delay_seconds": String(Int(max(delay, 0)))]
            )
        } catch {
            // A pending request with the same identifier is normal. It already
            // provides the intended fallback, so avoid treating it as a sync failure.
            DiagnosticLogStore.recordStateChange(
                "icloud.widget_refresh_fallback_not_scheduled",
                details: ["error": NativeICloudErrorFormatter.describe(error)]
            )
        }
    }

    /// BGTask has no Sendable conformance. Keep the SDK object inside the lock;
    /// only this value crosses into the async refresh, and no method returns the object.
    private struct RefreshCompletion: Sendable {
        private struct State {
            let task: BGAppRefreshTask
            var didComplete = false
        }
        private let state: OSAllocatedUnfairLock<State>

        init(task: BGAppRefreshTask) {
            state = OSAllocatedUnfairLock(uncheckedState: State(task: task))
        }

        func installExpirationHandler(_ handler: @escaping @Sendable () -> Void) {
            state.withLock { state in
                guard !state.didComplete else { return }
                state.task.expirationHandler = handler
            }
        }

        func finish(success: Bool) {
            state.withLock { state in
                guard !state.didComplete else { return }
                state.didComplete = true
                state.task.setTaskCompleted(success: success)
            }
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        scheduleFallback(after: 30 * 60)
        DiagnosticLogStore.recordStateChange("icloud.widget_refresh_fallback_started")

        let completion = RefreshCompletion(task: task)
        let refresh = Task {
            do {
                let imported = try await NativeICloudRuntime.shared
                    .importPrimaryForBackgroundCloudNotification(timeout: 20)
                DiagnosticLogStore.recordStateChange(
                    imported
                        ? "icloud.widget_refresh_fallback_imported"
                        : "icloud.widget_refresh_fallback_no_data"
                )
                completion.finish(success: true)
            } catch is CancellationError {
                completion.finish(success: false)
            } catch {
                DiagnosticLogStore.recordWarning(
                    "icloud.widget_refresh_fallback_failed",
                    details: ["error": NativeICloudErrorFormatter.describe(error)]
                )
                completion.finish(success: false)
            }
        }
        completion.installExpirationHandler {
            refresh.cancel()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private func clearLegacyNotifications() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let legacyIDs = requests
                .map(\.identifier)
                .filter { !TaskStartReminderService.isManagedNotificationID($0) && !DailyReminderService.isManagedNotificationID($0) }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: legacyIDs)
        }
        center.getDeliveredNotifications { notifications in
            let legacyIDs = notifications
                .map { $0.request.identifier }
                .filter { !TaskStartReminderService.isManagedNotificationID($0) && !DailyReminderService.isManagedNotificationID($0) }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: legacyIDs)
        }
        if #available(iOS 17.0, *) {
            center.setBadgeCount(0)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }

    private func scheduleLegacyNotificationCleanup() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.clearLegacyNotifications()
        }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if AppDebugFlags.appIconProbeEnabled { return true }
#if DEBUG
        FirebaseConfiguration.shared.setLoggerLevel(.debug)
#endif
        FirebaseApp.configure()
        AnalyticsService.setCollectionEnabled(true)
        UNUserNotificationCenter.current().delegate = self
        AppFontRegistrar.registerIfNeeded()
        AppAudioSessionConfigurator.configureForSoundEffects()
        AnalyticsService.bootstrap()
        DiagnosticLogStore.recordStateChange("app.launch")
        NativeICloudWidgetRefreshScheduler.register()
        NativeICloudWidgetRefreshScheduler.scheduleFallback()
        application.registerForRemoteNotifications()
        Task { @MainActor in
            NativeICloudSyncCoordinator.shared.startIfEnabled()
        }
        scheduleLegacyNotificationCleanup()
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if TaskStartReminderService.isManagedNotificationID(notification.request.identifier)
            || DailyReminderService.isManagedNotificationID(notification.request.identifier) {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([])
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        guard !AppDebugFlags.appIconProbeEnabled else { return }
        // Restore the non-intrusive UI-sound policy after returning from another app or
        // after a recording session, before any Bingo sound effect can be played.
        AppAudioSessionConfigurator.configureForSoundEffects()
        DiagnosticLogStore.recordStateChange("app.did_become_active")
        BingoBoardLiveActivityController.scheduleRefresh()
        scheduleLegacyNotificationCleanup()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        guard !AppDebugFlags.appIconProbeEnabled else { return }
        NativeICloudWidgetRefreshScheduler.scheduleFallback()
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard !AppDebugFlags.appIconProbeEnabled else {
            completionHandler(.noData)
            return
        }
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }
        guard NativeICloudPreferences.isEnabled else {
            completionHandler(.noData)
            return
        }

        DiagnosticLogStore.recordStateChange("icloud.background_push_received")
        Task {
            do {
                let imported = try await NativeICloudRuntime.shared
                    .importPrimaryForBackgroundCloudNotification()
                DiagnosticLogStore.recordStateChange(
                    imported
                        ? "icloud.background_push_imported"
                        : "icloud.background_push_no_data"
                )
                AnalyticsService.logICloudSyncResult(
                    operation: .backgroundPush,
                    result: imported ? .success : .noData
                )
                NativeICloudWidgetRefreshScheduler.scheduleFallback(after: 30 * 60)
                completionHandler(imported ? .newData : .noData)
            } catch {
                DiagnosticLogStore.recordWarning(
                    "icloud.background_push_failed",
                    details: ["error": NativeICloudErrorFormatter.describe(error)]
                )
                AnalyticsService.logICloudSyncResult(
                    operation: .backgroundPush,
                    result: .failed,
                    failureStage: "import"
                )
                completionHandler(.failed)
            }
        }
    }

}

@main
struct BingoADHDApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var services = AppServices()
    @State private var hasStartedDeferredBootstrap = false

    var body: some Scene {
        WindowGroup {
#if DEBUG
            if AppDebugFlags.appIconProbeEnabled {
                IconProbeView()
            } else {
                bingodaysRoot
            }
#else
            bingodaysRoot
#endif
        }
    }

    // The probe does not construct the production service graph or root view.
    @ViewBuilder
    private var bingodaysRoot: some View {
        if let production = services.production {
            BingodaysProductionRoot(
                subscriptionManager: production.subscriptionManager,
                appIconManager: production.appIconManager,
                iCloudSyncCoordinator: production.iCloudSyncCoordinator,
                scenePhase: scenePhase,
                hasStartedDeferredBootstrap: $hasStartedDeferredBootstrap
            )
        }
    }
}
