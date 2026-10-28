import Foundation
import WidgetKit

struct MacDesktopBoardProvider: TimelineProvider {
    struct Entry: TimelineEntry {
        let date: Date
        let snapshot: MacDesktopBoardSnapshot
    }
    func placeholder(in context: Context) -> Entry { Entry(date: .now, snapshot: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(currentEntry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = currentEntry()
        let futureEntries = (entry.snapshot.futureStates ?? []).filter { $0.date > entry.date }.map {
            Entry(date: $0.date, snapshot: entry.snapshot)
        }
        completion(Timeline(entries: [entry] + futureEntries, policy: .after(entry.date.addingTimeInterval(60 * 60))))
    }
    private func currentEntry() -> Entry {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: MacDesktopBoardSnapshot.groupID)
        return Entry(date: .now, snapshot: MacDesktopBoardSnapshot.load(from: container) ?? .empty)
    }
}
