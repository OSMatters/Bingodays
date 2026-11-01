import SwiftUI
import WidgetKit

struct CompanionWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CompanionWidgetEntry {
        let today = Calendar.current.startOfDay(for: .now)
        return CompanionWidgetEntry(date: .now, snapshot: AppOpenWidgetSnapshot(
            trackedSince: today, openedDays: [today], lastOpenedDay: today, streak: 12))
    }

    func getSnapshot(in context: Context, completion: @escaping (CompanionWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : makeEntry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CompanionWidgetEntry>) -> Void) {
        let now = Date()
        // Prebuild midnight entries so missed days appear without opening the app.
        let calendar = Calendar.autoupdatingCurrent
        let dates = [now] + (1...7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: now))
        }
        completion(Timeline(entries: dates.map(makeEntry), policy: .after(dates.last ?? now)))
    }

    private func makeEntry(at date: Date) -> CompanionWidgetEntry {
        CompanionWidgetEntry(date: date, snapshot: AppOpenWidgetSnapshot.load(from: BingoBoardStore.sharedDefaults))
    }
}
