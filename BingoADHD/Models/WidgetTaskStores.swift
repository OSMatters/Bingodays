import Foundation

enum WidgetPanelSelectionStore {
    static let selectedPanelKey = "widget_selected_panel_id_v1"

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: BingoBoardStore.appGroupID) ?? .standard
    }

    static func loadSelectedPanelID() -> UUID? {
        guard let raw = sharedDefaults.string(forKey: selectedPanelKey) else {
            return nil
        }
        return UUID(uuidString: raw)
    }

    static func saveSelectedPanelID(_ id: UUID?) {
        guard let id else {
            sharedDefaults.removeObject(forKey: selectedPanelKey)
            sharedDefaults.synchronize()
            return
        }
        sharedDefaults.set(id.uuidString, forKey: selectedPanelKey)
        sharedDefaults.synchronize()
    }
}

enum WidgetTaskSyncStore {
    private static let eventKey = "widget_task_sync_event_v1"
    private static let eventFileName = "widget_task_sync_event_v1.json"

    struct Event: Codable {
        let boardID: UUID
        let board: BingoBoardStore.NamedBoard
        let savedAt: Date
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: BingoBoardStore.appGroupID) ?? .standard
    }

    private static var eventFileURL: URL {
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BingoBoardStore.appGroupID) {
            let directory = containerURL.appendingPathComponent("Library/Application Support", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.appendingPathComponent(eventFileName)
        }

        #if targetEnvironment(simulator)
        let simulatorDirectory = URL(fileURLWithPath: "/tmp/\(BingoBoardStore.appGroupID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: simulatorDirectory, withIntermediateDirectories: true)
        return simulatorDirectory.appendingPathComponent(eventFileName)
        #else
        let fallbackDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: fallbackDirectory, withIntermediateDirectories: true)
        return fallbackDirectory.appendingPathComponent(eventFileName)
        #endif
    }

    static func save(board: BingoBoardStore.NamedBoard) {
        let event = Event(boardID: board.id, board: board, savedAt: board.updatedAt)
        guard let data = try? JSONEncoder().encode(event) else { return }

        try? data.write(to: eventFileURL, options: .atomic)
        sharedDefaults.set(data, forKey: eventKey)
        sharedDefaults.synchronize()
    }

    static func load() -> Event? {
        if let data = try? Data(contentsOf: eventFileURL),
           let event = try? JSONDecoder().decode(Event.self, from: data) {
            return event
        }

        guard let data = sharedDefaults.data(forKey: eventKey),
              let event = try? JSONDecoder().decode(Event.self, from: data) else {
            return nil
        }
        return event
    }

    static func loadBoard() -> SavedBoard? {
        load()?.board.board
    }

    static func loadCountdownEndsAt() -> Date? {
        load()?.board.countdownEndsAt
    }

    static func loadSavedAt() -> Date? {
        load()?.savedAt
    }

    static func clear() {
        try? FileManager.default.removeItem(at: eventFileURL)
        sharedDefaults.removeObject(forKey: eventKey)
        sharedDefaults.synchronize()
    }
}
