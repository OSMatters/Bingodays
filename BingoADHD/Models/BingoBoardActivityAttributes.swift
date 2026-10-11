import ActivityKit
import Foundation

struct BingoBoardActivityAttributes: ActivityAttributes {
    let boardID: UUID

    struct ContentState: Codable, Hashable {
        // Compression keeps full task text within ActivityKit's 4 KB envelope.
        let payload: Data

        init(snapshot: BingoBoardActivitySnapshot) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(snapshot)
            payload = try (data as NSData).compressed(using: .zlib) as Data
        }

        var snapshot: BingoBoardActivitySnapshot? {
            guard let data = try? (payload as NSData).decompressed(using: .zlib) as Data else { return nil }
            return try? JSONDecoder().decode(BingoBoardActivitySnapshot.self, from: data)
        }
    }
}

struct BingoBoardActivitySnapshot: Codable, Hashable {
    struct Cell: Codable, Hashable, Identifiable {
        let id: UUID
        let text: String
        let version: String
        let completed: Bool
        let inBingo: Bool
        let enabled: Bool

        enum CodingKeys: String, CodingKey {
            case id = "i", text = "t", version = "v"
            case completed = "c", inBingo = "b", enabled = "e"
        }
    }

    let gridSize: Int
    let theme: String
    let cells: [Cell]
}

extension BingoBoardActivitySnapshot {
    var taskCount: Int {
        cells.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    var completedTaskCount: Int {
        cells.filter { $0.completed && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    var completionProgress: Double {
        taskCount == 0 ? 0 : Double(completedTaskCount) / Double(taskCount)
    }

    var completionPercentage: Int { Int((completionProgress * 100).rounded()) }
}
