import Foundation

enum AppUpdatePromptStore {
    static var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    static var fallbackReleaseNotesItems: [String] {
        [
            L10n.updateItemQuickEditImproved,
            L10n.updateItemKnownIssuesFixed
        ]
    }

    static func releaseNotesItems(for info: AppUpdateInfo) -> [String] {
        guard let notes = info.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
              !notes.isEmpty else {
            return fallbackReleaseNotesItems
        }

        let items = notes
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return items.isEmpty ? fallbackReleaseNotesItems : items
    }
}
