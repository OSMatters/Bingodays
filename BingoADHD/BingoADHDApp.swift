import SwiftUI
import CoreText
import FirebaseCore
import GoogleSignIn
import UserNotifications

enum AppFeatureFlags {
    // Soft-off account capabilities for review builds.
    // Set to true to restore account features later.
    static let isAccountEnabled = false

    // Soft-off template sharing capabilities.
    // Set to true to restore share/import template flows later.
    static let isTemplateSharingEnabled = true
}

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
        switch settings.authorizationStatus {
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
        var boards = namedBoards
        if let selectedBoardID,
           let activeBoard,
           let selectedIndex = boards.firstIndex(where: { $0.id == selectedBoardID }) {
            boards[selectedIndex].board = activeBoard
        }

        let desiredReminders = desiredReminders(from: boards, now: now)
        let desiredIDs = Set(desiredReminders.map(\.identifier))
        let center = UNUserNotificationCenter.current()
        let pendingRequests = await pendingNotificationRequests(center: center)
        let managedPendingIDs = pendingRequests
            .map(\.identifier)
            .filter(isManagedNotificationID)

        center.removePendingNotificationRequests(withIdentifiers: managedPendingIDs)

        let deliveredIDs = await deliveredNotificationIDs(center: center)
        let staleDeliveredIDs = deliveredIDs
            .filter { isManagedNotificationID($0) && !desiredIDs.contains($0) }
        if !staleDeliveredIDs.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: staleDeliveredIDs)
        }

        guard await hasNotificationAuthorization(center: center) else { return }

        for reminder in desiredReminders {
            schedule(reminder, center: center)
        }
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
              let startDate = cell.startVisibleAt,
              cell.endVisibleAt != nil else {
            return nil
        }

        let offsetMinutes = normalizedOffsetMinutes(cell.startReminderOffsetMinutes)
        let reminderDate = startDate.addingTimeInterval(Double(-offsetMinutes * 60))
        guard reminderDate > now else { return nil }

        let title = offsetMinutes == 0
            ? L10n.tr("Task started", zhHans: "任务开始了", zhHant: "任務開始了", ja: "タスクが始まりました")
            : L10n.tr("Task starts soon", zhHans: "任务即将开始", zhHant: "任務即將開始", ja: "タスクがまもなく始まります")
        let body = offsetMinutes == 0
            ? L10n.tr(
                "\(taskText) is ready now.",
                zhHans: "\(taskText) 现在可以开始了。",
                zhHant: "\(taskText) 現在可以開始了。",
                ja: "\(taskText) を始められます。"
            )
            : L10n.tr(
                "\(taskText) starts in \(offsetMinutes) minutes.",
                zhHans: "\(taskText) 将在 \(offsetMinutes) 分钟后开始。",
                zhHant: "\(taskText) 將在 \(offsetMinutes) 分鐘後開始。",
                ja: "\(taskText) は\(offsetMinutes)分後に始まります。"
            )

        return PendingReminder(
            identifier: notificationID(boardID: boardID, cellID: cell.id),
            title: title,
            body: "\(boardName): \(body)",
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

    private static func hasNotificationAuthorization(center: UNUserNotificationCenter) async -> Bool {
        let settings = await notificationSettings(center: center)
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    private static func notificationSettings(center: UNUserNotificationCenter) async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private static func pendingNotificationRequests(
        center: UNUserNotificationCenter
    ) async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
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

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private func clearLegacyNotifications() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let legacyIDs = requests
                .map(\.identifier)
                .filter { !TaskStartReminderService.isManagedNotificationID($0) }
            center.removePendingNotificationRequests(withIdentifiers: legacyIDs)
        }
        center.getDeliveredNotifications { notifications in
            let legacyIDs = notifications
                .map { $0.request.identifier }
                .filter { !TaskStartReminderService.isManagedNotificationID($0) }
            center.removeDeliveredNotifications(withIdentifiers: legacyIDs)
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
#if DEBUG
        FirebaseConfiguration.shared.setLoggerLevel(.debug)
#endif
        FirebaseApp.configure()
        AnalyticsService.setCollectionEnabled(true)
        UNUserNotificationCenter.current().delegate = self
        AppFontRegistrar.registerIfNeeded()
        AnalyticsService.bootstrap()
        scheduleLegacyNotificationCleanup()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if TaskStartReminderService.isManagedNotificationID(notification.request.identifier) {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([])
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        scheduleLegacyNotificationCleanup()
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if GIDSignIn.sharedInstance.handle(url) {
            return true
        }
        guard AppFeatureFlags.isTemplateSharingEnabled else {
            return false
        }
        return BoardTemplateImportCoordinator.shared.handleIncomingURL(url)
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        guard AppFeatureFlags.isTemplateSharingEnabled else {
            return false
        }
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return false
        }
        return BoardTemplateImportCoordinator.shared.handleIncomingURL(url)
    }
}

@main
struct BingoADHDApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var subscriptionManager = SubscriptionManager()
    @State private var hasStartedDeferredBootstrap = false

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(subscriptionManager)
                .task {
                    guard !hasStartedDeferredBootstrap else { return }
                    hasStartedDeferredBootstrap = true
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    await subscriptionManager.refreshEntitlements()
                }
        }
    }
}
