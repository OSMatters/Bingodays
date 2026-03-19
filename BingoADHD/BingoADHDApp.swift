import SwiftUI
import FirebaseCore
import FirebaseAnalytics

enum AnalyticsService {
    static func bootstrap() {
        syncThemeUserProperty(AppTheme(rawValue: UserDefaults.standard.string(forKey: AppSettings.themeKey) ?? AppTheme.sky.rawValue) ?? .sky)
        syncMyTasksLibrary(CommonTasksStore.loadLibrary(), shouldLogEvent: false)
    }

    static func logStickerRedeemed(_ kind: StickerKind) {
        Analytics.logEvent("sticker_redeemed", parameters: [
            "sticker_id": kind.rawValue,
            "required_points": kind.requiredPoints
        ])
    }

    static func logBingoCompleted(boardSize: Int, completedLineCount: Int, filledTaskCount: Int) {
        Analytics.logEvent("bingo_completed", parameters: [
            "board_size": boardSize,
            "completed_line_count": completedLineCount,
            "filled_task_count": filledTaskCount
        ])
    }

    static func logThemeColorSelected(_ theme: AppTheme) {
        Analytics.logEvent("theme_color_selected", parameters: [
            "theme_color_id": theme.rawValue
        ])
        syncThemeUserProperty(theme)
    }

    static func syncMyTasksLibrary(_ library: MyTasksLibrary, shouldLogEvent: Bool = true) {
        let taskCount = library.tasks.count
        let groupCount = library.groups.count
        let groupTaskCount = library.groups.reduce(0) { $0 + $1.tasks.count }

        if shouldLogEvent {
            Analytics.logEvent("my_tasks_library_updated", parameters: [
                "task_count": taskCount,
                "group_count": groupCount,
                "group_task_count": groupTaskCount
            ])
        }

        Analytics.setUserProperty(String(taskCount), forName: "my_tasks_count")
        Analytics.setUserProperty(String(groupCount), forName: "my_group_count")
        Analytics.setUserProperty(String(groupTaskCount), forName: "my_group_task_count")
    }

    private static func syncThemeUserProperty(_ theme: AppTheme) {
        Analytics.setUserProperty(theme.rawValue, forName: "selected_theme_color")
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
#if DEBUG
        FirebaseConfiguration.shared.setLoggerLevel(.debug)
#endif
        FirebaseApp.configure()
        Analytics.setAnalyticsCollectionEnabled(true)
        AnalyticsService.bootstrap()
        return true
    }
}

@main
struct BingoADHDApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
