import SwiftUI
import AVFoundation
import AudioToolbox
import StoreKit
import UIKit
import CoreImage.CIFilterBuiltins
import CoreMotion
import Photos
import UniformTypeIdentifiers
import UserNotifications
#if canImport(FirebaseRemoteConfig)
import FirebaseRemoteConfig
#endif
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

extension Font {
    static func appSystem(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        switch AppLanguage.current {
        case .english:
            return .custom("Outfit", size: size).weight(weight)
        case .simplifiedChinese, .traditionalChinese, .japanese:
            return .system(size: size, weight: weight, design: design)
        }
    }
}

struct AppUpdateInfo: Equatable {
    let latestVersion: String
    let trackViewURL: URL
    let releaseNotes: String?
}

enum AppUpdateService {
    private static let remoteConfigKey = "ios_update_config"
    private static let fallbackTrackViewURL = URL(string: "https://apps.apple.com/us/search?term=Bingodays")!

    static func cachedUpdateInfo(currentVersion: String) -> AppUpdateInfo? {
        let defaults = UserDefaults.standard
        guard let cachedData = defaults.data(forKey: AppSettings.cachedUpdateInfoKey),
              let cached = try? JSONDecoder().decode(CachedUpdateRecord.self, from: cachedData),
              isVersion(cached.latestVersion, greaterThan: currentVersion),
              let trackViewURL = URL(string: cached.trackViewURL) else {
            return nil
        }
        return AppUpdateInfo(
            latestVersion: cached.latestVersion,
            trackViewURL: trackViewURL,
            releaseNotes: cached.releaseNotes
        )
    }

    static func fetchUpdateInfo(
        currentVersion: String
    ) async -> AppUpdateInfo? {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.bingoday.app"
        let countryCode = Locale.current.region?.identifier

#if canImport(FirebaseRemoteConfig)
        if let remoteInfo = await fetchFromRemoteConfig(currentVersion: currentVersion) {
            saveCachedUpdateInfo(remoteInfo)
            return remoteInfo
        }
#endif

        if let fallbackInfo = await fetchFromAppStoreLookup(
            currentVersion: currentVersion,
            bundleIdentifier: bundleIdentifier,
            countryCode: countryCode
        ) {
            saveCachedUpdateInfo(fallbackInfo)
            return fallbackInfo
        }

        return nil
    }

#if canImport(FirebaseRemoteConfig)
    private static func fetchFromRemoteConfig(
        currentVersion: String
    ) async -> AppUpdateInfo? {
        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
#if DEBUG
        settings.minimumFetchInterval = 0
#else
        settings.minimumFetchInterval = 60 * 60
#endif
        settings.fetchTimeout = 10
        remoteConfig.configSettings = settings

        let defaultPayload = defaultUpdateConfigJSON
        remoteConfig.setDefaults([
            remoteConfigKey: defaultPayload as NSObject
        ])

        do {
            _ = try await remoteConfig.fetchAndActivate()
        } catch {
            // Continue with cached/default payload when fetch fails.
        }

        let payload = remoteConfig.configValue(forKey: remoteConfigKey).stringValue
#if DEBUG
        print("[AppUpdate] RemoteConfig payload:", payload)
#endif
        guard let config = decodeUpdateConfig(from: payload) else {
#if DEBUG
            print("[AppUpdate] Failed to decode ios_update_config")
#endif
            return nil
        }

        guard isVersion(config.latestVersion, greaterThan: currentVersion) else {
#if DEBUG
            print("[AppUpdate] No update needed. current:", currentVersion, "latest:", config.latestVersion)
#endif
            return nil
        }

        let trackViewURL = URL(string: config.trackViewURL ?? "") ?? fallbackTrackViewURL
#if DEBUG
        print("[AppUpdate] current:", currentVersion, "latest:", config.latestVersion, "trackURL:", trackViewURL.absoluteString)
#endif
        return AppUpdateInfo(
            latestVersion: config.latestVersion,
            trackViewURL: trackViewURL,
            releaseNotes: config.localizedReleaseNotes(for: AppLanguage.current)
        )
    }
#endif

    private static func fetchFromAppStoreLookup(
        currentVersion: String,
        bundleIdentifier: String,
        countryCode: String?
    ) async -> AppUpdateInfo? {
        let candidateCountries = lookupCountryCandidates(preferredCountryCode: countryCode)

        for candidateCountry in candidateCountries {
            guard let lookupURL = buildLookupURL(bundleIdentifier: bundleIdentifier, countryCode: candidateCountry) else {
                continue
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: lookupURL)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    continue
                }

                let payload = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
                guard let app = payload.results.first,
                      let latestVersion = app.version?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let trackViewURLString = app.trackViewUrl,
                      let trackViewURL = URL(string: trackViewURLString) else {
                    continue
                }

                guard isVersion(latestVersion, greaterThan: currentVersion) else {
                    return nil
                }

                let notes = app.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
#if DEBUG
                print("[AppUpdate] fallback App Store lookup success. current:", currentVersion, "latest:", latestVersion)
#endif
                return AppUpdateInfo(
                    latestVersion: latestVersion,
                    trackViewURL: trackViewURL,
                    releaseNotes: notes?.isEmpty == false ? notes : nil
                )
            } catch {
                continue
            }
        }

        return nil
    }

#if DEBUG
    static func debugMockUpdateInfo(currentVersion: String) -> AppUpdateInfo {
        let mockVersion = currentVersion + ".1"
        return AppUpdateInfo(
            latestVersion: mockVersion,
            trackViewURL: fallbackTrackViewURL,
            releaseNotes: nil
        )
    }
#endif

    private static func isVersion(_ lhs: String, greaterThan rhs: String) -> Bool {
        let lhsParts = lhs.split(separator: ".").map(versionPartValue)
        let rhsParts = rhs.split(separator: ".").map(versionPartValue)
        let maxCount = max(lhsParts.count, rhsParts.count)

        for index in 0..<maxCount {
            let left = index < lhsParts.count ? lhsParts[index] : 0
            let right = index < rhsParts.count ? rhsParts[index] : 0

            if left != right {
                return left > right
            }
        }

        return false
    }

    private static func versionPartValue(_ part: Substring) -> Int {
        let digits = part.prefix { $0.isNumber }
        return Int(digits) ?? 0
    }

    private static func decodeUpdateConfig(from payload: String) -> RemoteUpdateConfig? {
        let sanitized = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = sanitized.data(using: .utf8) else { return nil }
        if let config = try? JSONDecoder().decode(RemoteUpdateConfig.self, from: data) {
            return config
        }

        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let latestVersion = (raw["latestVersion"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (raw["latest_version"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (raw["version"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let latestVersion, !latestVersion.isEmpty else { return nil }

        let trackViewURL = (raw["trackViewURL"] as? String)
            ?? (raw["track_view_url"] as? String)
            ?? (raw["store_url"] as? String)

        var notes: [String: [String]] = [:]
        if let dict = raw["notes"] as? [String: Any] {
            notes.merge(normalizeNoteDictionary(dict)) { _, new in new }
        }
        if let dict = raw["releaseNotes"] as? [String: Any] {
            notes.merge(normalizeNoteDictionary(dict)) { _, new in new }
        }
        if let dict = raw["release_notes"] as? [String: Any] {
            notes.merge(normalizeNoteDictionary(dict)) { _, new in new }
        }

        return RemoteUpdateConfig(
            latestVersion: latestVersion,
            trackViewURL: trackViewURL,
            notes: notes.isEmpty ? nil : notes,
            releaseNotes: nil
        )
    }

    private static func normalizeNoteDictionary(_ raw: [String: Any]) -> [String: [String]] {
        var result: [String: [String]] = [:]

        for (key, value) in raw {
            if let lines = value as? [String] {
                let normalized = lines
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !normalized.isEmpty {
                    result[key] = normalized
                }
            } else if let text = value as? String {
                let normalized = text
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !normalized.isEmpty {
                    result[key] = normalized
                }
            }
        }

        return result
    }

    private static var defaultUpdateConfigJSON: String {
        """
        {
          "latestVersion": "0.0.0",
          "trackViewURL": "https://apps.apple.com/us/search?term=Bingodays",
          "notes": {
            "en": [],
            "zh-Hans": [],
            "zh-Hant": []
          }
        }
        """
    }

    private static func saveCachedUpdateInfo(_ info: AppUpdateInfo) {
        let record = CachedUpdateRecord(
            latestVersion: info.latestVersion,
            trackViewURL: info.trackViewURL.absoluteString,
            releaseNotes: info.releaseNotes
        )
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: AppSettings.cachedUpdateInfoKey)
    }

    private static func buildLookupURL(bundleIdentifier: String, countryCode: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/lookup"
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "bundleId", value: bundleIdentifier)
        ]
        if let countryCode, !countryCode.isEmpty {
            queryItems.append(URLQueryItem(name: "country", value: countryCode.uppercased()))
        }
        components.queryItems = queryItems
        return components.url
    }

    private static func lookupCountryCandidates(preferredCountryCode: String?) -> [String?] {
        var candidates: [String?] = []

        if let preferredCountryCode, !preferredCountryCode.isEmpty {
            candidates.append(preferredCountryCode.uppercased())
        }

        if let localeCountry = Locale.current.region?.identifier, !localeCountry.isEmpty {
            let uppercased = localeCountry.uppercased()
            if !candidates.contains(where: { $0 == uppercased }) {
                candidates.append(uppercased)
            }
        }

        candidates.append(nil)
        return candidates
    }
}

private struct CachedUpdateRecord: Codable {
    let latestVersion: String
    let trackViewURL: String
    let releaseNotes: String?
}

private struct AppStoreLookupResponse: Decodable {
    let resultCount: Int
    let results: [AppStoreLookupApp]
}

private struct AppStoreLookupApp: Decodable {
    let version: String?
    let trackViewUrl: String?
    let releaseNotes: String?
}

private struct RemoteUpdateConfig: Decodable {
    let latestVersion: String
    let trackViewURL: String?
    let notes: [String: [String]]?
    let releaseNotes: [String: [String]]?

    func localizedReleaseNotes(for language: AppLanguage) -> String? {
        let source = notes ?? releaseNotes ?? [:]
        guard !source.isEmpty else { return nil }

        let keys: [String]
        switch language {
        case .simplifiedChinese:
            keys = ["zh-Hans", "zh_CN", "zh-CN", "zh"]
        case .traditionalChinese:
            keys = ["zh-Hant", "zh_TW", "zh-HK", "zh-TW", "zh-HK"]
        case .japanese:
            keys = ["en", "en-US"]
        case .english:
            keys = ["en", "en-US"]
        }

        for key in keys {
            if let lines = source[key], !lines.isEmpty {
                let normalized = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !normalized.isEmpty {
                    return normalized.joined(separator: "\n")
                }
            }
        }

        if let fallbackLines = source["en"], !fallbackLines.isEmpty {
            let normalized = fallbackLines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !normalized.isEmpty {
                return normalized.joined(separator: "\n")
            }
        }

        return nil
    }
}

private struct FinalHourReminderSnapshot: Equatable {
    let boardName: String
    let completedTaskCount: Int
    let totalTaskCount: Int
}

private enum FinalHourReminderService {
    private static let notificationIdentifierPrefix = "bingodays.finalhour"
    private static let notificationSlots: [(hour: Int, minute: Int)] = [
        (23, 0),
        (23, 20),
        (23, 40)
    ]

    static func sync(now: Date, snapshot: FinalHourReminderSnapshot) async {
        let context = ReminderContext(now: now, snapshot: snapshot)
        await syncLocalNotifications(context: context)
        await syncLiveActivity(context: context)
    }

    private static func syncLocalNotifications(context: ReminderContext) async {
        let center = UNUserNotificationCenter.current()
        let status = await authorizationStatus(for: center)
        var resolvedStatus = status
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            resolvedStatus = await authorizationStatus(for: center)
        }

        guard resolvedStatus == .authorized || resolvedStatus == .provisional || resolvedStatus == .ephemeral else {
            return
        }

        let identifiers = notificationIdentifiers

        guard context.shouldShowReminder else {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            UserDefaults.standard.removeObject(forKey: AppSettings.finalHourReminderFingerprintKey)
            return
        }

        let upcomingSlots = context.upcomingSlotDates
        guard !upcomingSlots.isEmpty else {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            UserDefaults.standard.removeObject(forKey: AppSettings.finalHourReminderFingerprintKey)
            return
        }

        let fingerprint = makeNotificationFingerprint(context: context, upcomingSlots: upcomingSlots)
        if fingerprint == UserDefaults.standard.string(forKey: AppSettings.finalHourReminderFingerprintKey) {
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        for (slotIndex, slotDate) in upcomingSlots {
            let content = UNMutableNotificationContent()
            content.title = L10n.finalHourReminderTitle
            content.body = context.message(for: slotIndex)
            content.sound = .default

            let components = Calendar.autoupdatingCurrent.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: slotDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: notificationIdentifier(slotIndex: slotIndex),
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }

        UserDefaults.standard.set(fingerprint, forKey: AppSettings.finalHourReminderFingerprintKey)
    }

    private static func syncLiveActivity(context: ReminderContext) async {
#if canImport(ActivityKit)
        if #available(iOS 17.0, *) {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                await endLiveActivityIfNeeded()
                return
            }

            guard context.isInFinalHour, context.shouldShowReminder else {
                await endLiveActivityIfNeeded()
                return
            }

            let contentState = BingodaysFinalHourActivityAttributes.ContentState(
                message: context.message(for: 1),
                progressText: L10n.finalHourProgress(
                    completed: context.snapshot.completedTaskCount,
                    total: context.snapshot.totalTaskCount
                ),
                compactText: context.compactText,
                updatedAt: context.now
            )
            let staleDate = context.windowEnd

            if let existing = Activity<BingodaysFinalHourActivityAttributes>.activities.first {
                await existing.update(
                    ActivityContent(
                        state: contentState,
                        staleDate: staleDate
                    )
                )
                return
            }

            let attributes = BingodaysFinalHourActivityAttributes(
                boardName: context.snapshot.boardName
            )
            _ = try? Activity.request(
                attributes: attributes,
                content: ActivityContent(
                    state: contentState,
                    staleDate: staleDate
                ),
                pushType: nil
            )
        }
#endif
    }

    private static func authorizationStatus(for center: UNUserNotificationCenter) async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private static var notificationIdentifiers: [String] {
        Array(notificationSlots.indices).map(notificationIdentifier(slotIndex:))
    }

    private static func notificationIdentifier(slotIndex: Int) -> String {
        "\(notificationIdentifierPrefix).\(slotIndex)"
    }

    private static func makeNotificationFingerprint(
        context: ReminderContext,
        upcomingSlots: [(Int, Date)]
    ) -> String {
        let slotsSignature = upcomingSlots
            .map { "\($0.0):\(Int($0.1.timeIntervalSince1970))" }
            .joined(separator: "|")
        return [
            PointsStore.dateKey(for: context.now),
            context.snapshot.boardName,
            "\(context.snapshot.completedTaskCount)",
            "\(context.snapshot.totalTaskCount)",
            AppLanguage.current == .simplifiedChinese ? "zh-Hans" : (AppLanguage.current == .traditionalChinese ? "zh-Hant" : "en"),
            slotsSignature
        ].joined(separator: "#")
    }

#if canImport(ActivityKit)
    @available(iOS 17.0, *)
    private static func endLiveActivityIfNeeded() async {
        for activity in Activity<BingodaysFinalHourActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
#else
    private static func endLiveActivityIfNeeded() async {}
#endif

    private struct ReminderContext {
        let now: Date
        let snapshot: FinalHourReminderSnapshot
        let finalHourStart: Date
        let windowEnd: Date

        init(now: Date, snapshot: FinalHourReminderSnapshot) {
            self.now = now
            self.snapshot = snapshot

            let calendar = Calendar.autoupdatingCurrent
            let startOfDay = calendar.startOfDay(for: now)
            self.finalHourStart = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: startOfDay) ?? now
            self.windowEnd = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now.addingTimeInterval(3600)
        }

        var isInFinalHour: Bool {
            now >= finalHourStart && now < windowEnd
        }

        var remainingTaskCount: Int {
            max(snapshot.totalTaskCount - snapshot.completedTaskCount, 0)
        }

        var shouldShowReminder: Bool {
            snapshot.totalTaskCount == 0 || remainingTaskCount > 0
        }

        var compactText: String {
            if snapshot.totalTaskCount == 0 {
                return L10n.finalHourCompactNoTask
            }
            if remainingTaskCount > 0 {
                return L10n.finalHourCompactRemaining(remainingTaskCount)
            }
            return L10n.finalHourCompactDone
        }

        var upcomingSlotDates: [(Int, Date)] {
            let calendar = Calendar.autoupdatingCurrent
            let startOfDay = calendar.startOfDay(for: now)
            var result: [(Int, Date)] = []

            for (slotIndex, slot) in notificationSlots.enumerated() {
                guard let slotDate = calendar.date(
                    bySettingHour: slot.hour,
                    minute: slot.minute,
                    second: 0,
                    of: startOfDay
                ) else {
                    continue
                }
                if slotDate > now {
                    result.append((slotIndex, slotDate))
                }
            }
            return result
        }

        func message(for slotIndex: Int) -> String {
            if snapshot.totalTaskCount == 0 {
                return L10n.finalHourNoTaskMessage(slotIndex: slotIndex)
            }
            if remainingTaskCount <= 0 {
                return L10n.finalHourAllDoneMessage
            }
            return L10n.finalHourRemainingMessage(remaining: remainingTaskCount, slotIndex: slotIndex)
        }
    }
}

final class PointsSoundPlayer {
    static let shared = PointsSoundPlayer()

    private var player: AVAudioPlayer?

    func preload() {
        guard AppSettings.isSoundEffectsEnabled else { return }
        guard player == nil,
              let url = Bundle.main.url(forResource: "get1point", withExtension: "aiff") else { return }

        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.prepareToPlay()
            player = audioPlayer
        } catch {
            player = nil
        }
    }

    func play() {
        guard AppSettings.isSoundEffectsEnabled else { return }
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }
}

struct NineTenthsSheetContainer<Content: View>: View {
    let contentMaxWidth: CGFloat
    let content: Content

    init(contentMaxWidth: CGFloat = 920, @ViewBuilder content: () -> Content) {
        self.contentMaxWidth = contentMaxWidth
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Capsule(style: .continuous)
                        .fill(NeumorphicColors.text.opacity(0.22))
                        .frame(width: 54, height: 6)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    content
                        .frame(maxWidth: min(contentMaxWidth, geo.size.width - 32), maxHeight: .infinity)
                }
                .frame(
                    width: min(max(geo.size.width - 24, 0), contentMaxWidth + 32),
                    height: geo.size.height * 0.9,
                    alignment: .top
                )
                .background(NeumorphicColors.background)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(NeumorphicColors.lightShadow.opacity(0.42), lineWidth: 1)
                )
                .shadow(color: NeumorphicColors.darkShadow.opacity(0.18), radius: 16, x: 0, y: -2)
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

struct ContentView: View {
    private enum FirstStepGuideState: Int {
        case notStarted = 0
        case tracking = 1
        case finished = 2
    }

    private enum FirstStepGuideOverlay: String, Identifiable {
        case intro
        case milestoneOne
        case milestoneTwo
        case milestoneThree

        var id: String { rawValue }
    }

    private enum TimeoutDelayPickerContext {
        case task
        case board
    }

    private struct BoardResetResult {
        let didReset: Bool
        let clearedCompletedTaskCount: Int

        static let noReset = BoardResetResult(
            didReset: false,
            clearedCompletedTaskCount: 0
        )
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var accountSession: AccountSession
    @EnvironmentObject private var boardTemplateImportCoordinator: BoardTemplateImportCoordinator
    @StateObject private var viewModel = BingoViewModel()
    @State private var isSidebarPresented = false
    @State private var isSettingsExpanded = false
    @State private var isWidgetGuideExpanded = false
    @State private var isThemePickerExpanded = false
    @State private var isPointsDetailsPresented = false
    @State private var isBoardCountdownPresented = false
    @State private var isBoardRulesPresented = false
    @State private var boardRulesTargetBoardID: UUID?
    @State private var selectedStickerID: UUID?
    @State private var isDiaryPresented = false
    @State private var isPremiumPaywallPresented = false
    @State private var premiumPaywallSource = "unknown"
    @State private var isQuickEditPresented = false
    @State private var isBlackBoxModePresented = false
    @State private var isContactUsPresented = false
    @State private var isContactUsCopyToastVisible = false
    @State private var contactUsCopyToastWorkItem: DispatchWorkItem?
    @State private var isEditActionsExpanded = false
    @State private var isGridSizeSheetPresented = false
    @State private var isClearBoardConfirmationPresented = false
    @State private var commonTasksToastMessage: String?
    @State private var isCommonTasksToastVisible = false
    @State private var hideCommonTasksToastWorkItem: DispatchWorkItem?
    @State private var pointsAnimationTrigger = 0
    @State private var floatingPointsDelta: Int?
    @State private var isFloatingPointsDeltaVisible = false
    @State private var isDailyResetToastVisible = false
    @State private var taskTimeoutDelayMinutes = 10
    @State private var boardTimeoutDelayMinutes = 10
    @State private var timeoutDelayPickerContext: TimeoutDelayPickerContext?
    @State private var timeoutDelayPickerHours = 0
    @State private var timeoutDelayPickerMinutes = 10
    @State private var isUpdatePromptPresented = false
    @State private var hasCheckedAppUpdateOnLaunch = false
    @State private var pendingUpdateInfo: AppUpdateInfo?
    @State private var firstStepGuideOverlay: FirstStepGuideOverlay?
    @State private var namedBoards: [BingoBoardStore.NamedBoard] = []
    @State private var selectedBoardID: UUID?
    @State private var hasLoadedBoardSwitcherState = false
    @State private var isCreateBoardAlertPresented = false
    @State private var createBoardNameDraft = ""
    @State private var isRenameBoardAlertPresented = false
    @State private var renameBoardNameDraft = ""
    @State private var boardPendingRenameID: UUID?
    @State private var boardActionSheetBoardID: UUID?
    @State private var pendingBoardDeleteID: UUID?
    @State private var isBoardDeleteAlertPresented = false
    @State private var boardTemplateShareDraft: BoardTemplatePayload?
    @State private var isTemplateShareComposerPresented = false
    @State private var boardTemplateImportPreviewDraft: BoardTemplatePayload?
    @State private var isTemplateImportPreviewPresented = false
    @State private var templateImportPageOpenSource = "unknown"
    @State private var lastFinalHourReminderMinuteKey = ""
    @State private var stickerInventoryCounts = StickerStore.loadInventoryCounts()
    @State private var homeStickerPlacements = StickerStore.loadPlacements()
    @State private var customRewards = RewardStore.loadRewards()
    @State private var lastBoardRulesEvaluationDateKey = ""
    @State private var hasAppliedDebugSimulatedResetThisLaunch = false
    @AppStorage(AppSettings.hapticsEnabledKey) private var isHapticsEnabled = true
    @AppStorage(AppSettings.soundEffectsEnabledKey) private var isSoundEffectsEnabled = true
    @AppStorage(AppSettings.themeKey) private var themeRawValue = AppTheme.concise.rawValue
    @AppStorage(AppSettings.lastPromptedUpdateVersionKey) private var lastPromptedUpdateVersion = ""
    @AppStorage(AppSettings.skippedUpdateVersionKey) private var skippedUpdateVersion = ""
    @AppStorage(AppSettings.firstStepGuideStateKey) private var firstStepGuideStateRawValue = FirstStepGuideState.notStarted.rawValue
    @AppStorage(AppSettings.firstStepGuideMilestoneKey) private var firstStepGuideMilestoneShown = 0
    private let countdownTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var countdownNow = Date()
    private var bingoStreakDays: Int { BingoDiaryStore.consecutiveBingoDays() }
    private var streakGoals: [Int] { bingoStreakDays >= 60 ? [60, 180, 270, 365] : [7, 14, 30, 60] }
    private var activeTheme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .concise }
    private var activeThemeColor: Color { activeTheme.color }
    private var conciseSurfaceColor: Color { NeumorphicColors.background }
    private var appShortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
    private var releaseNotesItems: [String] {
        [
            L10n.updateItemQuickEditImproved,
            L10n.updateItemKnownIssuesFixed
        ]
    }
    private var spentStickerPoints: Int {
        stickerInventoryCounts.reduce(0) { partial, entry in
            partial + (entry.key.requiredPoints * entry.value)
        }
    }
    private var spentRewardPoints: Int {
        customRewards.reduce(0) { partial, reward in
            partial + reward.totalSpentPoints
        }
    }
    private var availablePoints: Int { max(viewModel.totalPoints - spentStickerPoints - spentRewardPoints, 0) }
    private var filledTaskCount: Int {
        viewModel.cells.flatMap(\.self).filter { !$0.isEmpty }.count
    }
    private var completedTaskCount: Int {
        viewModel.cells.flatMap(\.self).filter { !$0.isEmpty && $0.isCompleted }.count
    }
    private var completionProgress: Double {
        guard filledTaskCount > 0 else { return 0 }
        return Double(completedTaskCount) / Double(filledTaskCount)
    }
    private var completionPercent: Int {
        Int((completionProgress * 100).rounded())
    }

    private var firstStepGuideState: FirstStepGuideState {
        FirstStepGuideState(rawValue: firstStepGuideStateRawValue) ?? .notStarted
    }

    private func normalizedStarterTaskText(_ text: String) -> String {
        String(text.prefix(BingoViewModel.maxTaskLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var starterSeedTasks: [String] {
        [
            L10n.tr("Drink a glass of water", zhHans: "喝一杯水", zhHant: "喝一杯水"),
            L10n.tr("Stand for 1 minute", zhHans: "站立1分钟", zhHant: "站立1分鐘"),
            L10n.tr("Stretch your body", zhHans: "拉伸身体", zhHant: "拉伸身體")
        ]
    }

    private var starterSeedTaskKeys: [String] {
        starterSeedTasks.map(normalizedStarterTaskText)
    }

    private var starterIntroTitle: String {
        L10n.tr("Welcome to Bingodays 👋", zhHans: "欢迎来到 Bingodays 👋", zhHant: "歡迎來到 Bingodays 👋")
    }

    private var starterIntroDescription: String {
        L10n.tr(
            "Complete these starter tasks to feel the Bingo flow.",
            zhHans: "先完成这几个任务，体验Bingo的乐趣",
            zhHant: "先完成這幾個任務，體驗 Bingo 的樂趣"
        )
    }

    private func starterMilestoneMessage(for overlay: FirstStepGuideOverlay) -> String {
        switch overlay {
        case .intro:
            return ""
        case .milestoneOne:
            return L10n.tr(
                "Nice! First step completed, keep going 💪",
                zhHans: "Nice！第一步已完成，继续冲吧 💪",
                zhHant: "Nice！第一步已完成，繼續衝吧 💪"
            )
        case .milestoneTwo:
            return L10n.tr(
                "One step away from Bingo. Keep it up 🚀",
                zhHans: "离Bingo就差一个了！继续加油 🚀",
                zhHant: "離 Bingo 就差一個了！繼續加油 🚀"
            )
        case .milestoneThree:
            return L10n.tr(
                "Amazing! You unlocked your first Bingo 🎉 Long-press a tile to edit tasks and start your next round!",
                zhHans: "太厉害了！你解锁了第一个Bingo🎉 长按格子编辑任务，开启下一轮挑战吧！",
                zhHant: "太厲害了！你解鎖了第一個 Bingo🎉 長按格子編輯任務，開啟下一輪挑戰吧！"
            )
        }
    }

private let boardNameMaxLength = 20
private var canCreateAdditionalBoard: Bool {
    subscriptionManager.hasPremiumAccess || namedBoards.count < 1
}
private var shouldImportTemplateAsNewBoard: Bool {
    subscriptionManager.hasPremiumAccess || subscriptionManager.hasActiveAutoRenewable || subscriptionManager.hasLifetimeAccess
}
private var selectedNamedBoardIndex: Int? {
    guard let selectedBoardID else { return nil }
    return namedBoards.firstIndex(where: { $0.id == selectedBoardID })
}
private var selectedBoardName: String {
    guard let selectedNamedBoardIndex else {
        return L10n.boardDefaultName(1)
    }
    return namedBoards[selectedNamedBoardIndex].name
}

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.26) : base
    }

    private var maxGridSizeForCurrentPlan: Int {
        subscriptionManager.hasPremiumAccess ? 5 : 4
    }

    private func resizeGridWithPremiumGate(targetSize: Int, source: String) {
        guard targetSize > viewModel.gridSize else {
            viewModel.resizeGrid(to: targetSize)
            return
        }

        guard targetSize <= maxGridSizeForCurrentPlan else {
            AnalyticsService.logPremiumGrid5x5LimitHit(
                currentGridSize: viewModel.gridSize,
                source: source
            )
            let hasBlockingOverlay = isGridSizeSheetPresented || isEditActionsExpanded
            if isGridSizeSheetPresented {
                isGridSizeSheetPresented = false
            }
            if isEditActionsExpanded {
                isEditActionsExpanded = false
            }
            if hasBlockingOverlay {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    presentPremiumPaywall(source: source)
                }
            } else {
                presentPremiumPaywall(source: source)
            }
            return
        }

        viewModel.resizeGrid(to: targetSize)
    }

    private func presentPremiumPaywall(source: String) {
        premiumPaywallSource = source
        Task { @MainActor in
            isPremiumPaywallPresented = true
            await subscriptionManager.warmupProductsForPaywall()
        }
    }

    var body: some View {
        withStateObservers(
            content: withBoardAlerts(
                content: withPresentationLayers(
                    content: mainScreenContent
                )
            )
        )
    }

    private var mainScreenContent: some View {
        GeometryReader { geo in
            let usesPadLayout = isPadLayout && geo.size.width >= 768
            let horizontalPadding: CGFloat = usesPadLayout ? 30 : 20
            let topLayoutSafeInset: CGFloat = 0
            let layoutLift: CGFloat = -30
            let widthLimitedContent = geo.size.width - (horizontalPadding * 2)
            let heightLimitedContent = geo.size.height
                - max(topLayoutSafeInset, 0)
                - max(geo.safeAreaInsets.bottom, 0)
                - (usesPadLayout ? 250 : 0)
            let contentWidth = usesPadLayout
                ? max(300, min(widthLimitedContent, heightLimitedContent))
                : min(353, widthLimitedContent)

            ZStack(alignment: .top) {
                conciseSurfaceColor
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    headerView
                        .frame(width: contentWidth)
                        .padding(.top, max(topLayoutSafeInset, 0) + 12)

                    boardMainContent(contentWidth: contentWidth, usesPadLayout: usesPadLayout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .offset(y: -layoutLift)

                homeStickerLayer(
                    canvasSize: geo.size,
                    topInset: topLayoutSafeInset,
                    bottomInset: geo.safeAreaInsets.bottom
                )

                if isSidebarPresented {
                    Color.black.opacity(0.16)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                isSidebarPresented = false
                            }
                        }
                }

                sidebarView(
                    width: usesPadLayout ? min(geo.size.width * 0.42, 420) : min(geo.size.width * 0.8, 332),
                    topInset: topLayoutSafeInset,
                    bottomInset: geo.safeAreaInsets.bottom
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .offset(x: isSidebarPresented ? 0 : -(usesPadLayout ? min(geo.size.width * 0.42, 420) : min(geo.size.width * 0.8, 320)))
                .allowsHitTesting(isSidebarPresented)
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isSidebarPresented)

                if viewModel.showCelebration {
                    CelebrationView()
                }

                if viewModel.showBoardCompletionAnimation {
                    PAGCompletionView(resourceName: "cat_bmp") {
                        viewModel.dismissBoardCompletionAnimation()
                    }
                    .frame(width: min(geo.size.width * 0.5, 220), height: min(geo.size.width * 0.5, 220))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }

                if isDailyResetToastVisible {
                    dailyResetToast
                        .frame(maxWidth: min(contentWidth, 620), maxHeight: .infinity, alignment: .top)
                        .padding(.top, max(geo.safeAreaInsets.top, 18) + 44)
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }

                if let commonTasksToastMessage, isCommonTasksToastVisible {
                    commonTasksToast(message: commonTasksToastMessage)
                        .frame(maxWidth: min(contentWidth, 520), maxHeight: .infinity, alignment: .top)
                        .padding(.top, max(geo.safeAreaInsets.top, 18) + 96)
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }

                if let firstStepGuideOverlay {
                    firstStepGuideOverlayView(firstStepGuideOverlay)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(40)
                }

                if isUpdatePromptPresented, pendingUpdateInfo != nil {
                    updatePromptOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                boardActionLayer(contentWidth: contentWidth, bottomInset: geo.safeAreaInsets.bottom)

                if isEditActionsExpanded {
                    editActionsFullscreenOverlay
                        .transition(.opacity)
                        .zIndex(12)
                }

                if let expiredTaskEvent = viewModel.expiredTaskEvent {
                    taskTimeoutOverlay(for: expiredTaskEvent)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(30)
                }

                if let expiredBoardEvent = viewModel.expiredBoardCountdownEvent {
                    boardTimeoutOverlay(for: expiredBoardEvent)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(30)
                }

                if let scheduledEvent = viewModel.scheduledTaskReplacementEvent {
                    scheduledTaskReplacementOverlay(for: scheduledEvent)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(30)
                }

                if timeoutDelayPickerContext != nil {
                    timeoutDelayPickerOverlay
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(40)
                }

            }
        }
    }

    private func withPresentationLayers<Content: View>(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isQuickEditPresented) {
                QuickEditView(viewModel: viewModel) { message in
                    showCommonTasksToast(message)
                }
            }
            .fullScreenCover(isPresented: $isBlackBoxModePresented) {
                BlackBoxModeEntryView()
            }
            .sheet(isPresented: $isContactUsPresented) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(L10n.contactUsMessage)
                            .font(.appSystem(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(NeumorphicColors.text)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.contactUsEmailLabel)
                                .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text.opacity(0.56))

                            HStack(spacing: 10) {
                                Text(L10n.contactUsEmail)
                                    .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                                    .foregroundColor(NeumorphicColors.accent)
                                    .textSelection(.enabled)

                                Spacer(minLength: 0)

                                Button {
                                    UIPasteboard.general.string = L10n.contactUsEmail
                                    showContactUsCopyToast()
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundColor(NeumorphicColors.accent)
                                        .frame(width: 30, height: 30)
                                        .background(
                                            Circle()
                                                .fill(NeumorphicColors.background)
                                                .shadow(color: NeumorphicColors.lightShadow.opacity(0.8), radius: 4, x: -2, y: -2)
                                                .shadow(color: NeumorphicColors.darkShadow.opacity(0.25), radius: 4, x: 2, y: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L10n.tr("Copy email", zhHans: "复制邮箱", zhHant: "複製信箱"))
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(NeumorphicColors.background)
                                .shadow(color: NeumorphicColors.lightShadow.opacity(0.8), radius: 8, x: -4, y: -4)
                                .shadow(color: NeumorphicColors.darkShadow.opacity(0.42), radius: 8, x: 4, y: 4)
                        )

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 20)
                    .background(NeumorphicColors.background.ignoresSafeArea())
                    .navigationTitle(L10n.contactUsTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L10n.done) {
                                isContactUsPresented = false
                            }
                            .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(NeumorphicColors.accent)
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    if isContactUsCopyToastVisible {
                        Text(L10n.contactUsEmailCopied)
                            .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.black.opacity(0.82))
                            )
                            .padding(.bottom, 22)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isContactUsCopyToastVisible)
                .presentationDetents([.height(isPadLayout ? 340 : 300)])
                .presentationDragIndicator(.visible)
                .presentationBackground(NeumorphicColors.background)
            }
            .fullScreenCover(isPresented: $isTemplateShareComposerPresented) {
                if let template = boardTemplateShareDraft {
                    BoardTemplateShareComposerView(template: template)
                }
            }
            .sheet(isPresented: $isTemplateImportPreviewPresented) {
                if let template = boardTemplateImportPreviewDraft {
                    BoardTemplateImportPreviewView(
                        template: template,
                        createsNewBoard: shouldImportTemplateAsNewBoard,
                        onImport: {
                            applyImportedTemplate(template)
                        },
                        onClose: {
                            isTemplateImportPreviewPresented = false
                        }
                    )
                    .presentationDetents([.height(templateImportSheetHeight(for: template.gridSize))])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: Binding(
                get: { !isPadLayout && isPointsDetailsPresented },
                set: { isPointsDetailsPresented = $0 }
            )) {
                PointsDetailSheet(
                    points: availablePoints,
                    inventoryCounts: stickerInventoryCounts,
                    usedCounts: currentStickerUsageCounts,
                    rewards: customRewards.filter { !$0.isArchived },
                    onRedeem: { kind in
                        redeemSticker(kind)
                    },
                    onAddToHome: { kind in
                        addStickerToHome(kind)
                    },
                    onCreateReward: { title, requiredPoints in
                        createReward(title: title, requiredPoints: requiredPoints)
                    },
                    onUpdateReward: { reward in
                        updateReward(reward)
                    },
                    onDeleteReward: { reward in
                        archiveReward(reward)
                    },
                    onRedeemReward: { reward in
                        redeemReward(reward)
                    }
                )
                .presentationDetents([.fraction(0.9)])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: Binding(
                get: { isPadLayout && isPointsDetailsPresented },
                set: { isPointsDetailsPresented = $0 }
            )) {
                NineTenthsSheetContainer(contentMaxWidth: 960) {
                    PointsDetailSheet(
                        points: availablePoints,
                        inventoryCounts: stickerInventoryCounts,
                        usedCounts: currentStickerUsageCounts,
                        rewards: customRewards.filter { !$0.isArchived },
                        onRedeem: { kind in
                            redeemSticker(kind)
                        },
                        onAddToHome: { kind in
                            addStickerToHome(kind)
                        },
                        onCreateReward: { title, requiredPoints in
                            createReward(title: title, requiredPoints: requiredPoints)
                        },
                        onUpdateReward: { reward in
                            updateReward(reward)
                        },
                        onDeleteReward: { reward in
                            archiveReward(reward)
                        },
                        onRedeemReward: { reward in
                            redeemReward(reward)
                        }
                    )
                }
                .background(Color.clear)
            }
            .sheet(isPresented: $isBoardCountdownPresented) {
                BoardCountdownSheet(
                    countdownEndsAt: viewModel.boardCountdownEndsAt,
                    onSave: { totalMinutes in
                        viewModel.setBoardCountdown(totalMinutes: totalMinutes)
                        isBoardCountdownPresented = false
                    },
                    onCancel: {
                        isBoardCountdownPresented = false
                    }
                )
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isBoardRulesPresented) {
                if let boardRulesTargetBoardID,
                   let board = namedBoards.first(where: { $0.id == boardRulesTargetBoardID }) {
                    BoardRulesSheet(
                        countdownEndsAt: board.countdownEndsAt,
                        initialResetMode: board.taskResetMode,
                        onSave: { totalMinutes, resetMode in
                            applyBoardRulesSettings(
                                for: board.id,
                                countdownMinutes: totalMinutes,
                                resetMode: resetMode
                            )
                            isBoardRulesPresented = false
                        },
                        onCancel: {
                            isBoardRulesPresented = false
                        }
                    )
                    .presentationDetents([.height(560)])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $isGridSizeSheetPresented) {
                gridSizeAdjustmentSheet
                    .presentationDetents([.height(280)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(NeumorphicColors.background)
            }
            .fullScreenCover(isPresented: $isDiaryPresented) {
                BingoDiaryScreen()
            }
            .fullScreenCover(isPresented: $isPremiumPaywallPresented) {
                PremiumPaywallView(entrySource: premiumPaywallSource)
            }
    }

    private func withBoardAlerts<Content: View>(content: Content) -> some View {
        content
            .alert(L10n.boardCreateTitle, isPresented: $isCreateBoardAlertPresented) {
                TextField(L10n.boardNamePlaceholder, text: $createBoardNameDraft)
                Button(L10n.cancel, role: .cancel) {
                    createBoardNameDraft = ""
                }
                Button(L10n.boardCreateAction) {
                    createBoard()
                }
            }
            .alert(L10n.boardRenameTitle, isPresented: $isRenameBoardAlertPresented) {
                TextField(L10n.boardNamePlaceholder, text: $renameBoardNameDraft)
                Button(L10n.cancel, role: .cancel) {
                    renameBoardNameDraft = ""
                    boardPendingRenameID = nil
                }
                Button(L10n.boardRenameAction) {
                    renameBoard()
                }
            }
            .alert(
                L10n.tr("Delete board?", zhHans: "删除棋盘？", zhHant: "刪除棋盤？"),
                isPresented: $isBoardDeleteAlertPresented
            ) {
                Button(L10n.cancel, role: .cancel) {
                    pendingBoardDeleteID = nil
                }
                Button(L10n.deleteConfirmationTitle, role: .destructive) {
                    guard let pendingBoardDeleteID else { return }
                    deleteBoard(pendingBoardDeleteID)
                }
            } message: {
                Text(pendingBoardDeleteMessage)
            }
            .alert(
                L10n.clearBoardConfirmationTitle,
                isPresented: $isClearBoardConfirmationPresented
            ) {
                Button(L10n.cancel, role: .cancel) {}
                Button(L10n.clearBoard, role: .destructive) {
                    viewModel.resetBoard()
                    showCommonTasksToast(L10n.boardClearedSuccess)
                }
            } message: {
                Text(L10n.clearBoardConfirmationMessage)
            }
    }

    private func withStateObservers<Content: View>(content: Content) -> some View {
        let baseContent = AnyView(content)
        let lifecycleObserved = withLifecycleObservers(content: baseContent)
        let presentationObserved = withPresentationStateObservers(content: lifecycleObserved)
        let boardObserved = withBoardStateObservers(content: presentationObserved)
        return withPointsAndTimeoutObservers(content: boardObserved)
    }

    private func withLifecycleObservers(content: AnyView) -> AnyView {
        AnyView(
            content
            .onAppear {
                if !AppFeatureFlags.isTemplateSharingEnabled {
                    boardTemplateShareDraft = nil
                    isTemplateShareComposerPresented = false
                    boardTemplateImportPreviewDraft = nil
                    isTemplateImportPreviewPresented = false
                    boardTemplateImportCoordinator.dismissPendingTemplate()
                }
                ensureBoardSwitcherLoaded()
                handleBoardResetLifecycle(now: Date(), force: true, source: "onAppear", shouldApplyForegroundCleanup: true)
                if shouldSimulateNextDayBoardRuleResetInDebug {
                    forceApplyBoardTaskResetRulesForDebug(now: Date())
                }
                evaluateFirstStepGuideEntryIfNeeded()
                countdownNow = Date()
                viewModel.processExpiredCountdowns(now: countdownNow)
                viewModel.processExpiredTaskCountdowns(now: countdownNow)
                viewModel.processScheduledTaskReplacementConflicts(now: countdownNow)
                PAGCompletionView.preload(resourceName: "cat_bmp")
                PointsSoundPlayer.shared.preload()
                if !hasCheckedAppUpdateOnLaunch {
                    hasCheckedAppUpdateOnLaunch = true
                    Task {
                        await checkForAppUpdateIfNeeded()
                    }
                }
                Task {
                    await subscriptionManager.refreshAll()
                }
                syncFinalHourReminderChannels(now: Date(), force: true)
                debugTileGestureBlockers(source: "onAppear")
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                ensureBoardSwitcherLoaded()
                handleBoardResetLifecycle(now: Date(), force: true, source: "sceneActive", shouldApplyForegroundCleanup: true)
                if shouldSimulateNextDayBoardRuleResetInDebug {
                    forceApplyBoardTaskResetRulesForDebug(now: Date())
                }
                evaluateFirstStepGuideEntryIfNeeded()
                countdownNow = Date()
                viewModel.processExpiredCountdowns(now: countdownNow)
                viewModel.processExpiredTaskCountdowns(now: countdownNow)
                viewModel.processScheduledTaskReplacementConflicts(now: countdownNow)
                Task {
                    await subscriptionManager.refreshEntitlements()
                }
                Task {
                    await checkForAppUpdateIfNeeded()
                }
                syncFinalHourReminderChannels(now: Date(), force: true)
                debugTileGestureBlockers(source: "sceneActive")
            }
        )
    }

    private func withPresentationStateObservers(content: AnyView) -> AnyView {
        AnyView(
            content
            .onChange(of: isQuickEditPresented) { _, newValue in
                if newValue { isEditActionsExpanded = false }
            }
            .onChange(of: boardTemplateImportCoordinator.pendingTemplate) { _, incomingTemplate in
                guard AppFeatureFlags.isTemplateSharingEnabled else { return }
                guard let incomingTemplate else { return }
                presentImportPreview(
                    template: incomingTemplate,
                    source: boardTemplateImportCoordinator.pendingTemplateSource
                )
                boardTemplateImportCoordinator.dismissPendingTemplate()
            }
            .onChange(of: isTemplateShareComposerPresented) { _, isPresented in
                if !isPresented {
                    boardTemplateShareDraft = nil
                }
            }
            .onChange(of: isTemplateImportPreviewPresented) { _, isPresented in
                if !isPresented {
                    boardTemplateImportPreviewDraft = nil
                }
            }
            .onChange(of: isBoardCountdownPresented) { _, newValue in
                if newValue { isEditActionsExpanded = false }
            }
            .onChange(of: isBoardRulesPresented) { _, newValue in
                if newValue { isEditActionsExpanded = false }
                if !newValue { boardRulesTargetBoardID = nil }
            }
            .onChange(of: isBlackBoxModePresented) { _, newValue in
                if newValue { isEditActionsExpanded = false }
            }
            .onChange(of: isGridSizeSheetPresented) { _, newValue in
                if newValue { isEditActionsExpanded = false }
            }
            .onChange(of: isSidebarPresented) { _, _ in
                debugTileGestureBlockers(source: "sidebar")
            }
            .onChange(of: isEditActionsExpanded) { _, _ in
                debugTileGestureBlockers(source: "quickEditOverlay")
            }
            .onChange(of: firstStepGuideOverlay) { _, _ in
                debugTileGestureBlockers(source: "firstStepGuide")
            }
            .onChange(of: isUpdatePromptPresented) { _, _ in
                debugTileGestureBlockers(source: "updatePrompt")
            }
            .onChange(of: boardActionSheetBoardID) { _, _ in
                debugTileGestureBlockers(source: "boardActionSheet")
            }
        )
    }

    private func withBoardStateObservers(content: AnyView) -> AnyView {
        AnyView(
            content
            .onChange(of: viewModel.cells) { _, _ in
                syncSelectedBoardSnapshotIfNeeded()
                evaluateFirstStepGuideProgressIfNeeded()
                reconcileStickerOwnershipIfPointsInsufficient()
                syncFinalHourReminderChannels(now: Date(), force: true)
            }
            .onChange(of: viewModel.gridSize) { _, _ in
                syncSelectedBoardSnapshotIfNeeded()
                syncFinalHourReminderChannels(now: Date(), force: true)
            }
            .onChange(of: viewModel.completedLines) { _, _ in
                syncSelectedBoardSnapshotIfNeeded()
            }
            .onChange(of: viewModel.boardCountdownEndsAt) { _, _ in
                syncSelectedBoardSnapshotIfNeeded()
            }
            .onChange(of: selectedBoardID) { _, _ in
                syncFinalHourReminderChannels(now: Date(), force: true)
            }
        )
    }

    private func withPointsAndTimeoutObservers(content: AnyView) -> AnyView {
        AnyView(
            content
            .onAppear {
                reconcileStickerOwnershipIfPointsInsufficient()
            }
            .onChange(of: viewModel.totalPoints) { _, _ in
                reconcileStickerOwnershipIfPointsInsufficient()
            }
            .onChange(of: availablePoints) { oldValue, newValue in
                reconcileStickerOwnershipIfPointsInsufficient()

                let delta = newValue - oldValue
                guard delta != 0 else { return }

                pointsAnimationTrigger += 1
                floatingPointsDelta = delta

                if delta > 0 {
                    PointsSoundPlayer.shared.play()
                }

                withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
                    isFloatingPointsDeltaVisible = true
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) {
                    withAnimation(.easeOut(duration: 0.32)) {
                        isFloatingPointsDeltaVisible = false
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.08) {
                    if !isFloatingPointsDeltaVisible {
                        floatingPointsDelta = nil
                    }
                }
            }
            .onChange(of: viewModel.dailyResetNoticeID) { _, newValue in
                guard newValue > 0 else { return }

                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    isDailyResetToastVisible = true
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                    withAnimation(.easeOut(duration: 0.28)) {
                        isDailyResetToastVisible = false
                    }
                }
            }
            .onReceive(countdownTicker) { _ in
                countdownNow = Date()
                handleBoardResetLifecycle(now: countdownNow, source: "ticker")
                viewModel.processExpiredCountdowns(now: countdownNow)
                viewModel.processExpiredTaskCountdowns(now: countdownNow)
                viewModel.processScheduledTaskReplacementConflicts(now: countdownNow)
                syncFinalHourReminderChannels(now: countdownNow)
            }
            .onChange(of: viewModel.expiredTaskEvent?.id) { _, _ in
                taskTimeoutDelayMinutes = 10
                timeoutDelayPickerContext = nil
            }
            .onChange(of: viewModel.expiredBoardCountdownEvent?.id) { _, _ in
                boardTimeoutDelayMinutes = 10
                timeoutDelayPickerContext = nil
            }
        )
    }

    private var shouldForceShowUpdatePromptInDebug: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ForceUpdatePrompt")
#else
        false
#endif
    }

    private var shouldSimulateNextDayBoardRuleResetInDebug: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-SimulateNextDayBoardRuleReset")
#else
        false
#endif
    }

    private var shouldPrepareStreakTestInDebug: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-DebugStreakReady")
#else
        false
#endif
    }

    private func syncFinalHourReminderChannels(now: Date = .now, force: Bool = false) {
        let calendar = Calendar.autoupdatingCurrent
        let minuteKey = "\(PointsStore.dateKey(for: now))-\(calendar.component(.hour, from: now))-\(calendar.component(.minute, from: now))"
        if !force && minuteKey == lastFinalHourReminderMinuteKey {
            return
        }
        lastFinalHourReminderMinuteKey = minuteKey

        let snapshot = FinalHourReminderSnapshot(
            boardName: selectedBoardName,
            completedTaskCount: completedTaskCount,
            totalTaskCount: filledTaskCount
        )

        Task {
            await FinalHourReminderService.sync(now: now, snapshot: snapshot)
        }
    }

    @MainActor
    private func checkForAppUpdateIfNeeded() async {
        if let cachedInfo = AppUpdateService.cachedUpdateInfo(currentVersion: appShortVersion),
           (shouldForceShowUpdatePromptInDebug || cachedInfo.latestVersion != skippedUpdateVersion),
           (shouldForceShowUpdatePromptInDebug || cachedInfo.latestVersion != lastPromptedUpdateVersion) {
            presentUpdatePrompt(with: cachedInfo)
        }

        if let info = await AppUpdateService.fetchUpdateInfo(currentVersion: appShortVersion) {
            if !shouldForceShowUpdatePromptInDebug && info.latestVersion == skippedUpdateVersion {
                return
            }
            if !shouldForceShowUpdatePromptInDebug && info.latestVersion == lastPromptedUpdateVersion {
                return
            }
            presentUpdatePrompt(with: info)
            return
        }

#if DEBUG
        if shouldForceShowUpdatePromptInDebug {
            presentUpdatePrompt(with: AppUpdateService.debugMockUpdateInfo(currentVersion: appShortVersion))
        }
#endif
    }

    private func presentUpdatePrompt(with info: AppUpdateInfo) {
        pendingUpdateInfo = info
        lastPromptedUpdateVersion = info.latestVersion
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            isUpdatePromptPresented = true
        }
    }

    private func dismissUpdatePrompt(markSkipped: Bool = false) {
        if markSkipped, let latestVersion = pendingUpdateInfo?.latestVersion, !latestVersion.isEmpty {
            skippedUpdateVersion = latestVersion
        }
        withAnimation(.easeOut(duration: 0.2)) {
            isUpdatePromptPresented = false
        }
    }

    private func evaluateFirstStepGuideEntryIfNeeded() {
        guard firstStepGuideState == .notStarted else { return }
        guard firstStepGuideOverlay == nil else { return }
        guard viewModel.currentTaskPoolTasks().isEmpty else { return }
        firstStepGuideOverlay = .intro
    }

    private func startFirstStepGuide() {
        if viewModel.gridSize < 3 {
            viewModel.resizeGrid(to: 3)
        }

        let seedTasks = starterSeedTaskKeys
        for (col, task) in seedTasks.enumerated() {
            viewModel.updateTask(
                row: 0,
                col: col,
                text: task,
                isForced: false,
                residentWeekdays: [],
                isOneTimeTask: false
            )
        }

        firstStepGuideStateRawValue = FirstStepGuideState.tracking.rawValue
        firstStepGuideMilestoneShown = 0
        firstStepGuideOverlay = nil
    }

    private func skipFirstStepGuide() {
        firstStepGuideStateRawValue = FirstStepGuideState.finished.rawValue
        firstStepGuideMilestoneShown = 3
        firstStepGuideOverlay = nil
    }

    private func starterCompletedTaskCount() -> Int {
        let allCells = viewModel.cells.flatMap { $0 }

        return starterSeedTaskKeys.reduce(0) { count, task in
            let hasCompleted = allCells.contains {
                $0.isCompleted &&
                normalizedStarterTaskText($0.storedTaskText) == task
            }
            return count + (hasCompleted ? 1 : 0)
        }
    }

    private func evaluateFirstStepGuideProgressIfNeeded() {
        guard firstStepGuideState == .tracking else { return }
        guard firstStepGuideOverlay != .intro else { return }

        let completedCount = starterCompletedTaskCount()
        let targetOverlay: FirstStepGuideOverlay?

        switch completedCount {
        case 3... where firstStepGuideMilestoneShown < 3:
            targetOverlay = .milestoneThree
        case 2 where firstStepGuideMilestoneShown < 2:
            targetOverlay = .milestoneTwo
        case 1 where firstStepGuideMilestoneShown < 1:
            targetOverlay = .milestoneOne
        default:
            targetOverlay = nil
        }

        guard let targetOverlay else { return }
        firstStepGuideOverlay = targetOverlay

        switch targetOverlay {
        case .milestoneOne:
            firstStepGuideMilestoneShown = max(firstStepGuideMilestoneShown, 1)
        case .milestoneTwo:
            firstStepGuideMilestoneShown = max(firstStepGuideMilestoneShown, 2)
        case .milestoneThree:
            firstStepGuideMilestoneShown = max(firstStepGuideMilestoneShown, 3)
        case .intro:
            break
        }
    }

    private func dismissFirstStepGuideOverlay() {
        if firstStepGuideOverlay == .milestoneThree {
            firstStepGuideStateRawValue = FirstStepGuideState.finished.rawValue
        }
        firstStepGuideOverlay = nil
    }

    @ViewBuilder
    private func firstStepGuideOverlayView(_ overlay: FirstStepGuideOverlay) -> some View {
        ZStack {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .blur(radius: 10)

                Color.black.opacity(0.6)
            }
            .ignoresSafeArea()

            VStack(spacing: 22) {
                switch overlay {
                case .intro:
                    firstStepIntroContent
                case .milestoneOne:
                    firstStepMilestoneContent(
                        imageName: "StarterGuideFirst",
                        message: starterMilestoneMessage(for: .milestoneOne)
                    )
                case .milestoneTwo:
                    firstStepMilestoneContent(
                        imageName: "StarterGuideSecond",
                        message: starterMilestoneMessage(for: .milestoneTwo)
                    )
                case .milestoneThree:
                    firstStepMilestoneThreeContent
                }
            }
            .padding(.horizontal, isPadLayout ? 38 : 28)
            .frame(maxWidth: 560)
        }
    }

    private var firstStepIntroContent: some View {
        VStack(spacing: 20) {
            Text(starterIntroTitle)
                .font(.appSystem(size: scaled(23, pad: 31), weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Image("StarterGuideArrow")
                .resizable()
                .scaledToFit()
                .frame(width: isPadLayout ? 72 : 56)
                .padding(.top, -4)
                .padding(.bottom, -2)

            starterIntroBoardPreview

            Text(starterIntroDescription)
                .font(.appSystem(size: scaled(19, pad: 23), weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            HStack {
                Spacer()
                Button {
                    startFirstStepGuide()
                } label: {
                    Text("OK")
                        .font(.appSystem(size: scaled(14, pad: 18), weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: isPadLayout ? 300 : 220)
                        .frame(height: isPadLayout ? 58 : 52)
                        .background(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                                        .stroke(Color.white.opacity(0.75), lineWidth: 1.5)
                                )
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                }
                .buttonStyle(.plain)
                .frame(width: isPadLayout ? 300 : 220, height: isPadLayout ? 58 : 52)
                .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                Spacer()
            }
            .padding(.top, 12)
        }
    }

    private var starterIntroBoardPreview: some View {
        let cardCorner: CGFloat = isPadLayout ? 34 : 28
        let cellCorner: CGFloat = isPadLayout ? 16 : 14
        let spacing: CGFloat = isPadLayout ? 14 : 10

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                .fill(NeumorphicColors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                        .stroke(Color.white.opacity(0.36), lineWidth: 1)
                )
                .shadow(color: Color.white.opacity(0.3), radius: 10, x: -4, y: -4)
                .shadow(color: Color.black.opacity(0.22), radius: 14, x: 5, y: 8)

            VStack(spacing: spacing) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<3, id: \.self) { col in
                            let taskText = row == 0 ? starterSeedTasks[col] : ""
                            RoundedRectangle(cornerRadius: cellCorner, style: .continuous)
                                .fill(NeumorphicColors.background)
                                .overlay(
                                    RoundedRectangle(cornerRadius: cellCorner, style: .continuous)
                                        .stroke(Color(hex: "E2DAD0"), lineWidth: 1)
                                )
                                .overlay {
                                    if !taskText.isEmpty {
                                        Text(taskText)
                                            .font(.appSystem(size: scaled(16, pad: 18), weight: .bold, design: .rounded))
                                            .foregroundColor(NeumorphicColors.text)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(2)
                                            .minimumScaleFactor(0.85)
                                            .padding(.horizontal, 4)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
            .padding(isPadLayout ? 20 : 16)

            Image("StarterGuideClick")
                .resizable()
                .scaledToFit()
                .frame(width: isPadLayout ? 77 : 65)
                .offset(x: isPadLayout ? 44 : 38, y: isPadLayout ? 92 : 80)
        }
        .frame(maxWidth: 480)
        .aspectRatio(1, contentMode: .fit)
    }

    private func firstStepMilestoneContent(imageName: String, message: String) -> some View {
        VStack(spacing: 20) {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: isPadLayout ? 240 : 188)

            Text(message)
                .font(.appSystem(size: scaled(21, pad: 29), weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 6)

            Button {
                dismissFirstStepGuideOverlay()
            } label: {
                Text("OK")
                    .font(.appSystem(size: scaled(14, pad: 18), weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: isPadLayout ? 300 : 220)
                    .frame(height: isPadLayout ? 60 : 52)
                    .background(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .stroke(Color.white.opacity(0.75), lineWidth: 1.5)
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(width: isPadLayout ? 300 : 220, height: isPadLayout ? 60 : 52)
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .padding(.top, 12)
        }
        .frame(maxWidth: 520)
    }

    private var firstStepMilestoneThreeContent: some View {
        VStack(spacing: 20) {
            Image("StarterGuideThird")
                .resizable()
                .scaledToFit()
                .frame(width: isPadLayout ? 210 : 150)

            HStack(spacing: 10) {
                ForEach(starterSeedTasks, id: \.self) { task in
                    VStack(spacing: 12) {
                        Text(task)
                            .font(.appSystem(size: scaled(15, pad: 17), weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)

                        Image(systemName: "checkmark.circle.fill")
                            .font(.appSystem(size: scaled(22, pad: 24), weight: .bold))
                            .foregroundColor(.white.opacity(0.96))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: isPadLayout ? 128 : 106)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(hex: "D3A375"))
                    )
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: "3F270F").opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color(hex: "CFA46F").opacity(0.7), lineWidth: 1)
                    )
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: "sparkles")
                    .font(.appSystem(size: scaled(18, pad: 20), weight: .bold))
                    .foregroundColor(Color(hex: "F5C164"))
                    .offset(x: 10, y: -10)
            }
            .overlay(alignment: .bottomLeading) {
                Image(systemName: "sparkles")
                    .font(.appSystem(size: scaled(16, pad: 18), weight: .bold))
                    .foregroundColor(Color(hex: "F5C164"))
                    .offset(x: -10, y: 10)
            }

            Text(starterMilestoneMessage(for: .milestoneThree))
                .font(.appSystem(size: scaled(21, pad: 29), weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Button {
                dismissFirstStepGuideOverlay()
            } label: {
                Text("OK")
                    .font(.appSystem(size: scaled(14, pad: 18), weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: isPadLayout ? 300 : 220)
                    .frame(height: isPadLayout ? 60 : 52)
                    .background(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .stroke(Color.white.opacity(0.75), lineWidth: 1.5)
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(width: isPadLayout ? 300 : 220, height: isPadLayout ? 60 : 52)
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .padding(.top, 10)
        }
        .frame(maxWidth: 520)
    }

    private func updatePromptItems(for info: AppUpdateInfo) -> [String] {
        if let notes = info.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !notes.isEmpty {
            let items = notes
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !items.isEmpty {
                return items
            }
        }
        return releaseNotesItems
    }

    private func openAppStoreForUpdate() {
        guard let info = pendingUpdateInfo else { return }
        dismissUpdatePrompt()
        openURL(info.trackViewURL) { accepted in
            if !accepted {
                showCommonTasksToast(L10n.updateStoreOpenFailed)
            }
        }
    }

    @ViewBuilder
    private var updatePromptOverlay: some View {
        if let info = pendingUpdateInfo {
            ZStack {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissUpdatePrompt(markSkipped: true)
                    }

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.updateWhatsNewTitle)
                            .font(.appSystem(size: scaled(20, pad: 26), weight: .heavy, design: .rounded))
                            .foregroundColor(NeumorphicColors.text)

                        Text(L10n.updateVersionTitle(info.latestVersion))
                            .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                            .foregroundColor(NeumorphicColors.text.opacity(0.58))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(updatePromptItems(for: info).enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.appSystem(size: scaled(11, pad: 13), weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(width: scaled(20, pad: 24), height: scaled(20, pad: 24))
                                    .background(
                                        Circle()
                                            .fill(NeumorphicColors.accent)
                                            .shadow(color: NeumorphicColors.accent.opacity(0.28), radius: 6, x: 0, y: 3)
                                    )
                                    .padding(.top, 1)

                                Text(item)
                                    .font(.appSystem(size: scaled(13, pad: 16), weight: .medium, design: .rounded))
                                    .foregroundColor(NeumorphicColors.text.opacity(0.88))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            dismissUpdatePrompt(markSkipped: true)
                        } label: {
                            Text(L10n.updateSecondaryAction)
                                .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text.opacity(0.78))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color.clear.neumorphicConvex(radius: 18))
                        }
                        .buttonStyle(.plain)

                        Button {
                            openAppStoreForUpdate()
                        } label: {
                            Text(L10n.updatePrimaryAction)
                                .font(.appSystem(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(NeumorphicColors.bingoAccent)
                                        .shadow(color: NeumorphicColors.bingoAccent.opacity(0.24), radius: 10, x: 0, y: 4)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 22)
                }
                .padding(22)
                .frame(maxWidth: isPadLayout ? 560 : 350)
                .background(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(NeumorphicColors.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .stroke(NeumorphicColors.lightShadow.opacity(0.42), lineWidth: 1)
                        )
                        .shadow(color: NeumorphicColors.darkShadow.opacity(0.18), radius: 16, x: 0, y: 8)
                        .shadow(color: Color.white.opacity(0.72), radius: 10, x: -4, y: -4)
                )
                .padding(.horizontal, 24)
            }
        }
    }

    private var dailyResetToast: some View {
        Text(L10n.newDayResetMessage)
            .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.96))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(NeumorphicColors.accent.opacity(0.92))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.28), lineWidth: 1)
                    )
            )
            .shadow(color: NeumorphicColors.accent.opacity(0.34), radius: 10, x: 0, y: 6)
    }

    private func showCommonTasksToast(_ message: String) {
        hideCommonTasksToastWorkItem?.cancel()
        commonTasksToastMessage = message

        withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
            isCommonTasksToastVisible = true
        }

        let workItem = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.26)) {
                isCommonTasksToastVisible = false
            }
        }
        hideCommonTasksToastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: workItem)
    }

    private func showContactUsCopyToast() {
        contactUsCopyToastWorkItem?.cancel()

        withAnimation(.easeInOut(duration: 0.2)) {
            isContactUsCopyToastVisible = true
        }

        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) {
                isContactUsCopyToastVisible = false
            }
        }

        contactUsCopyToastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: workItem)
    }

    private func commonTasksToast(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.appSystem(size: scaled(18, pad: 21), weight: .bold))
                .foregroundColor(.white.opacity(0.96))

            Text(message)
                .font(.appSystem(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.96))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(NeumorphicColors.accent.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.28), lineWidth: 1)
                )
        )
        .shadow(color: NeumorphicColors.darkShadow.opacity(0.22), radius: 16, x: 0, y: 8)
        .shadow(color: NeumorphicColors.accent.opacity(0.34), radius: 10, x: 0, y: 6)
    }

    @ViewBuilder
    private func taskTimeoutOverlay(for event: BingoViewModel.ExpiredTaskEvent) -> some View {
        ZStack {
            timeoutDialogBackdrop

            VStack(spacing: 20) {
                let overtimeSeconds = max(Int(countdownNow.timeIntervalSince(event.expiredAt)), 0)
                let taskText = event.taskText.isEmpty ? L10n.task : event.taskText

                timeoutDialogCard(
                    headline: L10n.taskTimedOutHeadline(task: taskText, seconds: overtimeSeconds),
                    onClose: {
                        viewModel.expiredTaskEvent = nil
                    },
                    onPrimaryAction: {
                        if let message = viewModel.resolveExpiredTask(.markAsCompleted, now: countdownNow) {
                            showCommonTasksToast(message)
                        }
                    },
                    onSecondaryAction: {
                        openTimeoutDelayPicker(for: .task, presetMinutes: taskTimeoutDelayMinutes)
                    }
                )

                Button {
                    if let message = viewModel.resolveExpiredTask(.abandon, now: countdownNow) {
                        showCommonTasksToast(message)
                    }
                } label: {
                    Text(L10n.tr("Remove task", zhHans: "删除任务", zhHant: "刪除任務"))
                        .font(.appSystem(size: scaled(17, pad: 20), weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private func boardTimeoutOverlay(for event: BingoViewModel.ExpiredBoardCountdownEvent) -> some View {
        ZStack {
            timeoutDialogBackdrop

            VStack(spacing: 20) {
                let overtimeSeconds = max(Int(countdownNow.timeIntervalSince(event.expiredAt)), 0)

                timeoutDialogCard(
                    headline: L10n.boardTimedOutHeadline(seconds: overtimeSeconds),
                    onClose: {
                        viewModel.expiredBoardCountdownEvent = nil
                    },
                    onPrimaryAction: {
                        if let message = viewModel.resolveExpiredBoardCountdown(.markAsCompleted, now: countdownNow) {
                            showCommonTasksToast(message)
                        }
                    },
                    onSecondaryAction: {
                        openTimeoutDelayPicker(for: .board, presetMinutes: boardTimeoutDelayMinutes)
                    }
                )

                Button {
                    if let message = viewModel.resolveExpiredBoardCountdown(.abandon, now: countdownNow) {
                        showCommonTasksToast(message)
                    }
                } label: {
                    Text(L10n.tr("Cancel countdown", zhHans: "取消倒计时", zhHant: "取消倒計時"))
                        .font(.appSystem(size: scaled(17, pad: 20), weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private func scheduledTaskReplacementOverlay(for event: BingoViewModel.ScheduledTaskReplacementEvent) -> some View {
        ZStack {
            timeoutDialogBackdrop

            VStack(spacing: 20) {
                scheduledTaskReplacementDialogCard(for: event)
            }
            .padding(.horizontal, 24)
        }
    }

    private var timeoutDialogBackdrop: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .blur(radius: 14)
            Color.black.opacity(0.62)
        }
        .ignoresSafeArea()
    }

    private func timeoutDialogCard(
        headline: String,
        onClose: @escaping () -> Void,
        onPrimaryAction: @escaping () -> Void,
        onSecondaryAction: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.appSystem(size: scaled(18, pad: 20), weight: .semibold))
                        .foregroundColor(Color.black.opacity(0.82))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            Image("ClockTimeout")
                .resizable()
                .scaledToFit()
                .frame(width: scaled(150, pad: 172), height: scaled(170, pad: 190))
                .padding(.top, -8)

            Text(headline)
                .font(.appSystem(size: scaled(20, pad: 24), weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.20, green: 0.14, blue: 0.09))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .minimumScaleFactor(0.75)
                .padding(.top, 8)
                .padding(.horizontal, 14)

            Button(action: onPrimaryAction) {
                Text(L10n.markAsCompleted)
                    .font(.appSystem(size: scaled(18, pad: 21), weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: scaled(56, pad: 62))
                    .background(
                        Capsule(style: .continuous)
                            .fill(NeumorphicColors.accent)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 36)

            Button(action: onSecondaryAction) {
                Text(L10n.tr("Task postpone", zhHans: "任务延期", zhHant: "任務延期"))
                    .font(.appSystem(size: scaled(18, pad: 21), weight: .semibold, design: .rounded))
                    .foregroundColor(Color(red: 0.20, green: 0.14, blue: 0.09))
                    .padding(.vertical, 26)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: isPadLayout ? 460 : 420)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.96, green: 0.95, blue: 0.94))
        )
    }

    private func scheduledTaskReplacementDialogCard(
        for event: BingoViewModel.ScheduledTaskReplacementEvent
    ) -> some View {
        let headline = L10n.tr(
            "A preset task is ready. Replace the current task in this tile?",
            zhHans: "预设任务已到时间，是否替换当前格子任务？",
            zhHant: "預設任務已到時間，是否替換目前格子任務？"
        )

        let detail = L10n.tr(
            "Current: \(event.currentTaskText)\nPreset: \(event.presetTaskText)",
            zhHans: "当前：\(event.currentTaskText)\n预设：\(event.presetTaskText)",
            zhHant: "目前：\(event.currentTaskText)\n預設：\(event.presetTaskText)"
        )

        return VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    viewModel.dismissScheduledTaskReplacementPrompt()
                } label: {
                    Image(systemName: "xmark")
                        .font(.appSystem(size: scaled(18, pad: 20), weight: .semibold))
                        .foregroundColor(Color.black.opacity(0.82))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            Image("ClockTimeout")
                .resizable()
                .scaledToFit()
                .frame(width: scaled(132, pad: 148), height: scaled(142, pad: 160))
                .padding(.top, -6)

            Text(headline)
                .font(.appSystem(size: scaled(20, pad: 24), weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.20, green: 0.14, blue: 0.09))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .minimumScaleFactor(0.75)
                .padding(.top, 8)
                .padding(.horizontal, 14)

            Text(detail)
                .font(.appSystem(size: scaled(15, pad: 17), weight: .medium, design: .rounded))
                .foregroundColor(Color.black.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 10)
                .padding(.horizontal, 14)

            Button {
                if let message = viewModel.resolveScheduledTaskReplacement(.replaceWithPreset, now: countdownNow) {
                    showCommonTasksToast(message)
                }
            } label: {
                Text(L10n.tr("Replace task", zhHans: "替换任务", zhHant: "替換任務"))
                    .font(.appSystem(size: scaled(18, pad: 21), weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: scaled(56, pad: 62))
                    .background(
                        Capsule(style: .continuous)
                            .fill(NeumorphicColors.accent)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 32)

            Button {
                if let message = viewModel.resolveScheduledTaskReplacement(.keepCurrentTask, now: countdownNow) {
                    showCommonTasksToast(message)
                }
            } label: {
                Text(L10n.tr("Keep current", zhHans: "保留当前", zhHant: "保留目前"))
                    .font(.appSystem(size: scaled(18, pad: 21), weight: .semibold, design: .rounded))
                    .foregroundColor(Color(red: 0.20, green: 0.14, blue: 0.09))
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: isPadLayout ? 460 : 420)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.96, green: 0.95, blue: 0.94))
        )
    }

    @ViewBuilder
    private var timeoutDelayPickerOverlay: some View {
        if timeoutDelayPickerContext != nil {
            ZStack(alignment: .bottom) {
                timeoutDialogBackdrop
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            timeoutDelayPickerContext = nil
                        }
                    }

                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button {
                            applyTimeoutDelayPickerSelection()
                        } label: {
                            Text(L10n.tr("Apply", zhHans: "应用", zhHant: "套用"))
                                .font(.appSystem(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(NeumorphicColors.accent)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                    HStack(spacing: 10) {
                        timeoutPickerColumn(
                            title: L10n.hours,
                            selection: $timeoutDelayPickerHours,
                            values: Array(0...24),
                            formatter: { L10n.hourValue($0) }
                        )

                        timeoutPickerColumn(
                            title: L10n.minutes,
                            selection: $timeoutDelayPickerMinutes,
                            values: Array(1...60),
                            formatter: { L10n.minuteValue($0) }
                        )
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 14)
                }
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(red: 0.96, green: 0.95, blue: 0.94))
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 0)
            }
        }
    }

    private func timeoutPickerColumn(
        title: String,
        selection: Binding<Int>,
        values: [Int],
        formatter: @escaping (Int) -> String
    ) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                .foregroundColor(Color.black.opacity(0.66))

            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text(formatter(value))
                        .foregroundColor(.black)
                        .tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.wheel)
            .frame(height: 90)
            .clipped()
            .tint(Color(red: 0.20, green: 0.14, blue: 0.09))
        }
        .frame(maxWidth: .infinity)
    }

    private func openTimeoutDelayPicker(for context: TimeoutDelayPickerContext, presetMinutes: Int) {
        let clamped = min(max(presetMinutes, 1), BingoViewModel.maxCountdownMinutes)
        if clamped <= 60 {
            timeoutDelayPickerHours = 0
            timeoutDelayPickerMinutes = clamped
        } else {
            let quotient = clamped / 60
            let remainder = clamped % 60
            if remainder == 0 {
                timeoutDelayPickerHours = max(quotient - 1, 0)
                timeoutDelayPickerMinutes = 60
            } else {
                timeoutDelayPickerHours = quotient
                timeoutDelayPickerMinutes = remainder
            }
        }
        timeoutDelayPickerContext = context
    }

    private func applyTimeoutDelayPickerSelection() {
        guard let context = timeoutDelayPickerContext else { return }
        var selectedMinutes = (timeoutDelayPickerHours * 60) + timeoutDelayPickerMinutes
        selectedMinutes = min(max(selectedMinutes, 1), BingoViewModel.maxCountdownMinutes)
        timeoutDelayPickerContext = nil
        let applyNow = Date()

        switch context {
        case .task:
            taskTimeoutDelayMinutes = selectedMinutes
            if let message = viewModel.resolveExpiredTask(.postpone(minutes: selectedMinutes), now: applyNow) {
                showCommonTasksToast(message)
            } else {
                showCommonTasksToast(L10n.tr("Postpone failed. Please try again.", zhHans: "延期失败，请重试", zhHant: "延期失敗，請重試"))
            }
        case .board:
            boardTimeoutDelayMinutes = selectedMinutes
            if let message = viewModel.resolveExpiredBoardCountdown(.postpone(minutes: selectedMinutes), now: applyNow) {
                showCommonTasksToast(message)
            } else {
                showCommonTasksToast(L10n.tr("Postpone failed. Please try again.", zhHans: "延期失败，请重试", zhHant: "延期失敗，請重試"))
            }
        }
    }

    private func conciseRaisedSurface(cornerRadius: CGFloat, shadowRadius: CGFloat, offset: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(conciseSurfaceColor)
            .shadow(color: Color.white.opacity(0.72), radius: shadowRadius, x: -offset, y: -offset)
            .shadow(color: NeumorphicColors.darkShadow.opacity(0.72), radius: shadowRadius, x: offset, y: offset)
    }

    private func conciseFlatSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(conciseSurfaceColor)
    }

    private func conciseOutlineSurface(cornerRadius: CGFloat, lineWidth: CGFloat = 1) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(conciseSurfaceColor)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(NeumorphicColors.accent.opacity(0.6), lineWidth: lineWidth)
            )
    }

    @ViewBuilder
    private var templateShareTrigger: some View {
        let buttonSize: CGFloat = isPadLayout ? 66 : 60

        if AppFeatureFlags.isTemplateSharingEnabled {
            Button {
                beginBoardTemplateShare()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.appSystem(size: isPadLayout ? 22 : 20, weight: .bold))
                    .foregroundColor(NeumorphicColors.accent)
                    .frame(width: buttonSize, height: buttonSize)
                    .background(
                        conciseRaisedSurface(
                            cornerRadius: buttonSize / 2,
                            shadowRadius: isPadLayout ? 11 : 9,
                            offset: isPadLayout ? 5 : 4
                        )
                    )
            }
            .buttonStyle(.plain)
            .disabled(isTemplateShareComposerPresented)
            .accessibilityLabel(L10n.shareBoardTemplate)
        } else {
            Color.clear
                .frame(width: buttonSize, height: buttonSize)
        }
    }

    private var editActionsTrigger: some View {
        let buttonSize: CGFloat = isPadLayout ? 66 : 60
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isEditActionsExpanded.toggle()
            }
        } label: {
            Image(systemName: isEditActionsExpanded ? "xmark" : "square.and.pencil")
                .font(.appSystem(size: isPadLayout ? 28 : 26, weight: .bold))
                .foregroundColor(NeumorphicColors.accent)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    conciseRaisedSurface(
                        cornerRadius: buttonSize / 2,
                        shadowRadius: isPadLayout ? 11 : 9,
                        offset: isPadLayout ? 5 : 4
                    )
                )
        }
        .buttonStyle(.plain)
        .frame(width: buttonSize, height: buttonSize, alignment: .bottomTrailing)
    }

    private var gridSizeAdjustmentSheet: some View {
        let controlSize: CGFloat = isPadLayout ? 56 : 50
        let iconSize: CGFloat = isPadLayout ? 24 : 22

        return GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                HStack(spacing: isPadLayout ? 20 : 16) {
                    Button {
                        withAnimation(.spring(response: 0.4)) {
                            viewModel.resizeGrid(to: viewModel.gridSize - 1)
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.appSystem(size: iconSize, weight: .bold))
                            .foregroundColor(NeumorphicColors.accent)
                            .frame(width: controlSize, height: controlSize)
                            .background(
                                conciseRaisedSurface(
                                    cornerRadius: controlSize / 2,
                                    shadowRadius: isPadLayout ? 10 : 8,
                                    offset: isPadLayout ? 5 : 4
                                )
                            )
                    }
                    .disabled(viewModel.gridSize <= 2)
                    .buttonStyle(.plain)
                    .opacity(viewModel.gridSize <= 2 ? 0.45 : 1)

                    Text("\(viewModel.gridSize) × \(viewModel.gridSize)")
                        .font(.appSystem(size: scaled(30, pad: 36), weight: .bold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                        .frame(minWidth: isPadLayout ? 140 : 120)
                        .multilineTextAlignment(.center)

                    Button {
                        withAnimation(.spring(response: 0.4)) {
                            resizeGridWithPremiumGate(
                                targetSize: viewModel.gridSize + 1,
                                source: "grid_size_sheet"
                            )
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.appSystem(size: iconSize, weight: .bold))
                            .foregroundColor(NeumorphicColors.accent)
                            .frame(width: controlSize, height: controlSize)
                            .background(
                                conciseRaisedSurface(
                                    cornerRadius: controlSize / 2,
                                    shadowRadius: isPadLayout ? 10 : 8,
                                    offset: isPadLayout ? 5 : 4
                                )
                            )
                    }
                    .disabled(viewModel.gridSize >= 5)
                    .buttonStyle(.plain)
                    .opacity(viewModel.gridSize >= 5 ? 0.45 : 1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: proxy.size.height * 0.42)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, isPadLayout ? 28 : 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NeumorphicColors.background)
    }

    private var editActionsFullscreenOverlay: some View {
        ZStack {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .blur(radius: 10)

                Color.black.opacity(0.6)
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isEditActionsExpanded = false
                }
            }

            VStack(spacing: isPadLayout ? 48 : 40) {
                editActionsTextButton(L10n.tr("Shuffle", zhHans: "随机排序")) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        viewModel.shuffleBoard()
                    }
                }

                editActionsTextButton(L10n.clearBoard) {
                    isClearBoardConfirmationPresented = true
                }

                editActionsTextButton(L10n.tr("Grid Size", zhHans: "格子大小")) {
                    isGridSizeSheetPresented = true
                }

                editActionsTextButton(L10n.quickEdit) {
                    isQuickEditPresented = true
                }

                editActionsTextButton(
                    L10n.cancel,
                    fontWeight: .semibold,
                    color: Color.white.opacity(0.55),
                    extraTopPadding: isPadLayout ? 14 : 8,
                    action: nil
                )
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func editActionsTextButton(
        _ title: String,
        fontWeight: Font.Weight = .bold,
        color: Color = .white,
        extraTopPadding: CGFloat = 0,
        action: (() -> Void)?
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isEditActionsExpanded = false
            }
            if let action {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    action()
                }
            }
        } label: {
            Text(title)
                .font(.appSystem(size: scaled(28, pad: 38), weight: fontWeight, design: .rounded))
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .padding(.top, extraTopPadding)
        }
        .buttonStyle(.plain)
    }

    private var quickEditTrigger: some View {
        return Button {
            isQuickEditPresented = true
        } label: {
            HStack(spacing: 10) {
                Text(L10n.quickEdit)
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)

                Image(systemName: "square.and.pencil")
                    .font(.appSystem(size: scaled(13, pad: 15), weight: .bold))
                    .foregroundColor(NeumorphicColors.accent)
            }
            .padding(.horizontal, isPadLayout ? 20 : 16)
            .frame(height: isPadLayout ? 42 : 36)
            .background(
                conciseRaisedSurface(
                    cornerRadius: isPadLayout ? 21 : 18,
                    shadowRadius: isPadLayout ? 12 : 10,
                    offset: isPadLayout ? 6 : 5
                )
            )
        }
        .buttonStyle(.plain)
    }

    private var blackBoxModeTrigger: some View {
        Button {
            isBlackBoxModePresented = true
        } label: {
            HStack(spacing: 10) {
                Text(L10n.blackBoxMode)
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)

                Image(systemName: "cube.fill")
                    .font(.appSystem(size: scaled(13, pad: 15), weight: .bold))
                    .foregroundColor(NeumorphicColors.accent)
            }
            .padding(.horizontal, isPadLayout ? 20 : 16)
            .frame(height: isPadLayout ? 42 : 36)
            .background(
                conciseRaisedSurface(
                    cornerRadius: isPadLayout ? 21 : 18,
                    shadowRadius: isPadLayout ? 12 : 10,
                    offset: isPadLayout ? 6 : 5
                )
            )
        }
        .buttonStyle(.plain)
    }

    private var boardCountdownTrigger: some View {
        Button {
            isBoardCountdownPresented = true
        } label: {
            HStack(spacing: 10) {
                Text(boardCountdownText ?? L10n.setBoardCountdown)
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(NeumorphicColors.text)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.appSystem(size: scaled(11, pad: 12), weight: .semibold))
                    .foregroundColor(NeumorphicColors.accent)
            }
            .padding(.horizontal, isPadLayout ? 20 : 16)
            .frame(height: isPadLayout ? 38 : 32)
            .frame(minWidth: isPadLayout ? 152 : 124)
            .background(
                conciseRaisedSurface(
                    cornerRadius: isPadLayout ? 19 : 16,
                    shadowRadius: isPadLayout ? 12 : 10,
                    offset: isPadLayout ? 6 : 5
                )
            )
        }
        .buttonStyle(.plain)
    }

    private var boardCompletionProgressView: some View {
        HStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(NeumorphicColors.background)
                        .neumorphicConcave(radius: 10)
                        .overlay(
                            Capsule()
                                .stroke(NeumorphicColors.lightShadow.opacity(0.34), lineWidth: 0.8)
                        )

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    NeumorphicColors.accent.opacity(0.88),
                                    NeumorphicColors.accent
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: filledTaskCount == 0 ? 14 : max(14, proxy.size.width * completionProgress))
                        .shadow(color: NeumorphicColors.accent.opacity(0.28), radius: 10, x: 0, y: 4)
                        .opacity(filledTaskCount == 0 ? 0.28 : 1)
                }
            }
            .frame(height: 12)

            Text("\(completedTaskCount)/\(filledTaskCount)")
                .font(.appSystem(size: scaled(13, pad: 15), weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(NeumorphicColors.accent)
        }
        .frame(height: 38)
        .frame(width: 180, alignment: .leading)
    }

private func boardSwitcherControls(contentWidth: CGFloat) -> some View {
    HStack(spacing: 10) {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(namedBoards) { board in
                    let isSelected = board.id == selectedBoardID

                    Button {
                        selectBoard(board.id)
                    } label: {
                        Text(board.name)
                            .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundColor(isSelected ? .white : NeumorphicColors.text)
                            .padding(.horizontal, 14)
                            .frame(height: isPadLayout ? 38 : 36)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isSelected ? NeumorphicColors.accent : NeumorphicColors.background)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(
                                        isSelected ? NeumorphicColors.accent : NeumorphicColors.accent.opacity(0.22),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in
                                beginBoardActions(for: board.id)
                            }
                    )
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Button {
            beginCreateBoard()
        } label: {
            Text(L10n.tr("+ add board", zhHans: "+ 添加棋盘", zhHant: "+ 新增棋盤"))
                .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: isPadLayout ? 38 : 36)
                .background(
                    RoundedRectangle(cornerRadius: isPadLayout ? 19 : 18, style: .continuous)
                        .fill(conciseSurfaceColor)
                        .shadow(color: Color.white.opacity(0.7), radius: isPadLayout ? 8 : 6, x: -4, y: -4)
                        .shadow(color: NeumorphicColors.darkShadow.opacity(0.22), radius: isPadLayout ? 8 : 6, x: 4, y: 4)
                )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }
    .frame(width: contentWidth, alignment: .leading)
}

private func beginBoardActions(for boardID: UUID) {
    focusedEditingResetForBoardActions()
    withAnimation(.easeInOut(duration: 0.2)) {
        boardActionSheetBoardID = boardID
    }
}

private func beginBoardRules(for boardID: UUID) {
    boardRulesTargetBoardID = boardID
    isBoardRulesPresented = true
}

private func templateImportSheetHeight(for gridSize: Int) -> CGFloat {
    switch gridSize {
    case ...3:
        return 540
    case 4:
        return 620
    default:
        return 700
    }
}

private func dismissBoardActions() {
    withAnimation(.easeInOut(duration: 0.2)) {
        boardActionSheetBoardID = nil
    }
}

private func focusedEditingResetForBoardActions() {
    isEditActionsExpanded = false
    selectedStickerID = nil
}

private func applyBoardRulesSettings(
    for boardID: UUID,
    countdownMinutes: Int?,
    resetMode: BoardTaskResetMode
) {
    guard let boardIndex = namedBoards.firstIndex(where: { $0.id == boardID }) else { return }
    let now = Date()
    let resolvedMinutes = countdownMinutes.map { min(max($0, 1), BingoViewModel.maxCountdownMinutes) }
    let countdownEndsAt = resolvedMinutes.map { now.addingTimeInterval(Double($0 * 60)) }

    namedBoards[boardIndex].taskResetMode = resetMode
    namedBoards[boardIndex].countdownEndsAt = countdownEndsAt
    // Start counting "next day reset" from when user saved board rules.
    namedBoards[boardIndex].lastTaskResetAppliedAt = now
    namedBoards[boardIndex].updatedAt = now

    if selectedBoardID == boardID {
        viewModel.setBoardCountdown(totalMinutes: resolvedMinutes)
        namedBoards[boardIndex].board = viewModel.makeSavedBoardSnapshot()
        namedBoards[boardIndex].countdownEndsAt = viewModel.boardCountdownEndsAt
    }

    persistNamedBoardsSnapshot()
    showCommonTasksToast(L10n.tr("Board rules saved", zhHans: "面板规则已保存", zhHant: "面板規則已儲存"))
}

private func handleBoardResetLifecycle(
    now: Date,
    force: Bool = false,
    source: String,
    shouldApplyForegroundCleanup: Bool = false
) {
    if shouldApplyForegroundCleanup {
        viewModel.applyForegroundCleanup()
    }

    let activeBoardID = selectedBoardID ?? namedBoards.first?.id
    // Capture countdown state before reset mutates namedBoards/viewModel snapshots.
    let didBoardCountdownExist = activeBoardID
        .flatMap { boardID in
            namedBoards.first(where: { $0.id == boardID })?.countdownEndsAt != nil
        } ?? false

    let result = evaluateBoardTaskResetRulesIfNeeded(
        now: now,
        force: force,
        source: source
    )

    guard result.didReset else { return }

    if let activeBoardID {
        if selectedBoardID == nil {
            selectedBoardID = activeBoardID
        }
        if let selectedBoard = namedBoards.first(where: { $0.id == activeBoardID }) {
            let beforeCompleted = viewModel.cells.flatMap(\.self).filter { $0.isCompleted && !$0.isEmpty }.count
            viewModel.applySavedBoardSnapshot(
                selectedBoard.board,
                countdownEndsAt: selectedBoard.countdownEndsAt,
                referenceDate: now
            )
            let afterCompleted = viewModel.cells.flatMap(\.self).filter { $0.isCompleted && !$0.isEmpty }.count
            debugBoardResetLog(
                "ui.refresh boardID=\(activeBoardID.uuidString) beforeCompleted=\(beforeCompleted) afterCompleted=\(afterCompleted)"
            )
        } else {
            debugBoardResetLog("ui.refresh skipped: missing active board after reset")
        }
    } else {
        debugBoardResetLog("ui.refresh skipped: no active board id")
    }

    viewModel.finalizePostResetState(
        now: now,
        didBoardCountdownExist: didBoardCountdownExist,
        clearedCompletedTaskCount: result.clearedCompletedTaskCount
    )
}

private func evaluateBoardTaskResetRulesIfNeeded(
    now: Date = .now,
    force: Bool = false,
    source: String = "unknown"
) -> BoardResetResult {
    debugBoardResetLog(
        "evaluate.enter source=\(source) force=\(force) day=\(PointsStore.dateKey(for: now)) " +
        "lastEval=\(lastBoardRulesEvaluationDateKey) boards=\(namedBoards.count) " +
        "simulateFlag=\(shouldSimulateNextDayBoardRuleResetInDebug) simulatedThisLaunch=\(hasAppliedDebugSimulatedResetThisLaunch)"
    )
    guard !namedBoards.isEmpty else {
        debugBoardResetToast("no boards")
        return .noReset
    }
    let dayKey = PointsStore.dateKey(for: now)
    if !force, dayKey == lastBoardRulesEvaluationDateKey {
        #if DEBUG
        if shouldSimulateNextDayBoardRuleResetInDebug,
           !hasAppliedDebugSimulatedResetThisLaunch {
            debugBoardResetToast("same-day gate -> trigger simulate")
            forceApplyBoardTaskResetRulesForDebug(now: now)
            return .noReset
        }
        #endif
        if source != "ticker" {
            debugBoardResetToast("skip by same-day gate (\(dayKey))")
        } else {
            debugBoardResetLog("evaluate.skip source=ticker same-day gate day=\(dayKey)")
        }
        return .noReset
    }
    debugBoardResetToast("evaluate day=\(dayKey), force=\(force)")
    lastBoardRulesEvaluationDateKey = dayKey
    return applyBoardTaskResetRules(now: now, source: source)
}

private func forceApplyBoardTaskResetRulesForDebug(now: Date) {
#if DEBUG
    guard shouldSimulateNextDayBoardRuleResetInDebug else {
        debugBoardResetLog("simulate.skip reason=flag_off")
        return
    }
    guard !hasAppliedDebugSimulatedResetThisLaunch else {
        debugBoardResetToast("simulate skipped: already applied in this launch")
        return
    }
    guard !namedBoards.isEmpty else {
        debugBoardResetToast("simulate skipped: no boards loaded")
        return
    }

    debugBoardResetToast("simulate next-day reset")
    hasAppliedDebugSimulatedResetThisLaunch = true
    let calendar = Calendar.current
    let simulatedPreviousDay = calendar.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86_400)

    if shouldPrepareStreakTestInDebug {
        let shiftedCount = backdateCompletionDatesForDebug(
            to: simulatedPreviousDay,
            referenceDate: now
        )
        debugBoardResetToast("simulate streak-ready shifted=\(shiftedCount)")
    }

    for index in namedBoards.indices {
        namedBoards[index].lastTaskResetAppliedAt = simulatedPreviousDay
    }

    // Clear daily gate so this simulated "next-day" pass is guaranteed to run now.
    lastBoardRulesEvaluationDateKey = ""
    handleBoardResetLifecycle(now: now, force: true, source: "simulate")
#else
    _ = now
#endif
}

private func backdateCompletionDatesForDebug(
    to simulatedPreviousDay: Date,
    referenceDate: Date
) -> Int {
#if DEBUG
    let maxGridSize = BingoViewModel.maxGridSize
    var shiftedCount = 0

    for index in namedBoards.indices {
        let board = namedBoards[index].board
        var fullBoard = expandedBoardCache(from: board, maxGridSize: maxGridSize)
        var didUpdateBoard = false

        for row in fullBoard.indices {
            for col in fullBoard[row].indices {
                guard fullBoard[row][col].hasStoredTask else { continue }
                let shouldBackdate =
                    fullBoard[row][col].isCompleted ||
                    fullBoard[row][col].completionStreakCount > 0 ||
                    fullBoard[row][col].lastCompletedAt != nil
                guard shouldBackdate else { continue }
                fullBoard[row][col].lastCompletedAt = simulatedPreviousDay
                shiftedCount += 1
                didUpdateBoard = true
            }
        }

        guard didUpdateBoard else { continue }
        let gridSize = min(max(board.gridSize, 2), maxGridSize)
        let visibleCells: [[BingoCell]] = (0..<gridSize).map { row in
            (0..<gridSize).map { col in
                fullBoard[row][col].projectedForDisplay(on: referenceDate)
            }
        }
        namedBoards[index].board = SavedBoard(
            gridSize: gridSize,
            cells: visibleCells,
            completedLines: board.completedLines,
            fullBoardCells: fullBoard
        )
    }

    return shiftedCount
#else
    _ = simulatedPreviousDay
    _ = referenceDate
    return 0
#endif
}

private func applyBoardTaskResetRules(now: Date, source: String) -> BoardResetResult {
    guard !namedBoards.isEmpty else { return .noReset }

    let calendar = Calendar.current
    let activeBoardID = selectedBoardID ?? namedBoards.first?.id
    var hasAnyUpdate = false
    var appliedCount = 0
    var skippedCount = 0
    var staleForceCount = 0
    var activeBoardClearedCompletedTaskCount = 0

    for index in namedBoards.indices {
        let board = namedBoards[index]
        let alreadyAppliedToday: Bool = {
            guard let lastApplied = board.lastTaskResetAppliedAt else { return false }
            return calendar.isDate(lastApplied, inSameDayAs: now)
        }()
        let shouldForceApplyForStaleCompletion =
            board.taskResetMode == .resetStatusNextDay &&
            boardHasStaleCompletedTasks(board, referenceDate: now, calendar: calendar)
        debugBoardResetLog(
            "apply.inspect source=\(source) board=\(index) mode=\(board.taskResetMode.rawValue) " +
            "alreadyAppliedToday=\(alreadyAppliedToday) staleForce=\(shouldForceApplyForStaleCompletion) " +
            "completedCount=\(completedTaskCount(in: board)) lastApplied=\(board.lastTaskResetAppliedAt?.description ?? "nil")"
        )

        if alreadyAppliedToday && !shouldForceApplyForStaleCompletion {
            skippedCount += 1
            continue
        }
        if shouldForceApplyForStaleCompletion {
            staleForceCount += 1
        }

        let clearedCompletedCount = completedTaskCount(in: board)
        let transformedBoard = transformedBoardSnapshotForResetMode(
            board.board,
            mode: board.taskResetMode,
            referenceDate: now
        )

        namedBoards[index].board = transformedBoard
        namedBoards[index].lastTaskResetAppliedAt = now
        namedBoards[index].updatedAt = now
        if board.id == activeBoardID {
            activeBoardClearedCompletedTaskCount = clearedCompletedCount
        }
        hasAnyUpdate = true
        appliedCount += 1

    }

    guard hasAnyUpdate else {
        debugBoardResetToast("no reset applied, skipped=\(skippedCount)")
        return .noReset
    }
    persistNamedBoardsSnapshot()
    debugBoardResetToast("reset applied=\(appliedCount), staleForce=\(staleForceCount), skipped=\(skippedCount)")
    return BoardResetResult(
        didReset: true,
        clearedCompletedTaskCount: activeBoardClearedCompletedTaskCount
    )
}

private func completedTaskCount(in board: BingoBoardStore.NamedBoard) -> Int {
    let fullBoard = expandedBoardCache(from: board.board, maxGridSize: BingoViewModel.maxGridSize)
    return fullBoard.flatMap(\.self).filter { $0.isCompleted && $0.hasStoredTask }.count
}

private func boardHasStaleCompletedTasks(
    _ board: BingoBoardStore.NamedBoard,
    referenceDate: Date,
    calendar: Calendar = .current
) -> Bool {
    let fullBoard = expandedBoardCache(from: board.board, maxGridSize: BingoViewModel.maxGridSize)

    for row in fullBoard {
        for cell in row {
            guard cell.isCompleted, cell.hasStoredTask else { continue }

            if let lastCompletedAt = cell.lastCompletedAt {
                if !calendar.isDate(lastCompletedAt, inSameDayAs: referenceDate) {
                    return true
                }
            } else if !calendar.isDate(board.updatedAt, inSameDayAs: referenceDate) {
                // Backward compatibility for older completions without lastCompletedAt.
                return true
            }
        }
    }

    return false
}

private func debugBoardResetToast(_ message: String) {
#if DEBUG
    debugBoardResetLog(message)
    guard shouldSimulateNextDayBoardRuleResetInDebug else { return }
    showCommonTasksToast("DEBUG reset: \(message)")
#else
    _ = message
#endif
}

private func debugBoardResetLog(_ message: String) {
#if DEBUG
    print("[BoardResetDebug] \(message)")
#else
    _ = message
#endif
}

private var isTileGestureDebugEnabled: Bool {
#if DEBUG
    ProcessInfo.processInfo.arguments.contains("-DebugTileGestures")
#else
    false
#endif
}

private func debugTileGestureBlockers(source: String) {
#if DEBUG
    guard isTileGestureDebugEnabled else { return }
    let blockers = [
        isSidebarPresented ? "sidebar" : nil,
        isEditActionsExpanded ? "quick_edit_overlay" : nil,
        firstStepGuideOverlay != nil ? "starter_guide" : nil,
        isUpdatePromptPresented ? "update_prompt" : nil,
        boardActionSheetBoardID != nil ? "board_action_sheet" : nil,
        viewModel.expiredTaskEvent != nil ? "task_timeout" : nil,
        viewModel.expiredBoardCountdownEvent != nil ? "board_timeout" : nil,
        viewModel.scheduledTaskReplacementEvent != nil ? "scheduled_replace" : nil,
        timeoutDelayPickerContext != nil ? "timeout_delay_picker" : nil,
        isTemplateImportPreviewPresented ? "template_import_preview" : nil,
        isBoardRulesPresented ? "board_rules_sheet" : nil,
        isBoardCountdownPresented ? "board_countdown_sheet" : nil,
        isGridSizeSheetPresented ? "grid_size_sheet" : nil
    ].compactMap { $0 }

    let summary = blockers.isEmpty ? "none" : blockers.joined(separator: ",")
    print("[TileGestureDebug][Overlay][\(source)] \(summary)")
#else
    _ = source
#endif
}

private func transformedBoardSnapshotForResetMode(
    _ board: SavedBoard,
    mode: BoardTaskResetMode,
    referenceDate: Date
) -> SavedBoard {
    let maxGridSize = BingoViewModel.maxGridSize
    var fullBoard: [[BingoCell]]

    switch mode {
    case .resetStatusNextDay:
        fullBoard = expandedBoardCache(from: board, maxGridSize: maxGridSize)
        let calendar = Calendar.current
        for row in fullBoard.indices {
            for col in fullBoard[row].indices {
                fullBoard[row][col] = normalizedBoardCellForNextDay(
                    fullBoard[row][col],
                    referenceDate: referenceDate,
                    calendar: calendar
                )
            }
        }
        for row in fullBoard.indices {
            for col in fullBoard[row].indices {
                guard !fullBoard[row][col].isEmpty else { continue }
                fullBoard[row][col].isCompleted = false
                fullBoard[row][col].isTaskHidden = false
                fullBoard[row][col].countdownEndsAt = nil
            }
        }
        normalizeForceFlagsForBoardReset(&fullBoard, referenceDate: referenceDate)
    case .clearTasksNextDay:
        fullBoard = uniqueEmptyGrid(size: maxGridSize)
    }

    let gridSize = min(max(board.gridSize, 2), maxGridSize)
    let visibleCells: [[BingoCell]] = (0..<gridSize).map { row in
        (0..<gridSize).map { col in
            fullBoard[row][col].projectedForDisplay(on: referenceDate)
        }
    }

    return SavedBoard(
        gridSize: gridSize,
        cells: visibleCells,
        completedLines: [],
        fullBoardCells: fullBoard
    )
}

private func normalizedBoardCellForNextDay(
    _ cell: BingoCell,
    referenceDate: Date,
    calendar: Calendar = .current
) -> BingoCell {
    var updated = cell

    // Keep force flag across days unless the task is currently completed.
    // Historical completion timestamp should not consume force mode.
    if updated.isForced, updated.isCompleted {
        updated.isForced = false
    }

    if updated.isOneTimeTask,
       let oneTimeVisibleDate = updated.oneTimeVisibleDate,
       !calendar.isDate(oneTimeVisibleDate, inSameDayAs: referenceDate) {
        updated.text = ""
        updated.residentTaskText = nil
        updated.residentWeekdays = []
        updated.oneTimeVisibleDate = nil
        updated.isTaskHidden = false
        updated.isForced = false
        updated.countdownEndsAt = nil
        updated.completionStreakCount = 0
        updated.lastCompletedAt = nil
        updated.isCompleted = false
    }

    return updated
}

private func normalizeForceFlagsForBoardReset(
    _ fullBoard: inout [[BingoCell]],
    referenceDate: Date
) {
    var forcedPositions: [(row: Int, col: Int)] = []

    for row in fullBoard.indices {
        for col in fullBoard[row].indices {
            guard fullBoard[row][col].isForced else { continue }

            if !fullBoard[row][col].hasStoredTask || fullBoard[row][col].isCompleted {
                fullBoard[row][col].isForced = false
                continue
            }

            forcedPositions.append((row, col))
        }
    }

    guard forcedPositions.count > 1 else { return }

    let keepPosition = forcedPositions.first {
        let projected = fullBoard[$0.row][$0.col].projectedForDisplay(on: referenceDate)
        return !projected.isEmpty
    } ?? forcedPositions[0]

    for position in forcedPositions where !(position.row == keepPosition.row && position.col == keepPosition.col) {
        fullBoard[position.row][position.col].isForced = false
    }
}

private func expandedBoardCache(from board: SavedBoard, maxGridSize: Int) -> [[BingoCell]] {
    var expanded = uniqueEmptyGrid(size: maxGridSize)

    if let fullBoardCells = board.fullBoardCells, !fullBoardCells.isEmpty {
        for row in 0..<min(fullBoardCells.count, maxGridSize) {
            for col in 0..<min(fullBoardCells[row].count, maxGridSize) {
                expanded[row][col] = fullBoardCells[row][col]
            }
        }
        return expanded
    }

    for row in 0..<min(board.cells.count, maxGridSize) {
        for col in 0..<min(board.cells[row].count, maxGridSize) {
            expanded[row][col] = board.cells[row][col]
        }
    }

    return expanded
}

private func uniqueEmptyGrid(size: Int) -> [[BingoCell]] {
    (0..<size).map { _ in
        (0..<size).map { _ in BingoCell() }
    }
}

private func boardName(for boardID: UUID) -> String {
    guard let board = namedBoards.first(where: { $0.id == boardID }) else {
        return L10n.boardDefaultName(1)
    }
    return board.name
}

private func requestDeleteBoard(_ boardID: UUID) {
    guard canDeleteBoardFromActions(boardID) else {
        showCommonTasksToast(boardDeleteBlockedMessage(for: boardID))
        return
    }

    pendingBoardDeleteID = boardID
    isBoardDeleteAlertPresented = true
}

private func canDeleteBoardFromActions(_ boardID: UUID) -> Bool {
    guard namedBoards.count > 1 else { return false }

    if !subscriptionManager.hasPremiumAccess,
       let firstBoardID = namedBoards.first?.id,
       boardID == firstBoardID {
        return false
    }

    return true
}

private func boardDeleteBlockedMessage(for boardID: UUID) -> String {
    if namedBoards.count <= 1 {
        return L10n.tr(
            "At least one board must remain.",
            zhHans: "至少需要保留一个棋盘。",
            zhHant: "至少需要保留一個棋盤。"
        )
    }

    if !subscriptionManager.hasPremiumAccess,
       let firstBoardID = namedBoards.first?.id,
       boardID == firstBoardID {
        return L10n.tr(
            "On Free plan, Board 1 cannot be deleted.",
            zhHans: "非会员模式下，Board 1 不能删除。",
            zhHant: "非會員模式下，Board 1 不能刪除。"
        )
    }

    return L10n.tr(
        "This board cannot be deleted right now.",
        zhHans: "当前无法删除该棋盘。",
        zhHant: "目前無法刪除該棋盤。"
    )
}

private func deleteBoard(_ boardID: UUID) {
    defer {
        pendingBoardDeleteID = nil
    }

    guard canDeleteBoardFromActions(boardID),
          let removeIndex = namedBoards.firstIndex(where: { $0.id == boardID }) else {
        return
    }

    var nextSelectedID = selectedBoardID
    if selectedBoardID == boardID {
        let fallbackIndex = removeIndex == 0 ? 1 : removeIndex - 1
        nextSelectedID = namedBoards.indices.contains(fallbackIndex) ? namedBoards[fallbackIndex].id : nil
    }

    namedBoards.remove(at: removeIndex)

    if let nextSelectedID,
       let selectedBoard = namedBoards.first(where: { $0.id == nextSelectedID }) {
        selectedBoardID = nextSelectedID
        viewModel.applySavedBoardSnapshot(
            selectedBoard.board,
            countdownEndsAt: selectedBoard.countdownEndsAt,
            referenceDate: .now
        )
    } else if let firstBoard = namedBoards.first {
        selectedBoardID = firstBoard.id
        viewModel.applySavedBoardSnapshot(
            firstBoard.board,
            countdownEndsAt: firstBoard.countdownEndsAt,
            referenceDate: .now
        )
    } else {
        selectedBoardID = nil
    }

    persistNamedBoardsSnapshot()
    showCommonTasksToast(L10n.tr("Board deleted", zhHans: "棋盘已删除", zhHant: "棋盤已刪除"))
}


private var pendingBoardDeleteMessage: String {
    let targetBoardName = pendingBoardDeleteID.flatMap { boardName(for: $0) } ?? ""
    return L10n.tr(
        "This will permanently delete \"\(targetBoardName)\" and its progress.",
        zhHans: "将永久删除「\(targetBoardName)」及其进度。",
        zhHant: "將永久刪除「\(targetBoardName)」及其進度。"
    )
}

@ViewBuilder
private func boardActionLayer(contentWidth: CGFloat, bottomInset: CGFloat) -> some View {
    if let boardActionSheetBoardID,
       let board = namedBoards.first(where: { $0.id == boardActionSheetBoardID }) {
        boardActionsOverlay(
            for: board,
            contentWidth: contentWidth,
            bottomInset: bottomInset
        )
        .transition(.opacity)
    }
}

private func boardActionsOverlay(
    for board: BingoBoardStore.NamedBoard,
    contentWidth: CGFloat,
    bottomInset: CGFloat
) -> some View {
    let canDelete = canDeleteBoardFromActions(board.id)

    return ZStack(alignment: .bottom) {
        Color.black.opacity(0.42)
            .ignoresSafeArea()
            .onTapGesture {
                dismissBoardActions()
            }

        VStack(spacing: 12) {
            Button {
                dismissBoardActions()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    beginBoardRules(for: board.id)
                }
            } label: {
                Text(L10n.tr("Board Rules", zhHans: "面板规则", zhHant: "面板規則"))
                    .font(.appSystem(size: scaled(16, pad: 18), weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(NeumorphicColors.background)
                    )
            }
            .buttonStyle(.plain)

            Button {
                dismissBoardActions()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    beginRenameBoard(board.id)
                }
            } label: {
                Text(L10n.tr("Edit", zhHans: "编辑", zhHant: "編輯"))
                    .font(.appSystem(size: scaled(16, pad: 18), weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(NeumorphicColors.background)
                    )
            }
            .buttonStyle(.plain)

            if canDelete {
                Button {
                    dismissBoardActions()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        requestDeleteBoard(board.id)
                    }
                } label: {
                    Text(L10n.deleteConfirmationTitle)
                        .font(.appSystem(size: scaled(16, pad: 18), weight: .semibold, design: .rounded))
                        .foregroundColor(Color.red.opacity(0.84))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(NeumorphicColors.background)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: min(contentWidth, isPadLayout ? 460 : 353))
        .padding(.bottom, max(bottomInset, 14) + 12)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
}

private func ensureBoardSwitcherLoaded() {


        guard !hasLoadedBoardSwitcherState else { return }
        hasLoadedBoardSwitcherState = true

        var snapshot = BingoBoardStore.loadNamedBoardsSnapshot()

        if snapshot.boards.isEmpty {
            let initialBoard = BingoBoardStore.NamedBoard(
                name: L10n.boardDefaultName(1),
                board: viewModel.makeSavedBoardSnapshot(),
                countdownEndsAt: viewModel.boardCountdownEndsAt,
                updatedAt: .now
            )
            snapshot = BingoBoardStore.NamedBoardsSnapshot(
                selectedBoardID: initialBoard.id,
                boards: [initialBoard]
            )
            BingoBoardStore.saveNamedBoardsSnapshot(snapshot)
        }

        namedBoards = snapshot.boards
        selectedBoardID = snapshot.selectedBoardID ?? snapshot.boards.first?.id

        if let selectedBoardID,
           let selectedBoard = namedBoards.first(where: { $0.id == selectedBoardID }) {
            viewModel.applySavedBoardSnapshot(
                selectedBoard.board,
                countdownEndsAt: selectedBoard.countdownEndsAt,
                referenceDate: .now
            )
            syncSelectedBoardSnapshotIfNeeded()
        }
    }

    private func persistNamedBoardsSnapshot() {
        let snapshot = BingoBoardStore.NamedBoardsSnapshot(
            selectedBoardID: selectedBoardID,
            boards: namedBoards
        )
        BingoBoardStore.saveNamedBoardsSnapshot(snapshot)
    }

    private func persistBoardState(for boardID: UUID, save: Bool = true) {
        guard let boardIndex = namedBoards.firstIndex(where: { $0.id == boardID }) else { return }
        namedBoards[boardIndex].board = viewModel.makeSavedBoardSnapshot()
        namedBoards[boardIndex].countdownEndsAt = viewModel.boardCountdownEndsAt
        namedBoards[boardIndex].updatedAt = .now
        if save {
            persistNamedBoardsSnapshot()
        }
    }

    private func syncSelectedBoardSnapshotIfNeeded() {
        guard hasLoadedBoardSwitcherState, let selectedBoardID else { return }
        persistBoardState(for: selectedBoardID)
    }

    private func selectBoard(_ boardID: UUID) {
        guard selectedBoardID != boardID else { return }

        if let previousBoardID = selectedBoardID {
            persistBoardState(for: previousBoardID, save: false)
        }

        selectedBoardID = boardID

        if let selectedBoard = namedBoards.first(where: { $0.id == boardID }) {
            viewModel.applySavedBoardSnapshot(
                selectedBoard.board,
                countdownEndsAt: selectedBoard.countdownEndsAt,
                referenceDate: .now
            )
        }

        persistNamedBoardsSnapshot()
    }

    private func beginCreateBoard() {
        guard canCreateAdditionalBoard else {
            AnalyticsService.logPremiumBoardsLimitHit(currentBoardCount: namedBoards.count)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                presentPremiumPaywall(source: "boards_limit")
            }
            return
        }

        createBoardNameDraft = L10n.boardDefaultName(namedBoards.count + 1)
        isCreateBoardAlertPresented = true
    }

    private func createBoard() {
        guard canCreateAdditionalBoard else {
            AnalyticsService.logPremiumBoardsLimitHit(currentBoardCount: namedBoards.count)
            return
        }

        if let selectedBoardID {
            persistBoardState(for: selectedBoardID, save: false)
        }

        let fallbackName = L10n.boardDefaultName(namedBoards.count + 1)
        let boardName = sanitizedBoardName(createBoardNameDraft, fallback: fallbackName)
        let newBoard = BingoBoardStore.NamedBoard(
            name: boardName,
            board: BingoViewModel.createDefaultSavedBoard(),
            countdownEndsAt: nil,
            updatedAt: .now
        )

        namedBoards.append(newBoard)
        selectedBoardID = newBoard.id
        viewModel.applySavedBoardSnapshot(
            newBoard.board,
            countdownEndsAt: nil,
            referenceDate: .now
        )
        createBoardNameDraft = ""
        persistNamedBoardsSnapshot()
    }

    private func beginBoardTemplateShare() {
        guard AppFeatureFlags.isTemplateSharingEnabled else { return }
        guard !isTemplateShareComposerPresented else { return }
        guard let template = makeCurrentBoardTemplate() else {
            showCommonTasksToast(L10n.templateShareEmptyBoard)
            return
        }
        AnalyticsService.logTemplateShareOpen(
            source: "board_header",
            gridSize: template.gridSize,
            isPremium: subscriptionManager.hasPremiumAccess
        )
        boardTemplateShareDraft = template
        isTemplateShareComposerPresented = true
    }

    private func beginBoardTemplateImport() {
        guard AppFeatureFlags.isTemplateSharingEnabled else { return }
        if let clipboardText = UIPasteboard.general.string,
           resolveTemplateImport(from: clipboardText, showsErrorToast: false) {
            return
        }
        showCommonTasksToast(L10n.templateImportInvalidLink)
    }

    @discardableResult
    private func resolveTemplateImport(from rawText: String, showsErrorToast: Bool = true) -> Bool {
        guard let template = parseBoardTemplate(from: rawText) else {
            if showsErrorToast {
                showCommonTasksToast(L10n.templateImportInvalidLink)
            }
            return false
        }
        presentImportPreview(template: template)
        boardTemplateImportCoordinator.dismissPendingTemplate()
        return true
    }

    private func presentImportPreview(template: BoardTemplatePayload) {
        presentImportPreview(template: template, source: "pasteboard")
    }

    private func presentImportPreview(template: BoardTemplatePayload, source: String) {
        // Delay one run loop when switching between two sheets to avoid presentation races.
        DispatchQueue.main.async {
            templateImportPageOpenSource = source
            AnalyticsService.logTemplateImportPageOpen(
                source: source,
                gridSize: template.gridSize,
                createsNewBoard: shouldImportTemplateAsNewBoard
            )
            boardTemplateImportPreviewDraft = template
            isTemplateImportPreviewPresented = true
        }
    }

    private func parseBoardTemplate(from rawText: String) -> BoardTemplatePayload? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let directURL = URL(string: trimmed),
           let template = BoardTemplatePayload.decode(from: directURL) {
            return template
        }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let matches = detector.matches(
            in: rawText,
            options: [],
            range: NSRange(location: 0, length: rawText.utf16.count)
        )

        for match in matches {
            guard let url = match.url else { continue }
            if let template = BoardTemplatePayload.decode(from: url) {
                return template
            }
        }
        return nil
    }

    private func makeCurrentBoardTemplate() -> BoardTemplatePayload? {
        let visibleCells = viewModel.cells
        let template = BoardTemplatePayload(
            title: selectedBoardName,
            gridSize: viewModel.gridSize,
            cells: visibleCells
        )
        return template.hasShareableContent ? template : nil
    }

    private func applyImportedTemplate(_ template: BoardTemplatePayload) {
        Task { @MainActor in
            await subscriptionManager.refreshEntitlements()
            applyImportedTemplateResolved(template, createsNewBoard: shouldImportTemplateAsNewBoard)
        }
    }

    private func applyImportedTemplateResolved(_ template: BoardTemplatePayload, createsNewBoard: Bool) {
        if template.gridSize >= 5 && !subscriptionManager.hasPremiumAccess {
            AnalyticsService.logPremiumGrid5x5LimitHit(
                currentGridSize: viewModel.gridSize,
                source: "template_import"
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                presentPremiumPaywall(source: "template_import")
            }
            isTemplateImportPreviewPresented = false
            boardTemplateImportCoordinator.dismissPendingTemplate()
            return
        }

        let savedBoard = template.makeSavedBoard(referenceDate: .now)
        let fallbackName = L10n.boardDefaultName(namedBoards.count + 1)
        let boardName = sanitizedBoardName(template.normalizedTitle, fallback: fallbackName)

        if createsNewBoard {
            if let selectedBoardID {
                persistBoardState(for: selectedBoardID, save: false)
            }

            let importedBoard = BingoBoardStore.NamedBoard(
                name: boardName,
                board: savedBoard,
                countdownEndsAt: nil,
                updatedAt: .now
            )
            namedBoards.append(importedBoard)
            selectedBoardID = importedBoard.id
            viewModel.applySavedBoardSnapshot(
                importedBoard.board,
                countdownEndsAt: nil,
                referenceDate: .now
            )
            persistNamedBoardsSnapshot()
            isTemplateImportPreviewPresented = false
            boardTemplateImportCoordinator.dismissPendingTemplate()
            AnalyticsService.logTemplateImportSuccess(
                source: templateImportPageOpenSource,
                gridSize: template.gridSize,
                createsNewBoard: createsNewBoard
            )
            showCommonTasksToast(L10n.templateImportSuccessCreated)
            return
        }

        guard let targetBoardID = selectedBoardID ?? namedBoards.first?.id,
              let boardIndex = namedBoards.firstIndex(where: { $0.id == targetBoardID }) else {
            return
        }

        namedBoards[boardIndex].name = boardName
        namedBoards[boardIndex].board = savedBoard
        namedBoards[boardIndex].countdownEndsAt = nil
        namedBoards[boardIndex].updatedAt = .now
        selectedBoardID = targetBoardID
        viewModel.applySavedBoardSnapshot(
            savedBoard,
            countdownEndsAt: nil,
            referenceDate: .now
        )
        persistNamedBoardsSnapshot()
        isTemplateImportPreviewPresented = false
        boardTemplateImportCoordinator.dismissPendingTemplate()
        AnalyticsService.logTemplateImportSuccess(
            source: templateImportPageOpenSource,
            gridSize: template.gridSize,
            createsNewBoard: createsNewBoard
        )
        showCommonTasksToast(L10n.templateImportSuccessReplaced)
    }

    private func beginRenameSelectedBoard() {
        guard let selectedNamedBoardIndex else { return }
        let board = namedBoards[selectedNamedBoardIndex]
        boardPendingRenameID = board.id
        renameBoardNameDraft = board.name
        isRenameBoardAlertPresented = true
    }

    private func beginRenameBoard(_ boardID: UUID) {
        guard let board = namedBoards.first(where: { $0.id == boardID }) else { return }
        boardPendingRenameID = boardID
        renameBoardNameDraft = board.name
        isRenameBoardAlertPresented = true
    }

    private func renameBoard() {
        defer {
            renameBoardNameDraft = ""
            boardPendingRenameID = nil
        }

        guard let boardPendingRenameID,
              let boardIndex = namedBoards.firstIndex(where: { $0.id == boardPendingRenameID }) else {
            return
        }

        let fallbackName = L10n.boardDefaultName(boardIndex + 1)
        namedBoards[boardIndex].name = sanitizedBoardName(renameBoardNameDraft, fallback: fallbackName)
        namedBoards[boardIndex].updatedAt = .now
        persistNamedBoardsSnapshot()
    }

    private func sanitizedBoardName(_ rawName: String, fallback: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(trimmed.prefix(boardNameMaxLength))
        return limited.isEmpty ? fallback : limited
    }

    private var boardCountdownText: String? {
        guard let endsAt = viewModel.boardCountdownEndsAt, endsAt > countdownNow else {
            return nil
        }

        let remainingSeconds = max(Int(endsAt.timeIntervalSince(countdownNow)), 0)
        let hours = min(remainingSeconds / 3600, 99)
        let minutes = (remainingSeconds % 3600) / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func homeStickerLayer(canvasSize: CGSize, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        ZStack {
            if selectedStickerID != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            selectedStickerID = nil
                        }
                    }
            }

            ForEach(homeStickerPlacements) { placement in
                EditableHomeStickerView(
                    placement: placement,
                    canvasSize: canvasSize,
                    isEditing: selectedStickerID == placement.id,
                    onSelect: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            selectedStickerID = placement.id
                        }
                    },
                    onUpdate: { updatedPlacement in
                        updateStickerPlacement(updatedPlacement)
                    },
                    onDelete: {
                        deleteStickerPlacement(id: placement.id)
                    }
                )
            }
        }
    }

    private var headerView: some View {
        let iconSize: CGFloat = isPadLayout ? 52 : 48

        return HStack {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    isSidebarPresented.toggle()
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.appSystem(size: scaled(20, pad: 23), weight: .semibold))
                    .foregroundColor(NeumorphicColors.accent)
                    .frame(width: iconSize, height: iconSize)
                    .background(
                        conciseFlatSurface(cornerRadius: iconSize / 2)
                    )
            }
            .buttonStyle(.plain)
            .offset(y: -20)

            Spacer()

            ZStack(alignment: .topTrailing) {
                Button {
                    isPointsDetailsPresented = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .font(.appSystem(size: scaled(20, pad: 22), weight: .semibold))
                            .foregroundColor(NeumorphicColors.accent)
                            .symbolEffect(.bounce, value: pointsAnimationTrigger)

                        Text("\(availablePoints)")
                            .font(.appSystem(size: scaled(18, pad: 20), weight: .medium, design: .rounded))
                            .foregroundColor(NeumorphicColors.text)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: availablePoints)
                    }
                    .padding(.horizontal, isPadLayout ? 22 : 20)
                    .frame(height: isPadLayout ? 52 : 48)
                    .background(
                        conciseFlatSurface(cornerRadius: isPadLayout ? 26 : 24)
                    )
                }
                .buttonStyle(.plain)
                .offset(y: -20)

                if let floatingPointsDelta {
                    Text(floatingPointsDelta > 0 ? "+\(floatingPointsDelta)" : "\(floatingPointsDelta)")
                        .font(.appSystem(size: scaled(13, pad: 15), weight: .bold, design: .rounded))
                        .foregroundColor(floatingPointsDelta > 0 ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.72))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(NeumorphicColors.background.opacity(0.96))
                                .shadow(color: NeumorphicColors.darkShadow.opacity(0.16), radius: 5, x: 2, y: 2)
                                .shadow(color: Color.white.opacity(0.72), radius: 4, x: -2, y: -2)
                        )
                        .offset(x: -4, y: isFloatingPointsDeltaVisible ? -30 : -8)
                        .opacity(isFloatingPointsDeltaVisible ? 1 : 0)
                }
            }
        }
    }

    private func boardMainContent(contentWidth: CGFloat, usesPadLayout: Bool) -> some View {
        VStack(spacing: 16) {
            boardSwitcherControls(contentWidth: contentWidth)
                .padding(.top, 14)

            BingoBoardView(
                viewModel: viewModel,
                currentTime: countdownNow,
                shouldShowCenterLongPressHint: firstStepGuideState == .finished,
                onCellCompletionToggled: {
                    reconcileStickerOwnershipIfPointsInsufficient()
                }
            )
                .frame(width: contentWidth, height: contentWidth)
                .padding(.top, 8)

            HStack(alignment: .center, spacing: 12) {
                templateShareTrigger
                Spacer(minLength: 0)
                if boardCountdownText != nil {
                    boardCountdownTrigger
                        .offset(y: isPadLayout ? 4 : 3)
                } else {
                    Color.clear
                        .frame(width: isPadLayout ? 170 : 140, height: isPadLayout ? 38 : 32)
                }
                Spacer(minLength: 0)
                editActionsTrigger
            }
            .padding(.top, 10)
        }
        .frame(width: contentWidth)
        .padding(.top, 32)
        .offset(y: usesPadLayout ? -35 : 0)
    }

    private func sidebarView(width: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        let sidebarShape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 28,
            topTrailingRadius: 28,
            style: .continuous
        )

        return VStack(alignment: .leading, spacing: 0) {
            List {
                Section {
                    sidebarStreakHero
                    sidebarStreakGoals

                    Button {
                        isSidebarPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            isDiaryPresented = true
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "calendar")
                                .font(.appSystem(size: scaled(18, pad: 20), weight: .bold))
                                .foregroundColor(NeumorphicColors.accent)
                                .frame(width: isPadLayout ? 44 : 40, height: isPadLayout ? 44 : 40)
                                .neumorphicConvex(radius: isPadLayout ? 22 : 20)

                            Text(L10n.bingoDiary)
                                .font(.appSystem(size: scaled(15, pad: 18), weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.appSystem(size: scaled(14, pad: 16), weight: .bold))
                                .foregroundColor(NeumorphicColors.text.opacity(0.42))
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    Button {
                        isSidebarPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isBlackBoxModePresented = true
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "gamecontroller.fill")
                                .font(.appSystem(size: scaled(18, pad: 20), weight: .bold))
                                .foregroundColor(NeumorphicColors.accent)
                                .frame(width: isPadLayout ? 44 : 40, height: isPadLayout ? 44 : 40)
                                .neumorphicConvex(radius: isPadLayout ? 22 : 20)

                            Text(L10n.tr("2048", zhHans: "2048", zhHant: "2048"))
                                .font(.appSystem(size: scaled(15, pad: 18), weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.appSystem(size: scaled(14, pad: 16), weight: .bold))
                                .foregroundColor(NeumorphicColors.text.opacity(0.42))
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    Button {
                        isSidebarPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            isContactUsPresented = true
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "envelope")
                                .font(.appSystem(size: scaled(18, pad: 20), weight: .bold))
                                .foregroundColor(NeumorphicColors.accent)
                                .frame(width: isPadLayout ? 44 : 40, height: isPadLayout ? 44 : 40)
                                .neumorphicConvex(radius: isPadLayout ? 22 : 20)

                            Text(L10n.contactUs)
                                .font(.appSystem(size: scaled(15, pad: 18), weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.appSystem(size: scaled(14, pad: 16), weight: .bold))
                                .foregroundColor(NeumorphicColors.text.opacity(0.42))
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            isSettingsExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "gearshape")
                                .font(.appSystem(size: scaled(18, pad: 20), weight: .bold))
                                .foregroundColor(NeumorphicColors.accent)
                                .frame(width: isPadLayout ? 44 : 40, height: isPadLayout ? 44 : 40)
                                .neumorphicConvex(radius: isPadLayout ? 22 : 20)

                            Text(L10n.setting)
                                .font(.appSystem(size: scaled(15, pad: 18), weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)

                            Spacer()

                            Image(systemName: "chevron.down")
                                .font(.appSystem(size: scaled(14, pad: 16), weight: .bold))
                                .foregroundColor(NeumorphicColors.text.opacity(0.42))
                                .rotationEffect(.degrees(isSettingsExpanded ? 0 : -90))
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    sidebarProEntryRow

                    if isSettingsExpanded {
                        sidebarToggleRow(title: L10n.haptics, isOn: $isHapticsEnabled)
                            .padding(.top, 6)

                        sidebarToggleRow(title: L10n.soundEffects, isOn: $isSoundEffectsEnabled)

                        widgetGuideRow

                        if isWidgetGuideExpanded {
                            widgetGuideTextRow
                        }

                        themePickerTriggerRow

                        if isThemePickerExpanded {
                            themePickerRow
                        }

#if DEBUG
                        pricingDebugInfoRow
#endif

                        if AppFeatureFlags.isAccountEnabled, let profile = accountSession.profile {
                            sidebarAccountSection(profile: profile)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .environment(\.defaultMinListRowHeight, 72)
            .padding(.top, max(topInset, 22))
            .padding(.bottom, max(bottomInset, 12))
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background {
            sidebarShape
                .fill(NeumorphicColors.background)
                .shadow(color: NeumorphicColors.darkShadow.opacity(0.75), radius: 14, x: 10, y: 0)
                .shadow(color: NeumorphicColors.lightShadow.opacity(0.8), radius: 8, x: -2, y: 0)
        }
        .overlay {
            sidebarShape
                .stroke(NeumorphicColors.background.opacity(0.95), lineWidth: 1.5)
        }
        .clipShape(sidebarShape)
        .overlay(alignment: .bottomLeading) {
            Text("v\(appShortVersion)")
                .font(.appSystem(size: scaled(12, pad: 13), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.35))
                .padding(.leading, 22)
                .padding(.bottom, max(bottomInset, 12) + 8)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 18, coordinateSpace: .local)
                .onEnded { value in
                    guard isSidebarPresented else { return }
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard abs(horizontal) > abs(vertical) else { return }
                    let dismissThreshold: CGFloat = isPadLayout ? 72 : 54
                    guard horizontal <= -dismissThreshold else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        isSidebarPresented = false
                    }
                }
        )
        .ignoresSafeArea(edges: .vertical)
    }

    private func sidebarRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.appSystem(size: 18, weight: .bold))
                .foregroundColor(NeumorphicColors.accent)
                .frame(width: 40, height: 40)
                .neumorphicConvex(radius: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)

                Text(value)
                    .font(.appSystem(size: scaled(16, pad: 18), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.78))
            }

            Spacer()
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var sidebarStreakHero: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(bingoStreakDays)")
                    .font(.appSystem(size: scaled(40, pad: 52), weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                activeThemeColor.opacity(0.72),
                                activeThemeColor
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.top, 10)

                Text(L10n.dayStreak)
                    .font(.appSystem(size: scaled(16, pad: 19), weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
            }

            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .fill(activeThemeColor.opacity(0.24))
                    .frame(width: 64, height: 64)
                    .blur(radius: 8)

                Image(systemName: "flame.fill")
                    .font(.appSystem(size: scaled(44, pad: 54), weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                activeThemeColor.opacity(0.42),
                                activeThemeColor.opacity(0.76),
                                activeThemeColor
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: activeThemeColor.opacity(0.34), radius: 10, x: 0, y: 6)
            }
            .frame(width: isPadLayout ? 90 : 78, height: isPadLayout ? 90 : 78)
        }
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets(top: 18, leading: 22, bottom: 10, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var sidebarStreakGoals: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.streakGoals)
                .font(.appSystem(size: scaled(15, pad: 18), weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            HStack(alignment: .center, spacing: 8) {
                ForEach(Array(streakGoals.enumerated()), id: \.offset) { index, goal in
                    streakGoalNode(goal: goal, previousGoal: index == 0 ? 0 : streakGoals[index - 1])

                    if index < streakGoals.count - 1 {
                        streakConnector(
                            from: goal,
                            to: streakGoals[index + 1]
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 10)
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(NeumorphicColors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(activeThemeColor.opacity(0.5), lineWidth: 1)
                )
        )
        .listRowInsets(EdgeInsets(top: 6, leading: 22, bottom: 14, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func streakConnector(from startGoal: Int, to endGoal: Int) -> some View {
        let fillProgress = streakConnectorProgress(from: startGoal, to: endGoal)

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(NeumorphicColors.darkShadow.opacity(0.22))
                .frame(height: 8)

            GeometryReader { geo in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                activeThemeColor.opacity(0.45),
                                activeThemeColor
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 8)
                    .frame(width: geo.size.width * fillProgress)
            }
        }
    }

    private func streakGoalNode(goal: Int, previousGoal: Int) -> some View {
        let isAchieved = bingoStreakDays >= goal
        let isCurrent = !isAchieved && bingoStreakDays >= previousGoal

        return ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isAchieved
                    ? activeThemeColor.opacity(0.18)
                    : NeumorphicColors.background.opacity(isCurrent ? 0.96 : 0.92)
                )
                .frame(width: 44, height: 48)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isAchieved ? activeThemeColor.opacity(0.72) : activeThemeColor.opacity(isCurrent ? 0.2 : 0.12))
                        .frame(width: 34, height: 10)
                        .padding(.top, 4)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isAchieved
                                ? activeThemeColor.opacity(0.9)
                                : activeThemeColor.opacity(isCurrent ? 0.62 : 0.42),
                            lineWidth: 1.2
                        )
                }
                .overlay(alignment: .top) {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Color.white.opacity(0.75))
                            .frame(width: 4, height: 4)
                        Circle()
                            .fill(Color.white.opacity(0.75))
                            .frame(width: 4, height: 4)
                    }
                    .padding(.top, 7)
                }
                .overlay {
                    Rectangle()
                        .fill((isAchieved ? activeThemeColor : activeThemeColor).opacity(isCurrent ? 0.22 : 0.14))
                        .frame(width: 28, height: 1)
                        .offset(y: -6)
                }

            Text("\(goal)")
                .font(.appSystem(size: scaled(16, pad: 18), weight: .bold, design: .rounded))
                .foregroundColor(isAchieved ? activeThemeColor : NeumorphicColors.text.opacity(isCurrent ? 0.86 : 0.78))
                .padding(.top, 10)
        }
        .frame(width: 44, height: 48)
    }

    private func streakConnectorProgress(from startGoal: Int, to endGoal: Int) -> CGFloat {
        if bingoStreakDays >= endGoal {
            return 1
        }
        if bingoStreakDays <= startGoal {
            return 0
        }

        let progress = CGFloat(bingoStreakDays - startGoal) / CGFloat(max(endGoal - startGoal, 1))
        return min(max(progress, 0), 1)
    }

    private func sidebarMetricRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.appSystem(size: 18, weight: .bold))
                .foregroundColor(NeumorphicColors.accent)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)

                Text(value)
                    .font(.appSystem(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.78))
            }

            Spacer()
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func sidebarToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.78))

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(SidebarGlassToggleStyle())
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var widgetGuideRow: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                isWidgetGuideExpanded.toggle()
            }
        } label: {
            HStack(spacing: 14) {
                Text(L10n.homeWidget)
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.78))

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.appSystem(size: 13, weight: .bold))
                    .foregroundColor(NeumorphicColors.accent)
                    .rotationEffect(.degrees(isWidgetGuideExpanded ? 0 : -90))
            }
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var widgetGuideTextRow: some View {
        Text(L10n.homeWidgetInstructions)
            .font(.appSystem(size: scaled(12.5, pad: 14.5), weight: .medium, design: .rounded))
            .foregroundColor(NeumorphicColors.text.opacity(0.6))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .listRowInsets(EdgeInsets(top: 2, leading: 22, bottom: 12, trailing: 22))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private var themePickerTriggerRow: some View {
        HStack(spacing: 14) {
            Text(L10n.themeColor)
                .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.78))

            Spacer()

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    isThemePickerExpanded.toggle()
                }
            } label: {
                Image("PickerButton")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 12, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var themePickerRow: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 12), count: 5), spacing: 12) {
            ForEach(AppTheme.allCases) { theme in
                Button {
                    guard themeRawValue != theme.rawValue else { return }
                    themeRawValue = theme.rawValue
                    UserDefaults(suiteName: BingoBoardStore.appGroupID)?.set(theme.rawValue, forKey: AppSettings.themeKey)
                    AnalyticsService.logThemeColorSelected(theme)
                    #if canImport(WidgetKit)
                    WidgetCenter.shared.reloadAllTimelines()
                    #endif
                } label: {
                    Circle()
                        .fill(theme.color)
                        .frame(width: 28, height: 28)
                        .overlay {
                            Circle()
                                .stroke(themeRawValue == theme.rawValue ? NeumorphicColors.text : .clear, lineWidth: 2)
                        }
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 4, leading: 76, bottom: 12, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

#if DEBUG
    private var pricingDebugInfoRow: some View {
        let regionCode = AppLanguage.currentRegionCode
        let languageCode: String
        switch AppLanguage.current {
        case .english:
            languageCode = "en"
        case .simplifiedChinese:
            languageCode = "zh-Hans"
        case .traditionalChinese:
            languageCode = "zh-Hant"
        case .japanese:
            languageCode = "ja"
        }

        let loaded = subscriptionManager.loadedProductIDs.isEmpty ? "none" : subscriptionManager.loadedProductIDs.joined(separator: ", ")
        let missing = subscriptionManager.missingProductIDs.isEmpty ? "none" : subscriptionManager.missingProductIDs.joined(separator: ", ")

        return VStack(alignment: .leading, spacing: 4) {
            Text("Debug")
                .font(.appSystem(size: scaled(12, pad: 13), weight: .semibold, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.6))
            Text("Locale Region: \(regionCode)")
                .font(.appSystem(size: scaled(12, pad: 13), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.66))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("Storefront: \(subscriptionManager.storefrontCountryCode) | \(subscriptionManager.storefrontID)")
                .font(.appSystem(size: scaled(12, pad: 13), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.66))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("Language: \(languageCode)")
                .font(.appSystem(size: scaled(12, pad: 13), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.66))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("Loaded Products: \(loaded)")
                .font(.appSystem(size: scaled(12, pad: 13), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.66))
                .lineLimit(1)
                .minimumScaleFactor(0.45)
            Text("Missing Products: \(missing)")
                .font(.appSystem(size: scaled(12, pad: 13), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.66))
                .lineLimit(1)
                .minimumScaleFactor(0.45)
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 22, bottom: 10, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
#endif

    private var sidebarProEntryRow: some View {
        let cardWidth: CGFloat = 254
        let cardHeight: CGFloat = 75
        let cornerRadius: CGFloat = 16
        let isPremiumMember = subscriptionManager.hasPremiumAccess
        let isEnglish = AppLanguage.current == .english
        let titleText = isPremiumMember ? L10n.proEntryMemberTitle : L10n.proEntryTitle
        let subtitleText = isPremiumMember ? L10n.proEntryMemberSubtitle : L10n.proEntrySubtitle
        let proTitleWidth: CGFloat = {
            if isPremiumMember {
                return isEnglish ? 172 : 132
            }
            return isEnglish ? 70 : 88
        }()
        let subtitleWidth: CGFloat = {
            if isPremiumMember {
                return isEnglish ? 214 : 188
            }
            return 168
        }()
        let proTitleCenterX: CGFloat = 27 + (proTitleWidth / 2)
        let proStarCenterX: CGFloat = {
            if isPremiumMember {
                return proTitleCenterX + (isEnglish ? 71 : 52)
            }
            return isEnglish ? 101.5 : 116.5
        }()
        let titleFrameWidth: CGFloat = isPremiumMember ? 220 : proTitleWidth
        let subtitleFrameWidth: CGFloat = isPremiumMember ? 224 : subtitleWidth
        let titlePositionX: CGFloat = isPremiumMember ? cardWidth / 2 : proTitleCenterX
        let subtitlePositionX: CGFloat = isPremiumMember ? cardWidth / 2 : 111
        let textAlignment: SwiftUI.Alignment = isPremiumMember ? .center : .leading
        let subtitleColor: Color = isPremiumMember ? .white : .white.opacity(0.82)
        let backgroundGradient = LinearGradient(
            colors: [Color(hex: "D3A375"), Color(hex: "DFAE7F")],
            startPoint: .top,
            endPoint: .bottom
        )

        return Button {
            isSidebarPresented = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                presentPremiumPaywall(source: "sidebar_pro_entry")
            }
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundGradient)

                Image("ProEntryCrown")
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.original)
                    .frame(width: 140.42, height: 140.42)
                    .rotationEffect(.degrees(-24.92))
                    .blendMode(.screen)
                    .opacity(0.6)
                    .position(x: 103.258, y: 37.5)

                Path { path in
                    path.move(to: CGPoint(x: 4.19505, y: 0.39209))
                    path.addCurve(
                        to: CGPoint(x: 5.17148, y: 0.392089),
                        control1: CGPoint(x: 4.3106, y: -0.130696),
                        control2: CGPoint(x: 5.05593, y: -0.130697)
                    )
                    path.addLine(to: CGPoint(x: 5.58452, y: 2.26079))
                    path.addCurve(
                        to: CGPoint(x: 7.10574, y: 3.78201),
                        control1: CGPoint(x: 5.75247, y: 3.02063),
                        control2: CGPoint(x: 6.34591, y: 3.61406)
                    )
                    path.addLine(to: CGPoint(x: 8.97444, y: 4.19505))
                    path.addCurve(
                        to: CGPoint(x: 8.97444, y: 5.17148),
                        control1: CGPoint(x: 9.49723, y: 4.3106),
                        control2: CGPoint(x: 9.49723, y: 5.05593)
                    )
                    path.addLine(to: CGPoint(x: 7.10575, y: 5.58452))
                    path.addCurve(
                        to: CGPoint(x: 5.58452, y: 7.10574),
                        control1: CGPoint(x: 6.34591, y: 5.75247),
                        control2: CGPoint(x: 5.75247, y: 6.34591)
                    )
                    path.addLine(to: CGPoint(x: 5.17148, y: 8.97444))
                    path.addCurve(
                        to: CGPoint(x: 4.19505, y: 8.97444),
                        control1: CGPoint(x: 5.05593, y: 9.49723),
                        control2: CGPoint(x: 4.3106, y: 9.49723)
                    )
                    path.addLine(to: CGPoint(x: 3.78201, y: 7.10575))
                    path.addCurve(
                        to: CGPoint(x: 2.26079, y: 5.58452),
                        control1: CGPoint(x: 3.61406, y: 6.34591),
                        control2: CGPoint(x: 3.02063, y: 5.75247)
                    )
                    path.addLine(to: CGPoint(x: 0.39209, y: 5.17148))
                    path.addCurve(
                        to: CGPoint(x: 0.392089, y: 4.19505),
                        control1: CGPoint(x: -0.130696, y: 5.05593),
                        control2: CGPoint(x: -0.130697, y: 4.3106)
                    )
                    path.addLine(to: CGPoint(x: 2.26079, y: 3.78201))
                    path.addCurve(
                        to: CGPoint(x: 3.78201, y: 2.26079),
                        control1: CGPoint(x: 3.02063, y: 3.61406),
                        control2: CGPoint(x: 3.61406, y: 3.02063)
                    )
                    path.addLine(to: CGPoint(x: 4.19505, y: 0.39209))
                    path.closeSubpath()
                }
                .fill(Color.white)
                .frame(width: 13, height: 13)
                .position(x: proStarCenterX, y: 21.5)

                Text(titleText)
                    .font(OnboardingFonts.supporting(size: 20, weight: 600))
                    .foregroundColor(.white)
                    .frame(width: titleFrameWidth, height: 25, alignment: textAlignment)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
                    .position(x: titlePositionX, y: 28.5)

                Text(subtitleText)
                    .font(OnboardingFonts.supporting(size: 14, weight: 500))
                    .foregroundColor(subtitleColor)
                    .frame(width: subtitleFrameWidth, height: 18, alignment: textAlignment)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                    .position(x: subtitlePositionX, y: 51)

                if !isPremiumMember {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))

                        Path { path in
                            path.move(to: CGPoint(x: 7.39049, y: 5.25716))
                            path.addLine(to: CGPoint(x: 10.1334, y: 8.00002))
                            path.addLine(to: CGPoint(x: 7.39049, y: 10.7429))
                        }
                        .stroke(
                            Color.white,
                            style: StrokeStyle(lineWidth: 1.06667, lineCap: .round, lineJoin: .round)
                        )
                    }
                    .frame(width: 16, height: 16)
                    .position(x: 227.5, y: 38)
                }
            }
            .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 10, leading: 22, bottom: 12, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var gridControls: some View {
        let controlSize: CGFloat = isPadLayout ? 38 : 32
        let iconSize: CGFloat = isPadLayout ? 18 : 16

        return HStack {
            HStack(spacing: isPadLayout ? 14 : 11) {
                Button {
                    withAnimation(.spring(response: 0.4)) {
                        viewModel.resizeGrid(to: viewModel.gridSize - 1)
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.appSystem(size: iconSize, weight: .bold))
                        .foregroundColor(NeumorphicColors.accent)
                        .frame(width: controlSize, height: controlSize)
                        .background(
                            conciseRaisedSurface(
                                cornerRadius: controlSize / 2,
                                shadowRadius: isPadLayout ? 10 : 8,
                                offset: isPadLayout ? 5 : 4
                            )
                        )
                }
                .disabled(viewModel.gridSize <= 2)
                .buttonStyle(.plain)
                .opacity(viewModel.gridSize <= 2 ? 0.45 : 1)

                Text("\(viewModel.gridSize) × \(viewModel.gridSize)")
                    .font(.appSystem(size: scaled(18, pad: 22), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .frame(width: isPadLayout ? 72 : 62)
                    .multilineTextAlignment(.center)

                Button {
                    withAnimation(.spring(response: 0.4)) {
                        resizeGridWithPremiumGate(
                            targetSize: viewModel.gridSize + 1,
                            source: "grid_controls"
                        )
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.appSystem(size: iconSize, weight: .bold))
                        .foregroundColor(NeumorphicColors.accent)
                        .frame(width: controlSize, height: controlSize)
                        .background(
                            conciseRaisedSurface(
                                cornerRadius: controlSize / 2,
                                shadowRadius: isPadLayout ? 10 : 8,
                                offset: isPadLayout ? 5 : 4
                            )
                        )
                }
                .disabled(viewModel.gridSize >= 5)
                .buttonStyle(.plain)
                .opacity(viewModel.gridSize >= 5 ? 0.45 : 1)
            }

            Spacer()

            HStack(spacing: isPadLayout ? 12 : 10) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isClearBoardConfirmationPresented = true
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.appSystem(size: isPadLayout ? 16 : 14, weight: .semibold))
                        .foregroundColor(NeumorphicColors.accent)
                        .frame(width: controlSize, height: controlSize)
                        .background(
                            conciseRaisedSurface(
                                cornerRadius: controlSize / 2,
                                shadowRadius: isPadLayout ? 10 : 8,
                                offset: isPadLayout ? 5 : 4
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.clearBoard)

                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        viewModel.shuffleBoard()
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.appSystem(size: isPadLayout ? 17 : 15, weight: .semibold))
                        .foregroundColor(NeumorphicColors.accent)
                        .frame(width: controlSize, height: controlSize)
                        .background(
                            conciseRaisedSurface(
                                cornerRadius: controlSize / 2,
                                shadowRadius: isPadLayout ? 10 : 8,
                                offset: isPadLayout ? 5 : 4
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sidebarAccountSection(profile: AccountProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Account")
                .font(.appSystem(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            Text(profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                 ? profile.displayName!
                 : (profile.email ?? profile.uid))
                .font(.appSystem(size: scaled(16, pad: 18), weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            if let email = profile.email, !email.isEmpty {
                Text(email)
                    .font(.appSystem(size: scaled(12.5, pad: 14.5), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.62))
            }

            Text(profile.providerIDs.map(providerDisplayName).joined(separator: " · "))
                .font(.appSystem(size: scaled(12.5, pad: 14.5), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.52))

            Button {
                accountSession.signOut()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    isSidebarPresented = false
                }
            } label: {
                Text("Sign Out")
                    .font(.appSystem(size: scaled(13.5, pad: 15.5), weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(activeThemeColor.opacity(0.92))
                    )
            }
            .buttonStyle(.plain)

            if let errorMessage = accountSession.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.appSystem(size: scaled(11.5, pad: 13), weight: .medium, design: .rounded))
                    .foregroundColor(Color.red.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(NeumorphicColors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(activeThemeColor.opacity(0.24), lineWidth: 1)
                )
        )
        .listRowInsets(EdgeInsets(top: 8, leading: 22, bottom: 14, trailing: 22))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func providerDisplayName(_ providerID: String) -> String {
        switch providerID {
        case "apple.com":
            return "Apple"
        case "google.com":
            return "Google"
        case "password":
            return "Email"
        default:
            return providerID
        }
    }

    private func redeemSticker(_ kind: StickerKind) {
        guard availablePoints >= kind.requiredPoints else { return }
        guard stickerInventoryCounts[kind] != 1 else { return }
        stickerInventoryCounts[kind] = 1
        StickerStore.saveInventoryCounts(stickerInventoryCounts)
        AnalyticsService.logStickerRedeemed(kind)
    }

    private func reconcileStickerOwnershipIfPointsInsufficient() {
        let stickerBudget = max(viewModel.totalPoints - spentRewardPoints, 0)
        var updatedInventory = stickerInventoryCounts
        var updatedPlacements = homeStickerPlacements

        var currentStickerCost = updatedInventory.reduce(0) { partial, entry in
            partial + (entry.key.requiredPoints * entry.value)
        }
        guard currentStickerCost > stickerBudget else { return }

        let ownedKinds = updatedInventory
            .filter { $0.value > 0 }
            .map(\.key)
            .sorted { lhs, rhs in
                if lhs.requiredPoints == rhs.requiredPoints {
                    return lhs.rawValue < rhs.rawValue
                }
                return lhs.requiredPoints > rhs.requiredPoints
            }

        var didChange = false
        for kind in ownedKinds where currentStickerCost > stickerBudget {
            guard updatedInventory[kind, default: 0] > 0 else { continue }
            updatedInventory[kind] = 0
            updatedPlacements.removeAll { $0.kind == kind }
            currentStickerCost -= kind.requiredPoints
            didChange = true
        }

        guard didChange else { return }
        stickerInventoryCounts = updatedInventory
        homeStickerPlacements = updatedPlacements
        StickerStore.saveInventoryCounts(updatedInventory)
        StickerStore.savePlacements(updatedPlacements)
        showCommonTasksToast(L10n.stickerRevokedDueToPoints)

        if let selectedStickerID, !updatedPlacements.contains(where: { $0.id == selectedStickerID }) {
            self.selectedStickerID = nil
        }
    }

    private func addStickerToHome(_ kind: StickerKind) {
        guard availableStickerCount(for: kind) > 0 else { return }

        let placement = HomeStickerPlacement(
            kind: kind,
            xRatio: kind.defaultPlacement.xRatio,
            yRatio: kind.defaultPlacement.yRatio
        )
        homeStickerPlacements.append(placement)
        StickerStore.savePlacements(homeStickerPlacements)
        isPointsDetailsPresented = false
        selectedStickerID = nil
    }

    private func updateStickerPlacement(_ placement: HomeStickerPlacement) {
        guard let index = homeStickerPlacements.firstIndex(where: { $0.id == placement.id }) else { return }
        homeStickerPlacements[index] = placement
        StickerStore.savePlacements(homeStickerPlacements)
    }

    private func deleteStickerPlacement(id: UUID) {
        homeStickerPlacements.removeAll { $0.id == id }
        StickerStore.savePlacements(homeStickerPlacements)
        if selectedStickerID == id {
            selectedStickerID = nil
        }
    }

    private var currentStickerUsageCounts: [StickerKind: Int] {
        homeStickerPlacements.reduce(into: [:]) { partial, placement in
            partial[placement.kind, default: 0] += 1
        }
    }

    private func availableStickerCount(for kind: StickerKind) -> Int {
        max((stickerInventoryCounts[kind] ?? 0) - (currentStickerUsageCounts[kind] ?? 0), 0)
    }

    private func createReward(title: String, requiredPoints: Int) {
        let trimmedTitle = String(title.prefix(AppSettings.maxRewardTitleLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPoints = min(max(requiredPoints, 1), 9_999)
        guard !trimmedTitle.isEmpty else { return }

        customRewards.append(
            CustomReward(
                title: trimmedTitle,
                requiredPoints: normalizedPoints
            )
        )
        RewardStore.saveRewards(customRewards)
    }

    private func updateReward(_ reward: CustomReward) {
        guard let index = customRewards.firstIndex(where: { $0.id == reward.id }) else { return }
        let trimmedTitle = String(reward.title.prefix(AppSettings.maxRewardTitleLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        customRewards[index].title = trimmedTitle
        customRewards[index].requiredPoints = min(max(reward.requiredPoints, 1), 9_999)
        RewardStore.saveRewards(customRewards)
    }

    private func archiveReward(_ reward: CustomReward) {
        guard let index = customRewards.firstIndex(where: { $0.id == reward.id }) else { return }
        customRewards[index].isArchived = true
        RewardStore.saveRewards(customRewards)
    }

    private func redeemReward(_ reward: CustomReward) {
        guard let index = customRewards.firstIndex(where: { $0.id == reward.id }) else { return }
        let requiredPoints = customRewards[index].requiredPoints
        guard availablePoints >= requiredPoints else { return }

        customRewards[index].redemptionCount += 1
        customRewards[index].totalSpentPoints += requiredPoints
        RewardStore.saveRewards(customRewards)
    }
private struct BlackBoxModeEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasSeenBlackBoxRules") private var hasSeenBlackBoxRules = false
    @State private var showRulesAlert = false

    @State private var selectedTheme: BlackBoxTheme = .health
    @State private var selectedGridSize: Int = 4
    @State private var gameState = BlackBoxGameState(theme: .health, size: 4)
    @State private var analyticsSessionStartDate: Date?
    @State private var hasLoggedAnalyticsSessionEnd = false
    @State private var hasLogged2048ScoreReached = false

    private var currentScore: Int {
        gameState.board
            .flatMap { $0 }
            .compactMap { $0 }
            .filter { $0.isCompleted }
            .reduce(0) { $0 + $1.score }
    }

    private var maxTileScore: Int {
        gameState.board
            .flatMap { $0 }
            .compactMap { $0 }
            .map(\.score)
            .max() ?? 0
    }

    var body: some View {
        ZStack {
            BlackBoxClassicPalette.background.ignoresSafeArea()

            BlackBoxModeGameView(
                game: $gameState,
                selectedTheme: $selectedTheme,
                selectedGridSize: $selectedGridSize,
                onRestart: {
                    gameState = BlackBoxGameState(theme: selectedTheme, size: selectedGridSize)
                },
                onBackToIntro: {
                    dismiss()
                },
                onShowRules: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showRulesAlert = true
                    }
                }
            )

            if showRulesAlert {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRulesAlert = false
                        }
                    }

                VStack(spacing: 20) {
                    Text(L10n.blackBoxModeHowToTitle)
                        .font(.appSystem(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(BlackBoxClassicPalette.text)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("• \(L10n.blackBoxModeFeatureTheme)")
                        Text("• \(L10n.blackBoxModeFeatureMerge)")
                        Text("• \(L10n.tr("See how high you can score!", zhHans: "看看你最后能获得多少分吧！", zhHant: "看看你最後能獲得多少分吧！"))")
                    }
                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(BlackBoxClassicPalette.text.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRulesAlert = false
                        }
                    } label: {
                        Text(L10n.tr("Got it", zhHans: "知道了", zhHant: "知道了"))
                            .font(.appSystem(size: 18, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                    .fill(BlackBoxClassicPalette.restart)
                                    .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(0.4), radius: 4, x: 0, y: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .background(
                    RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                        .fill(BlackBoxClassicPalette.background)
                        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
                )
                .padding(.horizontal, 40)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .onAppear {
            if analyticsSessionStartDate == nil {
                analyticsSessionStartDate = Date()
                hasLoggedAnalyticsSessionEnd = false
                hasLogged2048ScoreReached = false
                AnalyticsService.logBB2048SessionStart(
                    themeID: selectedTheme.rawValue,
                    gridSize: selectedGridSize
                )
            }

            if !hasSeenBlackBoxRules {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showRulesAlert = true
                }
                hasSeenBlackBoxRules = true
            }
        }
        .onDisappear {
            log2048SessionEndIfNeeded()
        }
        .onChange(of: currentScore) { oldValue, newValue in
            guard !hasLogged2048ScoreReached else { return }
            guard oldValue < 2048, newValue >= 2048 else { return }

            hasLogged2048ScoreReached = true
            AnalyticsService.logBB2048ScoreReached(
                themeID: selectedTheme.rawValue,
                gridSize: selectedGridSize,
                score: newValue,
                maxTileScore: maxTileScore,
                moveCount: gameState.moveCount,
                mergeCount: gameState.mergeCount
            )
        }
    }

    private func log2048SessionEndIfNeeded() {
        guard !hasLoggedAnalyticsSessionEnd else { return }
        guard let sessionStart = analyticsSessionStartDate else { return }

        hasLoggedAnalyticsSessionEnd = true
        let durationSeconds = max(Int(Date().timeIntervalSince(sessionStart)), 0)
        AnalyticsService.logBB2048SessionEnd(
            themeID: selectedTheme.rawValue,
            gridSize: selectedGridSize,
            durationSeconds: durationSeconds,
            finalScore: currentScore,
            maxTileScore: maxTileScore,
            moveCount: gameState.moveCount,
            mergeCount: gameState.mergeCount,
            bingoCount: gameState.bingoCount
        )
    }
}

private enum BlackBoxDirection {
    case up
    case down
    case left
    case right
}

private enum BlackBoxTheme: String, CaseIterable, Identifiable {
    case health
    case focus
    case home

    var id: String { rawValue }

    var title: String {
        switch self {
        case .health:
            return L10n.blackBoxModeHealthTheme
        case .focus:
            return L10n.blackBoxModeFocusTheme
        case .home:
            return L10n.blackBoxModeHomeTheme
        }
    }

    var taskDefinitions: [BlackBoxTaskDefinition] {
        switch self {
        case .health:
            return [
                BlackBoxTaskDefinition(
                    id: "health_drink_water",
                    baseScore: 2,
                    baseTitle: L10n.tr("Drink 1 cup of water", zhHans: "喝1杯水", zhHant: "喝1杯水"),
                    maxCount: 8
                ),
                BlackBoxTaskDefinition(
                    id: "health_breakfast",
                    baseScore: 2,
                    baseTitle: L10n.tr("Eat breakfast", zhHans: "吃早餐", zhHant: "吃早餐"),
                    maxCount: 1
                ),
                BlackBoxTaskDefinition(
                    id: "health_walk_10",
                    baseScore: 4,
                    baseTitle: L10n.tr("Walk 10 minutes", zhHans: "散步10分钟", zhHant: "散步10分鐘"),
                    maxCount: 3
                ),
                BlackBoxTaskDefinition(
                    id: "health_stretch_10",
                    baseScore: 4,
                    baseTitle: L10n.tr("Stretch 10 minutes", zhHans: "拉伸10分钟", zhHant: "拉伸10分鐘"),
                    maxCount: 2
                ),
                BlackBoxTaskDefinition(
                    id: "health_sleep_2330",
                    baseScore: 4,
                    baseTitle: L10n.tr("Sleep before 23:30", zhHans: "23:30前睡觉", zhHant: "23:30前睡覺"),
                    maxCount: 1
                ),
                BlackBoxTaskDefinition(
                    id: "health_fruit",
                    baseScore: 2,
                    baseTitle: L10n.tr("Eat fruit", zhHans: "吃水果", zhHant: "吃水果"),
                    maxCount: 2
                )
            ]
        case .focus:
            return [
                BlackBoxTaskDefinition(id: "focus_pomodoro", baseScore: 2, baseTitle: L10n.tr("Pomodoro 25 min", zhHans: "番茄专注25分钟", zhHant: "番茄專注25分鐘"), maxCount: 4),
                BlackBoxTaskDefinition(id: "focus_read", baseScore: 2, baseTitle: L10n.tr("Read 10 pages", zhHans: "阅读10页", zhHant: "閱讀10頁"), maxCount: 3),
                BlackBoxTaskDefinition(id: "focus_plan", baseScore: 4, baseTitle: L10n.tr("Write task plan", zhHans: "写任务计划", zhHant: "寫任務計劃"), maxCount: 1),
                BlackBoxTaskDefinition(id: "focus_finish_one", baseScore: 4, baseTitle: L10n.tr("Finish one small task", zhHans: "完成一个小任务", zhHant: "完成一個小任務"), maxCount: 3),
                BlackBoxTaskDefinition(id: "focus_no_social", baseScore: 4, baseTitle: L10n.tr("No social app 30 min", zhHans: "30分钟不刷社媒", zhHant: "30分鐘不刷社群媒體"), maxCount: 2)
            ]
        case .home:
            return [
                BlackBoxTaskDefinition(id: "home_trash", baseScore: 2, baseTitle: L10n.tr("Take out trash", zhHans: "倒垃圾", zhHant: "倒垃圾"), maxCount: 1),
                BlackBoxTaskDefinition(id: "home_dishes", baseScore: 2, baseTitle: L10n.tr("Wash dishes", zhHans: "洗碗", zhHant: "洗碗"), maxCount: 2),
                BlackBoxTaskDefinition(id: "home_wipe", baseScore: 2, baseTitle: L10n.tr("Wipe desk", zhHans: "擦桌子", zhHant: "擦桌子"), maxCount: 1),
                BlackBoxTaskDefinition(id: "home_laundry", baseScore: 4, baseTitle: L10n.tr("Laundry 1 cycle", zhHans: "洗衣1轮", zhHant: "洗衣1輪"), maxCount: 1),
                BlackBoxTaskDefinition(id: "home_drawer", baseScore: 4, baseTitle: L10n.tr("Organize one drawer", zhHans: "整理一个抽屉", zhHant: "整理一個抽屜"), maxCount: 2)
            ]
        }
    }

    var definitionMap: [String: BlackBoxTaskDefinition] {
        Dictionary(uniqueKeysWithValues: taskDefinitions.map { ($0.id, $0) })
    }

    func mergedTitle(score: Int) -> String {
        title
    }
}

private enum BlackBoxClassicPalette {
    static let edgeRadius: CGFloat = 2
    static let background = Color(hex: "FAF8EF")
    static let board = Color(hex: "BBADA0")
    static let boardShadow = Color(hex: "A89C90")
    static let boardHighlight = Color(hex: "D7CCBF")
    static let emptyTile = Color(hex: "CDC1B4")
    static let text = Color(hex: "776E65")
    static let darkText = Color(hex: "F9F6F2")
    static let restart = Color(hex: "8F7A66")
}

private struct BlackBoxTaskDefinition: Identifiable, Hashable {
    let id: String
    let baseScore: Int
    let baseTitle: String
    let maxCount: Int

    init(id: String, baseScore: Int, baseTitle: String, maxCount: Int = 99) {
        self.id = id
        self.baseScore = baseScore
        self.baseTitle = baseTitle
        self.maxCount = maxCount
    }

    func title(forCount count: Int) -> String {
        guard count > 1 else { return baseTitle }
        switch id {
        case "health_drink_water":
            return L10n.tr("Drink \(count) cups of water", zhHans: "喝\(count)杯水", zhHant: "喝\(count)杯水")
        default:
            return L10n.tr("\(baseTitle) x\(count)", zhHans: "\(baseTitle) x\(count)", zhHant: "\(baseTitle) x\(count)")
        }
    }
}

private struct BlackBoxTile: Identifiable, Equatable {
    var id = UUID()
    var displayTitle: String
    var score: Int
    var isCompleted: Bool
    var components: [String: Int]
}

private struct BlackBoxLineResult {
    let line: [BlackBoxTile?]
    let mergeCount: Int
}

private struct BlackBoxGameSnapshot {
    let board: [[BlackBoxTile?]]
    let moveCount: Int
    let mergeCount: Int
    let bingoCount: Int
    let isGameOver: Bool
}

private struct BlackBoxGameState {
    let theme: BlackBoxTheme
    let size: Int
    var board: [[BlackBoxTile?]]
    var moveCount: Int
    var mergeCount: Int
    var bingoCount: Int
    var isGameOver: Bool
    var history: [BlackBoxGameSnapshot]

    init(theme: BlackBoxTheme, size: Int) {
        self.theme = theme
        self.size = size
        self.board = Array(repeating: Array(repeating: nil, count: size), count: size)
        self.moveCount = 0
        self.mergeCount = 0
        self.bingoCount = 0
        self.isGameOver = false
        self.history = []
        spawnRandomTile()
        spawnRandomTile()
    }

    mutating func toggleCompletion(row: Int, col: Int) {
        guard row >= 0, row < size, col >= 0, col < size else { return }
        guard var tile = board[row][col] else { return }
        pushHistory()
        tile.isCompleted.toggle()
        board[row][col] = tile
        isGameOver = !hasMoveAvailable()
    }

    mutating func undoLastAction() {
        guard let snapshot = history.popLast() else { return }
        board = snapshot.board
        moveCount = snapshot.moveCount
        mergeCount = snapshot.mergeCount
        bingoCount = snapshot.bingoCount
        isGameOver = snapshot.isGameOver
    }

    mutating func swipe(_ direction: BlackBoxDirection) {
        guard !isGameOver else { return }

        var nextBoard = board
        var mergedTiles = 0

        switch direction {
        case .left, .right:
            for row in 0..<size {
                let processed = processLine(board[row], reverse: direction == .right)
                nextBoard[row] = processed.line
                mergedTiles += processed.mergeCount
            }
        case .up, .down:
            for col in 0..<size {
                let line = (0..<size).map { board[$0][col] }
                let processed = processLine(line, reverse: direction == .down)
                for row in 0..<size {
                    nextBoard[row][col] = processed.line[row]
                }
                mergedTiles += processed.mergeCount
            }
        }

        guard nextBoard != board else { return }

        pushHistory()
        board = nextBoard
        moveCount += 1
        mergeCount += mergedTiles
        bingoCount += mergedTiles
        spawnStrategicTile()
        isGameOver = !hasMoveAvailable()
    }

    mutating func refreshPendingTiles() {
        var targets: [(row: Int, col: Int)] = []
        for row in 0..<size {
            for col in 0..<size {
                guard let tile = board[row][col] else { continue }
                // Keep merged or completed tiles untouched.
                if tile.isCompleted || tile.components.count > 1 {
                    continue
                }
                targets.append((row, col))
            }
        }

        guard !targets.isEmpty else { return }
        pushHistory()

        for target in targets {
            guard let tile = board[target.row][target.col] else { continue }
            let task = taskDefinition(forScore: tile.score)
            board[target.row][target.col] = BlackBoxTile(
                displayTitle: task.title(forCount: 1),
                score: task.baseScore,
                isCompleted: false,
                components: [task.id: 1]
            )
        }
        isGameOver = !hasMoveAvailable()
    }

    private mutating func spawnRandomTile() {
        spawnStrategicTile(preferredScore: theme.taskDefinitions.map(\.baseScore).min())
    }

    private mutating func spawnStrategicTile(preferredScore: Int? = nil) {
        let emptyCoordinates = allEmptyCoordinates()
        guard !emptyCoordinates.isEmpty else { return }

        let targetScore = chooseSpawnScore(preferredScore: preferredScore)
        let preferredCoordinates = preferredScore.map { preferredSpawnCoordinates(for: $0) } ?? []
        let targetCoordinates = preferredCoordinates.isEmpty ? emptyCoordinates : preferredCoordinates
        guard let randomCoordinate = targetCoordinates.randomElement() else { return }

        let task = taskDefinition(forScore: targetScore)
        board[randomCoordinate.row][randomCoordinate.col] = BlackBoxTile(
            displayTitle: task.title(forCount: 1),
            score: task.baseScore,
            isCompleted: false,
            components: [task.id: 1]
        )
    }

    private func allEmptyCoordinates() -> [(row: Int, col: Int)] {
        var result: [(row: Int, col: Int)] = []
        for row in 0..<size {
            for col in 0..<size where board[row][col] == nil {
                result.append((row, col))
            }
        }
        return result
    }

    private func hasMoveAvailable() -> Bool {
        if board.flatMap(\.self).contains(where: { $0 == nil }) {
            return true
        }

        for row in 0..<size {
            for col in 0..<size {
                guard let current = board[row][col] else { continue }
                if row + 1 < size,
                   let nextRow = board[row + 1][col],
                   nextRow.score == current.score,
                   current.isCompleted,
                   nextRow.isCompleted {
                    return true
                }
                if col + 1 < size,
                   let nextCol = board[row][col + 1],
                   nextCol.score == current.score,
                   current.isCompleted,
                   nextCol.isCompleted {
                    return true
                }
            }
        }

        return false
    }

    private mutating func pushHistory() {
        history.append(
            BlackBoxGameSnapshot(
                board: board,
                moveCount: moveCount,
                mergeCount: mergeCount,
                bingoCount: bingoCount,
                isGameOver: isGameOver
            )
        )
        if history.count > 24 {
            history.removeFirst(history.count - 24)
        }
    }

    private func chooseSpawnScore(preferredScore: Int? = nil) -> Int {
        let completedCounts = completedScoreCounts()
        if let preferredScore, completedCounts[preferredScore] != nil {
            return preferredScore
        }

        if let bestExisting = completedCounts
            .sorted(by: { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            })
            .first?
            .key {
            return bestExisting
        }

        return theme.taskDefinitions.map(\.baseScore).min() ?? 2
    }

    private func completedScoreCounts() -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for row in board {
            for case let tile? in row where tile.isCompleted {
                counts[tile.score, default: 0] += 1
            }
        }
        return counts
    }

    private func preferredSpawnCoordinates(for score: Int) -> [(row: Int, col: Int)] {
        var coordinates: [(row: Int, col: Int)] = []
        for row in 0..<size {
            for col in 0..<size {
                guard let tile = board[row][col], tile.isCompleted, tile.score == score else { continue }
                coordinates.append(contentsOf: adjacentEmptyCoordinates(row: row, col: col))
            }
        }
        return uniqueCoordinates(coordinates)
    }

    private func adjacentEmptyCoordinates(row: Int, col: Int) -> [(row: Int, col: Int)] {
        var result: [(row: Int, col: Int)] = []
        let neighbors = [
            (row - 1, col),
            (row + 1, col),
            (row, col - 1),
            (row, col + 1)
        ]

        for neighbor in neighbors where neighbor.0 >= 0 && neighbor.0 < size && neighbor.1 >= 0 && neighbor.1 < size {
            if board[neighbor.0][neighbor.1] == nil {
                result.append(neighbor)
            }
        }

        return result
    }

    private func uniqueCoordinates(_ coordinates: [(row: Int, col: Int)]) -> [(row: Int, col: Int)] {
        var seen = Set<String>()
        var result: [(row: Int, col: Int)] = []
        for coordinate in coordinates {
            let key = "\(coordinate.row)-\(coordinate.col)"
            if seen.insert(key).inserted {
                result.append(coordinate)
            }
        }
        return result
    }

    private func taskDefinition(forScore score: Int) -> BlackBoxTaskDefinition {
        let boardTaskCounts = boardTaskCounts()
        let matches = theme.taskDefinitions.filter { $0.baseScore == score }
        let available = matches.filter { def in
            let currentCount = boardTaskCounts[def.id] ?? 0
            return currentCount < def.maxCount
        }
        return available.randomElement() ?? matches.randomElement() ?? theme.taskDefinitions.first ?? BlackBoxTaskDefinition(
            id: "fallback",
            baseScore: score,
            baseTitle: L10n.tr("Task", zhHans: "任务", zhHant: "任務")
        )
    }

    private func boardTaskCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for row in board {
            for case let tile? in row {
                for (taskID, count) in tile.components {
                    counts[taskID, default: 0] += count
                }
            }
        }
        return counts
    }

    private func processLine(_ line: [BlackBoxTile?], reverse: Bool) -> BlackBoxLineResult {
        let normalizedLine = reverse ? Array(line.reversed()) : line
        let compacted = normalizedLine.compactMap { $0 }

        var mergedLine: [BlackBoxTile] = []
        var mergeCount = 0
        var index = 0

        while index < compacted.count {
            if index + 1 < compacted.count {
                let first = compacted[index]
                let second = compacted[index + 1]
                if first.score == second.score, first.isCompleted, second.isCompleted {
                    let mergedComponents = mergeComponents(first.components, second.components)
                    let mergedScore = first.score * 2
                    mergedLine.append(
                        BlackBoxTile(
                            displayTitle: titleForMergedTile(components: mergedComponents, score: mergedScore),
                            score: mergedScore,
                            isCompleted: true,
                            components: mergedComponents
                        )
                    )
                    mergeCount += 1
                    index += 2
                    continue
                }
            }

            mergedLine.append(compacted[index])
            index += 1
        }

        var filledLine: [BlackBoxTile?] = mergedLine.map { $0 }
        while filledLine.count < size {
            filledLine.append(nil)
        }

        if reverse {
            filledLine.reverse()
        }

        return BlackBoxLineResult(line: filledLine, mergeCount: mergeCount)
    }

    private func mergeComponents(_ lhs: [String: Int], _ rhs: [String: Int]) -> [String: Int] {
        var merged = lhs
        for (key, value) in rhs {
            merged[key, default: 0] += value
        }
        return merged
    }

    private func titleForMergedTile(components: [String: Int], score: Int) -> String {
        if components.count == 1, let (taskID, count) = components.first, let definition = theme.definitionMap[taskID] {
            return definition.title(forCount: count)
        }
        return theme.mergedTitle(score: score)
    }
}

private struct BlackBoxHistoryRecord: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let themeRawValue: String
    let gridSize: Int
    let score: Int
    let moves: Int
    let merges: Int
    let completedTiles: Int

    var themeTitle: String {
        BlackBoxTheme(rawValue: themeRawValue)?.title ?? themeRawValue
    }
}

private enum BlackBoxHistoryStore {
    private static let key = "blackBox2048HistoryRecords.v1"

    static func load() -> [BlackBoxHistoryRecord] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([BlackBoxHistoryRecord].self, from: data)) ?? []
    }

    static func append(_ record: BlackBoxHistoryRecord, keep maxCount: Int = 50) {
        var records = load()
        records.insert(record, at: 0)
        if records.count > maxCount {
            records.removeLast(records.count - maxCount)
        }
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private struct BlackBoxModeGameView: View {
    private enum ConfirmAction: Identifiable {
        case exit
        case restart
        case switchTheme(BlackBoxTheme)
        case showRules
        case refreshPendingTasks

        var id: String {
            switch self {
            case .exit:
                return "exit"
            case .restart:
                return "restart"
            case .switchTheme(let theme):
                return "theme-\(theme.rawValue)"
            case .showRules:
                return "rules"
            case .refreshPendingTasks:
                return "refresh-pending"
            }
        }

        var title: String {
            switch self {
            case .exit:
                return L10n.tr("Confirm exit?", zhHans: "确认退出?", zhHant: "確認退出?")
            case .restart:
                return L10n.tr("Confirm restart?", zhHans: "确认重开?", zhHant: "確認重開?")
            case .switchTheme(let theme):
                return L10n.tr("Switch to \(theme.title)?", zhHans: "切换到\(theme.title)?", zhHant: "切換到\(theme.title)?")
            case .showRules:
                return L10n.tr("View how to play?", zhHans: "查看玩法说明?", zhHant: "查看玩法說明?")
            case .refreshPendingTasks:
                return L10n.tr("Refresh pending tasks?", zhHans: "刷新未完成任务?", zhHant: "刷新未完成任務?")
            }
        }

        var message: String {
            switch self {
            case .exit:
                return L10n.tr("You'll leave 2048 mode and current board progress won't be kept.", zhHans: "会离开 2048 模式，当前棋盘进度不会保留。", zhHant: "會離開 2048 模式，當前棋盤進度不會保留。")
            case .restart:
                return L10n.tr("This will clear the board and generate tasks again.", zhHans: "会清空当前棋盘并重新生成任务。", zhHant: "會清空當前棋盤並重新生成任務。")
            case .switchTheme:
                return L10n.tr("This will switch theme and reset the current board.", zhHans: "会切换主题并重置当前棋盘。", zhHant: "會切換主題並重置當前棋盤。")
            case .showRules:
                return L10n.tr("This will open the how-to-play popup.", zhHans: "将打开玩法说明弹窗。", zhHant: "將打開玩法說明彈窗。")
            case .refreshPendingTasks:
                return L10n.tr("Only incomplete and unmerged tiles will be refreshed.", zhHans: "仅刷新未完成且未合并的任务格。", zhHant: "僅刷新未完成且未合併的任務格。")
            }
        }

        var confirmTitle: String {
            switch self {
            case .exit:
                return L10n.tr("Exit", zhHans: "退出", zhHant: "退出")
            case .restart:
                return L10n.tr("Restart", zhHans: "重开", zhHant: "重開")
            case .switchTheme:
                return L10n.tr("Switch", zhHans: "切换", zhHant: "切換")
            case .showRules:
                return L10n.tr("View", zhHans: "查看", zhHant: "查看")
            case .refreshPendingTasks:
                return L10n.tr("Refresh", zhHans: "刷新", zhHant: "刷新")
            }
        }
    }

    @Binding var game: BlackBoxGameState
    @Binding var selectedTheme: BlackBoxTheme
    @Binding var selectedGridSize: Int
    let onRestart: () -> Void
    let onBackToIntro: () -> Void
    let onShowRules: () -> Void
    @State private var selectedDetail: BlackBoxTileDetailContext?
    @State private var confirmAction: ConfirmAction?
    @State private var isHistoryPresented = false
    @State private var historyRecords: [BlackBoxHistoryRecord] = BlackBoxHistoryStore.load()

    private var currentScore: Int {
        game.board.flatMap { $0 }.compactMap { $0 }.filter { $0.isCompleted }.reduce(0) { $0 + $1.score }
    }

    var body: some View {
        GeometryReader { geo in
            let safeBoardSide = min(geo.size.width - 32, geo.size.height * 0.55)

            ZStack {
                VStack(spacing: 24) {
                    Spacer(minLength: 16)

                    HStack(alignment: .center) {
                        HStack(spacing: 8) {
                            Text("2048")
                                .font(.appSystem(size: 44, weight: .heavy, design: .rounded))
                                .foregroundColor(BlackBoxClassicPalette.text)
                                .padding(.vertical, 8)

                            Button {
                                requestConfirmation(.showRules)
                            } label: {
                                Image(systemName: "questionmark.circle.fill")
                                    .font(.appSystem(size: 24))
                                    .foregroundColor(BlackBoxClassicPalette.text.opacity(0.3))
                            }

                            Button {
                                historyRecords = BlackBoxHistoryStore.load()
                                isHistoryPresented = true
                            } label: {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.appSystem(size: 21, weight: .bold))
                                    .foregroundColor(BlackBoxClassicPalette.text.opacity(0.3))
                            }
                        }

                        Spacer()

                        scoreBox(title: L10n.tr("Score", zhHans: "分数", zhHant: "分數"), value: "\(currentScore)")
                    }

                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            neumorphicButton(title: L10n.tr("Exit", zhHans: "退出", zhHant: "退出"), action: {
                                requestConfirmation(.exit)
                            })
                            Spacer()
                            neumorphicButton(title: L10n.undo, action: {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.92)) {
                                    game.undoLastAction()
                                }
                            })
                            neumorphicButton(title: L10n.tr("Restart", zhHans: "重新开始", zhHant: "重新開始"), action: {
                                requestConfirmation(.restart)
                            })
                        }

                        HStack(spacing: 10) {
                            ForEach(BlackBoxTheme.allCases) { theme in
                                Button {
                                    guard selectedTheme != theme else { return }
                                    requestConfirmation(.switchTheme(theme))
                                } label: {
                                    Text(theme.title)
                                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(selectedTheme == theme ? .white : BlackBoxClassicPalette.darkText)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 40)
                                        .background(
                                            RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                                .fill(selectedTheme == theme ? BlackBoxClassicPalette.restart : BlackBoxClassicPalette.emptyTile)
                                                .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(selectedTheme == theme ? 0.4 : 0.1), radius: 4, x: 0, y: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Spacer(minLength: 20)

                    VStack(spacing: 8) {
                        BlackBoxBoardGridView(game: $game) { row, col, tile in
                            if tile.components.count > 1 {
                                selectedDetail = BlackBoxTileDetailContext(tile: tile, theme: game.theme)
                            } else {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                                    game.toggleCompletion(row: row, col: col)
                                }
                            }
                        }
                        .frame(width: safeBoardSide, height: safeBoardSide)
                        .gesture(
                            DragGesture(minimumDistance: 22)
                                .onEnded { value in
                                    guard let direction = swipeDirection(for: value.translation) else { return }
                                    withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                                        game.swipe(direction)
                                    }
                                }
                        )

                        if game.isGameOver {
                            Text(L10n.blackBoxModeGameOver)
                                .font(.appSystem(size: 16, weight: .heavy, design: .rounded))
                                .foregroundColor(BlackBoxClassicPalette.text)
                                .padding(.top, 8)
                        }
                    }
                    .offset(y: -45)

                    HStack {
                        HStack(spacing: 8) {
                            ForEach([3, 4, 5], id: \.self) { size in
                                Button {
                                    saveCurrentHistoryIfNeeded()
                                    selectedGridSize = size
                                    onRestart()
                                } label: {
                                    Text("\(size)x\(size)")
                                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(selectedGridSize == size ? .white : BlackBoxClassicPalette.darkText)
                                        .frame(width: 52, height: 32)
                                        .background(
                                            RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                                .fill(selectedGridSize == size ? BlackBoxClassicPalette.restart : BlackBoxClassicPalette.emptyTile)
                                                .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(selectedGridSize == size ? 0.4 : 0.1), radius: 4, x: 0, y: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Spacer()

                        Button {
                            requestConfirmation(.refreshPendingTasks)
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.appSystem(size: 16, weight: .heavy))
                                .foregroundColor(BlackBoxClassicPalette.darkText)
                                .frame(width: 42, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                        .fill(BlackBoxClassicPalette.restart)
                                        .shadow(color: BlackBoxClassicPalette.boardHighlight.opacity(0.65), radius: 5, x: -2, y: -2)
                                        .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(0.35), radius: 5, x: 2, y: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: safeBoardSide)
                    .offset(y: -34)

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
                .sheet(item: $selectedDetail) { context in
                    BlackBoxTileDetailSheet(context: context)
                        .presentationDetents([.fraction(0.44), .medium])
                        .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $isHistoryPresented) {
                    BlackBoxHistorySheet(records: historyRecords)
                        .presentationDetents([.fraction(0.4), .medium, .large])
                        .presentationDragIndicator(.visible)
                }

            }
        }
        .alert(
            confirmAction?.title ?? "",
            isPresented: Binding(
                get: { confirmAction != nil },
                set: { isPresented in
                    if !isPresented {
                        confirmAction = nil
                    }
                }
            ),
            presenting: confirmAction
        ) { action in
            Button(L10n.cancel, role: .cancel) {}
            Button(action.confirmTitle, role: .destructive) {
                performConfirmedAction(action)
            }
        } message: { action in
            Text(action.message)
        }
    }

    private func swipeDirection(for translation: CGSize) -> BlackBoxDirection? {
        let x = translation.width
        let y = translation.height
        guard max(abs(x), abs(y)) > 24 else { return nil }
        if abs(x) > abs(y) { return x > 0 ? .right : .left }
        return y > 0 ? .down : .up
    }

    private func neumorphicButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(BlackBoxClassicPalette.darkText)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                        .fill(BlackBoxClassicPalette.restart)
                        .shadow(color: BlackBoxClassicPalette.boardHighlight.opacity(0.65), radius: 5, x: -2, y: -2)
                        .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(0.35), radius: 5, x: 2, y: 2)
                )
        }
        .buttonStyle(.plain)
    }

    private func scoreBox(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.appSystem(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
            Text(value)
                .font(.appSystem(size: 24, weight: .heavy, design: .rounded))
                .foregroundColor(Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
        }
        .frame(minWidth: 88)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                .fill(BlackBoxClassicPalette.board)
                .shadow(color: BlackBoxClassicPalette.boardHighlight.opacity(0.5), radius: 4, x: -2, y: -2)
                .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(0.2), radius: 4, x: 2, y: 2)
        )
    }

    private func requestConfirmation(_ action: ConfirmAction) {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
            confirmAction = action
        }
    }

    private func dismissConfirmation() {
        withAnimation(.easeInOut(duration: 0.18)) {
            confirmAction = nil
        }
    }

    private func performConfirmedAction(_ action: ConfirmAction) {
        dismissConfirmation()
        switch action {
        case .exit:
            saveCurrentHistoryIfNeeded()
            onBackToIntro()
        case .restart:
            saveCurrentHistoryIfNeeded()
            selectedDetail = nil
            withAnimation(.easeInOut(duration: 0.2)) {
                onRestart()
            }
        case .switchTheme(let theme):
            saveCurrentHistoryIfNeeded()
            selectedTheme = theme
            onRestart()
        case .showRules:
            onShowRules()
        case .refreshPendingTasks:
            withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                game.refreshPendingTiles()
            }
        }
    }

    private func saveCurrentHistoryIfNeeded() {
        let completedTiles = game.board.flatMap { $0 }.compactMap { $0 }.filter { $0.isCompleted }.count
        let hasProgress = game.moveCount > 0 || game.mergeCount > 0 || currentScore > 0 || completedTiles > 0
        guard hasProgress else { return }

        BlackBoxHistoryStore.append(
            BlackBoxHistoryRecord(
                id: UUID(),
                createdAt: Date(),
                themeRawValue: game.theme.rawValue,
                gridSize: game.size,
                score: currentScore,
                moves: game.moveCount,
                merges: game.mergeCount,
                completedTiles: completedTiles
            )
        )
    }

}

private struct BlackBoxBoardGridView: View {
    @Binding var game: BlackBoxGameState
    let onTileTap: (_ row: Int, _ col: Int, _ tile: BlackBoxTile) -> Void

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 10
            let outerPadding: CGFloat = 10
            let totalSpacing = CGFloat(game.size - 1) * spacing
            let side = min(geo.size.width, geo.size.height)
            let cellSide = (side - (outerPadding * 2) - totalSpacing) / CGFloat(game.size)

            ZStack {
                RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                    .fill(BlackBoxClassicPalette.board)
                    .shadow(color: BlackBoxClassicPalette.boardHighlight.opacity(0.72), radius: 8, x: -4, y: -4)
                    .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(0.32), radius: 8, x: 4, y: 4)

                VStack(spacing: spacing) {
                    ForEach(0..<game.size, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(0..<game.size, id: \.self) { col in
                                BlackBoxTileCellView(tile: game.board[row][col])
                                    .frame(width: cellSide, height: cellSide)
                                    .contentShape(RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous))
                                    .onTapGesture {
                                        guard let tile = game.board[row][col] else { return }
                                        onTileTap(row, col, tile)
                                    }
                            }
                        }
                    }
                }
                .padding(outerPadding)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

private struct BlackBoxTileCellView: View {
    let tile: BlackBoxTile?

    var body: some View {
        ZStack {
            if let tile {
                RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                    .fill(tileBackground(for: tile))
                    .shadow(color: tile.isCompleted ? BlackBoxClassicPalette.boardShadow.opacity(0.2) : BlackBoxClassicPalette.boardShadow.opacity(0.1), radius: 4, x: 0, y: 2)

                VStack(spacing: 2) {
                    Text("\(tile.score)")
                        .font(.appSystem(size: tile.score >= 1000 ? 24 : 32, weight: .heavy, design: .rounded))
                        .foregroundColor(tileTextColor(for: tile))
                        .minimumScaleFactor(0.5)

                    if tile.score < 2048 {
                        Text(tile.displayTitle)
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(tileTextColor(for: tile).opacity(0.8))
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                    .fill(BlackBoxClassicPalette.emptyTile)
                    .shadow(color: Color.white.opacity(0.3), radius: 4, x: -2, y: -2)
                    .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(0.1), radius: 4, x: 2, y: 2)
            }
        }
    }

    private func tileBackground(for tile: BlackBoxTile) -> Color {
        guard tile.isCompleted else { return BlackBoxClassicPalette.emptyTile.opacity(0.9) }
        switch tile.score {
        case ..<4:
            return Color(hex: "EEE4DA")
        case 4:
            return Color(hex: "EDE0C8")
        case 8:
            return Color(hex: "F2B179")
        case 16:
            return Color(hex: "F59563")
        case 32:
            return Color(hex: "F67C5F")
        case 64:
            return Color(hex: "F65E3B")
        case 128:
            return Color(hex: "EDCF72")
        case 256:
            return Color(hex: "EDCC61")
        case 512:
            return Color(hex: "EDC850")
        case 1024:
            return Color(hex: "EDC53F")
        case 2048:
            return Color(hex: "EDC22E")
        default:
            return Color(hex: "3C3A32")
        }
    }

    private func tileTextColor(for tile: BlackBoxTile) -> Color {
        if !tile.isCompleted {
            return BlackBoxClassicPalette.text
        }
        return tile.score >= 8 ? BlackBoxClassicPalette.darkText : BlackBoxClassicPalette.text
    }
}

private struct BlackBoxTileDetailContext: Identifiable {
    let id = UUID()
    let tile: BlackBoxTile
    let theme: BlackBoxTheme
}

private struct BlackBoxTileDetailSheet: View {
    let context: BlackBoxTileDetailContext

    var body: some View {
        NavigationStack {
            ZStack {
                BlackBoxClassicPalette.background
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(context.tile.displayTitle)
                                .font(.appSystem(size: 24, weight: .heavy, design: .rounded))
                                .foregroundColor(BlackBoxClassicPalette.text)
                                .lineLimit(2)
                        }

                        Spacer()
                    }

                    Text(L10n.blackBoxModeContainsTasks)
                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(BlackBoxClassicPalette.text.opacity(0.84))

                    ForEach(componentRows, id: \.id) { row in
                        HStack {
                            Text(row.title)
                                .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(BlackBoxClassicPalette.text)
                            Spacer()
                            Text("x\(row.count)")
                                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(BlackBoxClassicPalette.restart)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                .fill(Color.white.opacity(0.32))
                        )
                    }

                    Divider()
                        .overlay(BlackBoxClassicPalette.text.opacity(0.15))

                    HStack {
                        Text(L10n.blackBoxModeCompletionCount)
                            .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(BlackBoxClassicPalette.text.opacity(0.84))
                        Spacer()
                        Text("\(L10n.blackBoxModeTotalCompletions) \(totalCompletions)")
                            .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(BlackBoxClassicPalette.text)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle(L10n.blackBoxModeTileDetailTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var componentRows: [(id: String, title: String, count: Int)] {
        context.tile.components
            .sorted { $0.key < $1.key }
            .map { key, count in
                let title = context.theme.definitionMap[key]?.baseTitle ?? key
                return (id: key, title: title, count: count)
            }
    }

    private var totalCompletions: Int {
        context.tile.components.values.reduce(0, +)
    }
}

private struct BlackBoxHistorySheet: View {
    let records: [BlackBoxHistoryRecord]

    var body: some View {
        NavigationStack {
            ZStack {
                BlackBoxClassicPalette.background
                    .ignoresSafeArea()

                if records.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.appSystem(size: 28, weight: .bold))
                            .foregroundColor(BlackBoxClassicPalette.text.opacity(0.5))
                        Text(L10n.tr("No history yet", zhHans: "暂无历史记录", zhHant: "暫無歷史記錄"))
                            .font(.appSystem(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(BlackBoxClassicPalette.text.opacity(0.75))
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(records) { record in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.themeTitle)
                                            .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                                            .foregroundColor(BlackBoxClassicPalette.text)
                                        Text("\(record.gridSize)x\(record.gridSize) · \(record.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundColor(BlackBoxClassicPalette.text.opacity(0.7))
                                    }

                                    Spacer(minLength: 8)

                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("\(L10n.tr("Score", zhHans: "分数", zhHant: "分數")) \(record.score)")
                                            .font(.appSystem(size: 15, weight: .heavy, design: .rounded))
                                            .foregroundColor(BlackBoxClassicPalette.restart)
                                        Text("\(L10n.blackBoxModeMoves) \(record.moves) · \(L10n.blackBoxModeMerges) \(record.merges)")
                                            .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundColor(BlackBoxClassicPalette.text.opacity(0.72))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                        .fill(BlackBoxClassicPalette.board.opacity(0.12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                                .stroke(BlackBoxClassicPalette.board.opacity(0.24), lineWidth: 1)
                                        )
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle(L10n.tr("History", zhHans: "历史记录", zhHant: "歷史記錄"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct PointsDetailSheet: View {
    private enum PointsTab: String, CaseIterable, Identifiable {
        case stickers
        case rewards

        var id: String { rawValue }

        var title: String {
            switch self {
            case .stickers:
                return L10n.stickers
            case .rewards:
                return L10n.myRewards
            }
        }
    }

    let points: Int
    let inventoryCounts: [StickerKind: Int]
    let usedCounts: [StickerKind: Int]
    let rewards: [CustomReward]
    let onRedeem: (StickerKind) -> Void
    let onAddToHome: (StickerKind) -> Void
    let onCreateReward: (String, Int) -> Void
    let onUpdateReward: (CustomReward) -> Void
    let onDeleteReward: (CustomReward) -> Void
    let onRedeemReward: (CustomReward) -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss
    @State private var creatingReward = false
    @State private var editingReward: CustomReward?
    @State private var selectedTab: PointsTab = .stickers

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var contentMaxWidth: CGFloat {
        isPadLayout ? 820 : .infinity
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    private var stickerGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: isPadLayout ? 3 : 2)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NeumorphicColors.background
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(alignment: .center, spacing: 14) {
                            Text(L10n.myPoints)
                                .font(.appSystem(size: scaled(17, pad: 21), weight: .semibold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text.opacity(0.76))

                            HStack(spacing: 10) {
                                Image(systemName: "star.fill")
                                    .font(.appSystem(size: scaled(20, pad: 24), weight: .bold))
                                    .foregroundColor(NeumorphicColors.accent)

                                Text("\(points)")
                                    .font(.appSystem(size: scaled(34, pad: 44), weight: .bold, design: .rounded))
                                    .foregroundColor(NeumorphicColors.text)
                            }

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        tabSelector

                        if selectedTab == .stickers {
                            VStack(alignment: .leading, spacing: 14) {
                                LazyVGrid(
                                    columns: stickerGridColumns,
                                    spacing: 16
                                ) {
                                    ForEach(StickerKind.allCases) { kind in
                                        stickerCard(kind)
                                    }
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                if rewards.isEmpty {
                                    Text(L10n.noRewardsYet)
                                        .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                                        .foregroundColor(NeumorphicColors.text.opacity(0.62))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 4)
                                }

                                LazyVGrid(columns: stickerGridColumns, spacing: 16) {
                                    ForEach(rewards) { reward in
                                        rewardCard(reward)
                                    }
                                    addRewardCard
                                }
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NeumorphicColors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.done) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(NeumorphicColors.accent)
                }
            }
        }
        .sheet(isPresented: phoneCreatingRewardBinding) {
            rewardEditorSheet(for: nil)
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: padCreatingRewardBinding) {
            NineTenthsSheetContainer(contentMaxWidth: 700) {
                rewardEditorSheet(for: nil)
            }
            .background(Color.clear)
        }
        .sheet(item: phoneEditingRewardBinding) { reward in
            rewardEditorSheet(for: reward)
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: padEditingRewardBinding) { reward in
            NineTenthsSheetContainer(contentMaxWidth: 700) {
                rewardEditorSheet(for: reward)
            }
            .background(Color.clear)
        }
    }

    private var phoneCreatingRewardBinding: Binding<Bool> {
        Binding(
            get: { !isPadLayout && creatingReward },
            set: { creatingReward = $0 }
        )
    }

    private var padCreatingRewardBinding: Binding<Bool> {
        Binding(
            get: { isPadLayout && creatingReward },
            set: { creatingReward = $0 }
        )
    }

    private var phoneEditingRewardBinding: Binding<CustomReward?> {
        Binding(
            get: { isPadLayout ? nil : editingReward },
            set: { editingReward = $0 }
        )
    }

    private var padEditingRewardBinding: Binding<CustomReward?> {
        Binding(
            get: { isPadLayout ? editingReward : nil },
            set: { editingReward = $0 }
        )
    }

    private func rewardEditorSheet(for reward: CustomReward?) -> some View {
        RewardEditorSheet(
            reward: reward,
            onSave: { title, requiredPoints in
                if let reward {
                    onUpdateReward(
                        CustomReward(
                            id: reward.id,
                            title: title,
                            requiredPoints: requiredPoints,
                            redemptionCount: reward.redemptionCount,
                            totalSpentPoints: reward.totalSpentPoints,
                            isArchived: reward.isArchived
                        )
                    )
                    editingReward = nil
                } else {
                    onCreateReward(title, requiredPoints)
                    creatingReward = false
                }
            },
            onDelete: reward.map { existingReward in
                {
                    onDeleteReward(existingReward)
                    editingReward = nil
                }
            },
            onCancel: {
                if reward != nil {
                    editingReward = nil
                } else {
                    creatingReward = false
                }
            }
        )
    }

    private var tabSelector: some View {
        HStack(spacing: 12) {
            ForEach(PointsTab.allCases) { tab in
                tabButton(tab)
            }
        }
    }

    private func tabButton(_ tab: PointsTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                selectedTab = tab
            }
        } label: {
            Text(tab.title)
                .font(.appSystem(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                .foregroundColor(isSelected ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.6))
                .frame(maxWidth: .infinity)
                .frame(height: isPadLayout ? 46 : 40)
                .background(tabBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }

    private func tabBackground(isSelected: Bool) -> some View {
        Capsule(style: .continuous)
            .fill(isSelected ? NeumorphicColors.accent.opacity(0.12) : NeumorphicColors.background.opacity(0.5))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        isSelected
                            ? NeumorphicColors.accent.opacity(0.72)
                            : NeumorphicColors.accent.opacity(0.38),
                        lineWidth: 1
                    )
            )
    }

    private func stickerCard(_ sticker: StickerKind) -> some View {
        let inventoryCount = inventoryCounts[sticker] ?? 0
        let usedCount = usedCounts[sticker] ?? 0
        let isPlacedOnHome = usedCount > 0
        let hasOwned = inventoryCount > 0
        let canRedeem = points >= sticker.requiredPoints

        return VStack(spacing: 12) {
            Image((hasOwned || canRedeem) ? sticker.unlockedImageName : sticker.lockedImageName)
                .resizable()
                .scaledToFit()
                .frame(height: isPadLayout ? 120 : 100)

            VStack(spacing: 4) {
                Text("\(sticker.requiredPoints) \(L10n.pointsUnit)")
                    .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                    .foregroundColor((hasOwned || canRedeem) ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.58))

                if inventoryCount > 0 {
                    Text(L10n.ownedCount(inventoryCount))
                    .font(.appSystem(size: scaled(12, pad: 14), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.62))
                }
            }

            Button {
                if hasOwned {
                    onAddToHome(sticker)
                } else {
                    onRedeem(sticker)
                }
            } label: {
                Text(hasOwned ? (isPlacedOnHome ? L10n.onHome : L10n.addToHome) : L10n.redeem)
                    .font(.appSystem(size: scaled(13, pad: 15), weight: .bold, design: .rounded))
                    .foregroundColor((canRedeem || hasOwned) ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.42))
                    .frame(maxWidth: .infinity)
                    .frame(height: isPadLayout ? 38 : 34)
                    .background(flatStickerButtonSurface(cornerRadius: isPadLayout ? 19 : 17))
                    .opacity((canRedeem || hasOwned) ? 1 : 0.68)
            }
            .buttonStyle(.plain)
            .disabled((!canRedeem && !hasOwned) || isPlacedOnHome)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(flatStickerCardSurface(cornerRadius: 22))
        .opacity((hasOwned || canRedeem) ? 1 : 0.9)
    }

    private func rewardCard(_ reward: CustomReward) -> some View {
        let canRedeem = points >= reward.requiredPoints

        return ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Spacer(minLength: isPadLayout ? 14 : 10)

                Text(reward.title)
                    .font(.appSystem(size: scaled(16, pad: 20), weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 8)
                    .offset(y: 20)

                Spacer(minLength: isPadLayout ? 12 : 10)

                VStack(spacing: 4) {
                    Text("\(reward.requiredPoints) \(L10n.pointsUnit)")
                        .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                        .foregroundColor(canRedeem ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.58))

                    if reward.redemptionCount > 0 {
                        Text(L10n.redeemedCount(reward.redemptionCount))
                            .font(.appSystem(size: scaled(12, pad: 14), weight: .medium, design: .rounded))
                            .foregroundColor(NeumorphicColors.text.opacity(0.62))
                    }
                }
                .frame(maxWidth: .infinity)
                .offset(y: 20)

                Spacer(minLength: isPadLayout ? 12 : 10)

                Button {
                    onRedeemReward(reward)
                } label: {
                    Text(L10n.redeem)
                        .font(.appSystem(size: scaled(13, pad: 15), weight: .bold, design: .rounded))
                        .foregroundColor(canRedeem ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.42))
                        .frame(maxWidth: .infinity)
                        .frame(height: isPadLayout ? 38 : 34)
                        .background(themedOutlineSurface(cornerRadius: isPadLayout ? 19 : 17))
                        .opacity(canRedeem ? 1 : 0.68)
                }
                .buttonStyle(.plain)
                .disabled(!canRedeem)
                .padding(.top, isPadLayout ? 8 : 6)
            }

            Button {
                editingReward = reward
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.appSystem(size: scaled(12, pad: 14), weight: .bold))
                    .foregroundColor(NeumorphicColors.text.opacity(0.78))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: isPadLayout ? 192 : 176, alignment: .top)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(themedOutlineSurface(cornerRadius: 22))
        .opacity(canRedeem ? 1 : 0.9)
    }

    private var addRewardCard: some View {
        Button {
            creatingReward = true
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.appSystem(size: scaled(34, pad: 40), weight: .semibold))
                    .foregroundColor(NeumorphicColors.accent)

                Text(L10n.addReward)
                    .font(.appSystem(size: scaled(15, pad: 17), weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
            }
            .frame(maxWidth: .infinity, minHeight: isPadLayout ? 192 : 176)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background(themedOutlineSurface(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }

    private func themedOutlineSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(NeumorphicColors.background.opacity(0.94))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(NeumorphicColors.accent.opacity(0.58), lineWidth: 1)
            )
    }

    private func flatStickerCardSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(NeumorphicColors.background.opacity(0.78))
    }

    private func flatStickerButtonSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(NeumorphicColors.background.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(NeumorphicColors.text.opacity(0.08), lineWidth: 0.8)
            )
    }
}

private struct RewardEditorSheet: View {
    let reward: CustomReward?
    let onSave: (String, Int) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    @State private var titleText: String
    @State private var pointsText: String
    @FocusState private var focusedField: FocusedField?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss

    private enum FocusedField: Hashable {
        case title
        case points
    }

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    init(
        reward: CustomReward?,
        onSave: @escaping (String, Int) -> Void,
        onDelete: (() -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        self.reward = reward
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _titleText = State(initialValue: reward?.title ?? "")
        _pointsText = State(initialValue: reward.map { String($0.requiredPoints) } ?? "")
    }

    private var normalizedTitle: String {
        String(titleText.prefix(AppSettings.maxRewardTitleLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedPoints: Int? {
        guard let points = Int(pointsText), points > 0 else { return nil }
        return min(points, 9_999)
    }

    private var canSave: Bool {
        !normalizedTitle.isEmpty && normalizedPoints != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NeumorphicColors.background
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        focusedField = nil
                    }

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.rewardTitle)
                            .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                            .foregroundColor(NeumorphicColors.text.opacity(0.74))

                        TextField(L10n.rewardExampleHint, text: $titleText)
                            .font(.appSystem(size: scaled(17, pad: 20), weight: .semibold, design: .rounded))
                            .foregroundColor(NeumorphicColors.text)
                            .padding(.horizontal, 16)
                            .frame(height: isPadLayout ? 56 : 50)
                            .background(rewardEditorOutlineSurface(cornerRadius: isPadLayout ? 18 : 16))
                            .focused($focusedField, equals: .title)
                            .submitLabel(.done)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.rewardPoints)
                            .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                            .foregroundColor(NeumorphicColors.text.opacity(0.74))

                        TextField(L10n.rewardPointsHint, text: $pointsText)
                            .keyboardType(.numberPad)
                            .font(.appSystem(size: scaled(17, pad: 20), weight: .semibold, design: .rounded))
                            .foregroundColor(NeumorphicColors.text)
                            .padding(.horizontal, 16)
                            .frame(height: isPadLayout ? 56 : 50)
                            .background(rewardEditorOutlineSurface(cornerRadius: isPadLayout ? 18 : 16))
                            .focused($focusedField, equals: .points)
                    }

                    if let onDelete {
                        Button {
                            onDelete()
                        } label: {
                            Text(L10n.deleteReward)
                                .font(.appSystem(size: scaled(15, pad: 17), weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.bingoAccent)
                                .frame(maxWidth: .infinity)
                                .frame(height: isPadLayout ? 50 : 46)
                                .background(rewardEditorOutlineSurface(cornerRadius: isPadLayout ? 20 : 18))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: isPadLayout ? 560 : .infinity, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(reward == nil ? L10n.addReward : L10n.editReward)
                        .font(.appSystem(size: scaled(18, pad: 21), weight: .bold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) {
                        onCancel()
                    }
                    .foregroundColor(NeumorphicColors.text.opacity(0.78))
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.save) {
                        guard let requiredPoints = normalizedPoints else { return }
                        onSave(normalizedTitle, requiredPoints)
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(canSave ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.38))
                    .disabled(!canSave)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button(L10n.done) {
                        focusedField = nil
                    }
                    .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.accent)
                }
            }
        }
    }

    private func rewardEditorOutlineSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(NeumorphicColors.background.opacity(0.94))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(NeumorphicColors.accent.opacity(0.58), lineWidth: 1)
            )
    }
}

private struct EditableHomeStickerView: View {
    let placement: HomeStickerPlacement
    let canvasSize: CGSize
    let isEditing: Bool
    let onSelect: () -> Void
    let onUpdate: (HomeStickerPlacement) -> Void
    let onDelete: () -> Void

    @State private var dragStartPlacement: HomeStickerPlacement?
    @State private var magnifyStartScale: Double?

    private var baseStickerWidth: CGFloat {
        placement.kind.homeDisplayWidth
    }

    private var stickerWidth: CGFloat {
        baseStickerWidth * CGFloat(normalizedScale)
    }

    private var normalizedXRatio: Double {
        normalized(placement.xRatio, min: 0.02, max: 0.98, fallback: 0.5)
    }

    private var normalizedYRatio: Double {
        normalized(placement.yRatio, min: 0.02, max: 0.98, fallback: 0.5)
    }

    private var normalizedScale: Double {
        normalized(placement.scale, min: 0.5, max: 1.6, fallback: 1.0)
    }

    private var horizontalInsetRatio: Double {
        let inset = stickerWidth / 2
        return clampRatio(inset / max(canvasSize.width, 1))
    }

    private var verticalInsetRatio: Double {
        let inset = stickerWidth / 2
        return clampRatio(inset / max(canvasSize.height, 1))
    }

    var body: some View {
        let position = CGPoint(
            x: canvasSize.width * normalizedXRatio,
            y: canvasSize.height * normalizedYRatio
        )

        ZStack(alignment: .topTrailing) {
            Image(placement.kind.unlockedImageName)
                .resizable()
                .scaledToFit()
                .frame(width: stickerWidth)
                .shadow(color: NeumorphicColors.darkShadow.opacity(0.16), radius: 6, x: 3, y: 4)
                .overlay {
                    if isEditing {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(NeumorphicColors.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .padding(2)
                    }
                }

            if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.appSystem(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(NeumorphicColors.accent))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }
        }
        .contentShape(Rectangle())
        .position(position)
        .onTapGesture {
            onSelect()
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard isEditing else { return }

                    let baseline = dragStartPlacement ?? placement
                    if dragStartPlacement == nil {
                        dragStartPlacement = placement
                    }

                    let newX = clamp(
                        baseline.xRatio + value.translation.width / max(canvasSize.width, 1),
                        min: horizontalInsetRatio,
                        max: 1 - horizontalInsetRatio
                    )
                    let newY = clamp(
                        baseline.yRatio + value.translation.height / max(canvasSize.height, 1),
                        min: verticalInsetRatio,
                        max: 1 - verticalInsetRatio
                    )

                    onUpdate(
                        HomeStickerPlacement(
                            id: placement.id,
                            kind: placement.kind,
                            xRatio: newX,
                            yRatio: newY,
                            scale: placement.scale
                        )
                    )
                }
                .onEnded { _ in
                    dragStartPlacement = nil
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    guard isEditing else { return }

                    let baseline = magnifyStartScale ?? placement.scale
                    if magnifyStartScale == nil {
                        magnifyStartScale = placement.scale
                    }

                    let newScale = clamp(baseline * value.magnification, min: 0.5, max: 1.6)
                    onUpdate(
                        HomeStickerPlacement(
                            id: placement.id,
                            kind: placement.kind,
                            xRatio: placement.xRatio,
                            yRatio: placement.yRatio,
                            scale: newScale
                        )
                    )
                }
                .onEnded { _ in
                    magnifyStartScale = nil
                }
        )
    }

    private func clamp(_ value: Double, min lowerBound: Double, max upperBound: Double) -> Double {
        Swift.max(lowerBound, Swift.min(value, upperBound))
    }

    private func clampRatio(_ value: CGFloat) -> Double {
        let normalized = Double(value)
        return Swift.max(0.02, Swift.min(normalized, 0.48))
    }

    private func normalized(_ value: Double, min lowerBound: Double, max upperBound: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return Swift.max(lowerBound, Swift.min(value, upperBound))
    }
}

private struct QuickEditView: View {
    @ObservedObject var viewModel: BingoViewModel
    let onSaveSuccess: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var library = CommonTasksStore.loadLibrary()
    @State private var taskHistoryRecords = TaskHistoryStore.load()
    @State private var lastTrackedLibrary = CommonTasksStore.loadLibrary()
    @FocusState private var focusedField: FocusedMyTaskField?
    @State private var deleteConfirmationTarget: DeleteTarget?
    @State private var localToastMessage: String?
    @State private var isLocalToastVisible = false
    @State private var hideLocalToastWorkItem: DispatchWorkItem?
    @State private var selectedTaskKeys: [String] = []
    @State private var previewSlots: [PreviewSlot] = []
    @State private var previewDragSourceID: UUID?
    @State private var previewDropTargetID: UUID?
    @State private var initialSnapshot: QuickEditSnapshot?
    @State private var isExitDiscardAlertPresented = false
    @State private var targetGridSize = 4
    @State private var didApplyToBoard = false
    @State private var pendingApplyPlan: ApplyPlan?
    @State private var isPremiumPaywallPresented = false
    @State private var premiumPaywallSource = "quick_edit"
    @State private var activeFilter: FilterTab = .all
    @State private var isAddingTaskInline = false
    @State private var newTaskDraft = ""
    @State private var newTaskStartMonthDraft = ""
    @State private var newTaskStartDayDraft = ""
    @State private var isAddingGroupModalPresented = false
    @State private var newGroupNameDraft = ""
    @State private var pendingGroupDeleteFinalConfirmation: UUID?
    @State private var taskEditorDraft: TaskEditorDraft?
    @State private var previewEditingTarget: PreviewEditingTarget?
    @AppStorage(AppSettings.themeKey) private var themeRawValue = AppTheme.concise.rawValue

    private enum FocusedMyTaskField: Hashable {
        case task(Int)
        case groupTask(UUID, Int)
        case newTask
        case newTaskStartMonth
        case newTaskStartDay
        case newGroupName
        case taskEditorName
        case taskEditorMonth
        case taskEditorDay
    }

    private enum DeleteTarget: Equatable {
        case task(Int)
        case group(UUID)
        case groupTask(UUID, Int)
        case history(String)

        var title: String {
            L10n.deleteConfirmationTitle
        }

        var message: String {
            switch self {
            case .task:
                return L10n.deleteTaskConfirmationMessage
            case .groupTask:
                return L10n.deleteTaskConfirmationMessage
            case .history:
                return L10n.deleteTaskConfirmationMessage
            case .group:
                return L10n.deleteGroupConfirmationMessage
            }
        }

        var successMessage: String {
            switch self {
            case .task:
                return L10n.taskDeletedSuccess
            case .groupTask:
                return L10n.taskDeletedSuccess
            case .history:
                return L10n.taskDeletedSuccess
            case .group:
                return L10n.groupDeletedSuccess
            }
        }
    }

    private struct TaskCandidate: Identifiable {
        let id: String
        let task: MyTaskItem
    }

    private struct TaskEditorDraft: Identifiable, Equatable {
        enum Mode: Equatable {
            case createStandalone
            case createGroup(UUID)
            case edit(TaskLocation)
        }

        let id = UUID()
        let mode: Mode
        var text: String
        var startMonthText: String
        var startDayText: String

        var normalizedName: String {
            String(text.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var canSave: Bool {
            !normalizedName.isEmpty
        }
    }

    private enum FilterTab: Equatable {
        case all
        case group(UUID)
    }

    private enum TaskLocation: Hashable {
        case standalone(Int)
        case group(UUID, Int)
    }

    private enum FilteredTaskSource: Equatable {
        case library(TaskLocation)
        case history
    }

    private struct FilteredTaskItem: Identifiable {
        let id: String
        let source: FilteredTaskSource
        let task: MyTaskItem
        let operationDate: Date
        let isLocked: Bool
    }

    struct PreviewSlot: Identifiable, Equatable {
        let id: UUID
        var cellState: BingoCell?
        var sourceTaskKey: String?

        init(id: UUID = UUID(), cellState: BingoCell? = nil, sourceTaskKey: String? = nil) {
            self.id = id
            self.cellState = cellState
            self.sourceTaskKey = sourceTaskKey
        }

        var task: MyTaskItem? {
            guard let cellState else { return nil }
            let text = cellState.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return MyTaskItem(
                text: text,
                startMonth: cellState.startVisibleMonth,
                startDay: cellState.startVisibleDay
            )
        }
    }

    private struct QuickEditSnapshot: Equatable {
        struct PreviewItem: Equatable {
            let cellState: BingoCell?
            let sourceTaskKey: String?
        }

        let targetGridSize: Int
        let selectedTaskKeys: [String]
        let previewItems: [PreviewItem]
        let library: MyTasksLibrary
    }

    private struct ApplyPlan: Equatable {
        let tasks: [MyTaskItem]
        let targetGridSize: Int
    }

    private struct PreviewEditingTarget: Identifiable, Equatable {
        let slotID: UUID
        var id: UUID { slotID }
    }

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var quickEditSectionFlatBackground: Color { NeumorphicColors.innerSurface }
    private var quickEditTaskFlatBackground: Color { NeumorphicColors.background.opacity(0.96) }
    private var quickEditSelectedBadgeBackground: Color { NeumorphicColors.accent.opacity(0.14) }
    private var quickEditFieldStroke: Color { NeumorphicColors.text.opacity(0.06) }
    private var quickEditPlaceholderColor: Color { NeumorphicColors.text.opacity(0.34) }
    private var activeTheme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .concise }
    private var previewEmptySlotFill: Color { activeTheme.bingoSurfaceColor.opacity(0.16) }
    private var previewFilledSlotFill: Color { activeTheme.bingoSurfaceColor.opacity(0.44) }
    private var previewEmptySlotStroke: Color { activeTheme.bingoSurfaceShadowColor.opacity(0.44) }
    private var previewFilledSlotStroke: Color { activeTheme.bingoSurfaceShadowColor.opacity(0.66) }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }
    private var hasExistingBoardTasks: Bool {
        !viewModel.currentTaskPoolTasks().isEmpty
    }

    private var isPremiumUser: Bool {
        subscriptionManager.hasPremiumAccess
    }

    private var canAddStandaloneTask: Bool {
        isPremiumUser || library.tasks.count < AppSettings.maxCommonTasks
    }

    private var canAddGroup: Bool {
        isPremiumUser || library.groups.count < AppSettings.maxTaskGroups
    }

    private func canAddTask(to group: MyTaskGroup) -> Bool {
        isPremiumUser || group.tasks.count < AppSettings.maxTasksPerGroup
    }

    private var maxGridSizeForCurrentPlan: Int {
        isPremiumUser ? 5 : 4
    }

    private func taskKey(for task: MyTaskItem) -> String {
        task.id.uuidString
    }

    private func historyTaskKey(for record: TaskHistoryRecord) -> String {
        "history:\(record.key)"
    }

    private var libraryTaskIDs: Set<UUID> {
        Set(library.tasks.map(\.id) + library.groups.flatMap { $0.tasks.map(\.id) })
    }

    private var historyBySourceTaskID: [UUID: TaskHistoryRecord] {
        var result: [UUID: TaskHistoryRecord] = [:]
        for record in taskHistoryRecords {
            guard let sourceTaskID = record.sourceTaskID else { continue }
            if let existing = result[sourceTaskID], existing.lastEditedAt >= record.lastEditedAt {
                continue
            }
            result[sourceTaskID] = record
        }
        return result
    }

    private var historyOnlyRecordsSorted: [TaskHistoryRecord] {
        taskHistoryRecords
            .filter { record in
                guard !record.trimmedText.isEmpty else { return false }
                guard let sourceTaskID = record.sourceTaskID else { return true }
                return !libraryTaskIDs.contains(sourceTaskID)
            }
            .sorted { lhs, rhs in
                if lhs.lastEditedAt != rhs.lastEditedAt {
                    return lhs.lastEditedAt > rhs.lastEditedAt
                }
                return lhs.key < rhs.key
            }
    }

    private var unlockedHistoryRecords: [TaskHistoryRecord] {
        guard !isPremiumUser else { return historyOnlyRecordsSorted }
        return Array(historyOnlyRecordsSorted.prefix(AppSettings.freeHistoryTasksVisibleCount))
    }

    private var allTaskCandidates: [TaskCandidate] {
        var candidates: [TaskCandidate] = []
        var seenIDs = Set<String>()

        for index in library.tasks.indices {
            let task = library.tasks[index]
            guard !task.trimmedText.isEmpty else { continue }
            let key = taskKey(for: task)
            guard !seenIDs.contains(key) else { continue }
            candidates.append(TaskCandidate(id: key, task: task))
            seenIDs.insert(key)
        }

        for group in library.groups {
            for index in group.tasks.indices {
                let task = group.tasks[index]
                guard !task.trimmedText.isEmpty else { continue }
                let key = taskKey(for: task)
                guard !seenIDs.contains(key) else { continue }
                candidates.append(TaskCandidate(id: key, task: task))
                seenIDs.insert(key)
            }
        }

        for record in unlockedHistoryRecords {
            let key = historyTaskKey(for: record)
            guard !seenIDs.contains(key) else { continue }
            candidates.append(
                TaskCandidate(
                    id: key,
                    task: MyTaskItem(
                        text: record.trimmedText,
                        startMonth: record.startMonth,
                        startDay: record.startDay
                    )
                )
            )
            seenIDs.insert(key)
        }

        return candidates
    }

    private var filteredTaskItems: [FilteredTaskItem] {
        switch activeFilter {
        case .all:
            var items: [FilteredTaskItem] = library.tasks.indices.compactMap { index in
                let task = library.tasks[index]
                guard !task.trimmedText.isEmpty else { return nil }
                let operationDate = historyBySourceTaskID[task.id]?.lastEditedAt ?? .distantPast
                return FilteredTaskItem(
                    id: taskKey(for: task),
                    source: .library(.standalone(index)),
                    task: task,
                    operationDate: operationDate,
                    isLocked: false
                )
            }

            for group in library.groups {
                items.append(contentsOf: group.tasks.indices.compactMap { index in
                    let task = group.tasks[index]
                    guard !task.trimmedText.isEmpty else { return nil }
                    let operationDate = historyBySourceTaskID[task.id]?.lastEditedAt ?? .distantPast
                    return FilteredTaskItem(
                        id: taskKey(for: task),
                        source: .library(.group(group.id, index)),
                        task: task,
                        operationDate: operationDate,
                        isLocked: false
                    )
                })
            }

            let historyItems = historyOnlyRecordsSorted.enumerated().map { index, record in
                let isLocked = !isPremiumUser && index >= AppSettings.freeHistoryTasksVisibleCount
                return FilteredTaskItem(
                    id: historyTaskKey(for: record),
                    source: .history,
                    task: MyTaskItem(
                        text: record.trimmedText,
                        startMonth: record.startMonth,
                        startDay: record.startDay
                    ),
                    operationDate: record.lastEditedAt,
                    isLocked: isLocked
                )
            }
            items.append(contentsOf: historyItems)

            return items.sorted { lhs, rhs in
                if lhs.operationDate != rhs.operationDate {
                    return lhs.operationDate > rhs.operationDate
                }
                return lhs.id < rhs.id
            }
        case .group(let groupID):
            guard let group = library.groups.first(where: { $0.id == groupID }) else { return [] }
            return group.tasks.indices.compactMap { index in
                let task = group.tasks[index]
                guard !task.trimmedText.isEmpty else { return nil }
                let operationDate = historyBySourceTaskID[task.id]?.lastEditedAt ?? .distantPast
                return FilteredTaskItem(
                    id: taskKey(for: task),
                    source: .library(.group(groupID, index)),
                    task: task,
                    operationDate: operationDate,
                    isLocked: false
                )
            }
        }
    }

    private var candidateTaskMap: [String: MyTaskItem] {
        Dictionary(uniqueKeysWithValues: allTaskCandidates.map { ($0.id, $0.task) })
    }

    private var totalGridSlots: Int {
        targetGridSize * targetGridSize
    }

    private var selectedPreviewCount: Int {
        previewSlots.compactMap(\.task).count
    }

    private var selectedCountSummary: String {
        L10n.quickEditSelectedCount(selected: selectedPreviewCount, total: totalGridSlots)
    }

private var activeFilterTitle: String {
    switch activeFilter {
    case .all:
        return L10n.allTasks
    case .group(let groupID):
        guard let group = library.groups.first(where: { $0.id == groupID }) else {
            return L10n.allTasks
        }
        return displayGroupName(group)
    }
}

    private var activeGroupID: UUID? {
    if case .group(let groupID) = activeFilter {
        return groupID
    }
    return nil
}

    private var activeGroupTasks: [MyTaskItem] {
        guard case .group(let groupID) = activeFilter,
              let group = library.groups.first(where: { $0.id == groupID }) else {
            return []
        }
        return group.tasks.filter { !$0.trimmedText.isEmpty }
    }

    private var activeGroupTaskKeys: [String] {
        activeGroupTasks.map(taskKey(for:))
    }
    var body: some View {
        NavigationStack {
            ZStack {
                NeumorphicColors.background
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        focusedField = nil
                    }

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        quickEditControlsCard
                        filterTabsSection
                            .padding(.top, -10)
                        taskListSection
                    }
                    .frame(maxWidth: isPadLayout ? 760 : .infinity, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 110)
                }
                .scrollDismissesKeyboard(.interactively)

                if isLocalToastVisible, let localToastMessage {
                    VStack {
                        Text(localToastMessage)
                            .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.96))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(NeumorphicColors.accent.opacity(0.92))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(.white.opacity(0.28), lineWidth: 1)
                                    )
                            )
                            .shadow(color: NeumorphicColors.darkShadow.opacity(0.12), radius: 8, x: 0, y: 4)
                            .shadow(color: NeumorphicColors.accent.opacity(0.34), radius: 10, x: 0, y: 6)
                        Spacer()
                    }
                    .padding(.top, 18)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
                }
                if isAddingGroupModalPresented {
                    addGroupModal
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                if taskEditorDraft != nil {
                    taskEditorModal
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NeumorphicColors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L10n.quickEdit)
                        .font(.appSystem(size: scaled(20, pad: 23), weight: .bold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.tr("Exit", zhHans: "退出", zhHant: "退出")) {
                        handleExitTap()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(NeumorphicColors.text)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.tr("Apply", zhHans: "应用", zhHant: "套用")) {
                        handleDoneTap()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(NeumorphicColors.text)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button(L10n.done) {
                        focusedField = nil
                    }
                    .font(.appSystem(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.accent)
                }
            }
        }
        .onDisappear {
            guard !didApplyToBoard else { return }
            finalizeLibrary()
        }
        .onAppear {
            targetGridSize = viewModel.gridSize
            activeFilter = .all
            previewSlots = buildInitialPreviewSlots()
            selectedTaskKeys = []
            seedTaskHistoryIfNeeded()
            initialSnapshot = makeCurrentSnapshot()
            syncActiveFilterWithCurrentLibrary()
        }
        .onChange(of: library) { _, _ in
            TaskHistoryStore.ensureLibrarySeeded(library)
            refreshTaskHistory()
            syncSelectedTaskKeysWithCurrentLibrary()
            syncPreviewSlotsWithCurrentLibrary()
            syncActiveFilterWithCurrentLibrary()
        }
        .onChange(of: targetGridSize) { _, _ in
            adjustPreviewSlotCount()
        }
        .fullScreenCover(isPresented: $isPremiumPaywallPresented) {
            PremiumPaywallView(entrySource: premiumPaywallSource)
        }
        .fullScreenCover(item: $previewEditingTarget) { target in
            previewEditTaskSheet(for: target.slotID)
                .background(Color.clear)
                .presentationBackground(.clear)
        }
        .alert(
            L10n.tr("Discard changes?", zhHans: "确认退出？", zhHant: "確認退出？"),
            isPresented: $isExitDiscardAlertPresented
        ) {
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.tr("Exit", zhHans: "退出", zhHant: "退出"), role: .destructive) {
                dismiss()
            }
        } message: {
            Text(L10n.tr("If you exit now, your recent edits will not be applied to the board.", zhHans: "现在退出，刚刚的改动将不会应用到棋盘。", zhHant: "現在退出，剛剛的改動將不會套用到棋盤。"))
        }
        .alert(
            deleteConfirmationTarget?.title ?? L10n.deleteConfirmationTitle,
            isPresented: Binding(
                get: { deleteConfirmationTarget != nil },
                set: { isPresented in
                    if !isPresented {
                        deleteConfirmationTarget = nil
                    }
                }
            ),
            presenting: deleteConfirmationTarget
        ) { target in
            Button(L10n.cancel, role: .cancel) {}
            Button(target.title, role: .destructive) {
                confirmDelete(target)
            }
        } message: { target in
            Text(deleteMessage(for: target))
        }
        .alert(
            L10n.tr("Delete this group?", zhHans: "删除该分组？", zhHant: "刪除該分組？"),
            isPresented: Binding(
                get: { pendingGroupDeleteFinalConfirmation != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingGroupDeleteFinalConfirmation = nil
                    }
                }
            )
        ) {
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.deleteConfirmationTitle, role: .destructive) {
                guard let groupID = pendingGroupDeleteFinalConfirmation else { return }
                finalizeGroupDeletion(groupID)
            }
        } message: {
            let name = pendingGroupDeleteFinalConfirmation.map(groupName(for:)) ?? L10n.groupDefaultName
            Text(
                L10n.tr(
                    "All tasks in \"\(name)\" will be deleted and cannot be undone.",
                    zhHans: "「\(name)」中的所有任务将被删除，且不可恢复。",
                    zhHant: "「\(name)」中的所有任務將被刪除，且不可恢復。"
                )
            )
        }
        .alert(
            L10n.quickEditReplaceConfirmationTitle,
            isPresented: Binding(
                get: { pendingApplyPlan != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingApplyPlan = nil
                    }
                }
            )
        ) {
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.apply) {
                guard let plan = pendingApplyPlan else { return }
                pendingApplyPlan = nil
                applySelectionToBoard(plan)
            }
        } message: {
            Text(L10n.quickEditReplaceConfirmationMessage)
        }
        .safeAreaInset(edge: .bottom) {
            if isPremiumUser {
                quickEditBottomAddTaskBar
            }
        }
    }

private var quickEditControlsCard: some View {
    let gridSpacing: CGFloat = isPadLayout ? 16 : 12
    let controlSize: CGFloat = isPadLayout ? 38 : 32
    let iconSize: CGFloat = isPadLayout ? 18 : 16

    return flatSectionCard {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: isPadLayout ? 14 : 11) {
                    Button {
                        targetGridSize = max(2, targetGridSize - 1)
                    } label: {
                        Image(systemName: "minus")
                            .font(.appSystem(size: iconSize, weight: .bold))
                            .foregroundColor(NeumorphicColors.accent)
                            .frame(width: controlSize, height: controlSize)
                            .background(Color.clear.neumorphicConvex(radius: controlSize / 2))
                    }
                    .buttonStyle(.plain)
                    .disabled(targetGridSize <= 2)
                    .opacity(targetGridSize <= 2 ? 0.45 : 1)

                    Text("\(targetGridSize)")
                        .font(.appSystem(size: scaled(18, pad: 22), weight: .medium, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)

                    Image(systemName: "xmark")
                        .font(.appSystem(size: scaled(10, pad: 12), weight: .bold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text.opacity(0.6))

                    Text("\(targetGridSize)")
                        .font(.appSystem(size: scaled(18, pad: 22), weight: .medium, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)

                    Button {
                        let nextSize = targetGridSize + 1
                        guard nextSize <= maxGridSizeForCurrentPlan else {
                            AnalyticsService.logPremiumGrid5x5LimitHit(
                                currentGridSize: targetGridSize,
                                source: "quick_edit"
                            )
                            openPremiumPaywall(source: "quick_edit_grid_5x5")
                            return
                        }
                        targetGridSize = min(5, nextSize)
                    } label: {
                        Image(systemName: "plus")
                            .font(.appSystem(size: iconSize, weight: .bold))
                            .foregroundColor(NeumorphicColors.accent)
                            .frame(width: controlSize, height: controlSize)
                            .background(Color.clear.neumorphicConvex(radius: controlSize / 2))
                    }
                    .buttonStyle(.plain)
                    .disabled(targetGridSize >= 5)
                    .opacity(targetGridSize >= 5 ? 0.45 : 1)
                }

                Spacer(minLength: 0)

                Text(selectedCountSummary)
                    .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.92))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(quickEditSelectedBadgeBackground)
                    )
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: targetGridSize),
                spacing: gridSpacing
            ) {
                ForEach(previewSlots) { slot in
                    previewSlotCard(slot)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .onDrag {
                        guard slot.task != nil else { return NSItemProvider() }
                        previewDragSourceID = slot.id
                        previewDropTargetID = nil
                        return NSItemProvider(object: NSString(string: slot.id.uuidString))
                    }
                    .onDrop(
                        of: ["public.text", "public.plain-text"],
                        delegate: QuickEditPreviewDropDelegate(
                            targetSlotID: slot.id,
                            previewSlots: $previewSlots,
                            dragSourceID: $previewDragSourceID,
                            dropTargetID: $previewDropTargetID
                        )
                    )
                    .contextMenu {
                        if slot.task != nil {
                            Button {
                                previewEditingTarget = PreviewEditingTarget(slotID: slot.id)
                            } label: {
                                Label(L10n.editTask, systemImage: "square.and.pencil")
                            }

                            Button(role: .destructive) {
                                deletePreviewTask(slotID: slot.id)
                            } label: {
                                Label(L10n.deleteTask, systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .onDrop(of: ["public.text", "public.plain-text"], isTargeted: nil) { _ in
                clearPreviewDragState()
                return false
            }
        }
    }
}

    @ViewBuilder
    private func previewSlotCard(_ slot: PreviewSlot) -> some View {
        let cornerRadius: CGFloat = isPadLayout ? 18 : 16
        let hasTask = slot.task != nil

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(hasTask ? previewFilledSlotFill : previewEmptySlotFill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(hasTask ? previewFilledSlotStroke : previewEmptySlotStroke, lineWidth: 1)
                )

            if let task = slot.task?.trimmedText, !task.isEmpty {
                Text(task)
                    .font(.appSystem(size: scaled(14, pad: 18), weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
                    .padding(10)
            }
        }
    }

    private var filterTabsSection: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterTabButton(
                        title: L10n.allTasks,
                        isSelected: activeFilter == .all
                    ) {
                        activeFilter = .all
                    }

                    ForEach(library.groups) { group in
                        filterTabButton(
                            title: displayGroupName(group),
                            isSelected: activeFilter == .group(group.id)
                        ) {
                            activeFilter = .group(group.id)
                        }
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.8)
                                .onEnded { _ in
                                    focusedField = nil
                                    deleteConfirmationTarget = .group(group.id)
                                }
                        )
                    }
                }
                .padding(.vertical, 2)
            }

            Button {
                presentAddGroupModal()
            } label: {
                Text("+ \(L10n.addGroup)")
                    .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.clear.neumorphicConvex(radius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    private func filterTabButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                .foregroundColor(isSelected ? .white : NeumorphicColors.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? NeumorphicColors.accent : NeumorphicColors.background)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(
                            isSelected ? NeumorphicColors.accent : quickEditFieldStroke,
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
    }

private var taskListSection: some View {
    flatSectionCard {
        let visibleItems = filteredTaskItems.filter { !$0.isLocked }
        let lockedHistoryPreviewItems = Array(
            filteredTaskItems
                .filter { $0.isLocked && $0.source == .history }
                .prefix(5)
        )
        let isAllTasksFilter = activeFilter == .all

        VStack(alignment: .leading, spacing: isAllTasksFilter ? 8 : 12) {
            if !isAllTasksFilter {
                HStack(spacing: 10) {
                    Text(activeFilterTitle)
                        .font(.appSystem(size: scaled(15, pad: 19), weight: .semibold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)

                    Spacer(minLength: 0)

                    if let activeGroupID {
                        Button {
                            applyActiveGroupToPreview()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.appSystem(size: scaled(11, pad: 13), weight: .semibold))
                                Text(L10n.quickEditApplyGroup)
                                    .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(NeumorphicColors.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(quickEditTaskFlatBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(NeumorphicColors.accent.opacity(0.28), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(activeGroupTaskKeys.isEmpty)
                        .opacity(activeGroupTaskKeys.isEmpty ? 0.45 : 1)

                        Button {
                            focusedField = nil
                            deleteConfirmationTarget = .group(activeGroupID)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.appSystem(size: scaled(11, pad: 13), weight: .semibold))
                                Text(L10n.tr("Delete Group", zhHans: "删除分组", zhHant: "刪除分組"))
                                    .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(NeumorphicColors.bingoAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(quickEditTaskFlatBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(NeumorphicColors.bingoAccent.opacity(0.28), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if isAllTasksFilter {
                Text(
                    L10n.tr(
                        "You can view and edit all your task history here.",
                        zhHans: "在这里可以查看并编辑你所有的历史任务",
                        zhHant: "在這裡可以查看並編輯你所有的歷史任務"
                    )
                )
                .font(.appSystem(size: scaled(12, pad: 14), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.55))
                .padding(.top, 2)
                .padding(.bottom, 4)
            }

            if visibleItems.isEmpty && !isAddingTaskInline && lockedHistoryPreviewItems.isEmpty {
                Text(L10n.quickEditNoTasksInFilter)
                    .font(.appSystem(size: scaled(13, pad: 15), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.56))
                    .padding(.vertical, 8)
            }

            VStack(spacing: 10) {
                ForEach(visibleItems) { item in
                    taskRow(for: item)
                }

                if !lockedHistoryPreviewItems.isEmpty {
                    lockedHistoryPreviewBlock(items: lockedHistoryPreviewItems)
                }

                if isAddingTaskInline {
                    newTaskInlineRow
                }
            }

            if activeGroupID != nil {
                addTaskButton
                    .padding(.top, 8)
            }
        }
    }
}

    private var quickEditBottomAddTaskBar: some View {
        VStack(spacing: 0) {
            addTaskButton
                .frame(maxWidth: isPadLayout ? 760 : .infinity)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)
                .padding(.top, 6)
                .padding(.bottom, 10)
        }
        .background(NeumorphicColors.background.opacity(0.96))
    }

    private func lockedHistoryPreviewBlock(items: [FilteredTaskItem]) -> some View {
        Button {
            presentPremiumPaywallForLimit(source: "quick_edit_all_tasks_history_locked")
        } label: {
            ZStack {
                VStack(spacing: 10) {
                    ForEach(items) { item in
                        HStack(spacing: 10) {
                            Image(systemName: "circle")
                                .font(.appSystem(size: scaled(18, pad: 20), weight: .bold))
                                .foregroundColor(NeumorphicColors.text.opacity(0.28))
                                .frame(width: 24, height: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.task.trimmedText)
                                    .font(.appSystem(size: scaled(15, pad: 18), weight: .medium, design: .rounded))
                                    .foregroundColor(NeumorphicColors.text.opacity(0.7))
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(quickEditTaskFlatBackground)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(quickEditFieldStroke, lineWidth: 1)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .blur(radius: 2.8)
                .allowsHitTesting(false)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.2))
                    .overlay(
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.appSystem(size: scaled(11, pad: 13), weight: .bold))
                            Text(L10n.quickEditHistoryPaywallHint)
                                .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                                .lineLimit(1)
                        }
                        .foregroundColor(.white.opacity(0.96))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.36))
                        )
                    )
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func taskRow(for item: FilteredTaskItem) -> some View {
        if item.isLocked {
            lockedHistoryTaskRow(for: item)
        } else {
            switch item.source {
            case .library(let location):
                editableLibraryTaskRow(for: item, location: location)
            case .history:
                readOnlyHistoryTaskRow(for: item)
            }
        }
    }

    private func editableLibraryTaskRow(for item: FilteredTaskItem, location: TaskLocation) -> some View {
        let key = item.id
        let isSelected = selectedTaskKeys.contains(key)

        return HStack(spacing: 10) {
            Button {
                toggleSelection(for: key)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.appSystem(size: scaled(18, pad: 20), weight: .bold))
                    .foregroundColor(isSelected ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.38))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            TextField(
                text: taskBinding(for: location),
                prompt: Text(placeholder(for: location))
                    .foregroundColor(quickEditPlaceholderColor)
            ) {
                EmptyView()
            }
            .textInputAutocapitalization(.sentences)
            .font(.appSystem(size: scaled(15, pad: 18), weight: .medium, design: .rounded))
            .foregroundColor(NeumorphicColors.text)
            .lineLimit(1)
            .focused($focusedField, equals: focusedField(for: location))

            Button {
                focusedField = nil
                deleteConfirmationTarget = deleteTarget(for: location)
            } label: {
                Image(systemName: "trash")
                    .font(.appSystem(size: scaled(13, pad: 15), weight: .medium))
                    .foregroundColor(NeumorphicColors.text.opacity(0.52))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(quickEditTaskFlatBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(quickEditFieldStroke, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func readOnlyHistoryTaskRow(for item: FilteredTaskItem) -> some View {
        let key = item.id
        let isSelected = selectedTaskKeys.contains(key)

        return HStack(spacing: 10) {
            Button {
                toggleSelection(for: key)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.appSystem(size: scaled(18, pad: 20), weight: .bold))
                    .foregroundColor(isSelected ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.38))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.task.trimmedText)
                    .font(.appSystem(size: scaled(15, pad: 18), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                deleteConfirmationTarget = .history(item.id)
                focusedField = nil
            } label: {
                Image(systemName: "trash")
                    .font(.appSystem(size: scaled(13, pad: 15), weight: .medium))
                    .foregroundColor(NeumorphicColors.text.opacity(0.52))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(quickEditTaskFlatBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(quickEditFieldStroke, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func lockedHistoryTaskRow(for item: FilteredTaskItem) -> some View {
        Button {
            presentPremiumPaywallForLimit(source: "quick_edit_all_tasks_history_locked")
        } label: {
            ZStack {
                HStack(spacing: 10) {
                    Image(systemName: "circle")
                        .font(.appSystem(size: scaled(18, pad: 20), weight: .bold))
                        .foregroundColor(NeumorphicColors.text.opacity(0.28))
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.task.trimmedText)
                            .font(.appSystem(size: scaled(15, pad: 18), weight: .medium, design: .rounded))
                            .foregroundColor(NeumorphicColors.text.opacity(0.7))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(quickEditTaskFlatBackground)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(quickEditFieldStroke, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .blur(radius: 2.8)

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.18))

                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.appSystem(size: scaled(11, pad: 13), weight: .bold))
                    Text(L10n.quickEditHistoryPaywallHint)
                        .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundColor(.white.opacity(0.96))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.32))
                )
            }
        }
        .buttonStyle(.plain)
    }

private var newTaskInlineRow: some View {
    HStack(spacing: 10) {
        TextField(
            "",
            text: $newTaskDraft,
            prompt: Text(L10n.quickEditTaskNamePlaceholder)
                .foregroundColor(quickEditPlaceholderColor)
        )
        .textInputAutocapitalization(.sentences)
        .font(.appSystem(size: scaled(15, pad: 18), weight: .medium, design: .rounded))
        .foregroundColor(NeumorphicColors.text)
        .focused($focusedField, equals: .newTask)
        .onSubmit {
            commitAddingTaskInline()
        }

        Button(L10n.save) {
            commitAddingTaskInline()
        }
        .font(.appSystem(size: scaled(12, pad: 14), weight: .bold, design: .rounded))
        .foregroundColor(NeumorphicColors.accent)
        .buttonStyle(.plain)
        .disabled(newTaskDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(newTaskDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)

        Button(L10n.cancel) {
            cancelAddingTaskInline()
        }
        .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
        .foregroundColor(NeumorphicColors.text.opacity(0.62))
        .buttonStyle(.plain)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 50)
    .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(quickEditTaskFlatBackground)
    )
    .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(NeumorphicColors.accent.opacity(0.45), lineWidth: 1)
            .allowsHitTesting(false)
    }
}

    private var addTaskButton: some View {
        Button {
            if isAddingTaskInline {
                commitAddingTaskInline()
            } else {
                startAddingTaskInline()
            }
        } label: {
            Text(L10n.addTask)
                .font(.appSystem(size: scaled(15, pad: 17), weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(NeumorphicColors.accent)
                        .shadow(color: NeumorphicColors.accent.opacity(0.24), radius: 10, x: 0, y: 6)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var addGroupModal: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissAddGroupModal()
                }

            VStack(spacing: 14) {
                Text(L10n.quickEditAddGroupTitle)
                    .font(.appSystem(size: scaled(19, pad: 24), weight: .bold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)

                TextField(
                    "",
                    text: $newGroupNameDraft,
                    prompt: Text(L10n.quickEditGroupNamePlaceholder)
                        .foregroundColor(quickEditPlaceholderColor)
                )
                .textInputAutocapitalization(.sentences)
                .font(.appSystem(size: scaled(15, pad: 18), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(quickEditTaskFlatBackground)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(quickEditFieldStroke, lineWidth: 1)
                }
                .focused($focusedField, equals: .newGroupName)
                .onSubmit {
                    commitAddGroup()
                }

                HStack(spacing: 12) {
                    Button(L10n.cancel) {
                        dismissAddGroupModal()
                    }
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.78))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.clear.neumorphicConvex(radius: 18))
                    .buttonStyle(.plain)

                    Button(L10n.addGroup) {
                        commitAddGroup()
                    }
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(NeumorphicColors.accent)
                            .shadow(color: NeumorphicColors.accent.opacity(0.25), radius: 10, x: 0, y: 4)
                    )
                    .buttonStyle(.plain)
                    .disabled(newGroupNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(newGroupNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                }
            }
            .padding(20)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(NeumorphicColors.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(NeumorphicColors.lightShadow.opacity(0.42), lineWidth: 1)
                    )
                    .shadow(color: NeumorphicColors.darkShadow.opacity(0.18), radius: 16, x: 0, y: 8)
                    .shadow(color: Color.white.opacity(0.72), radius: 10, x: -4, y: -4)
            )
            .padding(.horizontal, 28)
        }
    }

    @ViewBuilder
    private var taskEditorModal: some View {
        if let taskEditorDraft {
            ZStack {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissTaskEditor()
                    }

                VStack(spacing: 14) {
                    Text(L10n.quickEditTaskEditorTitle)
                        .font(.appSystem(size: scaled(19, pad: 24), weight: .bold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)

                    TextField(
                        "",
                        text: taskEditorNameBinding,
                        prompt: Text(L10n.quickEditTaskNamePlaceholder)
                            .foregroundColor(quickEditPlaceholderColor)
                    )
                    .textInputAutocapitalization(.sentences)
                    .font(.appSystem(size: scaled(15, pad: 18), weight: .medium, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(quickEditTaskFlatBackground)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(quickEditFieldStroke, lineWidth: 1)
                    }
                    .focused($focusedField, equals: .taskEditorName)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.quickEditTaskStartDate)
                            .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                            .foregroundColor(NeumorphicColors.text.opacity(0.68))

                        HStack(spacing: 8) {
                            TextField(L10n.quickEditTaskStartMonth, text: taskEditorMonthBinding)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                                .frame(height: 40)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(quickEditTaskFlatBackground)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(quickEditFieldStroke, lineWidth: 1)
                                }
                                .focused($focusedField, equals: .taskEditorMonth)

                            Text("/")
                                .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text.opacity(0.6))

                            TextField(L10n.quickEditTaskStartDay, text: taskEditorDayBinding)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                                .frame(height: 40)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(quickEditTaskFlatBackground)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(quickEditFieldStroke, lineWidth: 1)
                                }
                                .focused($focusedField, equals: .taskEditorDay)
                        }

                        Button(L10n.quickEditTaskNoStartDate) {
                            clearTaskEditorStartDate()
                        }
                        .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text.opacity(0.66))
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 12) {
                        Button(L10n.cancel) {
                            dismissTaskEditor()
                        }
                        .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text.opacity(0.78))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.clear.neumorphicConvex(radius: 18))
                        .buttonStyle(.plain)

                        Button(L10n.save) {
                            saveTaskEditorDraft()
                        }
                        .font(.appSystem(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(NeumorphicColors.accent)
                                .shadow(color: NeumorphicColors.accent.opacity(0.25), radius: 10, x: 0, y: 4)
                        )
                        .buttonStyle(.plain)
                        .disabled(!taskEditorDraft.canSave)
                        .opacity(taskEditorDraft.canSave ? 1 : 0.45)
                    }
                }
                .padding(20)
                .frame(maxWidth: 340)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(NeumorphicColors.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(NeumorphicColors.lightShadow.opacity(0.42), lineWidth: 1)
                        )
                        .shadow(color: NeumorphicColors.darkShadow.opacity(0.18), radius: 16, x: 0, y: 8)
                        .shadow(color: Color.white.opacity(0.72), radius: 10, x: -4, y: -4)
                )
                .padding(.horizontal, 28)
            }
        }
    }

    private var taskEditorNameBinding: Binding<String> {
        Binding(
            get: { taskEditorDraft?.text ?? "" },
            set: { newValue in
                guard var draft = taskEditorDraft else { return }
                draft.text = newValue
                taskEditorDraft = draft
            }
        )
    }

    private var taskEditorMonthBinding: Binding<String> {
        Binding(
            get: { taskEditorDraft?.startMonthText ?? "" },
            set: { newValue in
                guard var draft = taskEditorDraft else { return }
                draft.startMonthText = String(newValue.filter(\.isNumber).prefix(2))
                taskEditorDraft = draft
            }
        )
    }

    private var taskEditorDayBinding: Binding<String> {
        Binding(
            get: { taskEditorDraft?.startDayText ?? "" },
            set: { newValue in
                guard var draft = taskEditorDraft else { return }
                draft.startDayText = String(newValue.filter(\.isNumber).prefix(2))
                taskEditorDraft = draft
            }
        )
    }

    private func taskBinding(for location: TaskLocation) -> Binding<String> {
        switch location {
        case .standalone(let index):
            return taskBinding(for: index)
        case .group(let groupID, let index):
            return groupTaskBinding(groupID: groupID, index: index)
        }
    }

    private func focusedField(for location: TaskLocation) -> FocusedMyTaskField {
        switch location {
        case .standalone(let index):
            return .task(index)
        case .group(let groupID, let index):
            return .groupTask(groupID, index)
        }
    }

    private func placeholder(for location: TaskLocation) -> String {
        switch location {
        case .standalone(let index):
            return L10n.taskNumber(index + 1)
        case .group:
            return L10n.task
        }
    }

    private func deleteTarget(for location: TaskLocation) -> DeleteTarget {
        switch location {
        case .standalone(let index):
            return .task(index)
        case .group(let groupID, let index):
            return .groupTask(groupID, index)
        }
    }

    private func task(for location: TaskLocation) -> MyTaskItem? {
        switch location {
        case .standalone(let index):
            guard library.tasks.indices.contains(index) else { return nil }
            return library.tasks[index]
        case .group(let groupID, let index):
            guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }),
                  library.groups[groupIndex].tasks.indices.contains(index) else { return nil }
            return library.groups[groupIndex].tasks[index]
        }
    }

    private func setTask(_ task: MyTaskItem, for location: TaskLocation) {
        switch location {
        case .standalone(let index):
            guard library.tasks.indices.contains(index) else { return }
            library.tasks[index] = task
        case .group(let groupID, let index):
            guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }),
                  library.groups[groupIndex].tasks.indices.contains(index) else { return }
            library.groups[groupIndex].tasks[index] = task
        }
    }

    private func taskStartDateLabel(for location: TaskLocation) -> String {
        guard let task = task(for: location),
              let month = task.startMonth,
              let day = task.startDay else {
            return L10n.quickEditTaskNoStartDate
        }
        return "\(month)/\(day)"
    }

    private func normalizedMonthDay(monthText: String, dayText: String) -> (Int?, Int?) {
        let trimmedMonth = monthText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDay = dayText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMonth.isEmpty || !trimmedDay.isEmpty else {
            return (nil, nil)
        }

        guard let month = Int(trimmedMonth), let day = Int(trimmedDay) else {
            return (nil, nil)
        }

        guard (1...12).contains(month), (1...31).contains(day) else {
            return (nil, nil)
        }

        var components = DateComponents()
        components.year = 2000
        components.month = month
        components.day = day
        guard Calendar.current.date(from: components) != nil else {
            return (nil, nil)
        }

        return (month, day)
    }

    private func makePreviewCell(from task: MyTaskItem, preserving existingCell: BingoCell? = nil) -> BingoCell {
        var taskCopy = task
        taskCopy.text = String(task.text.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        taskCopy.normalizeStartDate()

        guard let existingCell else {
            return BingoCell(
                text: taskCopy.trimmedText,
                residentTaskText: nil,
                residentWeekdays: [],
                oneTimeVisibleDate: nil,
                startVisibleMonth: taskCopy.startMonth,
                startVisibleDay: taskCopy.startDay,
                isTaskHidden: false,
                isCompleted: false,
                isForced: false,
                countdownEndsAt: nil,
                completionStreakCount: 0,
                lastCompletedAt: nil
            )
        }

        var cell = existingCell
        cell.text = taskCopy.trimmedText
        if cell.residentTaskText != nil {
            cell.residentTaskText = taskCopy.trimmedText
        }
        cell.startVisibleMonth = taskCopy.startMonth
        cell.startVisibleDay = taskCopy.startDay
        cell.isTaskHidden = false
        // Force flag is only set by explicit EditTaskSheet toggle.
        cell.isForced = false
        return cell
    }

    private func makePreviewCellFromEdit(
        existingCell: BingoCell?,
        text: String,
        isForcedTask: Bool,
        residentWeekdays: Set<Int>,
        isOneTimeTask: Bool,
        estimatedDurationMinutes: Int?,
        startVisibleMonth: Int?,
        startVisibleDay: Int?
    ) -> BingoCell? {
        let limitedText = String(text.prefix(AppSettings.maxTaskLength))
        let trimmedText = limitedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        let normalizedWeekdays = Set(residentWeekdays.filter { (1...7).contains($0) })
        let normalizedOneTimeTask = isOneTimeTask
        let usesStoredSchedule = !normalizedWeekdays.isEmpty || normalizedOneTimeTask
        let normalizedStart = normalizedMonthDay(
            monthText: startVisibleMonth.map(String.init) ?? "",
            dayText: startVisibleDay.map(String.init) ?? ""
        )

        var cell = existingCell ?? BingoCell()
        let previousStoredTaskText = cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isReplacingTaskIdentity = previousStoredTaskText != trimmedText

        cell.residentWeekdays = normalizedWeekdays
        cell.oneTimeVisibleDate = normalizedOneTimeTask ? .now : nil
        cell.startVisibleMonth = normalizedStart.0
        cell.startVisibleDay = normalizedStart.1
        cell.residentTaskText = usesStoredSchedule ? limitedText : nil
        cell.text = limitedText
        cell.isTaskHidden = false
        cell.isForced = isForcedTask
        cell.countdownEndsAt = nil

        if let estimatedDurationMinutes {
            let totalMinutes = min(max(estimatedDurationMinutes, 1), BingoViewModel.maxCountdownMinutes)
            cell.countdownEndsAt = Date().addingTimeInterval(Double(totalMinutes * 60))
        }

        if isReplacingTaskIdentity {
            cell.completionStreakCount = 0
            cell.lastCompletedAt = nil
        }

        return cell
    }

    private func remainingMinutes(from countdownEndsAt: Date?) -> Int? {
        guard let countdownEndsAt else { return nil }
        let remainingSeconds = max(countdownEndsAt.timeIntervalSince(.now), 0)
        let remainingMinutes = Int(ceil(remainingSeconds / 60))
        return max(remainingMinutes, 1)
    }

    private func openTaskEditor(for location: TaskLocation) {
        guard let currentTask = task(for: location) else { return }
        taskEditorDraft = TaskEditorDraft(
            mode: .edit(location),
            text: currentTask.text,
            startMonthText: currentTask.startMonth.map(String.init) ?? "",
            startDayText: currentTask.startDay.map(String.init) ?? ""
        )

        DispatchQueue.main.async {
            focusedField = .taskEditorName
        }
    }

    @ViewBuilder
    private func previewEditTaskSheet(for slotID: UUID) -> some View {
        if let index = previewSlots.firstIndex(where: { $0.id == slotID }),
           let currentCell = previewSlots[index].cellState {
            EditTaskSheet(
                text: currentCell.storedTaskText,
                isForcedTask: currentCell.isForced,
                residentWeekdays: currentCell.residentWeekdays,
                isOneTimeTask: currentCell.isOneTimeTask,
                startVisibleMonth: currentCell.startVisibleMonth,
                startVisibleDay: currentCell.startVisibleDay,
                isCompletedTask: currentCell.isCompleted,
                estimatedDurationMinutes: remainingMinutes(from: currentCell.countdownEndsAt),
                onSave: { newText, isForcedTask, residentWeekdays, isOneTimeTask, estimatedDurationMinutes, startVisibleMonth, startVisibleDay in
                    guard let latestIndex = previewSlots.firstIndex(where: { $0.id == slotID }) else {
                        previewEditingTarget = nil
                        return
                    }

                    let existingCell = previewSlots[latestIndex].cellState
                    previewSlots[latestIndex].cellState = makePreviewCellFromEdit(
                        existingCell: existingCell,
                        text: newText,
                        isForcedTask: isForcedTask,
                        residentWeekdays: residentWeekdays,
                        isOneTimeTask: isOneTimeTask,
                        estimatedDurationMinutes: estimatedDurationMinutes,
                        startVisibleMonth: startVisibleMonth,
                        startVisibleDay: startVisibleDay
                    )

                    if let sourceTaskKey = previewSlots[latestIndex].sourceTaskKey {
                        let syncedTask = previewSlots[latestIndex].task ?? MyTaskItem(text: "")
                        syncLibraryTask(forTaskKey: sourceTaskKey, with: syncedTask)
                    }
                    previewEditingTarget = nil
                },
                onDelete: {
                    deletePreviewTask(slotID: slotID)
                    previewEditingTarget = nil
                },
                onCancel: {
                    previewEditingTarget = nil
                }
            )
        } else {
            Color.clear
                .onAppear {
                    previewEditingTarget = nil
                }
        }
    }

    private func deletePreviewTask(slotID: UUID) {
        guard let index = previewSlots.firstIndex(where: { $0.id == slotID }) else { return }
        if let sourceTaskKey = previewSlots[index].sourceTaskKey {
            selectedTaskKeys.removeAll(where: { $0 == sourceTaskKey })
        }
        previewSlots[index].cellState = nil
        previewSlots[index].sourceTaskKey = nil
        showLocalToast(L10n.taskDeletedSuccess)
    }

    private func clearTaskEditorStartDate() {
        guard var draft = taskEditorDraft else { return }
        draft.startMonthText = ""
        draft.startDayText = ""
        taskEditorDraft = draft
    }

    private func dismissTaskEditor() {
        taskEditorDraft = nil
        focusedField = nil
    }

    private func saveTaskEditorDraft() {
        guard let draft = taskEditorDraft else { return }
        let normalizedName = draft.normalizedName
        guard draft.canSave else { return }

        let (startMonth, startDay) = normalizedMonthDay(
            monthText: draft.startMonthText,
            dayText: draft.startDayText
        )

        switch draft.mode {
        case .edit(let location):
            guard var existingTask = task(for: location) else {
                dismissTaskEditor()
                return
            }
            existingTask.text = normalizedName
            existingTask.startMonth = startMonth
            existingTask.startDay = startDay
            existingTask.normalizeStartDate()
            setTask(existingTask, for: location)
            recordTaskHistory(existingTask, sourceTaskID: existingTask.id)
        case .createStandalone:
            break
        case .createGroup:
            break
        }

        taskEditorDraft = nil
        focusedField = nil
    }

    private func syncLibraryTask(forTaskKey key: String, with newTask: MyTaskItem) {
        guard let location = taskLocation(forTaskKey: key),
              var existingTask = task(for: location) else { return }
        existingTask.text = newTask.trimmedText
        existingTask.startMonth = newTask.startMonth
        existingTask.startDay = newTask.startDay
        existingTask.normalizeStartDate()
        setTask(existingTask, for: location)
        recordTaskHistory(existingTask, sourceTaskID: existingTask.id)
    }

    private func taskLocation(forTaskKey key: String) -> TaskLocation? {
        if let index = library.tasks.firstIndex(where: { taskKey(for: $0) == key }) {
            return .standalone(index)
        }

        for group in library.groups {
            if let taskIndex = group.tasks.firstIndex(where: { taskKey(for: $0) == key }) {
                return .group(group.id, taskIndex)
            }
        }
        return nil
    }

    private func displayGroupName(_ group: MyTaskGroup) -> String {
        let trimmed = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.groupDefaultName : trimmed
    }

    private func syncActiveFilterWithCurrentLibrary() {
        switch activeFilter {
        case .all:
            return
        case .group(let groupID):
            if !library.groups.contains(where: { $0.id == groupID }) {
                activeFilter = .all
            }
        }
    }

    private func refreshTaskHistory() {
        taskHistoryRecords = TaskHistoryStore.load()
    }

    private func seedTaskHistoryIfNeeded() {
        TaskHistoryStore.ensureLibrarySeeded(library)
        seedBoardTasksIntoHistory()
        backfillLegacyTaskHistoryIfNeeded()
        refreshTaskHistory()
    }

    private func recordTaskHistory(_ task: MyTaskItem, sourceTaskID: UUID? = nil) {
        guard !task.trimmedText.isEmpty else { return }
        TaskHistoryStore.upsert(task: task, sourceTaskID: sourceTaskID)
        refreshTaskHistory()
    }

    private func seedBoardTasksIntoHistory() {
        let boardTasks = viewModel.currentBoardTasksInRowMajor(size: BingoViewModel.maxGridSize).compactMap { $0 }
        guard !boardTasks.isEmpty else { return }
        TaskHistoryStore.upsertBoardTasks(boardTasks)
    }

    private func backfillLegacyTaskHistoryIfNeeded() {
        guard taskHistoryRecords.isEmpty else { return }

        var insertedAny = false
        let now = Date()

        for entry in BingoDiaryStore.loadAllEntriesDictionary().values {
            for task in entry.completedTaskCounts.keys {
                let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                TaskHistoryStore.upsert(task: MyTaskItem(text: trimmed), at: entry.date)
                insertedAny = true
            }

            for cell in entry.board.cells.flatMap({ $0 }) {
                let trimmed = cell.storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                TaskHistoryStore.upsert(
                    task: MyTaskItem(
                        text: trimmed,
                        startMonth: cell.startVisibleMonth,
                        startDay: cell.startVisibleDay
                    ),
                    at: entry.date
                )
                insertedAny = true
            }
        }

        for (dateKey, tasks) in BingoTimeoutStore.loadAllPayload() {
            let date = parseDateKey(dateKey) ?? now
            for task in tasks.keys {
                let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                TaskHistoryStore.upsert(task: MyTaskItem(text: trimmed), at: date)
                insertedAny = true
            }
        }

        if insertedAny {
            taskHistoryRecords = TaskHistoryStore.load()
        }
    }

    private func parseDateKey(_ key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }

    private func startAddingTaskInline() {
        if case .group(let groupID) = activeFilter,
           let group = library.groups.first(where: { $0.id == groupID }) {
            guard canAddTask(to: group) else {
                presentPremiumPaywallForLimit(source: "group_task_limit_inline")
                return
            }
        } else {
            guard canAddStandaloneTask else {
                presentPremiumPaywallForLimit(source: "standalone_task_limit_inline")
                return
            }
        }

        isAddingTaskInline = true
        newTaskDraft = ""
        newTaskStartMonthDraft = ""
        newTaskStartDayDraft = ""
        DispatchQueue.main.async {
            focusedField = .newTask
        }
    }

    private func cancelAddingTaskInline() {
        isAddingTaskInline = false
        newTaskDraft = ""
        newTaskStartMonthDraft = ""
        newTaskStartDayDraft = ""
        focusedField = nil
    }

    private func commitAddingTaskInline() {
        let text = String(newTaskDraft.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let (startMonth, startDay) = normalizedMonthDay(monthText: newTaskStartMonthDraft, dayText: newTaskStartDayDraft)
        let task = MyTaskItem(text: text, startMonth: startMonth, startDay: startDay)

        switch activeFilter {
        case .all:
            guard canAddStandaloneTask else {
                presentPremiumPaywallForLimit(source: "standalone_task_limit_commit")
                return
            }
            library.tasks.append(task)
            recordTaskHistory(task, sourceTaskID: task.id)
        case .group(let groupID):
            guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }) else {
                activeFilter = .all
                return
            }
            guard canAddTask(to: library.groups[groupIndex]) else {
                presentPremiumPaywallForLimit(source: "group_task_limit_commit")
                return
            }
            library.groups[groupIndex].tasks.append(task)
            recordTaskHistory(task, sourceTaskID: task.id)
        }

        isAddingTaskInline = false
        newTaskDraft = ""
        newTaskStartMonthDraft = ""
        newTaskStartDayDraft = ""
        focusedField = nil
    }

    private func presentAddGroupModal() {
        guard canAddGroup else {
            presentPremiumPaywallForLimit(source: "group_limit_modal")
            return
        }
        newGroupNameDraft = ""
        isAddingGroupModalPresented = true
        DispatchQueue.main.async {
            focusedField = .newGroupName
        }
    }

    private func dismissAddGroupModal() {
        isAddingGroupModalPresented = false
        newGroupNameDraft = ""
        focusedField = nil
    }

    private func commitAddGroup() {
        guard canAddGroup else {
            presentPremiumPaywallForLimit(source: "group_limit_commit")
            return
        }

        let trimmedName = String(newGroupNameDraft.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let group = MyTaskGroup(name: trimmedName, tasks: [])
        library.groups.append(group)
        activeFilter = .group(group.id)
        dismissAddGroupModal()
    }

    private func taskBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard library.tasks.indices.contains(index) else { return "" }
                return library.tasks[index].text
            },
            set: { newValue in
                guard library.tasks.indices.contains(index) else { return }
                library.tasks[index].text = String(newValue.prefix(AppSettings.maxTaskLength))
                recordTaskHistory(library.tasks[index], sourceTaskID: library.tasks[index].id)
            }
        )
    }

    private func groupTaskBinding(groupID: UUID, index: Int) -> Binding<String> {
        Binding(
            get: {
                guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }),
                      library.groups[groupIndex].tasks.indices.contains(index) else { return "" }
                return library.groups[groupIndex].tasks[index].text
            },
            set: { newValue in
                guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }),
                      library.groups[groupIndex].tasks.indices.contains(index) else { return }
                library.groups[groupIndex].tasks[index].text = String(newValue.prefix(AppSettings.maxTaskLength))
                recordTaskHistory(
                    library.groups[groupIndex].tasks[index],
                    sourceTaskID: library.groups[groupIndex].tasks[index].id
                )
            }
        )
    }

    private func toggleSelection(for key: String) {
        if let index = selectedTaskKeys.firstIndex(of: key) {
            selectedTaskKeys.remove(at: index)
            removePreviewTask(for: key)
        } else {
            guard addPreviewTask(for: key) else {
                showLocalToast(
                    L10n.tr(
                        "Preview board is full.",
                        zhHans: "预览棋盘已满。",
                        zhHant: "預覽棋盤已滿。"
                    )
                )
                return
            }
            selectedTaskKeys.append(key)
        }
    }

    private func applyActiveGroupToPreview() {
        guard !activeGroupTaskKeys.isEmpty else { return }
        focusedField = nil
        selectedTaskKeys = activeGroupTaskKeys
        rebuildPreviewFromSelectedKeys()
        showLocalToast(L10n.quickEditGroupAppliedToPreview)
    }

    private func handleExitTap() {
        focusedField = nil
        if hasUnsavedChanges {
            isExitDiscardAlertPresented = true
        } else {
            dismiss()
        }
    }

    private var hasUnsavedChanges: Bool {
        guard let initialSnapshot else { return false }
        return makeCurrentSnapshot() != initialSnapshot
    }

    private func makeCurrentSnapshot() -> QuickEditSnapshot {
        let previewItems = previewSlots.map { slot in
            QuickEditSnapshot.PreviewItem(
                cellState: slot.cellState,
                sourceTaskKey: slot.sourceTaskKey
            )
        }

        return QuickEditSnapshot(
            targetGridSize: targetGridSize,
            selectedTaskKeys: selectedTaskKeys,
            previewItems: previewItems,
            library: library
        )
    }

    private func handleDoneTap() {
        focusedField = nil
        guard hasUnsavedChanges else {
            dismiss()
            return
        }
        finalizeLibrary(showSuccessToast: false, emitChangeToast: false)
        let plan = ApplyPlan(tasks: previewSlots.compactMap(\.task), targetGridSize: targetGridSize)

        guard !plan.tasks.isEmpty else {
            didApplyToBoard = true
            onSaveSuccess(L10n.quickEditKeptBoardWithoutSelection)
            dismiss()
            return
        }

        if hasExistingBoardTasks {
            pendingApplyPlan = plan
            return
        }

        applySelectionToBoard(plan)
    }

    private func applySelectionToBoard(_ plan: ApplyPlan) {
        let orderedCells = previewSlots.map(\.cellState)
        viewModel.applyBoardOrderedCells(orderedCells, targetGridSize: plan.targetGridSize)
        didApplyToBoard = true
        onSaveSuccess(L10n.quickEditAppliedSuccess(min(plan.tasks.count, plan.targetGridSize * plan.targetGridSize)))
        dismiss()
    }

    private func initialSelectedKeys(from taskTexts: [String], candidates: [TaskCandidate]) -> [String] {
        var pendingByText = Dictionary(grouping: candidates, by: { $0.task.trimmedText })
        var resolved: [String] = []

        for text in taskTexts {
            guard var list = pendingByText[text], let candidate = list.first else { continue }
            resolved.append(candidate.id)
            list.removeFirst()
            pendingByText[text] = list
        }

        return resolved
    }

    private func syncSelectedTaskKeysWithCurrentLibrary() {
        let validKeys = Set(allTaskCandidates.map(\.id))
        selectedTaskKeys = selectedTaskKeys.filter { validKeys.contains($0) }
    }

    private func buildInitialPreviewSlots() -> [PreviewSlot] {
        let boardCells = viewModel.currentBoardCellsInRowMajor(size: targetGridSize)
        let slots = boardCells.prefix(totalGridSlots).map { cell in
            PreviewSlot(cellState: cell, sourceTaskKey: nil)
        }
        if slots.count >= totalGridSlots {
            return Array(slots.prefix(totalGridSlots))
        }
        return slots + emptyPreviewSlots(count: totalGridSlots - slots.count)
    }

    private func adjustPreviewSlotCount() {
        if previewSlots.isEmpty {
            previewSlots = buildInitialPreviewSlots()
            return
        }

        if previewSlots.count > totalGridSlots {
            previewSlots = Array(previewSlots.prefix(totalGridSlots))
        } else if previewSlots.count < totalGridSlots {
            previewSlots.append(contentsOf: emptyPreviewSlots(count: totalGridSlots - previewSlots.count))
        }
    }

    private func addPreviewTask(for key: String) -> Bool {
        guard let task = candidateTaskMap[key], task.isStartDateReached() else { return false }

        if let existingIndex = previewSlots.firstIndex(where: { $0.sourceTaskKey == key }) {
            previewSlots[existingIndex].cellState = makePreviewCell(from: task, preserving: previewSlots[existingIndex].cellState)
            return true
        }

        guard let emptyIndex = previewSlots.firstIndex(where: { $0.task == nil }) else {
            return false
        }

        previewSlots[emptyIndex].cellState = makePreviewCell(from: task)
        previewSlots[emptyIndex].sourceTaskKey = key
        return true
    }

    private func removePreviewTask(for key: String) {
        guard let index = previewSlots.firstIndex(where: { $0.sourceTaskKey == key }) else { return }
        previewSlots[index].cellState = nil
        previewSlots[index].sourceTaskKey = nil
    }

    private func rebuildPreviewFromSelectedKeys() {
        let activeTasks = selectedTaskKeys.compactMap { key -> PreviewSlot? in
            guard let task = candidateTaskMap[key], task.isStartDateReached() else { return nil }
            return PreviewSlot(cellState: makePreviewCell(from: task), sourceTaskKey: key)
        }

        previewSlots = Array(activeTasks.prefix(totalGridSlots))
        if previewSlots.count < totalGridSlots {
            previewSlots.append(contentsOf: emptyPreviewSlots(count: totalGridSlots - previewSlots.count))
        }
    }

    private func emptyPreviewSlots(count: Int) -> [PreviewSlot] {
        guard count > 0 else { return [] }
        return (0..<count).map { _ in PreviewSlot() }
    }

    private func syncPreviewSlotsWithCurrentLibrary() {
        guard !previewSlots.isEmpty else { return }

        for index in previewSlots.indices {
            guard let sourceTaskKey = previewSlots[index].sourceTaskKey else { continue }

            guard let task = candidateTaskMap[sourceTaskKey],
                  !task.trimmedText.isEmpty,
                  task.isStartDateReached() else {
                previewSlots[index].cellState = nil
                previewSlots[index].sourceTaskKey = nil
                continue
            }

            previewSlots[index].cellState = makePreviewCell(from: task, preserving: previewSlots[index].cellState)
        }
        adjustPreviewSlotCount()
    }

    private func clearPreviewDragState() {
        previewDragSourceID = nil
        previewDropTargetID = nil
    }

    private func finalizeLibrary(showSuccessToast: Bool = false, emitChangeToast: Bool = true) {
        let previousLibrary = lastTrackedLibrary
        CommonTasksStore.saveLibrary(library)
        let savedLibrary = CommonTasksStore.loadLibrary()
        library = savedLibrary
        TaskHistoryStore.ensureLibrarySeeded(savedLibrary)
        refreshTaskHistory()

        if showSuccessToast {
            onSaveSuccess(L10n.tasksSavedSuccess)
        } else if emitChangeToast,
                  savedLibrary != lastTrackedLibrary,
                  let message = saveSuccessMessage(previous: previousLibrary, current: savedLibrary) {
            onSaveSuccess(message)
        }
        AnalyticsService.syncMyTasksLibrary(savedLibrary)
        lastTrackedLibrary = savedLibrary
    }

    private func presentPremiumPaywallForLimit(source: String) {
        AnalyticsService.logPremiumTasksGroupsLimitHit(
            source: source,
            taskCount: library.tasks.count,
            groupCount: library.groups.count,
            groupTaskCount: library.groups.reduce(0) { $0 + $1.tasks.count }
        )
        openPremiumPaywall(source: source)
    }

    private func openPremiumPaywall(source: String) {
        premiumPaywallSource = source
        focusedField = nil
        Task { @MainActor in
            isPremiumPaywallPresented = true
            await subscriptionManager.warmupProductsForPaywall()
        }
    }
private func confirmDelete(_ target: DeleteTarget) {
    switch target {
    case .task(let index):
        guard library.tasks.indices.contains(index) else { return }
        let task = library.tasks[index]
        recordTaskHistory(task, sourceTaskID: task.id)
        library.tasks.remove(at: index)
        showLocalToast(target.successMessage)
        deleteConfirmationTarget = nil
        focusedField = nil
    case .group(let groupID):
        deleteConfirmationTarget = nil
        focusedField = nil
        pendingGroupDeleteFinalConfirmation = groupID
    case .groupTask(let groupID, let index):
        guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }),
              library.groups[groupIndex].tasks.indices.contains(index) else { return }
        let task = library.groups[groupIndex].tasks[index]
        recordTaskHistory(task, sourceTaskID: task.id)
        library.groups[groupIndex].tasks.remove(at: index)
        showLocalToast(target.successMessage)
        deleteConfirmationTarget = nil
        focusedField = nil
    case .history(let historyItemID):
        let prefix = "history:"
        guard historyItemID.hasPrefix(prefix) else {
            deleteConfirmationTarget = nil
            focusedField = nil
            return
        }
        let historyKey = String(historyItemID.dropFirst(prefix.count))
        TaskHistoryStore.deleteRecord(withKey: historyKey)
        selectedTaskKeys.removeAll(where: { $0 == historyItemID })
        removePreviewTask(for: historyItemID)
        refreshTaskHistory()
        showLocalToast(target.successMessage)
        deleteConfirmationTarget = nil
        focusedField = nil
    }
}

private func finalizeGroupDeletion(_ groupID: UUID) {
    guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }) else {
        pendingGroupDeleteFinalConfirmation = nil
        return
    }

    for task in library.groups[groupIndex].tasks where !task.trimmedText.isEmpty {
        recordTaskHistory(task, sourceTaskID: task.id)
    }

    library.groups.remove(at: groupIndex)
    if activeFilter == .group(groupID) {
        activeFilter = .all
    }

    showLocalToast(L10n.groupDeletedSuccess)
    pendingGroupDeleteFinalConfirmation = nil
    deleteConfirmationTarget = nil
    focusedField = nil
}

    private func saveSuccessMessage(previous: MyTasksLibrary, current: MyTasksLibrary) -> String? {
        let taskDelta = current.tasks.count - previous.tasks.count
        let groupDelta = current.groups.count - previous.groups.count

        if taskDelta > 0 && groupDelta > 0 {
            return L10n.tasksAndGroupsAddedSuccess
        }
        if taskDelta > 0 {
            return L10n.taskAddedSuccess
        }
        if groupDelta > 0 {
            return L10n.groupAddedSuccess
        }
        if taskDelta < 0 && groupDelta < 0 {
            return L10n.tasksAndGroupsDeletedSuccess
        }
        if taskDelta < 0 {
            return L10n.taskDeletedSuccess
        }
        if groupDelta < 0 {
            return L10n.groupDeletedSuccess
        }

        return nil
    }

    private func showLocalToast(_ message: String) {
        hideLocalToastWorkItem?.cancel()
        localToastMessage = message

        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
            isLocalToastVisible = true
        }

        let workItem = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.22)) {
                isLocalToastVisible = false
            }
        }
        hideLocalToastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: workItem)
    }

private func deleteMessage(for target: DeleteTarget) -> String {
    switch target {
    case .groupTask(let groupID, _):
        let name = groupName(for: groupID)
        return L10n.tr(
            "This task will be removed from \(name).",
            zhHans: "该任务将从「\(name)」中移除。",
            zhHant: "該任務將從「\(name)」中移除。"
        )
    default:
        return target.message
    }
}

private func groupName(for groupID: UUID) -> String {
    guard let group = library.groups.first(where: { $0.id == groupID }) else {
        return L10n.groupDefaultName
    }
    return displayGroupName(group)
}

    private func sectionHeader(title: String, subtitle: String, detail: String, actionTitle: String?, action: (() -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: subtitle.isEmpty ? 0 : 4) {
                Text(detail.isEmpty ? title : "\(title) (\(detail))")
                    .font(.appSystem(size: scaled(15, pad: 19), weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.appSystem(size: scaled(12, pad: 16), weight: .medium, design: .rounded))
                        .foregroundColor(NeumorphicColors.text.opacity(0.56))
                }
            }

            Spacer(minLength: 0)

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.appSystem(size: scaled(11, pad: 14), weight: .bold))
                        Text(actionTitle)
                            .font(.appSystem(size: scaled(13, pad: 18), weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(NeumorphicColors.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.clear.neumorphicConvex(radius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func flatSectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(isPadLayout ? 22 : 18)
            .background(
                RoundedRectangle(cornerRadius: isPadLayout ? 30 : 26, style: .continuous)
                    .fill(quickEditSectionFlatBackground)
            )
    }

    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(isPadLayout ? 22 : 18)
            .background(Color.clear.neumorphicConcave(radius: isPadLayout ? 30 : 26))
    }

    private func emptyStateCard(title: String, message: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.appSystem(size: scaled(16, pad: 22), weight: .bold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            Text(message)
                .font(.appSystem(size: scaled(13, pad: 17), weight: .medium, design: .rounded))
                .foregroundColor(NeumorphicColors.text.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.appSystem(size: scaled(12, pad: 14), weight: .bold))
                    Text(actionTitle)
                        .font(.appSystem(size: scaled(14, pad: 18), weight: .semibold, design: .rounded))
                }
                .foregroundColor(NeumorphicColors.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.clear.neumorphicConvex(radius: 18))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isPadLayout ? 22 : 18)
        .background(Color.clear.neumorphicConvex(radius: 24))
    }
}

private struct QuickEditPreviewDropDelegate: DropDelegate {
    let targetSlotID: UUID
    @Binding var previewSlots: [QuickEditView.PreviewSlot]
    @Binding var dragSourceID: UUID?
    @Binding var dropTargetID: UUID?

    func dropEntered(info: DropInfo) {
        guard dragSourceID != nil else { return }
        dropTargetID = targetSlotID
    }

    func dropExited(info: DropInfo) {
        if dropTargetID == targetSlotID {
            dropTargetID = nil
        }

        let sourceAtExit = dragSourceID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            guard dropTargetID == nil, dragSourceID == sourceAtExit else { return }
            dragSourceID = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [UTType.text.identifier, UTType.plainText.identifier])
        if let provider = providers.first {
            provider.loadObject(ofClass: NSString.self) { object, _ in
                let rawID = (object as? NSString).map(String.init)
                guard let rawID, let sourceID = UUID(uuidString: rawID) else {
                    DispatchQueue.main.async {
                        dropTargetID = nil
                        dragSourceID = nil
                    }
                    return
                }

                DispatchQueue.main.async {
                    swapSlotsIfNeeded(sourceID: sourceID)
                    dropTargetID = nil
                    dragSourceID = nil
                }
            }
            return true
        }

        if let sourceID = dragSourceID {
            swapSlotsIfNeeded(sourceID: sourceID)
        }

        dropTargetID = nil
        dragSourceID = nil
        return true
    }

    private func swapSlotsIfNeeded(sourceID: UUID) {
        guard sourceID != targetSlotID,
              let sourceIndex = previewSlots.firstIndex(where: { $0.id == sourceID }),
              let destinationIndex = previewSlots.firstIndex(where: { $0.id == targetSlotID }) else {
            return
        }

        let sourceCellState = previewSlots[sourceIndex].cellState
        let sourceKey = previewSlots[sourceIndex].sourceTaskKey
        previewSlots[sourceIndex].cellState = previewSlots[destinationIndex].cellState
        previewSlots[sourceIndex].sourceTaskKey = previewSlots[destinationIndex].sourceTaskKey
        previewSlots[destinationIndex].cellState = sourceCellState
        previewSlots[destinationIndex].sourceTaskKey = sourceKey
    }
}


private struct PremiumPaywallView: View {
    private enum PaywallPlan: String, CaseIterable, Identifiable {
        case monthly
        case yearly
        case lifetime

        var id: String { rawValue }

        init(kind: PremiumPlanKind) {
            switch kind {
            case .monthly:
                self = .monthly
            case .yearly:
                self = .yearly
            case .lifetime:
                self = .lifetime
            }
        }

        var productID: String {
            switch self {
            case .monthly:
                return SubscriptionManager.monthlyProductID
            case .yearly:
                return SubscriptionManager.yearlyProductID
            case .lifetime:
                return SubscriptionManager.lifetimeProductID
            }
        }

        var title: String {
            switch self {
            case .monthly:
                return L10n.paywallOneMonth
            case .yearly:
                return L10n.paywallOneYear
            case .lifetime:
                return L10n.paywallLifetime
            }
        }
    }

    private enum PaywallRegion {
        case mainlandChina
        case taiwan
        case international

        static var current: PaywallRegion {
            let regionIdentifier = AppLanguage.currentRegionCode

            if regionIdentifier == "HK" {
                return .international
            }
            if regionIdentifier == "TW" || AppLanguage.hasTaiwanLanguageHint {
                return .taiwan
            }
            if regionIdentifier == "CN" {
                return .mainlandChina
            }

            return .international
        }
    }

    private struct PlanPriceDisplay {
        let displayPrice: String
        let subtitle: String?
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    let entrySource: String

    @State private var selectedPlan: PaywallPlan = .monthly
    @State private var feedbackMessage: String?
    @State private var didRunInitialPriceWarmup = false
    @State private var isRetryingPriceLoad = false

    private let designWidth: CGFloat = 393
    private let designHeight: CGFloat = 852

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var classicPaywallVerticalLift: CGFloat {
        isPadLayout ? 22 : 18
    }

    private var featurePanelHeight: CGFloat {
        isPadLayout ? 232 : 236
    }

    private var isMemberCenter: Bool {
        subscriptionManager.hasPremiumAccess
    }

    private var currentPlan: PaywallPlan? {
        guard let kind = subscriptionManager.currentPlanKind else { return nil }
        return PaywallPlan(kind: kind)
    }

    private var hasLoadedAllPaywallProducts: Bool {
        subscriptionManager.hasLoadedAllPaywallProducts
    }

    private var usesLifetimeTheme: Bool {
        selectedPlan == .lifetime
    }

    private var backgroundGradient: LinearGradient {
        if usesLifetimeTheme {
            return LinearGradient(
                stops: [
                    .init(color: Color(hex: "734A37"), location: 0),
                    .init(color: Color(hex: "1D1002"), location: 0.52549),
                    .init(color: Color(hex: "1D1002"), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        return LinearGradient(
            stops: [
                .init(color: Color(hex: "D3A375"), location: 0),
                .init(color: Color(hex: "F2E9DF"), location: 0.42324),
                .init(color: Color(hex: "F2E9DF"), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var featureTitleColor: Color {
        usesLifetimeTheme ? .white : Color(hex: "3F270F")
    }

    private var featureBodyColor: Color {
        usesLifetimeTheme ? .white : Color(hex: "373F4B")
    }

    private var actionButtonColor: Color {
        usesLifetimeTheme ? Color(hex: "D3A375") : Color(hex: "3F270F")
    }

    private var actionButtonTextColor: Color {
        .white
    }

    private var backButtonFillColor: Color {
        Color.black.opacity(0.06)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                paywallBackground
                    .ignoresSafeArea()

                if isMemberCenter {
                    memberCenterContent
                } else {
                    classicPaywallContent(in: geo)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .task {
            if !didRunInitialPriceWarmup {
                didRunInitialPriceWarmup = true
                await refreshProductsForPaywallIfNeeded(force: true)
            } else {
                await refreshProductsForPaywallIfNeeded()
            }
            syncSelectedPlanWithCurrentStatus()
        }
        .onChange(of: subscriptionManager.currentPlanKind) { _, _ in
            syncSelectedPlanWithCurrentStatus()
        }
        .alert(L10n.subscription, isPresented: feedbackAlertBinding) {
            Button(L10n.ok) {
                feedbackMessage = nil
            }
        } message: {
            Text(feedbackMessage ?? "")
        }
    }

    @MainActor
    private func refreshProductsForPaywallIfNeeded(force: Bool = false) async {
        guard force || !hasLoadedAllPaywallProducts else { return }
        guard !isRetryingPriceLoad else { return }

        isRetryingPriceLoad = true
        defer { isRetryingPriceLoad = false }

        for attempt in 0..<3 {
            await subscriptionManager.refreshAll()
            if hasLoadedAllPaywallProducts { break }
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }
    }

    private var feedbackAlertBinding: Binding<Bool> {
        Binding(
            get: { feedbackMessage != nil },
            set: { isPresented in
                if !isPresented {
                    feedbackMessage = nil
                }
            }
        )
    }

    private func classicPaywallContent(in geo: GeometryProxy) -> some View {
        let scale = min(geo.size.width / designWidth, geo.size.height / designHeight)
        let contentWidth = designWidth * scale
        let horizontalOffset = max((geo.size.width - contentWidth) / 2, 0)

        return ZStack(alignment: .topLeading) {
            heroSection
            featureSection
            planCardsSection
            subscribeButton
            restoreSubscriptionButton
        }
        .frame(width: designWidth, height: designHeight, alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading)
        .offset(x: horizontalOffset, y: 0)
        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            legalFooter
                .padding(.bottom, 0)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .clipped()
    }

    private var memberCenterContent: some View {
        VStack(spacing: 0) {
            memberCenterHeader
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    memberSummaryCard
                    memberPlanSelectionSection
                    memberActionsSection
                    if selectedPlan == .lifetime && subscriptionManager.hasActiveAutoRenewable {
                        memberNoticeCard(text: L10n.paywallLifetimeAutoRenewNote)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
    }

    private var memberCenterHeader: some View {
        HStack(spacing: 12) {
            backButton
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.paywallMembershipTitle)
                    .font(paywallFont(size: 28, weight: .bold))
                    .foregroundColor(featureTitleColor)
                Text(L10n.paywallMembershipSubtitle)
                    .font(paywallFont(size: 14, weight: .medium))
                    .foregroundColor(featureBodyColor.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 54)
        .padding(.bottom, 14)
    }

    private var memberSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.subscriptionCurrentPlan)
                .font(paywallFont(size: 14, weight: .medium))
                .foregroundColor(featureBodyColor.opacity(0.72))

            Text(currentPlanTitle)
                .font(paywallFont(size: 26, weight: .bold))
                .foregroundColor(featureTitleColor)

            Text(currentPlanDetailText)
                .font(paywallFont(size: 14, weight: .medium))
                .foregroundColor(featureBodyColor.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(memberCardBackground)
    }

    private var memberPlanSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(PaywallPlan.allCases) { plan in
                memberPlanCard(plan)
            }
        }
    }

    private func memberPlanCard(_ plan: PaywallPlan) -> some View {
        let isSelected = selectedPlan == plan
        let isCurrent = currentPlan == plan
        let price = priceDisplay(for: plan)

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedPlan = plan
            }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(paywallFont(size: 19, weight: .semibold))
                            .foregroundColor(featureTitleColor)
                        if isCurrent {
                            Text(L10n.paywallCurrentPlanButton)
                                .font(paywallFont(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color(hex: "3F270F").opacity(0.85))
                                )
                        }
                    }

                    if let subtitle = price.subtitle {
                        Text(subtitle)
                            .font(paywallFont(size: 13, weight: .medium))
                            .foregroundColor(featureBodyColor.opacity(0.72))
                    }
                }

                Spacer(minLength: 12)

                Text(price.displayPrice)
                    .font(paywallFont(size: 22, weight: .semibold))
                    .foregroundColor(featureTitleColor)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(isSelected ? Color(hex: "D3A375") : Color.white.opacity(0.24), lineWidth: isSelected ? 2.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(subscriptionManager.isPurchasing || subscriptionManager.hasLifetimeAccess)
        .opacity(subscriptionManager.hasLifetimeAccess && plan != .lifetime ? 0.7 : 1)
    }

    private var memberActionsSection: some View {
        VStack(spacing: 12) {
            Button {
                handlePrimaryMembershipAction()
            } label: {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(actionButtonColor)
                    .frame(height: 54)
                    .overlay {
                        Text(primaryMembershipActionTitle)
                            .font(paywallFont(size: 18, weight: .semibold))
                            .foregroundColor(actionButtonTextColor)
                    }
            }
            .buttonStyle(.plain)
            .disabled(!canPerformPrimaryMembershipAction || subscriptionManager.isPurchasing)
            .opacity((!canPerformPrimaryMembershipAction || subscriptionManager.isPurchasing) ? 0.6 : 1)

            HStack(spacing: 12) {
                memberSecondaryActionButton(title: L10n.subscriptionRestoreSubscription) {
                    Task {
                        feedbackMessage = await subscriptionManager.restorePurchases()
                    }
                }

                if subscriptionManager.hasActiveAutoRenewable {
                    memberSecondaryActionButton(title: L10n.paywallManageSubscription) {
                        openManageSubscriptionPage()
                    }
                }
            }
        }
    }

    private func memberSecondaryActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.14))
                .frame(height: 48)
                .overlay {
                    Text(title)
                        .font(paywallFont(size: 15, weight: .semibold))
                        .foregroundColor(featureTitleColor)
                }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func memberNoticeCard(text: String) -> some View {
        Text(text)
            .font(paywallFont(size: 13, weight: .medium))
            .foregroundColor(featureBodyColor.opacity(0.82))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(memberCardBackground)
    }

    private var memberCardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.white.opacity(selectedPlan == .lifetime ? 0.08 : 0.22))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(selectedPlan == .lifetime ? 0.18 : 0.3), lineWidth: 1)
            )
    }

    private var currentPlanTitle: String {
        guard let currentPlan else {
            return L10n.subscriptionStatusInactive
        }

        return currentPlan.title
    }

    private var currentPlanDetailText: String {
        if subscriptionManager.hasLifetimeAccess {
            return L10n.subscriptionLifetimeOwned
        }

        if let expirationDate = subscriptionManager.currentPlanExpirationDate {
            return L10n.subscriptionRenewsOn(formattedMembershipDate(expirationDate))
        }

        return L10n.subscriptionStatusActive
    }

    private var primaryMembershipActionTitle: String {
        if subscriptionManager.hasLifetimeAccess || currentPlan == selectedPlan {
            return L10n.paywallCurrentPlanButton
        }

        switch selectedPlan {
        case .monthly:
            return L10n.paywallSwitchToMonthly
        case .yearly:
            return L10n.paywallSwitchToYearly
        case .lifetime:
            return L10n.paywallBuyLifetime
        }
    }

    private var canPerformPrimaryMembershipAction: Bool {
        !subscriptionManager.hasLifetimeAccess && currentPlan != selectedPlan
    }

    private func syncSelectedPlanWithCurrentStatus() {
        if let currentPlan {
            selectedPlan = currentPlan
        }
    }

    private func formattedMembershipDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.displayLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func openManageSubscriptionPage() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        openURL(url) { accepted in
            if !accepted {
                feedbackMessage = L10n.subscriptionManageFailed
            }
        }
    }

    private func handlePrimaryMembershipAction() {
        guard canPerformPrimaryMembershipAction else { return }

        Task {
            let hadAutoRenewableBeforePurchase = subscriptionManager.hasActiveAutoRenewable
            let message = await subscriptionManager.purchase(
                productID: selectedPlan.productID,
                analyticsSource: entrySource,
                analyticsPlan: selectedPlan.rawValue
            )

            if selectedPlan == .lifetime,
               shouldTrackPremiumPurchaseSuccess(for: message),
               hadAutoRenewableBeforePurchase {
                feedbackMessage = L10n.paywallLifetimePurchaseReminder
                return
            }

            if shouldTrackPremiumPurchaseSuccess(for: message) {
                if subscriptionManager.hasPremiumAccess {
                    dismiss()
                } else {
                    feedbackMessage = message
                }
            } else {
                feedbackMessage = message
            }
        }
    }

    private func shouldTrackPremiumPurchaseSuccess(for message: String) -> Bool {
        message == L10n.subscriptionPurchaseSucceeded || message == L10n.subscriptionActivationPending
    }

    private var heroSection: some View {
        ZStack(alignment: .topLeading) {
            backButton
                .offset(x: 10, y: 49)

            Image("PaywallBearAndStar")
                .resizable()
                .interpolation(.high)
                .renderingMode(.original)
                .frame(width: 196.5, height: 146)
                .opacity(usesLifetimeTheme ? 0.98 : 1)
                .offset(x: 98, y: 6)
        }
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image("PaywallBack")
                .resizable()
                .interpolation(.high)
                .renderingMode(.original)
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
    }

    private var featureSection: some View {
        ZStack(alignment: .topLeading) {
            featurePanelBackground

            Text(L10n.paywallUnlockProFeatures)
                .font(paywallFont(size: 24, weight: .bold))
                .foregroundColor(featureTitleColor)
                .frame(width: 373, alignment: .center)
                .offset(x: 0, y: 28)

            featureRow(
                text: L10n.paywallUnlimitedBoards,
                x: 36,
                y: 94
            )

            featureRow(
                text: L10n.paywallUnlimitedQuickTasksAndGroups,
                x: 36,
                y: 145
            )

            featureRow(
                text: L10n.paywallEditAllHistoryTasks,
                x: 36,
                y: 196
            )

        }
        .frame(width: 373, height: featurePanelHeight)
        .offset(x: 10, y: 183 - classicPaywallVerticalLift)
    }

    private var featurePanelBackground: some View {
        Image(usesLifetimeTheme ? "PaywallPrivilegeBGDark" : "PaywallPrivilegeBG")
            .resizable()
            .interpolation(.high)
            .renderingMode(.original)
            .frame(width: 373, height: featurePanelHeight)
    }

    private func featureRow(text: String, x: CGFloat, y: CGFloat) -> some View {
        HStack(spacing: 12) {
            featureCheckIcon
                .frame(width: 19, height: 19)

            Text(text)
                .font(paywallFont(size: 18, weight: .medium))
                .foregroundColor(featureBodyColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .offset(x: x, y: y)
    }

    private var featureCheckIcon: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "D3A375"))

            Image(systemName: "checkmark")
                .font(.appSystem(size: 11, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private var planCardsSection: some View {
        ZStack(alignment: .topLeading) {
            planCard(.monthly, y: 455 - classicPaywallVerticalLift)
            planCard(.yearly, y: 551 - classicPaywallVerticalLift)
            planCard(.lifetime, y: 647 - classicPaywallVerticalLift)
        }
    }

    private func planCard(_ plan: PaywallPlan, y: CGFloat) -> some View {
        let price = priceDisplay(for: plan)
        let isSelected = selectedPlan == plan

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPlan = plan
            }
        } label: {
            ZStack(alignment: .topLeading) {
                if usesLifetimeTheme {
                    darkPlanCardBackground(for: plan, isSelected: isSelected)
                } else {
                    lightPlanCardBackground(isSelected: isSelected)
                }

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(plan.title)
                                .font(paywallFont(size: 20, weight: .semibold))
                                .foregroundColor(usesLifetimeTheme ? .white : Color(hex: "3F270F"))
                                .lineLimit(1)
                                .minimumScaleFactor(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .layoutPriority(1)

                            if plan == .yearly {
                                popularBadge
                            }
                        }

                        if let subtitle = price.subtitle {
                            Text(subtitle)
                                .font(paywallFont(size: 13, weight: .medium))
                                .foregroundColor(Color(hex: "828282"))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(price.displayPrice)
                        .font(paywallFont(size: 32, weight: .medium))
                        .foregroundColor(usesLifetimeTheme ? .white : Color(hex: "3F270F"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, usesLifetimeTheme ? 20 : 24)
                .padding(.vertical, 16)
                .frame(width: 349, height: 80)
            }
            .frame(width: 349, height: 80)
        }
        .buttonStyle(.plain)
        .disabled(subscriptionManager.isPurchasing)
        .opacity(subscriptionManager.isPurchasing ? 0.92 : 1)
        .offset(x: 21, y: y)
    }

    @ViewBuilder
    private func lightPlanCardBackground(isSelected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        ZStack {
            if isSelected {
                shape
                    .fill(Color.clear)
                    .overlay(
                        shape
                            .stroke(Color(hex: "D3A375"), lineWidth: 3)
                    )
            } else {
                shape
                    .fill(Color(hex: "EDE2D7").opacity(0.88))
                    .overlay(
                        shape
                            .stroke(Color.white.opacity(0.92), lineWidth: 1)
                    )
            }
        }
        .shadow(color: Color.white.opacity(isSelected ? 0.45 : 0.7), radius: 10, x: -4, y: -4)
        .shadow(color: Color(hex: "D3A375").opacity(isSelected ? 0.16 : 0.12), radius: 12, x: 6, y: 6)
    }

    @ViewBuilder
    private func darkPlanCardBackground(for plan: PaywallPlan, isSelected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        shape
            .fill(Color(hex: "321B06"))
            .overlay(
                shape
                    .stroke(isSelected ? Color(hex: "D3A375") : Color(hex: "3F270F"), lineWidth: isSelected ? 3 : 1)
            )
            .shadow(color: Color(hex: "0A0500").opacity(0.35), radius: 10, x: 4, y: 6)
            .shadow(color: Color(hex: "8C5F39").opacity(0.12), radius: 8, x: -3, y: -3)
    }

    private var popularBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    usesLifetimeTheme
                    ? LinearGradient(
                        colors: [Color(hex: "643D19"), Color(hex: "9B6E45"), Color(hex: "58310E")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    : LinearGradient(
                        colors: [Color(hex: "E6B17D"), Color(hex: "E6B78A"), Color(hex: "DBA169")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(
                    color: usesLifetimeTheme ? Color(hex: "0A0500") : Color(hex: "CFD4DA").opacity(0.7),
                    radius: 12,
                    x: 6,
                    y: 6
                )
                .shadow(
                    color: usesLifetimeTheme ? Color(hex: "9D734B").opacity(0.3) : .white.opacity(0.7),
                    radius: 12,
                    x: -6,
                    y: -6
                )

            Text(L10n.paywallPopular)
                .font(paywallFont(size: 13, weight: .medium))
                .foregroundColor(.white)
        }
        .frame(width: 85, height: 26)
    }

    private var subscribeButton: some View {
        Button {
            Task {
                let message = await subscriptionManager.purchase(
                    productID: selectedPlan.productID,
                    analyticsSource: entrySource,
                    analyticsPlan: selectedPlan.rawValue
                )
                if shouldTrackPremiumPurchaseSuccess(for: message) {
                    if subscriptionManager.hasPremiumAccess {
                        dismiss()
                    } else {
                        feedbackMessage = message
                    }
                } else {
                    feedbackMessage = message
                }
            }
        } label: {
            RoundedRectangle(cornerRadius: 100, style: .continuous)
                .fill(actionButtonColor)
                .frame(width: 350, height: 56)
                .overlay {
                    Text(subscriptionManager.isPurchasing ? L10n.subscriptionPleaseWait : L10n.paywallSubscribeNow)
                        .font(paywallFont(size: 20, weight: .semibold))
                        .foregroundColor(actionButtonTextColor)
                }
                .shadow(
                    color: usesLifetimeTheme ? .clear : Color(hex: "CFD4DA").opacity(0.7),
                    radius: 12,
                    x: 6,
                    y: 6
                )
                .shadow(
                    color: usesLifetimeTheme ? .clear : .white.opacity(0.7),
                    radius: 12,
                    x: -6,
                    y: -6
                )
        }
        .buttonStyle(.plain)
        .disabled(subscriptionManager.isPurchasing)
        .opacity(subscriptionManager.isPurchasing ? 0.92 : 1)
        .offset(x: 20, y: 755 - classicPaywallVerticalLift)
    }

    private var restoreSubscriptionButton: some View {
        Button {
            Task {
                let message = await subscriptionManager.restorePurchases()
                if subscriptionManager.hasPremiumAccess {
                    dismiss()
                } else {
                    feedbackMessage = message
                }
            }
        } label: {
            Text(L10n.subscriptionRestoreSubscription)
                .font(paywallFont(size: 14, weight: .semibold))
                .foregroundColor(usesLifetimeTheme ? .white.opacity(0.95) : .black.opacity(0.82))
                .frame(width: 350, alignment: .center)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(subscriptionManager.isPurchasing)
        .opacity(subscriptionManager.isPurchasing ? 0.72 : 1)
        .offset(x: 20, y: 817 - classicPaywallVerticalLift)
    }

    private var legalFooter: some View {
        Text(legalFooterAttributedText)
            .font(paywallFont(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.92))
            .tint(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.42)
            .allowsTightening(true)
            .truncationMode(.tail)
            .frame(width: 350)
            .multilineTextAlignment(.center)
    }
    private var legalFooterAttributedText: AttributedString {
        var text = AttributedString(L10n.paywallLegalOneLine)

        if let termsRange = text.range(of: L10n.paywallTermsOfUse) {
            text[termsRange].link = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
        }

        if let privacyRange = text.range(of: L10n.paywallPrivacyPolicy) {
            text[privacyRange].link = URL(string: "https://osmatters.github.io/bingoday-support/privacy")
        }

        return text
    }

    private var paywallBackground: some View {
        Image(usesLifetimeTheme ? "PaywallDarkBG" : "PaywallLightBG")
            .resizable()
            .interpolation(.high)
            .renderingMode(.original)
            .aspectRatio(contentMode: .fill)
    }

    private var wordmarkPositions: [(x: CGFloat, y: CGFloat, opacity: Double)] {
        let baseOpacity = usesLifetimeTheme ? 0.30 : 1.0
        return [
            (-17.7, -73.3, 0.20 * baseOpacity),
            (-7.7, -22.3, 0.20 * baseOpacity),
            (1.8, 30.25, 0.15 * baseOpacity),
            (10.7, 79.46, 0.10 * baseOpacity),
            (19.58, 128.66, 0.05 * baseOpacity),
            (359, -0.86, 0.20 * baseOpacity),
            (369, 50.14, 0.20 * baseOpacity),
            (378.5, 102.73, 0.15 * baseOpacity),
            (387.39, 151.93, 0.10 * baseOpacity),
            (396.29, 201.13, 0.05 * baseOpacity)
        ]
    }

    private func priceDisplay(for plan: PaywallPlan) -> PlanPriceDisplay {
        if let product = subscriptionManager.productsByID[plan.productID] {
            let subtitle: String?
            switch plan {
            case .yearly:
                subtitle = yearlyPerMonthSubtitle(for: product)
            case .lifetime:
                subtitle = L10n.paywallOneTimePayment
            case .monthly:
                subtitle = nil
            }
            return PlanPriceDisplay(displayPrice: product.displayPrice, subtitle: subtitle)
        }

        let cachedPrice = subscriptionManager.displayPrice(for: plan.productID)
        let fallbackSubtitle: String?
        switch plan {
        case .lifetime:
            fallbackSubtitle = L10n.paywallOneTimePayment
        case .yearly, .monthly:
            fallbackSubtitle = nil
        }
        return PlanPriceDisplay(displayPrice: cachedPrice, subtitle: fallbackSubtitle)
    }

    private func yearlyPerMonthSubtitle(for product: Product) -> String {
        let monthlyPrice = NSDecimalNumber(decimal: product.price).dividing(by: 12).decimalValue
        let formattedMonthlyPrice = formattedMonthlyPrice(monthlyPrice, from: product.displayPrice)
        return L10n.paywallPerMonth(formattedMonthlyPrice)
    }

    private func formattedMonthlyPrice(_ monthlyPrice: Decimal, from displayPrice: String) -> String {
        guard let firstDigit = displayPrice.firstIndex(where: { $0.isNumber }),
              let lastDigit = displayPrice.lastIndex(where: { $0.isNumber }) else {
            return decimalString(monthlyPrice, decimalSeparator: ".")
        }

        let prefix = String(displayPrice[..<firstDigit])
        let suffixStart = displayPrice.index(after: lastDigit)
        let suffix = suffixStart < displayPrice.endIndex ? String(displayPrice[suffixStart...]) : ""
        let numericPortion = String(displayPrice[firstDigit...lastDigit])
        let decimalSeparator: String = (numericPortion.contains(",") && !numericPortion.contains(".")) ? "," : "."
        let amount = decimalString(monthlyPrice, decimalSeparator: decimalSeparator)

        return "\(prefix)\(amount)\(suffix)"
    }

    private func decimalString(_ value: Decimal, decimalSeparator: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        formatter.decimalSeparator = decimalSeparator
        formatter.groupingSeparator = ""
        formatter.locale = Locale(identifier: "en_US_POSIX")

        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? NSDecimalNumber(decimal: value).stringValue
    }

    private func paywallFont(size: CGFloat, weight: Font.Weight) -> Font {
        switch AppLanguage.current {
        case .english:
            return .custom("Outfit", size: size).weight(weight)
        case .simplifiedChinese, .traditionalChinese, .japanese:
            return .system(size: size, weight: weight, design: .default)
        }
    }

    private func sparkleShape(fill: Color) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 4.19505, y: 0.39209))
            path.addCurve(to: CGPoint(x: 5.17148, y: 0.39209), control1: CGPoint(x: 4.3106, y: -0.1307), control2: CGPoint(x: 5.05593, y: -0.1307))
            path.addLine(to: CGPoint(x: 5.58452, y: 2.26079))
            path.addCurve(to: CGPoint(x: 7.10574, y: 3.78201), control1: CGPoint(x: 5.75247, y: 3.02063), control2: CGPoint(x: 6.34591, y: 3.61406))
            path.addLine(to: CGPoint(x: 8.97444, y: 4.19505))
            path.addCurve(to: CGPoint(x: 8.97444, y: 5.17148), control1: CGPoint(x: 9.49723, y: 4.3106), control2: CGPoint(x: 9.49723, y: 5.05593))
            path.addLine(to: CGPoint(x: 7.10575, y: 5.58452))
            path.addCurve(to: CGPoint(x: 5.58452, y: 7.10574), control1: CGPoint(x: 6.34591, y: 5.75247), control2: CGPoint(x: 5.75247, y: 6.34591))
            path.addLine(to: CGPoint(x: 5.17148, y: 8.97444))
            path.addCurve(to: CGPoint(x: 4.19505, y: 8.97444), control1: CGPoint(x: 5.05593, y: 9.49723), control2: CGPoint(x: 4.3106, y: 9.49723))
            path.addLine(to: CGPoint(x: 3.78201, y: 7.10575))
            path.addCurve(to: CGPoint(x: 2.26079, y: 5.58452), control1: CGPoint(x: 3.61406, y: 6.34591), control2: CGPoint(x: 3.02063, y: 5.75247))
            path.addLine(to: CGPoint(x: 0.39209, y: 5.17148))
            path.addCurve(to: CGPoint(x: 0.39209, y: 4.19505), control1: CGPoint(x: -0.1307, y: 5.05593), control2: CGPoint(x: -0.1307, y: 4.3106))
            path.addLine(to: CGPoint(x: 2.26079, y: 3.78201))
            path.addCurve(to: CGPoint(x: 3.78201, y: 2.26079), control1: CGPoint(x: 3.02063, y: 3.61406), control2: CGPoint(x: 3.61406, y: 3.02063))
            path.addLine(to: CGPoint(x: 4.19505, y: 0.39209))
        }
        .fill(fill)
        .shadow(color: fill.opacity(0.4), radius: 3, x: 0, y: 1)
    }
}

private struct BingoDiaryScreen: View {
    private struct DiarySnapshot {
        var completedTaskStats: [BingoDiaryTaskCount]
        var timeoutTaskStats: [BingoDiaryTaskCount]
        var totalCompletedTasks: Int
        var totalExpiredTasks: Int

        static let empty = DiarySnapshot(
            completedTaskStats: [],
            timeoutTaskStats: [],
            totalCompletedTasks: 0,
            totalExpiredTasks: 0
        )
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var gravityMonitor = BingoDiaryGravityMonitor()
    @State private var isStatsListPresented = false
    @State private var selectedTaskDetail: BingoDiaryTaskCount?
    @State private var snapshot: DiarySnapshot = .empty
    @State private var isLoadingSnapshot = true
    @State private var statsSectionHeight: CGFloat = 0
    @State private var isBubbleCloudInteracting = false

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    private var diaryTitle: String {
        L10n.tr("Bingo Dairy", zhHans: "Bingo 日记", zhHant: "Bingo 日記")
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let contentWidth = geometry.size.width
                let statsToBubbleSpacing = scaled(10, pad: 10)
                let resolvedStatsHeight = max(
                    statsSectionHeight,
                    scaled(132, pad: 150)
                )
                let bubbleViewportHeight = max(
                    scaled(300, pad: 360),
                    geometry.size.height
                    - resolvedStatsHeight
                    - statsToBubbleSpacing  // space between stats and bubble area
                    - scaled(16, pad: 24)   // top content padding
                    - scaled(36, pad: 44)   // bottom content padding
                    - geometry.safeAreaInsets.top
                    - scaled(56, pad: 68)   // header + safe margin
                )
                let bubbleLayout = BingoDiaryBubbleLayout.layout(
                    taskCounts: snapshot.completedTaskStats,
                    width: contentWidth,
                    viewportHeight: bubbleViewportHeight,
                    maximumBubbleCount: 80
                )

                ZStack(alignment: .top) {
                    NeumorphicColors.background
                        .ignoresSafeArea()

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: statsToBubbleSpacing) {
                            statsSummarySection
                                .padding(.horizontal, scaled(20, pad: 28))
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear
                                            .preference(
                                                key: BingoDiaryStatsHeightPreferenceKey.self,
                                                value: proxy.size.height
                                            )
                                    }
                                )

                            if isLoadingSnapshot {
                                ProgressView()
                                    .tint(NeumorphicColors.accent)
                                    .frame(maxWidth: .infinity, minHeight: bubbleViewportHeight)
                                    .padding(.horizontal, scaled(20, pad: 28))
                            } else if bubbleLayout.bubbles.isEmpty {
                                emptyDiaryState
                                    .padding(.horizontal, scaled(20, pad: 28))
                            } else {
                                let horizontalPanInset = scaled(22, pad: 28)
                                let alwaysScrollableCanvasWidth = max(
                                    bubbleLayout.width,
                                    contentWidth + horizontalPanInset * 2
                                )

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 0) {
                                        BingoDiaryBubbleCloud(
                                            bubbles: bubbleLayout.bubbles,
                                            canvasWidth: bubbleLayout.width,
                                            canvasHeight: bubbleLayout.height,
                                            globalMotionOffset: gravityMonitor.offset,
                                            isInteractionPaused: isBubbleCloudInteracting,
                                            onBubbleTap: { bubble in
                                                selectedTaskDetail = snapshot.completedTaskStats.first(where: { $0.id == bubble.id })
                                                    ?? BingoDiaryTaskCount(task: bubble.task, count: bubble.count, firstCompletedAt: nil)
                                            }
                                        )
                                        .padding(.horizontal, max((alwaysScrollableCanvasWidth - bubbleLayout.width) / 2, 0))
                                    }
                                    .frame(width: alwaysScrollableCanvasWidth, alignment: .leading)
                                }
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 2)
                                        .onChanged { _ in
                                            if !isBubbleCloudInteracting {
                                                isBubbleCloudInteracting = true
                                            }
                                        }
                                        .onEnded { _ in
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                                isBubbleCloudInteracting = false
                                            }
                                        }
                                )
                                .frame(height: bubbleLayout.height)
                                .clipped()
                            }
                        }
                        .padding(.top, scaled(16, pad: 24))
                        .padding(.bottom, scaled(36, pad: 44))
                    }
                }
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top) {
                headerBar
                    .background(NeumorphicColors.background.opacity(0.96))
            }
            .sheet(isPresented: $isStatsListPresented) {
                BingoDiaryStatsListSheet(
                    title: diaryTitle,
                    completedStats: snapshot.completedTaskStats,
                    timeoutStats: snapshot.timeoutTaskStats
                )
            }
            .onPreferenceChange(BingoDiaryStatsHeightPreferenceKey.self) { newHeight in
                guard newHeight > 0, abs(newHeight - statsSectionHeight) > 0.5 else { return }
                statsSectionHeight = newHeight
            }
            .onAppear {
                gravityMonitor.start()
                // Defer heavier diary data aggregation until transition finishes,
                // so entering this screen feels immediate.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    loadSnapshot()
                }
            }
            .onDisappear {
                gravityMonitor.stop()
            }
            .navigationDestination(item: $selectedTaskDetail) { item in
                BingoDiaryTaskDetailView(task: item.task)
            }
        }
    }

    private var headerBar: some View {
        ZStack {
            Text(diaryTitle)
                .font(.appSystem(size: scaled(20, pad: 24), weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "2B1A0D"))

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.appSystem(size: scaled(18, pad: 20), weight: .semibold))
                        .foregroundColor(Color(hex: "2B1A0D"))
                        .frame(width: scaled(40, pad: 44), height: scaled(40, pad: 44))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    isStatsListPresented = true
                } label: {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.appSystem(size: scaled(19, pad: 22), weight: .semibold))
                        .foregroundColor(Color(hex: "2B1A0D"))
                        .frame(width: scaled(40, pad: 44), height: scaled(40, pad: 44))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, scaled(12, pad: 20))
        .padding(.top, scaled(6, pad: 10))
        .padding(.bottom, scaled(4, pad: 8))
    }

    private var statsSummarySection: some View {
        HStack(spacing: scaled(14, pad: 18)) {
            diarySummaryCard(
                value: snapshot.totalCompletedTasks,
                title: L10n.tr("Tasks completed", zhHans: "已完成任务", zhHant: "已完成任務")
            )

            diarySummaryCard(
                value: snapshot.totalExpiredTasks,
                title: L10n.tr("Expired tasks", zhHans: "超时任务", zhHant: "超時任務")
            )
        }
    }

    private func loadSnapshot() {
        isLoadingSnapshot = true
        DispatchQueue.global(qos: .userInitiated).async {
            let completed = BingoDiaryStore.allTimeCompletedTaskStats().map {
                BingoDiaryTaskCount(task: $0.task, count: $0.count, firstCompletedAt: $0.firstCompletedAt)
            }
            let timeout = BingoTimeoutStore.allTimeTimeoutTaskCounts().map {
                BingoDiaryTaskCount(task: $0.task, count: $0.count, firstCompletedAt: nil)
            }
            let snapshot = DiarySnapshot(
                completedTaskStats: completed,
                timeoutTaskStats: timeout,
                totalCompletedTasks: BingoDiaryStore.totalCompletedTasks(),
                totalExpiredTasks: BingoTimeoutStore.totalTimedOutTasks()
            )
            DispatchQueue.main.async {
                self.snapshot = snapshot
                self.isLoadingSnapshot = false
            }
        }
    }

    private func diarySummaryCard(value: Int, title: String) -> some View {
        VStack(spacing: scaled(6, pad: 8)) {
            Text("\(value)")
                .font(.appSystem(size: scaled(54, pad: 68), weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "2B1A0D"))
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            Text(title)
                .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "8A8179"))
        }
        .frame(maxWidth: .infinity)
        .frame(height: scaled(132, pad: 150))
        .background(
            RoundedRectangle(cornerRadius: scaled(20, pad: 24), style: .continuous)
                .fill(Color.white.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: scaled(20, pad: 24), style: .continuous)
                        .stroke(Color.white.opacity(0.95), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 6)
        )
    }

    private var emptyDiaryState: some View {
        VStack(alignment: .center, spacing: scaled(10, pad: 14)) {
            Text(L10n.noTaskCompletions)
                .font(.appSystem(size: scaled(17, pad: 20), weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "2B1A0D"))

            Text(L10n.tr("Complete a few tasks and they will appear here.", zhHans: "完成一些任务后，它们会出现在这里。", zhHant: "完成一些任務後，它們會出現在這裡。"))
                .font(.appSystem(size: scaled(13, pad: 15), weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "8A8179"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, scaled(48, pad: 64))
        .background(
            RoundedRectangle(cornerRadius: scaled(24, pad: 28), style: .continuous)
                .fill(Color.white.opacity(0.75))
        )
    }
}

private struct BingoDiaryStatsHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DiaryCalendarDay: Identifiable {
    let date: Date
    let isCurrentMonth: Bool
    let isWithinVisibleRange: Bool

    var id: TimeInterval { date.timeIntervalSince1970 }
}

private enum BingoDiaryStatsRange: CaseIterable {
    case week
    case month
    case year

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .year: return 365
        }
    }

    var title: String {
        switch self {
        case .week: return L10n.statsWeekShort
        case .month: return L10n.statsMonthShort
        case .year: return L10n.statsYearShort
        }
    }
}

private enum BingoDiaryStatsMode: CaseIterable {
    case completed
    case timeoutUnfinished

    var title: String {
        switch self {
        case .completed:
            return L10n.completedTasksShort
        case .timeoutUnfinished:
            return L10n.timeoutTasksShort
        }
    }
}

private struct BingoDiaryTaskCount: Identifiable, Equatable, Hashable {
    let task: String
    let count: Int
    let firstCompletedAt: Date?

    var id: String { task }
}

private struct BingoDiaryBubbleCloud: View {
    let bubbles: [BingoDiaryBubble]
    let canvasWidth: CGFloat
    let canvasHeight: CGFloat
    let globalMotionOffset: CGSize
    let isInteractionPaused: Bool
    var onBubbleTap: ((BingoDiaryBubble) -> Void)? = nil
    @StateObject private var simulator = BingoDiaryBubbleDynamicsSimulator()

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(bubbles) { bubble in
                let dynamicOffset = simulator.offset(for: bubble.id)
                BingoDiaryBubbleView(bubble: bubble)
                    .contentShape(Circle())
                    .onTapGesture {
                        onBubbleTap?(bubble)
                    }
                    .offset(
                        x: bubble.position.x - (bubble.diameter / 2) + dynamicOffset.width,
                        y: bubble.position.y - (bubble.diameter / 2) + dynamicOffset.height
                    )
            }
        }
        .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
        .onAppear {
            simulator.start()
            simulator.setPaused(isInteractionPaused)
            simulator.updateBubbles(
                bubbles,
                canvasSize: CGSize(width: canvasWidth, height: canvasHeight)
            )
            simulator.updateGravity(globalMotionOffset)
        }
        .onDisappear {
            simulator.stop()
        }
        .onChange(of: bubblesSignature) {
            simulator.updateBubbles(
                bubbles,
                canvasSize: CGSize(width: canvasWidth, height: canvasHeight)
            )
        }
        .onChange(of: canvasSignature) {
            simulator.updateBubbles(
                bubbles,
                canvasSize: CGSize(width: canvasWidth, height: canvasHeight)
            )
        }
        .onChange(of: globalMotionOffset) { _, newValue in
            simulator.updateGravity(newValue)
        }
        .onChange(of: isInteractionPaused) { _, newValue in
            simulator.setPaused(newValue)
        }
    }

    private var bubblesSignature: String {
        bubbles
            .map { "\($0.id)|\($0.diameter)|\($0.motionFactor)" }
            .joined(separator: "||")
    }

    private var canvasSignature: String {
        "\(Int(canvasWidth.rounded()))x\(Int(canvasHeight.rounded()))"
    }
}

private final class BingoDiaryBubbleDynamicsSimulator: ObservableObject {
    @Published private var offsets: [String: CGSize] = [:]

    private var velocities: [String: CGVector] = [:]
    private var impulses: [String: CGVector] = [:]
    private var motionFactors: [String: CGFloat] = [:]
    private var diameters: [String: CGFloat] = [:]
    private var baseCenters: [String: CGPoint] = [:]
    private var radii: [String: CGFloat] = [:]
    private var canvasSize: CGSize = .zero
    private var gravity: CGSize = .zero
    private var timer: Timer?
    private var isPaused = false

    func start() {
        guard timer == nil else { return }
        let interval: CGFloat = 1.0 / 45.0
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.step(deltaTime: interval)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        offsets.removeAll()
        velocities.removeAll()
        impulses.removeAll()
        motionFactors.removeAll()
        diameters.removeAll()
        baseCenters.removeAll()
        radii.removeAll()
        canvasSize = .zero
        gravity = .zero
        isPaused = false
    }

    func updateBubbles(_ bubbles: [BingoDiaryBubble], canvasSize: CGSize) {
        self.canvasSize = canvasSize
        let activeIDs = Set(bubbles.map(\.id))
        offsets = offsets.filter { activeIDs.contains($0.key) }
        velocities = velocities.filter { activeIDs.contains($0.key) }
        impulses = impulses.filter { activeIDs.contains($0.key) }
        motionFactors = motionFactors.filter { activeIDs.contains($0.key) }
        diameters = diameters.filter { activeIDs.contains($0.key) }
        baseCenters = baseCenters.filter { activeIDs.contains($0.key) }
        radii = radii.filter { activeIDs.contains($0.key) }

        for bubble in bubbles {
            motionFactors[bubble.id] = bubble.motionFactor
            diameters[bubble.id] = bubble.diameter
            let radius = bubble.diameter / 2
            radii[bubble.id] = radius
            baseCenters[bubble.id] = bubble.position
            if offsets[bubble.id] == nil {
                offsets[bubble.id] = .zero
            }
            if velocities[bubble.id] == nil {
                velocities[bubble.id] = .zero
            }
            if impulses[bubble.id] == nil {
                impulses[bubble.id] = .zero
            }
        }
    }

    func updateGravity(_ value: CGSize) {
        gravity = value
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
    }

    func offset(for id: String) -> CGSize {
        offsets[id] ?? .zero
    }

    private func step(deltaTime: CGFloat) {
        guard !isPaused, !offsets.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else { return }

        var updatedOffsets = offsets
        let gravityX = activeGravityComponent(gravity.width)
        let gravityY = activeGravityComponent(gravity.height)
        let smoothing = min(max(deltaTime * 14, 0.10), 0.36)
        let maxOffsetDistance: CGFloat = 15
        var maxDelta: CGFloat = 0
        let unifiedTargetOffset = clampedOffset(
            CGSize(
                width: gravityX * maxOffsetDistance,
                height: gravityY * maxOffsetDistance
            ),
            maxDistance: maxOffsetDistance
        )

        for (id, currentOffset) in offsets {
            let nextOffset = clampedOffset(
                CGSize(
                    width: currentOffset.width + (unifiedTargetOffset.width - currentOffset.width) * smoothing,
                    height: currentOffset.height + (unifiedTargetOffset.height - currentOffset.height) * smoothing
                ),
                maxDistance: maxOffsetDistance
            )
            maxDelta = max(maxDelta, hypot(nextOffset.width - currentOffset.width, nextOffset.height - currentOffset.height))
            updatedOffsets[id] = nextOffset
        }
        // Avoid needless full cloud redraws when offset changes are visually negligible.
        if maxDelta > 0.03 {
            offsets = updatedOffsets
        }
    }

    private func clampedOffset(_ offset: CGSize, maxDistance: CGFloat) -> CGSize {
        let distance = hypot(offset.width, offset.height)
        guard distance > maxDistance, distance > 0 else { return offset }
        let scale = maxDistance / distance
        return CGSize(width: offset.width * scale, height: offset.height * scale)
    }

    private func resolveCircleCollisions(
        offsets: inout [String: CGSize],
        velocities: inout [String: CGVector]
    ) {
        let ids = offsets.keys.sorted()
        guard ids.count > 1 else { return }

        let separationGap: CGFloat = 8.0
        let iterations = 7

        for _ in 0..<iterations {
            for i in 0..<(ids.count - 1) {
                for j in (i + 1)..<ids.count {
                    let idA = ids[i]
                    let idB = ids[j]

                    guard let baseA = baseCenters[idA],
                          let baseB = baseCenters[idB],
                          let radiusA = radii[idA],
                          let radiusB = radii[idB],
                          let offsetA = offsets[idA],
                          let offsetB = offsets[idB] else {
                        continue
                    }

                    var positionA = CGPoint(x: baseA.x + offsetA.width, y: baseA.y + offsetA.height)
                    var positionB = CGPoint(x: baseB.x + offsetB.width, y: baseB.y + offsetB.height)

                    var dx = positionB.x - positionA.x
                    var dy = positionB.y - positionA.y
                    var distance = hypot(dx, dy)
                    let minimumDistance = radiusA + radiusB + separationGap

                    if distance == 0 {
                        let direction = (stableHash(idA) ^ stableHash(idB)) % 2 == 0 ? 1.0 : -1.0
                        dx = CGFloat(direction)
                        dy = 0
                        distance = 1
                    }

                    guard distance < minimumDistance else { continue }

                    let normalX = dx / distance
                    let normalY = dy / distance
                    let overlap = minimumDistance - distance

                    // 质量与半径成正比：大圆更“重”，位移更小
                    let invMassA = 1.0 / max(radiusA, 1)
                    let invMassB = 1.0 / max(radiusB, 1)
                    let invMassSum = invMassA + invMassB

                    let moveA = overlap * CGFloat(invMassA / invMassSum)
                    let moveB = overlap * CGFloat(invMassB / invMassSum)

                    positionA.x -= normalX * moveA
                    positionA.y -= normalY * moveA
                    positionB.x += normalX * moveB
                    positionB.y += normalY * moveB

                    positionA = clampPosition(positionA, radius: radiusA)
                    positionB = clampPosition(positionB, radius: radiusB)

                    offsets[idA] = CGSize(width: positionA.x - baseA.x, height: positionA.y - baseA.y)
                    offsets[idB] = CGSize(width: positionB.x - baseB.x, height: positionB.y - baseB.y)

                    var velocityA = velocities[idA] ?? .zero
                    var velocityB = velocities[idB] ?? .zero

                    let relativeNormalVelocity =
                        (velocityB.dx - velocityA.dx) * normalX +
                        (velocityB.dy - velocityA.dy) * normalY

                    if relativeNormalVelocity < 0 {
                        let restitution: CGFloat = 0.22
                        let impulse = -(1 + restitution) * relativeNormalVelocity / CGFloat(invMassSum)
                        velocityA.dx -= impulse * normalX * CGFloat(invMassA)
                        velocityA.dy -= impulse * normalY * CGFloat(invMassA)
                        velocityB.dx += impulse * normalX * CGFloat(invMassB)
                        velocityB.dy += impulse * normalY * CGFloat(invMassB)
                        velocities[idA] = velocityA
                        velocities[idB] = velocityB
                    }
                }
            }
        }
    }

    private func clampPosition(_ position: CGPoint, radius: CGFloat) -> CGPoint {
        let edgePadding: CGFloat = 10
        let minX = radius + edgePadding
        let maxX = canvasSize.width - radius - edgePadding
        let minY = radius + edgePadding
        let maxY = canvasSize.height - radius - edgePadding
        return CGPoint(
            x: min(max(position.x, minX), maxX),
            y: min(max(position.y, minY), maxY)
        )
    }

    private func stableHash(_ text: String) -> UInt64 {
        text.unicodeScalars.reduce(1469598103934665603) { partialResult, scalar in
            let mixed = partialResult ^ UInt64(scalar.value)
            return mixed &* 1099511628211
        }
    }

    private func recenterCluster(
        offsets: inout [String: CGSize],
        velocities: inout [String: CGVector]
    ) {
        guard !offsets.isEmpty else { return }
        let avgX = offsets.values.reduce(CGFloat.zero) { $0 + $1.width } / CGFloat(offsets.count)
        let avgY = offsets.values.reduce(CGFloat.zero) { $0 + $1.height } / CGFloat(offsets.count)
        let horizontalStrength: CGFloat = 0.018
        let verticalStrength: CGFloat = 0.01

        for id in offsets.keys {
            guard var offset = offsets[id] else { continue }
            offset.width -= avgX * horizontalStrength
            offset.height -= avgY * verticalStrength

            if let baseCenter = baseCenters[id], let radius = radii[id] {
                let clamped = clampPosition(
                    CGPoint(x: baseCenter.x + offset.width, y: baseCenter.y + offset.height),
                    radius: radius
                )
                offsets[id] = CGSize(width: clamped.x - baseCenter.x, height: clamped.y - baseCenter.y)
            } else {
                offsets[id] = offset
            }

            if var velocity = velocities[id] {
                velocity.dx *= 0.97
                velocity.dy *= 0.97
                velocities[id] = velocity
            }
        }
    }

    private func activeGravityComponent(_ rawValue: CGFloat) -> CGFloat {
        let deadZone: CGFloat = 0.03
        let magnitude = abs(rawValue)
        guard magnitude > deadZone else { return 0 }
        let normalized = min(1.0, (magnitude - deadZone) / max(0.0001, 1.0 - deadZone))
        let curved = pow(normalized, 0.92)
        return rawValue.sign == .minus ? -curved : curved
    }
}

private final class BingoDiaryImpactFeedbackEngine {
    static let shared = BingoDiaryImpactFeedbackEngine()

    private let generator = UIImpactFeedbackGenerator(style: .medium)
    private var lastTriggerTime: TimeInterval = 0
    private let minimumInterval: TimeInterval = 0.12

    private init() {
        generator.prepare()
    }

    func trigger(intensity: CGFloat) {
        let now = CACurrentMediaTime()
        guard now - lastTriggerTime >= minimumInterval else { return }
        lastTriggerTime = now

        let normalizedIntensity = max(0.35, min(1.0, intensity))
        generator.impactOccurred(intensity: normalizedIntensity)
        generator.prepare()

        if AppSettings.isSoundEffectsEnabled {
            AudioServicesPlaySystemSound(1104)
        }
    }
}

private struct BingoDiaryBubbleView: View {
    let bubble: BingoDiaryBubble

    private var labelWidth: CGFloat {
        bubble.diameter * (bubble.diameter <= 70 ? 0.72 : 0.78)
    }

    private var labelHeight: CGFloat {
        bubble.diameter * 0.56
    }

    private var backgroundNumberFontSize: CGFloat {
        // radius 40~140 -> font 40~150
        let radius = bubble.diameter / 2
        let normalized = max(0, min(1, (radius - 40) / 100))
        return 40 + normalized * 110
    }

    private var taskFontSize: CGFloat {
        let baseSize: CGFloat
        switch bubble.diameter {
        case ..<90:
            baseSize = 13
        case ..<150:
            baseSize = 16
        case ..<210:
            baseSize = 19
        default:
            baseSize = 22
        }
        let lengthPenalty = CGFloat(max(0, bubble.task.count - 8)) * 0.22
        return max(10, baseSize - lengthPenalty)
    }

    private var bubbleTextColor: Color {
        let mixed = mix(colorA: bubble.gradientStart, colorB: bubble.gradientEnd, ratio: 0.56)
        return deepenedColor(from: mixed)
    }

    private func mix(colorA: Color, colorB: Color, ratio: CGFloat) -> UIColor {
        let left = UIColor(colorA)
        let right = UIColor(colorB)
        var lr: CGFloat = 0
        var lg: CGFloat = 0
        var lb: CGFloat = 0
        var la: CGFloat = 0
        var rr: CGFloat = 0
        var rg: CGFloat = 0
        var rb: CGFloat = 0
        var ra: CGFloat = 0
        let leftOK = left.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        let rightOK = right.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)
        guard leftOK, rightOK else { return left }
        let clamped = min(max(ratio, 0), 1)
        let inv = 1 - clamped
        return UIColor(
            red: lr * clamped + rr * inv,
            green: lg * clamped + rg * inv,
            blue: lb * clamped + rb * inv,
            alpha: la * clamped + ra * inv
        )
    }

    private func deepenedColor(from color: UIColor) -> Color {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        if color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            let deeper = UIColor(
                hue: hue,
                saturation: min(1.0, saturation * 1.12 + 0.04),
                brightness: max(0.08, brightness * 0.38),
                alpha: 1
            )
            return Color(uiColor: deeper)
        }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var rgbaAlpha: CGFloat = 0
        if color.getRed(&red, green: &green, blue: &blue, alpha: &rgbaAlpha) {
            return Color(
                red: max(0, red * 0.42),
                green: max(0, green * 0.42),
                blue: max(0, blue * 0.42)
            )
        }
        return Color(hex: "2B1A0D")
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [bubble.gradientStart, bubble.gradientEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("\(bubble.count)")
                .font(.appSystem(size: backgroundNumberFontSize, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.2))
                .minimumScaleFactor(0.4)

            Text(bubble.task)
                .font(.appSystem(size: taskFontSize, weight: .bold, design: .rounded))
                .foregroundColor(bubbleTextColor)
                .frame(width: labelWidth, height: labelHeight, alignment: .center)
                .lineLimit(nil)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.55)
                .allowsTightening(true)
        }
        .frame(width: bubble.diameter, height: bubble.diameter)
        .clipShape(Circle())
    }
}

private struct BingoDiaryBubble: Identifiable, Equatable {
    let id: String
    let task: String
    let count: Int
    let diameter: CGFloat
    let position: CGPoint
    let gradientStart: Color
    let gradientEnd: Color
    let motionFactor: CGFloat
}

private enum BingoDiaryBubbleTier {
    case round1
    case round2
    case round3
    case round4

    var diameter: CGFloat {
        switch self {
        case .round1: return 237
        case .round2: return 200
        case .round3: return 130
        case .round4: return 70
        }
    }

    var backgroundFontSize: CGFloat {
        switch self {
        case .round1: return 150
        case .round2: return 110
        case .round3: return 90
        case .round4: return 40
        }
    }
}

private enum BingoDiaryBubbleLayout {
    private struct Descriptor {
        let taskCount: BingoDiaryTaskCount
        let radius: CGFloat
        let gradientStart: Color
        let gradientEnd: Color
        let motionFactor: CGFloat

        var diameter: CGFloat { radius * 2 }
    }

    private struct Placement {
        let descriptor: Descriptor
        let center: CGPoint
        let radius: CGFloat
    }

    private static let minimumGap: CGFloat = 8
    private static let sideInset: CGFloat = 16
    private static let topInset: CGFloat = 0
    private static let initialTopGap: CGFloat = 0
    private static let bottomVisibilityReserve: CGFloat = 28
    private static let palette: [(Color, Color)] = [
        (Color(hex: "F1C397"), Color(hex: "F7E3CF")),
        (Color(hex: "F1A0A0"), Color(hex: "FFDBDB")),
        (Color(hex: "99DAC0"), Color(hex: "CCF4D0")),
        (Color(hex: "7DC5E2"), Color(hex: "D6F3FF")),
        (Color(hex: "BF9CD6"), Color(hex: "FDE4FC")),
        (Color(hex: "EBA1CA"), Color(hex: "FDD7EC"))
    ]

    static func layout(
        taskCounts: [BingoDiaryTaskCount],
        width: CGFloat,
        viewportHeight: CGFloat,
        maximumBubbleCount: Int
    ) -> (bubbles: [BingoDiaryBubble], width: CGFloat, height: CGFloat, isHorizontallyOverflowing: Bool) {
        let visibleItems = Array(taskCounts.prefix(maximumBubbleCount))
        let usableWidth = width.isFinite ? max(width, 0) : 0
        guard !visibleItems.isEmpty else { return ([], usableWidth, 0, false) }
        // Wait for a real measured width instead of using a synthetic fallback.
        // This avoids first-entry transient vertical stacks caused by early narrow passes.
        guard usableWidth > 1 else { return ([], 0, 0, false) }

        let sortedItems = visibleItems.sorted { lhs, rhs in
            if lhs.count == rhs.count {
                switch (lhs.firstCompletedAt, rhs.firstCompletedAt) {
                case let (l?, r?) where l != r:
                    return l < r
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                default:
                    return lhs.task.localizedCaseInsensitiveCompare(rhs.task) == .orderedAscending
                }
            }
            return lhs.count > rhs.count
        }

        let minimumCount = sortedItems.map(\.count).min() ?? 0
        let maximumCount = sortedItems.map(\.count).max() ?? 0
        let countSpread = maximumCount - minimumCount
        let uniqueCountsAscending = Array(Set(sortedItems.map(\.count))).sorted()
        let shouldUseAdjacentTierSizing = sortedItems.count < 4 || countSpread < 2

        let adjacentTierByCount: [Int: BingoDiaryBubbleTier] = {
            guard shouldUseAdjacentTierSizing, !uniqueCountsAscending.isEmpty else { return [:] }
            let tiersAscending: [BingoDiaryBubbleTier] = [.round4, .round3, .round2, .round1] // small -> large
            let requiredTierCount = min(max(uniqueCountsAscending.count, 1), tiersAscending.count)
            let preferredStart = adjacentTierStartIndex(maxCount: maximumCount, requiredTierCount: requiredTierCount)
            let maxStart = tiersAscending.count - requiredTierCount
            let startIndex = min(max(preferredStart, 0), maxStart)
            var mapping: [Int: BingoDiaryBubbleTier] = [:]
            for (index, count) in uniqueCountsAscending.enumerated() {
                let tierOffset = min(index, requiredTierCount - 1)
                mapping[count] = tiersAscending[startIndex + tierOffset]
            }
            return mapping
        }()

        func radius(for value: Int) -> CGFloat {
            if shouldUseAdjacentTierSizing, let tier = adjacentTierByCount[value] {
                return tier.diameter / 2
            }
            guard maximumCount > minimumCount else { return 90 }
            let normalized = CGFloat(value - minimumCount) / CGFloat(maximumCount - minimumCount)
            return 40 + normalized * 100
        }

        let descriptors: [Descriptor] = sortedItems.enumerated().map { index, item in
            let resolvedRadius = radius(for: item.count)
            let paletteItem = palette[colorIndex(for: item.task)]
            let normalizedRadius = max(0, min(1, (resolvedRadius - 40) / 100))
            let tierMotionBase: CGFloat = 1.12 - normalizedRadius * 0.16
            let colorJitter = CGFloat(colorIndex(for: item.task) % 4) * 0.04
            let motionFactor = min(1.25, tierMotionBase + colorJitter)
            return Descriptor(
                taskCount: item,
                radius: resolvedRadius,
                gradientStart: paletteItem.0,
                gradientEnd: paletteItem.1,
                motionFactor: motionFactor
            )
        }

        if descriptors.count == 1 {
            let descriptor = descriptors[0]
            let canvasHeight = max(360, descriptor.radius * 2 + 160) + bottomVisibilityReserve
            let center = CGPoint(
                x: usableWidth / 2,
                y: canvasHeight / 2
            )
            let bubbles = [makeBubble(from: descriptor, at: center)]
            return (
                bubbles,
                usableWidth,
                canvasHeight,
                false
            )
        }

        return horizontalOverflowLayout(
            descriptors: descriptors,
            canvasWidth: usableWidth,
            viewportHeight: viewportHeight
        )
    }

    private static func adjacentTierStartIndex(maxCount: Int, requiredTierCount: Int) -> Int {
        let preferredStart: Int
        switch maxCount {
        case ...2:
            preferredStart = 0
        case ...5:
            preferredStart = 1
        case ...24:
            preferredStart = 2
        default:
            preferredStart = 2
        }
        return min(max(preferredStart, 0), max(0, 4 - requiredTierCount))
    }

    private static func shouldUseHorizontalOverflowByWidth(
        descriptors: [Descriptor],
        availableWidth: CGFloat
    ) -> Bool {
        let totalDiameters = descriptors.reduce(CGFloat.zero) { $0 + $1.diameter }
        let totalGaps = CGFloat(max(descriptors.count - 1, 0)) * minimumGap
        let requiredWidth = sideInset + totalDiameters + totalGaps + sideInset
        return requiredWidth > availableWidth
    }

    private static func centeredVerticalColumnsLayout(
        descriptors: [Descriptor],
        canvasWidth: CGFloat
    ) -> (bubbles: [BingoDiaryBubble], width: CGFloat, height: CGFloat, isHorizontallyOverflowing: Bool) {
        guard !descriptors.isEmpty else { return ([], canvasWidth, 0, false) }

        let centerX = canvasWidth / 2
        let centerIndex: Int = descriptors.enumerated().min { lhs, rhs in
            let leftDate = lhs.element.taskCount.firstCompletedAt
            let rightDate = rhs.element.taskCount.firstCompletedAt
            switch (leftDate, rightDate) {
            case let (l?, r?):
                if l != r { return l < r }
                return lhs.offset < rhs.offset
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.offset < rhs.offset
            }
        }?.offset ?? 0

        let centerDescriptor = descriptors[centerIndex]
        var remainingDescriptors = descriptors.enumerated().compactMap { index, descriptor in
            index == centerIndex ? nil : descriptor
        }

        let centerAnchor = CGPoint(
            x: centerX,
            y: topInset + centerDescriptor.radius + initialTopGap
        )
        var bubbles: [BingoDiaryBubble] = []
        bubbles.reserveCapacity(descriptors.count)
        bubbles.append(
            makeBubble(
                from: centerDescriptor,
                at: centerAnchor
            )
        )

        var nextTopY = centerAnchor.y + centerDescriptor.radius + minimumGap
        var rowIndex = 0

        while !remainingDescriptors.isEmpty {
            let leftDescriptor = remainingDescriptors.isEmpty ? nil : remainingDescriptors.removeFirst()
            let rightDescriptor = remainingDescriptors.isEmpty ? nil : remainingDescriptors.removeFirst()
            let rowHeight = max(leftDescriptor?.diameter ?? 0, rightDescriptor?.diameter ?? 0)
            guard rowHeight > 0 else { break }

            let rowCenterY = nextTopY + (rowHeight / 2)
            let horizontalExtra = CGFloat(rowIndex) * 4

            if let leftDescriptor {
                let leftCenterX = clamp(
                    centerX - (centerDescriptor.radius + leftDescriptor.radius + minimumGap + 12 + horizontalExtra),
                    sideInset + leftDescriptor.radius,
                    canvasWidth - sideInset - leftDescriptor.radius
                )
                bubbles.append(
                    makeBubble(
                        from: leftDescriptor,
                        at: CGPoint(x: leftCenterX, y: rowCenterY)
                    )
                )
            }

            if let rightDescriptor {
                let rightCenterX = clamp(
                    centerX + (centerDescriptor.radius + rightDescriptor.radius + minimumGap + 12 + horizontalExtra),
                    sideInset + rightDescriptor.radius,
                    canvasWidth - sideInset - rightDescriptor.radius
                )
                bubbles.append(
                    makeBubble(
                        from: rightDescriptor,
                        at: CGPoint(x: rightCenterX, y: rowCenterY)
                    )
                )
            }

            nextTopY += rowHeight + minimumGap
            rowIndex += 1
        }

        let contentBottom = max(
            bubbles.map { $0.position.y + ($0.diameter / 2) }.max() ?? 0,
            nextTopY - minimumGap
        )
        let canvasHeight = max(420, contentBottom + topInset + bottomVisibilityReserve)
        let relaxed = relaxInitialOverlaps(
            bubbles: bubbles,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight
        )
        return (relaxed, canvasWidth, canvasHeight, false)
    }

    private static func verticalStackLayout(
        descriptors: [Descriptor],
        canvasWidth: CGFloat
    ) -> (bubbles: [BingoDiaryBubble], width: CGFloat, height: CGFloat, isHorizontallyOverflowing: Bool) {
        guard !descriptors.isEmpty else { return ([], canvasWidth, 0, false) }

        let centerX = canvasWidth / 2
        var nextTopY = topInset + initialTopGap
        var bubbles: [BingoDiaryBubble] = []
        bubbles.reserveCapacity(descriptors.count)

        for descriptor in descriptors {
            let centerY = nextTopY + descriptor.radius
            bubbles.append(
                makeBubble(
                    from: descriptor,
                    at: CGPoint(x: centerX, y: centerY)
                )
            )
            nextTopY = centerY + descriptor.radius + minimumGap
        }

        let contentBottom = nextTopY - minimumGap
        let canvasHeight = max(420, contentBottom + topInset + bottomVisibilityReserve)
        return (bubbles, canvasWidth, canvasHeight, false)
    }

    private static func tier(for count: Int, rank: Int, total: Int, topCount: Int) -> BingoDiaryBubbleTier {
        if total == 1 { return .round1 }
        if rank == 0 { return .round1 }
        if total == 2 { return rank == 1 ? .round2 : .round1 }
        if total == 3 {
            return rank == 1 ? .round2 : (rank == 2 ? .round3 : .round1)
        }

        let normalizedTop = max(topCount, 1)
        let ratio = Double(count) / Double(normalizedTop)

        // 在窄屏上避免前几颗圆过大导致只能纵向堆叠：当头部完成数不高时，压缩到 round3/round4。
        if normalizedTop <= 2 {
            return rank <= 4 ? .round3 : .round4
        }

        if normalizedTop <= 4 {
            if rank <= 1 && ratio >= 0.8 {
                return .round2
            }
            if rank <= 6 || ratio >= 0.22 {
                return .round3
            }
            return .round4
        }

        if rank <= 2 && ratio >= 0.58 {
            return .round2
        }
        if rank <= 7 || ratio >= 0.14 {
            return .round3
        }
        return .round4
    }

    private static func uniformTier(forItemCount itemCount: Int) -> BingoDiaryBubbleTier {
        switch itemCount {
        case ...4:
            return .round2
        case ...12:
            return .round3
        default:
            return .round4
        }
    }

    private static func shouldPreferHorizontalOverflow(
        descriptors: [Descriptor],
        availableWidth: CGFloat,
        clusteredHeight: CGFloat
    ) -> Bool {
        // 优先使用“最大圆居中 + 周围随机分布”，只有数量很多且高度明显过高时才切换到右延展。
        if descriptors.count < 14 {
            return false
        }
        if availableWidth >= 430 && descriptors.count < 18 {
            return false
        }
        return clusteredHeight > 2200
    }

    private static func horizontalOverflowLayout(
        descriptors: [Descriptor],
        canvasWidth: CGFloat,
        viewportHeight: CGFloat
    ) -> (bubbles: [BingoDiaryBubble], width: CGFloat, height: CGFloat, isHorizontallyOverflowing: Bool) {
        guard !descriptors.isEmpty else { return ([], canvasWidth, 0, false) }

        let effectiveViewportHeight = viewportHeight.isFinite ? max(viewportHeight, 0) : 0
        let baseHeight = effectiveViewportHeight > 1 ? effectiveViewportHeight : 560
        let pageHeight = max(560, baseHeight + 140)
        let availableTop = topInset + initialTopGap
        let availableBottom = pageHeight - topInset
        let edgeOverflowX: CGFloat = 26
        let edgeOverflowY: CGFloat = 0

        let sortedDescriptors = descriptors.sorted { lhs, rhs in
            if lhs.radius != rhs.radius { return lhs.radius > rhs.radius }
            return lhs.taskCount.count > rhs.taskCount.count
        }

        var placed: [Placement] = []
        var requiredPageCount = 1
        let maxAttemptsPerPage = 800

        for (index, descriptor) in sortedDescriptors.enumerated() {
            var placement: Placement?
            var pageIndex = 0

            while placement == nil && pageIndex < 120 {
                let pageStartX = CGFloat(pageIndex) * canvasWidth
                let minX = pageStartX + descriptor.radius - edgeOverflowX
                let maxX = pageStartX + canvasWidth - descriptor.radius + edgeOverflowX
                let minY = availableTop + descriptor.radius - edgeOverflowY
                let maxY = availableBottom - descriptor.radius + edgeOverflowY

                var generator = SeededGenerator(
                    state: seed(for: descriptor.taskCount.task)
                    &+ UInt64(index * 131)
                    &+ UInt64(pageIndex * 9_973)
                    &+ 1
                )
                let pagePlaced = placed.filter { placement in
                    placement.center.x >= pageStartX - edgeOverflowX &&
                    placement.center.x <= pageStartX + canvasWidth + edgeOverflowX
                }
                var bestPlacementForPage: (placement: Placement, score: CGFloat)?

                let tangentAttempts = Int(CGFloat(maxAttemptsPerPage) * 0.9)
                for attempt in 0..<maxAttemptsPerPage {
                    let candidate: CGPoint
                    if !pagePlaced.isEmpty,
                       attempt < tangentAttempts,
                       let base = pagePlaced.randomElement(using: &generator) {
                        let angle = CGFloat.random(in: 0...(2 * .pi), using: &generator)
                        // Keep edge spacing uniform regardless of bubble sizes.
                        let targetDistance = base.radius + descriptor.radius + minimumGap
                        candidate = CGPoint(
                            x: base.center.x + cos(angle) * targetDistance,
                            y: base.center.y + sin(angle) * targetDistance
                        )
                    } else {
                        candidate = CGPoint(
                            x: CGFloat.random(in: minX...maxX, using: &generator),
                            y: CGFloat.random(in: minY...maxY, using: &generator)
                        )
                    }

                    guard candidate.x >= minX, candidate.x <= maxX,
                          candidate.y >= minY, candidate.y <= maxY else {
                        continue
                    }
                    if fits(candidate, radius: descriptor.radius, among: placed) {
                        let resolvedPlacement = Placement(
                            descriptor: descriptor,
                            center: candidate,
                            radius: descriptor.radius
                        )
                        let nearestEdgeDistance: CGFloat = placed.isEmpty
                            ? 0
                            : placed.reduce(CGFloat.greatestFiniteMagnitude) { current, other in
                                let centerDistance = hypot(candidate.x - other.center.x, candidate.y - other.center.y)
                                let edgeDistance = max(0, centerDistance - (descriptor.radius + other.radius))
                                return min(current, edgeDistance)
                            }
                        let pageCenter = CGPoint(
                            x: pageStartX + (canvasWidth / 2),
                            y: (availableTop + availableBottom) / 2
                        )
                        let centerDistance = hypot(candidate.x - pageCenter.x, candidate.y - pageCenter.y)
                        // Prefer candidates that keep the nearest edge gap close to minimumGap.
                        let score = nearestEdgeDistance * 8 + centerDistance * 0.02

                        if let best = bestPlacementForPage {
                            if score < best.score {
                                bestPlacementForPage = (resolvedPlacement, score)
                            }
                        } else {
                            bestPlacementForPage = (resolvedPlacement, score)
                        }
                    }
                }

                if let bestPlacementForPage {
                    placement = bestPlacementForPage.placement
                    requiredPageCount = max(requiredPageCount, pageIndex + 1)
                }

                if placement == nil {
                    pageIndex += 1
                }
            }

            if let placement {
                placed.append(placement)
            } else {
                let fallbackPage = requiredPageCount
                let fallbackCenter = CGPoint(
                    x: CGFloat(fallbackPage) * canvasWidth + canvasWidth * 0.5,
                    y: (availableTop + availableBottom) * 0.5
                )
                placed.append(
                    Placement(
                        descriptor: descriptor,
                        center: fallbackCenter,
                        radius: descriptor.radius
                    )
                )
                requiredPageCount = fallbackPage + 1
            }
        }

        let bubbles = placed.map { placement in
            makeBubble(from: placement.descriptor, at: placement.center)
        }
        let totalCanvasWidth = max(canvasWidth, CGFloat(requiredPageCount) * canvasWidth)
        return (bubbles, totalCanvasWidth, pageHeight, requiredPageCount > 1)
    }

    private static func uniformSideWrappedLayout(
        descriptors: [Descriptor],
        canvasWidth: CGFloat
    ) -> (bubbles: [BingoDiaryBubble], width: CGFloat, height: CGFloat, isHorizontallyOverflowing: Bool) {
        guard let centerDescriptor = descriptors.first else {
            return ([], canvasWidth, 0, false)
        }

        var canvasHeight = max(420, centerDescriptor.diameter + 220)
        let anchor = CGPoint(
            x: canvasWidth / 2,
            y: topInset + centerDescriptor.radius + initialTopGap
        )
        let sidePreferredAngles = sideWrappingAngleIndices(count: 24).map {
            (CGFloat($0) / 24.0) * .pi * 2
        }

        var placed: [Placement] = [
            Placement(descriptor: centerDescriptor, center: anchor, radius: centerDescriptor.radius)
        ]

        for descriptor in descriptors.dropFirst() {
            var placedPoint: CGPoint?
            let minX = sideInset + descriptor.radius
            let maxX = canvasWidth - sideInset - descriptor.radius

            var expansion = 0
            while placedPoint == nil && expansion < 7 {
                let minY = topInset + descriptor.radius
                let maxY = canvasHeight - topInset - descriptor.radius
                let maxReachX = max(18, min(anchor.x - minX, maxX - anchor.x))
                let maxReachY = max(18, min(anchor.y - minY, maxY - anchor.y))

                var bestRelaxedCandidate: (point: CGPoint, overlapPenalty: CGFloat, distancePenalty: CGFloat)?

                for ring in 1...18 {
                    let baseX = max(descriptor.radius + minimumGap + 6, CGFloat(ring) * (descriptor.radius * 1.18 + minimumGap))
                    let baseY = max(descriptor.radius + minimumGap + 6, CGFloat(ring) * (descriptor.radius * 1.05 + minimumGap))
                    let ellipseX = min(maxReachX * 0.96, baseX)
                    let ellipseY = min(maxReachY * 0.96, baseY)

                    for angle in sidePreferredAngles {
                        let candidate = CGPoint(
                            x: anchor.x + cos(angle) * ellipseX,
                            y: anchor.y + sin(angle) * ellipseY
                        )

                        guard candidate.x >= minX, candidate.x <= maxX,
                              candidate.y >= minY, candidate.y <= maxY else {
                            continue
                        }

                        if fits(candidate, radius: descriptor.radius, among: placed) {
                            placedPoint = candidate
                            break
                        }

                        let overlapPenalty = placed.reduce(CGFloat.zero) { partial, other in
                            let distance = hypot(candidate.x - other.center.x, candidate.y - other.center.y)
                            let minDistance = descriptor.radius + other.radius + minimumGap
                            return partial + max(0, minDistance - distance)
                        }
                        let horizontalPreference = abs(candidate.y - anchor.y) * 0.7 + abs(candidate.x - anchor.x) * 0.25
                        if let current = bestRelaxedCandidate {
                            if overlapPenalty < current.overlapPenalty ||
                                (overlapPenalty == current.overlapPenalty && horizontalPreference < current.distancePenalty) {
                                bestRelaxedCandidate = (candidate, overlapPenalty, horizontalPreference)
                            }
                        } else {
                            bestRelaxedCandidate = (candidate, overlapPenalty, horizontalPreference)
                        }
                    }

                    if placedPoint != nil { break }
                }

                if placedPoint == nil {
                    if let relaxed = bestRelaxedCandidate {
                        placedPoint = relaxed.point
                    } else {
                        canvasHeight += 90
                        expansion += 1
                    }
                }
            }

            if placedPoint == nil {
                let fallbackAngle = sidePreferredAngles[(placed.count - 1) % sidePreferredAngles.count]
                let minY = topInset + descriptor.radius
                let maxY = canvasHeight - topInset - descriptor.radius
                let fallback = CGPoint(
                    x: clamp(anchor.x + cos(fallbackAngle) * max(22, descriptor.radius + 8), minX, maxX),
                    y: clamp(anchor.y + sin(fallbackAngle) * max(22, descriptor.radius + 8), minY, maxY)
                )
                placedPoint = fallback
            }

            placed.append(
                Placement(
                    descriptor: descriptor,
                    center: placedPoint ?? anchor,
                    radius: descriptor.radius
                )
            )
        }

        let maxY = placed.map { $0.center.y + $0.radius }.max() ?? anchor.y
        let bubbles = placed.map { makeBubble(from: $0.descriptor, at: $0.center) }
        let finalHeight = max(canvasHeight, maxY + 24 + bottomVisibilityReserve)
        let relaxed = relaxInitialOverlaps(
            bubbles: bubbles,
            canvasWidth: canvasWidth,
            canvasHeight: finalHeight
        )
        return (relaxed, canvasWidth, finalHeight, false)
    }

    private static func clusteredLayout(
        descriptors: [Descriptor],
        canvasWidth: CGFloat,
        preferSideWrapping: Bool = false
    ) -> (bubbles: [BingoDiaryBubble], width: CGFloat, height: CGFloat, isHorizontallyOverflowing: Bool) {
        guard let firstDescriptor = descriptors.first else {
            return ([], canvasWidth, 0, false)
        }

        var canvasHeight = max(430, firstDescriptor.diameter + 240)
        let centerAnchor = CGPoint(
            x: canvasWidth / 2,
            y: topInset + firstDescriptor.radius + initialTopGap
        )
        var placed: [Placement] = [
            Placement(descriptor: firstDescriptor, center: centerAnchor, radius: firstDescriptor.radius)
        ]

        for descriptor in descriptors.dropFirst() {
            var placedPoint: CGPoint?
            var relaxedCandidate: (point: CGPoint, score: CGFloat)?
            var laneIndex = 0

            while placedPoint == nil && laneIndex < 22 {
                let minX = sideInset + descriptor.radius
                let maxX = canvasWidth - sideInset - descriptor.radius
                let minY = topInset + descriptor.radius
                let maxY = canvasHeight - topInset - descriptor.radius

                let lane = CGFloat(laneIndex)
                let xOffset =
                    firstDescriptor.radius +
                    descriptor.radius +
                    minimumGap +
                    16 +
                    lane * max(descriptor.radius * 0.85, 24)

                let yStep = max(descriptor.radius * 0.95, 22)
                let yOffsets: [CGFloat] = [0, -yStep, yStep, -2 * yStep, 2 * yStep]
                let sidePriority: [CGFloat] = placed.count.isMultiple(of: 2) ? [1, -1] : [-1, 1]

                for side in sidePriority {
                    for yOffset in yOffsets {
                        let candidate = CGPoint(
                            x: clamp(centerAnchor.x + side * xOffset, minX, maxX),
                            y: clamp(centerAnchor.y + yOffset, minY, maxY)
                        )

                        if fits(candidate, radius: descriptor.radius, among: placed) {
                            placedPoint = candidate
                            break
                        }

                        let overlapPenalty = placed.reduce(CGFloat.zero) { partial, other in
                            let distance = hypot(candidate.x - other.center.x, candidate.y - other.center.y)
                            let minDistance = descriptor.radius + other.radius + minimumGap
                            return partial + max(0, minDistance - distance)
                        }
                        let verticalPenalty = abs(candidate.y - centerAnchor.y)
                        let sidePenalty = abs((candidate.x - centerAnchor.x) / max(1, xOffset))
                        let score = overlapPenalty * 2.0 + verticalPenalty * 0.65 + sidePenalty * 20

                        if let current = relaxedCandidate {
                            if score < current.score {
                                relaxedCandidate = (candidate, score)
                            }
                        } else {
                            relaxedCandidate = (candidate, score)
                        }
                    }
                    if placedPoint != nil { break }
                }

                if placedPoint == nil {
                    laneIndex += 1
                    if laneIndex % 5 == 0 {
                        canvasHeight += 56
                    }
                }
            }

            if placedPoint == nil, preferSideWrapping {
                let stepSeed = seed(for: descriptor.taskCount.task) &+ UInt64(placed.count * 97)
                placedPoint = findClusterCenter(
                    radius: descriptor.radius,
                    clusterAnchor: centerAnchor,
                    canvasWidth: canvasWidth,
                    canvasHeight: canvasHeight,
                    placed: placed,
                    seed: stepSeed,
                    preferSideWrapping: true
                )
            }

            let sideSign: CGFloat = placed.count.isMultiple(of: 2) ? 1 : -1
            let lane = CGFloat(max(0, placed.count - 1) / 2)
            let fallback = CGPoint(
                x: clamp(
                    centerAnchor.x + sideSign * (firstDescriptor.radius + descriptor.radius + minimumGap + 14 + lane * 20),
                    sideInset + descriptor.radius,
                    canvasWidth - sideInset - descriptor.radius
                ),
                y: clamp(
                    centerAnchor.y + ((lane.truncatingRemainder(dividingBy: 2) == 0) ? -1 : 1) * (descriptor.radius * 0.2 + lane * 4),
                    topInset + descriptor.radius,
                    canvasHeight - topInset - descriptor.radius
                )
            )
            placed.append(
                Placement(
                    descriptor: descriptor,
                    center: placedPoint ?? relaxedCandidate?.point ?? fallback,
                    radius: descriptor.radius
                )
            )
        }

        if !placed.isEmpty {
            let minBoundX = placed.map { $0.center.x - $0.radius }.min() ?? sideInset
            let maxBoundX = placed.map { $0.center.x + $0.radius }.max() ?? (canvasWidth - sideInset)
            let clusterMidX = (minBoundX + maxBoundX) / 2
            let allowablePositive = (canvasWidth - sideInset) - maxBoundX
            let allowableNegative = sideInset - minBoundX
            let shiftX = clamp(centerAnchor.x - clusterMidX, allowableNegative, allowablePositive)
            if abs(shiftX) > 0.5 {
                placed = placed.map { current in
                    Placement(
                        descriptor: current.descriptor,
                        center: CGPoint(x: current.center.x + shiftX, y: current.center.y),
                        radius: current.radius
                    )
                }
            }
        }

        let maxY = placed.map { $0.center.y + $0.radius }.max() ?? 0
        let bubbles = placed.map { makeBubble(from: $0.descriptor, at: $0.center) }
        let finalHeight = max(canvasHeight, maxY + 28 + bottomVisibilityReserve)
        let relaxed = relaxInitialOverlaps(
            bubbles: bubbles,
            canvasWidth: canvasWidth,
            canvasHeight: finalHeight
        )
        return (relaxed, canvasWidth, finalHeight, false)
    }

    private static func findClusterCenter(
        radius: CGFloat,
        clusterAnchor: CGPoint,
        canvasWidth: CGFloat,
        canvasHeight: CGFloat,
        placed: [Placement],
        seed: UInt64,
        preferSideWrapping: Bool
    ) -> CGPoint? {
        let minX = sideInset + radius
        let maxX = canvasWidth - sideInset - radius
        let minY = topInset + radius
        let maxY = canvasHeight - topInset - radius

        let largestRadius = placed.first?.radius ?? 0
        let ringStart = largestRadius + radius + minimumGap
        let angleCount = 24
        var bestCandidate: (point: CGPoint, score: CGFloat)?

        for ringIndex in 0..<30 {
            let ringDistance = ringStart + CGFloat(ringIndex) * 18
            let angleOrder: [Int]
            if preferSideWrapping {
                angleOrder = sideWrappingAngleIndices(count: angleCount)
            } else {
                angleOrder = shuffledIndices(
                    count: angleCount,
                    seed: seed &+ UInt64(ringIndex * 31)
                )
            }

            for angleIndex in angleOrder {
                let angle = (CGFloat(angleIndex) / CGFloat(angleCount)) * .pi * 2
                let rawPoint = CGPoint(
                    x: clusterAnchor.x + cos(angle) * ringDistance,
                    y: clusterAnchor.y + sin(angle) * ringDistance
                )
                let candidate = CGPoint(
                    x: clamp(rawPoint.x, minX, maxX),
                    y: clamp(rawPoint.y, minY, maxY)
                )

                guard fits(candidate, radius: radius, among: placed) else { continue }

                let centerDistance = hypot(
                    candidate.x - clusterAnchor.x,
                    candidate.y - clusterAnchor.y
                )
                let nearbyCount = placed.reduce(0) { partialResult, placement in
                    let distance = hypot(
                        candidate.x - placement.center.x,
                        candidate.y - placement.center.y
                    )
                    let edgeDistance = distance - radius - placement.radius
                    return partialResult + (edgeDistance <= minimumGap + 20 ? 1 : 0)
                }
                let randomBias = CGFloat((seed &+ UInt64(angleIndex * 13)) % 100) / 500.0
                let verticalPenalty = abs(candidate.y - clusterAnchor.y)
                let sideBias = abs(cos(angle))
                let sidePenalty = max(0, 0.55 - sideBias) * 180
                let score: CGFloat
                if preferSideWrapping {
                    score = centerDistance * 0.28 + verticalPenalty * 1.45 + sidePenalty - CGFloat(nearbyCount) * 20 + randomBias
                } else {
                    score = centerDistance - CGFloat(nearbyCount) * 26 + randomBias
                }

                if let currentBest = bestCandidate {
                    if score < currentBest.score {
                        bestCandidate = (candidate, score)
                    }
                } else {
                    bestCandidate = (candidate, score)
                }
            }
        }

        return bestCandidate?.point
    }

    private static func fits(_ candidate: CGPoint, radius: CGFloat, among placed: [Placement]) -> Bool {
        for other in placed {
            let distance = hypot(candidate.x - other.center.x, candidate.y - other.center.y)
            if distance < radius + other.radius + minimumGap {
                return false
            }
        }
        return true
    }

    private static func makeBubble(from descriptor: Descriptor, at center: CGPoint) -> BingoDiaryBubble {
        BingoDiaryBubble(
            id: descriptor.taskCount.id,
            task: descriptor.taskCount.task,
            count: descriptor.taskCount.count,
            diameter: descriptor.diameter,
            position: center,
            gradientStart: descriptor.gradientStart,
            gradientEnd: descriptor.gradientEnd,
            motionFactor: descriptor.motionFactor
        )
    }

    private static func shuffledIndices(count: Int, seed: UInt64) -> [Int] {
        var values = Array(0..<count)
        var generator = SeededGenerator(state: max(seed, 1))
        values.shuffle(using: &generator)
        return values
    }

    private static func sideWrappingAngleIndices(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let all = Array(0..<count)
        let angles = all.map { idx in
            (idx: idx, angle: (CGFloat(idx) / CGFloat(count)) * .pi * 2)
        }

        let left = angles
            .filter { cos($0.angle) < 0 }
            .sorted {
                let lhs = abs(sin($0.angle))
                let rhs = abs(sin($1.angle))
                if lhs == rhs {
                    return abs(cos($0.angle)) > abs(cos($1.angle))
                }
                return lhs < rhs
            }
            .map(\.idx)

        let right = angles
            .filter { cos($0.angle) >= 0 }
            .sorted {
                let lhs = abs(sin($0.angle))
                let rhs = abs(sin($1.angle))
                if lhs == rhs {
                    return abs(cos($0.angle)) > abs(cos($1.angle))
                }
                return lhs < rhs
            }
            .map(\.idx)

        var result: [Int] = []
        var leftIndex = 0
        var rightIndex = 0
        while leftIndex < left.count || rightIndex < right.count {
            if leftIndex < left.count {
                result.append(left[leftIndex])
                leftIndex += 1
            }
            if rightIndex < right.count {
                result.append(right[rightIndex])
                rightIndex += 1
            }
        }
        return result
    }

    private static func deterministicJitter(task: String, amplitude: CGFloat) -> CGFloat {
        guard amplitude > 0 else { return 0 }
        let value = CGFloat(seed(for: task) % 10_000) / 10_000.0
        return (value * 2 - 1) * amplitude
    }

    private static func seed(for text: String) -> UInt64 {
        text.unicodeScalars.reduce(1469598103934665603) { partialResult, scalar in
            let mixed = partialResult ^ UInt64(scalar.value)
            return mixed &* 1099511628211
        }
    }

    private static func clamp(_ value: CGFloat, _ minValue: CGFloat, _ maxValue: CGFloat) -> CGFloat {
        min(max(value, minValue), maxValue)
    }

    private static func colorIndex(for task: String) -> Int {
        abs(task.unicodeScalars.reduce(0) { partialResult, scalar in
            ((partialResult * 31) + Int(scalar.value)) % 100_000
        }) % palette.count
    }

    private static func relaxInitialOverlaps(
        bubbles: [BingoDiaryBubble],
        canvasWidth: CGFloat,
        canvasHeight: CGFloat
    ) -> [BingoDiaryBubble] {
        guard bubbles.count > 1 else { return bubbles }

        var centers = bubbles.map(\.position)
        let radii = bubbles.map { $0.diameter / 2 }
        let gap = minimumGap
        let iterations = 18
        let minXPadding = sideInset
        let minYPadding = topInset + 4

        for _ in 0..<iterations {
            for i in 0..<(centers.count - 1) {
                for j in (i + 1)..<centers.count {
                    var dx = centers[j].x - centers[i].x
                    var dy = centers[j].y - centers[i].y
                    var distance = hypot(dx, dy)
                    let minDistance = radii[i] + radii[j] + gap
                    if distance == 0 {
                        dx = 1
                        dy = 0
                        distance = 1
                    }
                    guard distance < minDistance else { continue }
                    let overlap = minDistance - distance
                    let nx = dx / distance
                    let ny = dy / distance
                    let push = overlap * 0.5
                    centers[i].x -= nx * push
                    centers[i].y -= ny * push
                    centers[j].x += nx * push
                    centers[j].y += ny * push
                }
            }

            for index in centers.indices {
                let radius = radii[index]
                centers[index].x = clamp(
                    centers[index].x,
                    minXPadding + radius,
                    canvasWidth - minXPadding - radius
                )
                centers[index].y = clamp(
                    centers[index].y,
                    minYPadding + radius,
                    canvasHeight - minYPadding - radius
                )
            }
        }

        return zip(bubbles, centers).map { bubble, center in
            BingoDiaryBubble(
                id: bubble.id,
                task: bubble.task,
                count: bubble.count,
                diameter: bubble.diameter,
                position: center,
                gradientStart: bubble.gradientStart,
                gradientEnd: bubble.gradientEnd,
                motionFactor: bubble.motionFactor
            )
        }
    }

    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }
}

private final class BingoDiaryGravityMonitor: ObservableObject {
    @Published var offset: CGSize = .zero

    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()
    private var referenceTilt: CGSize?

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        guard !motionManager.isDeviceMotionActive else { return }
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        referenceTilt = nil
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            let userAcceleration = motion?.userAcceleration
            let accelX = CGFloat(userAcceleration?.x ?? 0)
            let accelY = CGFloat(userAcceleration?.y ?? 0)

            // 以当前拿起手机的姿态作为“零重力位”，避免默认持续下坠。
            let currentTilt = CGSize(width: CGFloat(gravity.x), height: CGFloat(-gravity.y))
            if self.referenceTilt == nil {
                self.referenceTilt = currentTilt
            } else if abs(accelX) < 0.035 && abs(accelY) < 0.035 {
                // 慢速重基线：消除静置状态下的长期偏航，防止圆群持续单向漂移。
                let old = self.referenceTilt ?? .zero
                self.referenceTilt = CGSize(
                    width: old.width * 0.985 + currentTilt.width * 0.015,
                    height: old.height * 0.985 + currentTilt.height * 0.015
                )
            }
            let reference = self.referenceTilt ?? .zero

            // 归一化输入：相对倾斜 + 抖动冲量，范围控制在可模拟区间。
            var tiltX = (currentTilt.width - reference.width) * 3.4
            var tiltY = (currentTilt.height - reference.height) * 3.4
            if abs(tiltX) < 0.04 { tiltX = 0 }
            if abs(tiltY) < 0.04 { tiltY = 0 }
            let jerkX = accelX * 2.8
            let jerkY = CGFloat(-accelY) * 2.8
            let rawX = max(min(tiltX + jerkX, 2.35), -2.35)
            let rawY = max(min(tiltY + jerkY, 2.35), -2.35)
            DispatchQueue.main.async {
                // 保留足够响应性，避免重力信号被过度抹平。
                self.offset = CGSize(
                    width: self.offset.width * 0.10 + rawX * 0.90,
                    height: self.offset.height * 0.10 + rawY * 0.90
                )
            }
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        referenceTilt = nil
        offset = .zero
    }
}

private struct BingoDiaryStatsListSheet: View {
    let title: String
    let completedStats: [BingoDiaryTaskCount]
    let timeoutStats: [BingoDiaryTaskCount]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: scaled(20, pad: 24)) {
                    diaryListSection(
                        title: L10n.tr("Completed tasks", zhHans: "完成任务", zhHant: "完成任務"),
                        items: completedStats
                    )

                    diaryListSection(
                        title: L10n.tr("Expired tasks", zhHans: "超时任务", zhHant: "超時任務"),
                        items: timeoutStats
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, scaled(20, pad: 26))
                .padding(.vertical, scaled(20, pad: 26))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(NeumorphicColors.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(NeumorphicColors.accent)
                }
            }
        }
    }

    private func diaryListSection(title: String, items: [BingoDiaryTaskCount]) -> some View {
        VStack(alignment: .leading, spacing: scaled(12, pad: 14)) {
            Text(title)
                .font(.appSystem(size: scaled(17, pad: 19), weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "2B1A0D"))

            if items.isEmpty {
                Text(L10n.tr("None", zhHans: "暂无", zhHant: "暫無"))
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "8A8179"))
            } else {
                VStack(spacing: scaled(10, pad: 12)) {
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            Text(item.task)
                                .font(.appSystem(size: scaled(15, pad: 17), weight: .semibold, design: .rounded))
                                .foregroundColor(Color(hex: "2B1A0D"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)

                            Text("\(item.count)")
                                .font(.appSystem(size: scaled(15, pad: 17), weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "8A8179"))
                        }
                        .padding(.horizontal, scaled(16, pad: 18))
                        .padding(.vertical, scaled(14, pad: 16))
                        .background(
                            RoundedRectangle(cornerRadius: scaled(18, pad: 20), style: .continuous)
                                .fill(Color.white.opacity(0.92))
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BingoDiaryTaskDetailView: View {
    let task: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    private var pageTitle: String {
        L10n.tr("Task Details", zhHans: "任务详情", zhHant: "任務詳情")
    }

    private var totalCompletionsTitle: String {
        L10n.tr("Total Completions", zhHans: "总完成次数", zhHant: "總完成次數")
    }

    private var thisWeekTitle: String {
        L10n.tr("This Week", zhHans: "本周完成", zhHant: "本週完成")
    }

    private var recentActivityTitle: String {
        L10n.tr("Recent Activity", zhHans: "近期记录", zhHant: "近期記錄")
    }

    private var noActivityTitle: String {
        L10n.tr("No activity yet", zhHans: "暂无记录", zhHant: "暫無記錄")
    }

    private var normalizedTask: String {
        task.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activityRows: [(date: Date, count: Int)] {
        BingoDiaryStore.taskDailyCompletions(task: normalizedTask, limit: 30)
    }

    private var totalCompletions: Int {
        activityRows.reduce(0) { $0 + $1.count }
    }

    private var thisWeekCompletions: Int {
        BingoDiaryStore.taskCompletionsThisWeek(task: normalizedTask)
    }

    var body: some View {
        ZStack(alignment: .top) {
            NeumorphicColors.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: scaled(18, pad: 22)) {
                    VStack(alignment: .leading, spacing: scaled(2, pad: 4)) {
                        Text(normalizedTask.isEmpty ? pageTitle : normalizedTask)
                            .font(.appSystem(size: scaled(24, pad: 30), weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: "121A2B"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }

                    HStack(spacing: 0) {
                        metricColumn(
                            title: totalCompletionsTitle,
                            value: totalCompletions,
                            valueColor: Color(hex: "C5915E")
                        )

                        metricColumn(
                            title: thisWeekTitle,
                            value: thisWeekCompletions,
                            valueColor: Color(hex: "121A2B")
                        )
                    }
                    .padding(.vertical, scaled(20, pad: 24))
                    .background(
                        RoundedRectangle(cornerRadius: scaled(18, pad: 22), style: .continuous)
                            .fill(Color.white.opacity(0.92))
                    )

                    Text(recentActivityTitle)
                        .font(.appSystem(size: scaled(19, pad: 24), weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "121A2B"))

                    if activityRows.isEmpty {
                        RoundedRectangle(cornerRadius: scaled(18, pad: 22), style: .continuous)
                            .fill(Color.white.opacity(0.9))
                            .frame(height: scaled(108, pad: 126))
                            .overlay(
                                Text(noActivityTitle)
                                    .font(.appSystem(size: scaled(15, pad: 18), weight: .semibold, design: .rounded))
                                    .foregroundColor(Color(hex: "6C7889"))
                            )
                    } else {
                        VStack(spacing: scaled(12, pad: 14)) {
                            ForEach(activityRows, id: \.date) { row in
                                activityRow(date: row.date, count: row.count)
                            }
                        }
                    }
                }
                .padding(.horizontal, scaled(20, pad: 26))
                .padding(.top, scaled(12, pad: 18))
                .padding(.bottom, scaled(34, pad: 44))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            topBar
                .background(NeumorphicColors.background.opacity(0.96))
        }
    }

    private var topBar: some View {
        ZStack {
            Text(pageTitle)
                .font(.appSystem(size: scaled(20, pad: 24), weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "2B1A0D"))

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.appSystem(size: scaled(18, pad: 20), weight: .semibold))
                        .foregroundColor(Color(hex: "2B1A0D"))
                        .frame(width: scaled(40, pad: 44), height: scaled(40, pad: 44))
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.horizontal, scaled(12, pad: 20))
        .padding(.top, scaled(6, pad: 10))
        .padding(.bottom, scaled(4, pad: 8))
    }

    private func metricColumn(title: String, value: Int, valueColor: Color) -> some View {
        VStack(spacing: scaled(6, pad: 8)) {
            Text(title)
                .font(.appSystem(size: scaled(15, pad: 18), weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "4B5A6C"))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text("\(value)")
                .font(.appSystem(size: scaled(28, pad: 34), weight: .bold, design: .rounded))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }

    private func activityRow(date: Date, count: Int) -> some View {
        HStack(spacing: scaled(12, pad: 16)) {
            VStack(alignment: .leading, spacing: scaled(4, pad: 6)) {
                Text(activityDateText(from: date))
                    .font(.appSystem(size: scaled(16, pad: 20), weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "121A2B"))

                Text(activityCountText(count))
                    .font(.appSystem(size: scaled(14, pad: 17), weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "4B5A6C"))
            }

            Spacer(minLength: scaled(8, pad: 10))

            ZStack {
                Circle()
                    .fill(Color(hex: "C9DAE8"))
                Text("\(count)")
                    .font(.appSystem(size: scaled(14, pad: 18), weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(width: scaled(60, pad: 68), height: scaled(60, pad: 68))
        }
        .padding(.horizontal, scaled(16, pad: 20))
        .padding(.vertical, scaled(14, pad: 16))
        .background(
            RoundedRectangle(cornerRadius: scaled(18, pad: 22), style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
    }

    private func activityDateText(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        return formatter.string(from: date)
    }

    private func activityCountText(_ count: Int) -> String {
        let lang = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if lang.hasPrefix("zh-hans") || lang.hasPrefix("zh-cn") || lang == "zh" {
            return "完成 \(count) 次"
        }
        if lang.hasPrefix("zh-hant") || lang.hasPrefix("zh-tw") || lang.hasPrefix("zh-hk") {
            return "完成 \(count) 次"
        }
        return count == 1 ? "Completed 1 time" : "Completed \(count) times"
    }
}

private struct BingoDiaryDetailView: View {
    let entry: BingoDiaryEntry
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NeumorphicColors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    BingoDiaryBoardView(board: entry.board)
                        .frame(maxWidth: isPadLayout ? 720 : .infinity)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)

                    Spacer()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NeumorphicColors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.done) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(NeumorphicColors.accent)
                }

                ToolbarItem(placement: .principal) {
                    Text(detailTitle)
                        .font(.appSystem(size: scaled(17, pad: 20), weight: .semibold, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                }
            }
        }
    }

    private var detailTitle: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.displayLocale
        formatter.dateStyle = .long
        return formatter.string(from: entry.date)
    }
}

private struct BingoDiaryBoardView: View {
    let board: SavedBoard

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 6
            let totalSpacing = spacing * CGFloat(max(board.gridSize - 1, 0))
            let cellSize = (geo.size.width - 24 - totalSpacing) / CGFloat(max(board.gridSize, 1))

            VStack(spacing: spacing) {
                ForEach(0..<board.gridSize, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<board.gridSize, id: \.self) { col in
                            if row < board.cells.count && col < board.cells[row].count {
                                BingoDiaryCellView(
                                    cell: board.cells[row][col],
                                    isInBingoLine: isInCompletedLine(row: row, col: col),
                                    isLocked: isLocked(row: row, col: col),
                                    cellSize: cellSize
                                )
                            }
                        }
                    }
                }
            }
            .padding(8)
            .padding(12)
            .neumorphicConvex(radius: 20)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func isInCompletedLine(row: Int, col: Int) -> Bool {
        for line in board.completedLines {
            switch line {
            case .row(let r): if r == row { return true }
            case .column(let c): if c == col { return true }
            case .diagonalMain: if row == col { return true }
            case .diagonalAnti: if row + col == board.gridSize - 1 { return true }
            }
        }
        return false
    }

    private func isLocked(row: Int, col: Int) -> Bool {
        let activeForced = activeForcedPositions
        guard !activeForced.isEmpty else { return false }
        return !activeForced.contains(DiaryPosition(row: row, col: col))
    }

    private var activeForcedPositions: Set<DiaryPosition> {
        var positions: Set<DiaryPosition> = []

        for row in board.cells.indices {
            for col in board.cells[row].indices {
                let cell = board.cells[row][col]
                if cell.isForced && !cell.isCompleted && !cell.isEmpty {
                    positions.insert(DiaryPosition(row: row, col: col))
                }
            }
        }

        return positions
    }

    private struct DiaryPosition: Hashable {
        let row: Int
        let col: Int
    }
}

private struct BingoDiaryCellView: View {
    let cell: BingoCell
    let isInBingoLine: Bool
    let isLocked: Bool
    let cellSize: CGFloat

    @AppStorage(AppSettings.themeKey) private var themeRawValue = AppTheme.concise.rawValue
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var activeTheme: AppTheme { AppTheme(rawValue: themeRawValue) ?? .concise }
    private var bingoSurfaceColor: Color { activeTheme.bingoSurfaceColor }
    private var bingoSurfaceShadowColor: Color { activeTheme.bingoSurfaceShadowColor }
    private var isPadLayout: Bool { horizontalSizeClass == .regular }

    var body: some View {
        ZStack {
            backgroundSurface

            if isInBingoLine {
                bingoLineContent
            } else if !cell.isEmpty {
                VStack(spacing: 2) {
                    Text(cell.text)
                        .font(.appSystem(size: dynamicFontSize, weight: .medium))
                        .foregroundColor(isLocked ? NeumorphicColors.text.opacity(0.35) : NeumorphicColors.text)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.5)
                        .padding(8)

                    if cell.isCompleted && !isLocked {
                        completionIcon(isLarge: false)
                    }
                }
            }

            if isLocked {
                lockOverlay
            }
        }
        .frame(width: cellSize, height: cellSize)
    }

    private var dynamicFontSize: CGFloat {
        let maxBaseSize: CGFloat = isPadLayout ? 22.0 : 16.0
        let minimumSize: CGFloat = isPadLayout ? 11.0 : 9.0
        let baseSize = min(cellSize * (isPadLayout ? 0.24 : 0.22), maxBaseSize)
        return cell.text.count > 6 ? max(baseSize * (isPadLayout ? 0.84 : 0.8), minimumSize) : baseSize
    }

    private var bingoLineContent: some View {
        VStack(spacing: 4) {
            Text(cell.text)
                .font(.appSystem(size: dynamicFontSize, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            if !isLocked {
                completionIcon(isLarge: false, usesGoldSurface: true)
            }
        }
    }

    private var backgroundSurface: some View {
        Group {
            if isInBingoLine {
                RoundedRectangle(cornerRadius: 12)
                    .fill(bingoSurfaceColor)
                    .shadow(color: bingoSurfaceShadowColor.opacity(0.28), radius: 7, x: 4, y: 4)
                    .shadow(color: Color.white.opacity(0.42), radius: 7, x: -4, y: -4)
            } else if cell.isCompleted {
                Color.clear
                    .neumorphicConcave(radius: 12)
            } else {
                Color.clear
                    .neumorphicConvex(radius: 12)
            }
        }
        .overlay {
            if isLocked && !isInBingoLine {
                RoundedRectangle(cornerRadius: 12)
                    .fill(NeumorphicColors.background.opacity(0.62))
            }
        }
    }

    private func completionIcon(isLarge: Bool, usesGoldSurface: Bool = false) -> some View {
        let size = isLarge
            ? min(max(cellSize * 0.42, 34), 52)
            : min(max(cellSize * 0.16, 16), 22)

        return ZStack {
            Circle()
                .fill(isLarge || usesGoldSurface ? bingoSurfaceColor : NeumorphicColors.background)
                .shadow(
                    color: ((isLarge || usesGoldSurface) ? bingoSurfaceShadowColor : NeumorphicColors.darkShadow).opacity(0.3),
                    radius: isLarge ? 6 : 4,
                    x: isLarge ? 4 : 3,
                    y: isLarge ? 4 : 3
                )
                .shadow(
                    color: ((isLarge || usesGoldSurface) ? Color.white : NeumorphicColors.lightShadow).opacity(0.85),
                    radius: isLarge ? 6 : 4,
                    x: isLarge ? -4 : -3,
                    y: isLarge ? -4 : -3
                )

            Image(systemName: "checkmark")
                .font(.appSystem(size: size * 0.42, weight: .bold))
                .foregroundColor((isLarge || usesGoldSurface) ? .white : activeTheme.color)
        }
        .frame(width: size, height: size)
        .padding(.top, isLarge ? 0 : 6)
    }

    private var lockOverlay: some View {
        let size = min(max(cellSize * 0.22, 20), 28)

        return ZStack {
            Circle()
                .fill(NeumorphicColors.background)
                .shadow(color: NeumorphicColors.darkShadow.opacity(0.25), radius: 4, x: 2, y: 2)
                .shadow(color: NeumorphicColors.lightShadow.opacity(0.85), radius: 4, x: -2, y: -2)

            Image(systemName: "lock.fill")
                .font(.appSystem(size: size * 0.42, weight: .bold))
                .foregroundColor(NeumorphicColors.text.opacity(0.55))
        }
        .frame(width: size, height: size)
    }
}

private struct SidebarGlassToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.interpolatingSpring(stiffness: 210, damping: 18)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? NeumorphicColors.accent.opacity(0.78) : Color.white.opacity(0.18))
                    .frame(width: 42, height: 24)
                    .overlay {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(configuration.isOn ? 0.22 : 0.12),
                                        Color.white.opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.34), lineWidth: 0.8)
                    }
                    .shadow(color: NeumorphicColors.darkShadow.opacity(0.12), radius: 4, x: 1, y: 1)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.9), Color.white.opacity(0.68)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 18, height: 18)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.58), lineWidth: 0.6)
                    }
                    .shadow(color: NeumorphicColors.darkShadow.opacity(0.14), radius: 4, x: 1.5, y: 1.5)
                    .shadow(color: Color.white.opacity(0.28), radius: 1.5, x: -0.8, y: -0.8)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct BoardCountdownSheet: View {
    let countdownEndsAt: Date?
    let onSave: (Int?) -> Void
    let onCancel: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isCountdownEnabled: Bool
    @State private var countdownHours: Int
    @State private var countdownMinutes: Int
    @State private var isCancelCountdownConfirmationPresented = false

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var hasExistingCountdown: Bool {
        guard let countdownEndsAt else { return false }
        return countdownEndsAt > Date()
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    init(countdownEndsAt: Date?, onSave: @escaping (Int?) -> Void, onCancel: @escaping () -> Void) {
        let countdownTotalMinutes = Self.remainingMinutes(until: countdownEndsAt)
        self.countdownEndsAt = countdownEndsAt
        self.onSave = onSave
        self.onCancel = onCancel

        let (initialHours, initialMinutes) = Self.makeWheelValues(from: countdownTotalMinutes ?? 1)
        _isCountdownEnabled = State(initialValue: countdownTotalMinutes != nil)
        _countdownHours = State(initialValue: initialHours)
        _countdownMinutes = State(initialValue: initialMinutes)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NeumorphicColors.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Button(L10n.cancel) {
                            onCancel()
                        }
                        .buttonStyle(.plain)
                        .font(.appSystem(size: scaled(17, pad: 19), weight: .regular, design: .rounded))
                        .foregroundColor(NeumorphicColors.text.opacity(0.8))

                        Spacer()

                        Button(L10n.save) {
                            onSave(resolvedTotalMinutes)
                        }
                        .buttonStyle(.plain)
                        .font(.appSystem(size: scaled(17, pad: 19), weight: .semibold, design: .rounded))
                        .foregroundColor(NeumorphicColors.accent)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.boardCountdownTitle)
                                    .font(.appSystem(size: scaled(17, pad: 20), weight: .bold, design: .rounded))
                                    .foregroundColor(NeumorphicColors.text)
                            }

                            Spacer()

                            Toggle("", isOn: $isCountdownEnabled)
                                .labelsHidden()
                                .toggleStyle(NeumorphicSwitchToggleStyle())
                        }

                        if isCountdownEnabled {
                            HStack(spacing: 12) {
                                countdownWheelPicker(
                                    selection: $countdownHours,
                                    values: Array(0...24),
                                    unit: L10n.hours,
                                    formatter: { L10n.hourValue($0) }
                                )

                                countdownWheelPicker(
                                    selection: $countdownMinutes,
                                    values: Array(1...60),
                                    unit: L10n.minutes,
                                    formatter: { L10n.minuteValue($0) }
                                )
                            }

                            Text(countdownSummaryText)
                                .font(.appSystem(size: scaled(12, pad: 14), design: .rounded))
                                .foregroundColor(NeumorphicColors.text.opacity(0.62))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                        }

                        if hasExistingCountdown {
                            Button {
                                isCancelCountdownConfirmationPresented = true
                            } label: {
                                Text(L10n.tr("Cancel countdown", zhHans: "取消倒计时", zhHant: "取消倒計時"))
                                    .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                                    .foregroundColor(NeumorphicColors.text.opacity(0.82))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: scaled(42, pad: 48))
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(NeumorphicColors.background.opacity(0.94))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .stroke(NeumorphicColors.accent.opacity(0.58), lineWidth: 1)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }

                    Spacer()
                }
                .frame(maxWidth: isPadLayout ? 560 : .infinity, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(24)
            }
            .alert(
                L10n.tr("Cancel countdown?", zhHans: "取消倒计时？", zhHant: "取消倒計時？"),
                isPresented: $isCancelCountdownConfirmationPresented
            ) {
                Button(L10n.cancel, role: .cancel) {}
                Button(L10n.tr("Confirm", zhHans: "确认", zhHant: "確認"), role: .destructive) {
                    onSave(nil)
                }
            } message: {
                Text(
                    L10n.tr(
                        "After canceling, the board countdown will stop immediately.",
                        zhHans: "取消后，面板倒计时会立即停止。",
                        zhHant: "取消後，面板倒計時會立即停止。"
                    )
                )
            }
        }
    }

    private var totalMinutes: Int {
        min((countdownHours * 60) + countdownMinutes, BingoViewModel.maxCountdownMinutes)
    }

    private var resolvedTotalMinutes: Int? {
        guard isCountdownEnabled else { return nil }
        return totalMinutes
    }

    private var countdownSummaryText: String {
        let summaryHours = totalMinutes / 60
        let summaryMinutes = totalMinutes % 60
        return L10n.boardWillClearIn(hours: summaryHours, minutes: summaryMinutes)
    }

    private func countdownWheelPicker(
        selection: Binding<Int>,
        values: [Int],
        unit: String,
        formatter: @escaping (Int) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(unit)
                .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            Picker(unit, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text(formatter(value))
                        .foregroundColor(NeumorphicColors.text)
                        .tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.wheel)
            .tint(NeumorphicColors.text)
            .frame(height: isPadLayout ? 138 : 126)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(NeumorphicColors.background.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(NeumorphicColors.accent.opacity(0.58), lineWidth: 1)
                )
        )
    }

    private static func remainingMinutes(until date: Date?) -> Int? {
        guard let date, date > Date() else { return nil }
        let seconds = date.timeIntervalSinceNow
        let totalMinutes = Int(ceil(seconds / 60))
        return min(max(totalMinutes, 1), BingoViewModel.maxCountdownMinutes)
    }

    private static func makeWheelValues(from totalMinutes: Int) -> (Int, Int) {
        let clamped = min(max(totalMinutes, 1), BingoViewModel.maxCountdownMinutes)
        if clamped <= 60 {
            return (0, clamped)
        }

        let quotient = clamped / 60
        let remainder = clamped % 60
        if remainder == 0 {
            return (max(quotient - 1, 0), 60)
        }
        return (quotient, remainder)
    }
}

private struct BoardRulesSheet: View {
    let countdownEndsAt: Date?
    let initialResetMode: BoardTaskResetMode
    let onSave: (Int?, BoardTaskResetMode) -> Void
    let onCancel: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isCountdownEnabled: Bool
    @State private var countdownHours: Int
    @State private var countdownMinutes: Int
    @State private var selectedResetMode: BoardTaskResetMode

    private var isPadLayout: Bool {
        horizontalSizeClass == .regular
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

    init(
        countdownEndsAt: Date?,
        initialResetMode: BoardTaskResetMode,
        onSave: @escaping (Int?, BoardTaskResetMode) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let countdownTotalMinutes = Self.remainingMinutes(until: countdownEndsAt)
        let (initialHours, initialMinutes) = Self.makeWheelValues(from: countdownTotalMinutes ?? 1)

        self.countdownEndsAt = countdownEndsAt
        self.initialResetMode = initialResetMode
        self.onSave = onSave
        self.onCancel = onCancel

        _isCountdownEnabled = State(initialValue: countdownTotalMinutes != nil)
        _countdownHours = State(initialValue: initialHours)
        _countdownMinutes = State(initialValue: initialMinutes)
        _selectedResetMode = State(initialValue: initialResetMode)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NeumorphicColors.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.tr("Board Countdown", zhHans: "面板倒计时", zhHant: "面板倒計時"))
                                .font(.appSystem(size: scaled(17, pad: 20), weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)

                            HStack(spacing: 12) {
                                Text(L10n.tr("Enable countdown", zhHans: "开启倒计时", zhHant: "開啟倒計時"))
                                    .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                                    .foregroundColor(NeumorphicColors.text)
                                Spacer()
                                Toggle("", isOn: $isCountdownEnabled)
                                    .labelsHidden()
                                    .toggleStyle(NeumorphicSwitchToggleStyle())
                            }

                            if isCountdownEnabled {
                                HStack(spacing: 12) {
                                    countdownWheelPicker(
                                        selection: $countdownHours,
                                        values: Array(0...24),
                                        unit: L10n.hours,
                                        formatter: { L10n.hourValue($0) }
                                    )

                                    countdownWheelPicker(
                                        selection: $countdownMinutes,
                                        values: Array(1...60),
                                        unit: L10n.minutes,
                                        formatter: { L10n.minuteValue($0) }
                                    )
                                }

                                Text(countdownSummaryText)
                                    .font(.appSystem(size: scaled(12, pad: 14), design: .rounded))
                                    .foregroundColor(NeumorphicColors.text.opacity(0.62))
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .multilineTextAlignment(.center)
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.tr("Board task reset mode", zhHans: "面板任务重置方式", zhHant: "面板任務重置方式"))
                                .font(.appSystem(size: scaled(17, pad: 20), weight: .bold, design: .rounded))
                                .foregroundColor(NeumorphicColors.text)

                            resetOptionRow(
                                mode: .resetStatusNextDay,
                                title: L10n.tr("Auto reset task status every other day", zhHans: "隔天自动重置任务状态", zhHant: "隔天自動重置任務狀態"),
                                hint: L10n.tr("Task status will reset to incomplete on the next day.", zhHans: "将在第二天自动将任务状态重置为未完成", zhHant: "將在第二天自動將任務狀態重置為未完成")
                            )

                            resetOptionRow(
                                mode: .clearTasksNextDay,
                                title: L10n.tr("Auto clear all tiles every other day", zhHans: "隔天自动清空格子任务", zhHant: "隔天自動清空格子任務"),
                                hint: L10n.tr("All tile tasks will be cleared on the next day.", zhHans: "将在第二天自动清空所有格子任务", zhHant: "將在第二天自動清空所有格子任務")
                            )
                        }
                    }
                    .frame(maxWidth: isPadLayout ? 560 : .infinity, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(24)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(L10n.tr("Board Rules", zhHans: "面板规则", zhHant: "面板規則"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NeumorphicColors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { onCancel() }
                        .foregroundColor(NeumorphicColors.text.opacity(0.8))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.save) {
                        onSave(resolvedTotalMinutes, selectedResetMode)
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(NeumorphicColors.accent)
                }
            }
        }
    }

    private func resetOptionRow(mode: BoardTaskResetMode, title: String, hint: String) -> some View {
        let isSelected = selectedResetMode == mode
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                selectedResetMode = mode
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.appSystem(size: scaled(16, pad: 18), weight: .semibold))
                        .foregroundColor(isSelected ? NeumorphicColors.accent : NeumorphicColors.text.opacity(0.45))

                    Text(title)
                        .font(.appSystem(size: scaled(14, pad: 16), weight: .medium, design: .rounded))
                        .foregroundColor(NeumorphicColors.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isSelected {
                Text(hint)
                    .font(.appSystem(size: scaled(12, pad: 14), weight: .regular, design: .rounded))
                    .foregroundColor(NeumorphicColors.text.opacity(0.62))
                    .padding(.leading, 28)
            }
        }
    }

    private var totalMinutes: Int {
        min((countdownHours * 60) + countdownMinutes, BingoViewModel.maxCountdownMinutes)
    }

    private var resolvedTotalMinutes: Int? {
        guard isCountdownEnabled else { return nil }
        return totalMinutes
    }

    private var countdownSummaryText: String {
        let summaryHours = totalMinutes / 60
        let summaryMinutes = totalMinutes % 60
        return L10n.boardWillClearIn(hours: summaryHours, minutes: summaryMinutes)
    }

    private func countdownWheelPicker(
        selection: Binding<Int>,
        values: [Int],
        unit: String,
        formatter: @escaping (Int) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(unit)
                .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                .foregroundColor(NeumorphicColors.text)

            Picker(unit, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text(formatter(value))
                        .foregroundColor(NeumorphicColors.text)
                        .tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.wheel)
            .tint(NeumorphicColors.text)
            .frame(height: isPadLayout ? 138 : 126)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(NeumorphicColors.background.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(NeumorphicColors.accent.opacity(0.58), lineWidth: 1)
                )
        )
    }

    private static func remainingMinutes(until date: Date?) -> Int? {
        guard let date, date > Date() else { return nil }
        let seconds = date.timeIntervalSinceNow
        let totalMinutes = Int(ceil(seconds / 60))
        return min(max(totalMinutes, 1), BingoViewModel.maxCountdownMinutes)
    }

    private static func makeWheelValues(from totalMinutes: Int) -> (Int, Int) {
        let clamped = min(max(totalMinutes, 1), BingoViewModel.maxCountdownMinutes)
        if clamped <= 60 {
            return (0, clamped)
        }

        let quotient = clamped / 60
        let remainder = clamped % 60
        if remainder == 0 {
            return (max(quotient - 1, 0), 60)
        }
        return (quotient, remainder)
    }
}

}

struct BoardTemplateShareComposerView: View {
    let template: BoardTemplatePayload

    @Environment(\.dismiss) private var dismiss
    @State private var titleDraft: String
    @State private var actionMessage: String?
    @State private var actionMessageToken = UUID()
    private let overallVerticalShift: CGFloat = 30
    private let backButtonExtraDownShift: CGFloat = 20

    init(template: BoardTemplatePayload) {
        self.template = template
        _titleDraft = State(initialValue: template.normalizedTitle)
    }

    private var composedTemplate: BoardTemplatePayload {
        var updated = template
        updated.title = String(titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
        return updated
    }

    private var qrCodeImage: UIImage? {
        let urlString = composedTemplate.qrCodeURL.absoluteString
        return BoardTemplateQRCodeGenerator.makeImage(from: urlString, size: 360)
    }

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(348.0, max(geo.size.width - 42.0, 300))
            let cardScale = cardWidth / 348.0

            ZStack {
                Image("BlackBG")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.appSystem(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text(L10n.templateShareSheetTitle)
                            .font(.appSystem(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer()

                        Color.clear
                            .frame(width: 32, height: 32)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 2 + backButtonExtraDownShift)

                    Spacer(minLength: 0)

                    VStack(spacing: 0) {
                        ZStack(alignment: .topTrailing) {
                            TemplateShareFigmaCardView(
                                template: composedTemplate,
                                qrCodeImage: qrCodeImage,
                                cardWidth: cardWidth,
                                isTitleEditable: true,
                                editableTitle: $titleDraft
                            )

                            Image("TemplateShareBear")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 132 * cardScale, height: 122 * cardScale)
                                .offset(x: -4, y: -52 * cardScale)
                        }
                        .frame(width: cardWidth + 24, height: cardWidth + 235 * cardScale)
                        .padding(.horizontal, 12)

                        HStack(spacing: 12) {
                            TemplateShareFigmaActionButton(
                                title: L10n.templateShareSaveImage,
                                systemName: "square.and.arrow.down",
                                action: {
                                    saveShareImageToPhotoLibrary()
                                }
                            )
                        }
                        .padding(.horizontal, 24)
                    }
                    .offset(y: 0)

                    Spacer(minLength: 14)

                    Spacer(minLength: max(10, geo.safeAreaInsets.bottom > 0 ? geo.safeAreaInsets.bottom - 6 : 16))
                }
                .padding(.top, overallVerticalShift)
            }
            .ignoresSafeArea(.container, edges: .top)
            .overlay(alignment: .bottom) {
                if let actionMessage {
                    Text(actionMessage)
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.45))
                        )
                        .padding(.bottom, max(geo.safeAreaInsets.bottom, 16) + 28)
                        .id(actionMessageToken)
                }
            }
            .onChange(of: titleDraft) { _, newValue in
                if newValue.count > 20 {
                    titleDraft = String(newValue.prefix(20))
                }
            }
        }
    }

    @MainActor
    private func saveShareImageToPhotoLibrary() {
        let preparedTemplate = composedTemplate
        guard let image = renderedShareImage(for: preparedTemplate) else {
            showActionMessage(L10n.templateShareImageSaveFailed)
            return
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    showActionMessage(L10n.templateShareImageSaveDenied)
                }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { saved, _ in
                Task { @MainActor in
                    showActionMessage(saved ? L10n.templateShareImageSaved : L10n.templateShareImageSaveFailed)
                }
            }
        }
    }

    @MainActor
    private func renderedShareImage(for template: BoardTemplatePayload) -> UIImage? {
        BoardTemplateShareRenderer.renderCard(for: template)
    }

    @MainActor
    private func showActionMessage(_ message: String) {
        let token = UUID()
        actionMessage = message
        actionMessageToken = token
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run {
                guard actionMessageToken == token else { return }
                actionMessage = nil
            }
        }
    }
}

private struct TemplateShareFigmaActionButton: View {
    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(.appSystem(size: 17, weight: .semibold))
                Text(title)
                    .font(.appSystem(size: 16, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "C39060"), Color(hex: "D3A375")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TemplateShareFigmaBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                watermarkColumn(in: geo.size, xOffset: -52)
                watermarkColumn(in: geo.size, xOffset: geo.size.width - 52)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func watermarkColumn(in size: CGSize, xOffset: CGFloat) -> some View {
        ForEach(0..<5, id: \.self) { index in
            Text("BINGODAYS")
                .font(.custom("Outfit", size: 62))
                .fontWeight(.heavy)
                .foregroundColor(.white.opacity(max(0.04, 0.22 - (Double(index) * 0.04))))
                .rotationEffect(.degrees(10.25))
                .offset(
                    x: xOffset,
                    y: -70 + CGFloat(index) * 52
                )
        }
    }
}

private struct TemplateShareFigmaCardView: View {
    let template: BoardTemplatePayload
    let qrCodeImage: UIImage?
    let cardWidth: CGFloat
    let isTitleEditable: Bool
    @Binding var editableTitle: String

    @FocusState private var isTitleFieldFocused: Bool
    @State private var isEditingTitle = false

    private var titleText: String {
        let source = isTitleEditable ? editableTitle : template.normalizedTitle
        let normalized = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? L10n.templateShareNamePlaceholder : String(normalized.prefix(20))
    }

    private var scale: CGFloat {
        cardWidth / 348.0
    }

    private var cardHeight: CGFloat {
        cardWidth * (828.0 / 562.0)
    }

    var body: some View {
        let gridFrameWidth = cardWidth - (50 * scale)

        VStack(alignment: .leading, spacing: 14 * scale) {
            if isTitleEditable && isEditingTitle {
                TextField(L10n.templateShareNamePlaceholder, text: $editableTitle)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .font(.appSystem(size: 24 * scale, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "3F270F"))
                    .focused($isTitleFieldFocused)
                    .padding(.leading, 20 * scale)
                    .onSubmit {
                        isEditingTitle = false
                    }
            } else {
                Text(titleText)
                    .font(.appSystem(size: 24 * scale, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "3F270F"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.leading, 20 * scale)
                    .onTapGesture(count: 2) {
                        guard isTitleEditable else { return }
                        isEditingTitle = true
                        DispatchQueue.main.async {
                            isTitleFieldFocused = true
                        }
                    }
            }

            BoardTemplateGridPreview(
                template: template,
                tileBackground: Color(hex: "E7D5C4"),
                textColor: Color(hex: "3F270F"),
                isPreview: true,
                previewTextSize: 18 * scale
            )
            .frame(width: gridFrameWidth)
            .aspectRatio(1, contentMode: .fit)
            .offset(x: 10 * scale, y: 15 * scale)

            HStack(alignment: .top, spacing: 12 * scale) {
                Group {
                    if let qrCodeImage {
                        Image(uiImage: qrCodeImage)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
                            .fill(Color(hex: "E7D5C4"))
                    }
                }
                .frame(width: 82 * scale, height: 82 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous))

                Text(L10n.templateShareFooterSubtitle)
                    .font(.appSystem(size: 14 * scale, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "8A5F34"))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6 * scale)
                    .offset(y: 1 * scale)
            }
            .frame(width: gridFrameWidth, alignment: .leading)
            .offset(x: 10 * scale, y: 20 * scale)
        }
        .padding(.top, 18 * scale)
        .padding(.horizontal, 14 * scale)
        .padding(.bottom, 16 * scale)
        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
        .background(
            Image("ShareTemplateCardBG")
                .resizable()
                .renderingMode(.original)
                .frame(width: cardWidth, height: cardHeight)
        )
        .onChange(of: isTitleFieldFocused) { _, focused in
            if !focused {
                isEditingTitle = false
            }
        }
        .onChange(of: editableTitle) { _, newValue in
            if newValue.count > 20 {
                editableTitle = String(newValue.prefix(20))
            }
        }
    }
}

struct BoardTemplateImportPreviewView: View {
    let template: BoardTemplatePayload
    let createsNewBoard: Bool
    let onImport: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                BoardTemplateShareCardView(
                    template: template,
                    qrCodeImage: nil,
                    isPreview: true,
                    showsFooterCopy: false
                )

                if !createsNewBoard {
                    Text(L10n.templateImportFreePlanHint)
                        .font(.appSystem(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(NeumorphicColors.text.opacity(0.58))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(NeumorphicColors.background)
            .navigationTitle(L10n.templateImportTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { onClose() }
                        .foregroundColor(NeumorphicColors.text.opacity(0.8))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.templateImportAction) {
                        onImport()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(NeumorphicColors.accent)
                }
            }
        }
    }
}

struct BoardTemplateShareCardView: View {
    let template: BoardTemplatePayload
    let qrCodeImage: UIImage?
    let isPreview: Bool
    let isTitleEditable: Bool
    let showsFooterCopy: Bool
    @Binding var editableTitle: String

    @FocusState private var isTitleFieldFocused: Bool
    @State private var isEditingTitle = false

    private var cardBackground: Color { Color(hex: "F5EDE4") }
    private var tileBackground: Color { Color(hex: "FFF9F2") }
    private var previewWidth: CGFloat { isPreview ? 340 : 1080 }
    private var previewPadding: CGFloat { isPreview ? 18 : 56 }
    private var titleText: String {
        let source = isTitleEditable ? editableTitle : template.normalizedTitle
        let normalized = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? L10n.templateShareNamePlaceholder : String(normalized.prefix(20))
    }

    init(
        template: BoardTemplatePayload,
        qrCodeImage: UIImage?,
        isPreview: Bool,
        isTitleEditable: Bool = false,
        showsFooterCopy: Bool = true,
        editableTitle: Binding<String> = .constant("")
    ) {
        self.template = template
        self.qrCodeImage = qrCodeImage
        self.isPreview = isPreview
        self.isTitleEditable = isTitleEditable
        self.showsFooterCopy = showsFooterCopy
        _editableTitle = editableTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isPreview ? 16 : 36) {
            VStack(alignment: .leading, spacing: isPreview ? 8 : 18) {
                if isTitleEditable && isEditingTitle {
                    TextField(L10n.templateShareNamePlaceholder, text: $editableTitle)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .font(.appSystem(size: isPreview ? 24 : 70, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "3B2411"))
                        .focused($isTitleFieldFocused)
                        .onSubmit {
                            isEditingTitle = false
                        }
                } else {
                    Text(titleText)
                        .font(.appSystem(size: isPreview ? 24 : 70, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "3B2411"))
                        .lineLimit(2)
                        .onTapGesture(count: 2) {
                            guard isTitleEditable else { return }
                            isEditingTitle = true
                            DispatchQueue.main.async {
                                isTitleFieldFocused = true
                            }
                        }
                }
            }

            BoardTemplateGridPreview(
                template: template,
                tileBackground: tileBackground,
                textColor: Color(hex: "4A3423"),
                isPreview: isPreview
            )

            if qrCodeImage != nil || showsFooterCopy {
                HStack(alignment: .center, spacing: isPreview ? 14 : 28) {
                    if let qrCodeImage {
                        Image(uiImage: qrCodeImage)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: isPreview ? 88 : 220, height: isPreview ? 88 : 220)
                            .clipShape(RoundedRectangle(cornerRadius: isPreview ? 18 : 28, style: .continuous))
                    }

                    if showsFooterCopy {
                        VStack(alignment: .leading, spacing: isPreview ? 6 : 12) {
                            Text(L10n.templateShareFooterTitle)
                                .font(.appSystem(size: isPreview ? 16 : 34, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "3B2411"))

                            Text(L10n.templateShareFooterSubtitle)
                                .font(.appSystem(size: isPreview ? 12 : 24, weight: .medium, design: .rounded))
                                .foregroundColor(Color(hex: "7D6149"))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(previewPadding)
        .frame(width: previewWidth)
        .background(
            RoundedRectangle(cornerRadius: isPreview ? 28 : 64, style: .continuous)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: isPreview ? 28 : 64, style: .continuous)
                        .stroke(Color.white.opacity(0.6), lineWidth: isPreview ? 1 : 3)
                )
                .shadow(color: Color(hex: "C7AA8B").opacity(0.28), radius: isPreview ? 18 : 36, x: 0, y: isPreview ? 10 : 20)
        )
        .onChange(of: isTitleFieldFocused) { _, focused in
            if !focused {
                isEditingTitle = false
            }
        }
        .onChange(of: editableTitle) { _, newValue in
            if newValue.count > 20 {
                editableTitle = String(newValue.prefix(20))
            }
        }
    }
}

struct BoardTemplateGridPreview: View {
    let template: BoardTemplatePayload
    let tileBackground: Color
    let textColor: Color
    let isPreview: Bool
    var previewTextSize: CGFloat = 12

    private var gridSpacing: CGFloat {
        switch template.gridSize {
        case ...3: return 15
        case 4: return 10
        default: return 8
        }
    }

    private var paddedTiles: [BoardTemplateTile] {
        let requiredTiles = template.gridSize * template.gridSize
        return Array(template.tiles.prefix(requiredTiles)) + Array(
            repeating: BoardTemplateTile(text: ""),
            count: max(requiredTiles - template.tiles.count, 0)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let columnsCount = max(template.gridSize, 1)
            let totalSpacing = gridSpacing * CGFloat(columnsCount - 1)
            let cellSize = max((proxy.size.width - totalSpacing) / CGFloat(columnsCount), 0)
            let columns = Array(repeating: GridItem(.fixed(cellSize), spacing: gridSpacing), count: columnsCount)

            LazyVGrid(columns: columns, spacing: gridSpacing) {
                ForEach(Array(paddedTiles.enumerated()), id: \.offset) { _, tile in
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(tileBackground)
                            .shadow(color: Color.white.opacity(0.52), radius: isPreview ? 5 : 12, x: -2, y: -2)
                            .shadow(color: Color(hex: "D9C5B4").opacity(0.42), radius: isPreview ? 6 : 14, x: 3, y: 3)

                        Text(tile.trimmedText.isEmpty ? " " : tile.trimmedText)
                            .font(.appSystem(size: isPreview ? previewTextSize : 28, weight: .semibold, design: .rounded))
                            .foregroundColor(textColor)
                            .multilineTextAlignment(.center)
                            .lineLimit(isPreview ? 3 : 4)
                            .padding(isPreview ? 8 : 18)
                    }
                    .frame(width: cellSize, height: cellSize, alignment: .center)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

enum BoardTemplateShareRenderer {
    @MainActor
    static func renderCard(for template: BoardTemplatePayload) -> UIImage? {
        let canvasSize = CGSize(width: 1440, height: 2560)
        let qrCodeImage = BoardTemplateQRCodeGenerator.makeImage(
            from: template.qrCodeURL.absoluteString,
            size: 1400
        )

        let content = TemplateShareExportPosterView(
            template: template,
            qrCodeImage: qrCodeImage,
            canvasSize: canvasSize
        )
        .frame(width: canvasSize.width, height: canvasSize.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: canvasSize.width, height: canvasSize.height)
        guard let rendered = renderer.uiImage else { return nil }
        return compositedShareLogo(on: rendered)
    }

    @MainActor
    private static func compositedShareLogo(on image: UIImage) -> UIImage {
        guard let logo = UIImage(named: "ShareLogo"), image.size.width > 0, image.size.height > 0 else {
            return image
        }

        let canvas = image.size
        let targetWidth = canvas.width * 0.24
        let targetHeight = targetWidth * (logo.size.height / max(logo.size.width, 1))
        let logoX = (canvas.width - targetWidth) * 0.5
        let logoY = canvas.height - targetHeight - 88
        let logoRect = CGRect(x: logoX, y: max(logoY, 0), width: targetWidth, height: targetHeight)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: canvas))
            logo.draw(in: logoRect)
        }
    }
}

private struct TemplateShareExportPosterView: View {
    let template: BoardTemplatePayload
    let qrCodeImage: UIImage?
    let canvasSize: CGSize

    private var cardWidth: CGFloat {
        canvasSize.width - 120
    }

    var body: some View {
        ZStack {
            Image("BlackBG")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 88)

                ZStack(alignment: .topTrailing) {
                    TemplateShareFigmaCardView(
                        template: template,
                        qrCodeImage: qrCodeImage,
                        cardWidth: cardWidth,
                        isTitleEditable: false,
                        editableTitle: .constant("")
                    )

                    Image("TemplateShareBear")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 132 * (cardWidth / 348.0), height: 122 * (cardWidth / 348.0))
                        .offset(x: -4, y: -52 * (cardWidth / 348.0))
                }
                .frame(width: cardWidth + 24, height: cardWidth + 235 * (cardWidth / 348.0))

                Spacer(minLength: 0)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }
}

enum BoardTemplateQRCodeGenerator {
    static func makeImage(from string: String, size: CGFloat) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.correctionLevel = "L"

        guard let outputImage = filter.outputImage else { return nil }

        let falseColorFilter = CIFilter.falseColor()
        falseColorFilter.inputImage = outputImage
        falseColorFilter.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        falseColorFilter.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        guard let coloredImage = falseColorFilter.outputImage else { return nil }

        let quietZone = max(size * 0.14, 18)
        let qrSideLength = max(size - (quietZone * 2), size * 0.7)
        let scaleX = qrSideLength / coloredImage.extent.width
        let scaleY = qrSideLength / coloredImage.extent.height
        let transformed = coloredImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }

        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        rendererFormat.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: rendererFormat)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: size, height: size)))
            context.cgContext.interpolationQuality = .none
            context.cgContext.setShouldAntialias(false)

            let drawRect = CGRect(
                x: quietZone,
                y: quietZone,
                width: qrSideLength,
                height: qrSideLength
            )
            context.cgContext.draw(cgImage, in: drawRect.integral)
        }
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}

// MARK: - Celebration View
struct CelebrationView: View {
    @State private var confettiItems: [ConfettiItem] = []

    struct ConfettiItem: Identifiable {
        let id: Int
        let emoji: String
        let fontSize: CGFloat
        let startX: CGFloat
        let endX: CGFloat
        let duration: Double
        let delay: Double
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(confettiItems) { item in
                    ConfettiPiece(item: item, height: geo.size.height)
                }
            }
            .onAppear { generateConfetti(in: geo.size) }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func generateConfetti(in size: CGSize) {
        let emojis = ["🎉", "⭐️", "✨", "🎊", "💫", "🌟", "🎯", "🏆"]
        confettiItems = (0..<25).map { i in
            ConfettiItem(
                id: i,
                emoji: emojis[i % emojis.count],
                fontSize: CGFloat.random(in: 18...34),
                startX: CGFloat.random(in: 0...size.width),
                endX: CGFloat.random(in: -60...60),
                duration: Double.random(in: 1.2...2.2),
                delay: Double.random(in: 0...0.6)
            )
        }
    }
}

struct ConfettiPiece: View {
    let item: CelebrationView.ConfettiItem
    let height: CGFloat
    @State private var animate = false

    var body: some View {
        Text(item.emoji)
            .font(.appSystem(size: item.fontSize))
            .offset(
                x: item.startX + (animate ? item.endX : 0),
                y: animate ? height + 50 : -50
            )
            .opacity(animate ? 0 : 1)
            .onAppear {
                withAnimation(.easeIn(duration: item.duration).delay(item.delay)) {
                    animate = true
                }
            }
    }
}
