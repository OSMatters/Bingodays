import Foundation

/// A read-only, platform-independent projection for the desktop extension.
struct MacDesktopBoardSnapshot: Codable, Equatable {
    struct Cell: Codable, Equatable {
        let text: String
        let completed: Bool
        let inBingo: Bool
    }
    struct FutureState: Codable, Equatable {
        let date: Date
        let cells: [Cell]
    }
    struct PaletteColor: Codable, Equatable {
        let red: Double
        let green: Double
        let blue: Double
    }
    static let widgetKind = "BingodaysMacDesktopBoard"
    static let groupID = "group.com.bingoday.app"
    static let fileName = "mac_desktop_board_v1.json"
    let boardID: UUID?
    let gridSize: Int
    let cells: [Cell]
    let accent: PaletteColor
    let surface: PaletteColor
    let outline: PaletteColor
    let backgroundImage: String?
    let updatedAt: Date
    var futureStates: [FutureState]? = nil

    func cells(at date: Date) -> [Cell] {
        futureStates?.filter { $0.date <= date }.max(by: { $0.date < $1.date })?.cells ?? cells
    }

    var destination: URL {
        var components = URLComponents()
        components.scheme = "bingodays-mac"
        components.host = "board"
        components.path = boardID.map { "/\($0.uuidString)" } ?? ""
        // Scheme and host are fixed valid literals.
        return components.url!
    }
    static func boardID(from url: URL) -> UUID? {
        guard url.scheme == "bingodays-mac", url.host == "board" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
    static func fileURL(in container: URL) -> URL {
        container.appendingPathComponent("Library/Application Support", isDirectory: true).appendingPathComponent(fileName)
    }
    static func load(from container: URL?) -> Self? {
        guard let container,
              let data = try? Data(contentsOf: fileURL(in: container)),
              let snapshot = try? JSONDecoder().decode(Self.self, from: data),
              (2...5).contains(snapshot.gridSize),
              snapshot.cells.count == snapshot.gridSize * snapshot.gridSize,
              snapshot.futureStates?.allSatisfy({ $0.cells.count == snapshot.cells.count }) ?? true else { return nil }
        return snapshot
    }
    static var empty: Self {
        Self(boardID: nil, gridSize: 3,
             cells: Array(repeating: Cell(text: "", completed: false, inBingo: false), count: 9),
             accent: PaletteColor(red: 0.87, green: 0.68, blue: 0.51),
             surface: PaletteColor(red: 0.94, green: 0.88, blue: 0.82),
             outline: PaletteColor(red: 0.94, green: 0.88, blue: 0.82),
             backgroundImage: nil, updatedAt: .now)
    }
}
