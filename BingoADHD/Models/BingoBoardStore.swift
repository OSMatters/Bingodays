import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum BingoBoardStore {
    static let appGroupID = "group.com.bingoday.app"
    private static let saveKey = "bingo_board_v1"
    private static let sharedFileName = "bingo_board_v1.json"
    private static let metricsFileName = "bingo_metrics_v1.json"

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

    static func saveBoard(_ board: SavedBoard) {
        guard let data = try? JSONEncoder().encode(board) else { return }

        persistSharedFile(data)
        sharedDefaults.set(data, forKey: saveKey)
        UserDefaults.standard.set(data, forKey: saveKey)

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
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

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    private static var sharedFileURL: URL {
        sharedURL(for: sharedFileName)
    }

    private static func persistSharedFile(_ data: Data) {
        try? data.write(to: sharedFileURL, options: .atomic)
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
