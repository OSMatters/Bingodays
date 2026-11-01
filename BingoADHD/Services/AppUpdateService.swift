import Foundation

#if canImport(FirebaseRemoteConfig)
import FirebaseRemoteConfig
#endif

extension Notification.Name {
    static let limitedOfferEligibilityDidChange = Notification.Name("limitedOfferEligibilityDidChange")
}

struct LimitedTimeOfferConfig: Equatable {
    static let defaultCampaignID = "lifetime_early_supporter_early20_relaunch_v1"
    static let defaultOfferDurationHours = 48.0
    static let defaultMinimumAppVersion = "2.3.0"
    static let disabled = LimitedTimeOfferConfig(
        isEnabled: false,
        campaignID: defaultCampaignID,
        offerDuration: defaultOfferDurationHours * 60 * 60,
        minimumAppVersion: defaultMinimumAppVersion
    )
    static let bundledFallback = LimitedTimeOfferConfig(
        isEnabled: true,
        campaignID: defaultCampaignID,
        offerDuration: defaultOfferDurationHours * 60 * 60,
        minimumAppVersion: defaultMinimumAppVersion
    )

    let isEnabled: Bool
    let campaignID: String
    let offerDuration: TimeInterval
    let minimumAppVersion: String

    func isEnabled(forAppVersion appVersion: String) -> Bool {
        isEnabled && AppVersionComparator.isVersion(appVersion, atLeast: minimumAppVersion)
    }
}

enum LimitedOfferEntryEligibility {
    static func shouldShowEntry(
        config: LimitedTimeOfferConfig,
        appVersion: String,
        hasPremiumAccess: Bool,
        hasCompletedEntitlementRefresh: Bool = true,
        hasVisitedPaywallWithoutPurchase: Bool,
        hasLegacyExposure: Bool,
        startedAt: Double,
        campaignID: String,
        now: Date
    ) -> Bool {
        config.isEnabled(forAppVersion: appVersion)
            && hasCompletedEntitlementRefresh
            && !hasPremiumAccess
            && (hasVisitedPaywallWithoutPurchase || hasLegacyExposure)
            && !hasCountdownExpired(
                config: config,
                startedAt: startedAt,
                campaignID: campaignID,
                now: now
            )
    }

    static func hasCountdownExpired(
        config: LimitedTimeOfferConfig,
        startedAt: Double,
        campaignID: String,
        now: Date
    ) -> Bool {
        guard startedAt > 0 else { return false }
        return now.timeIntervalSince1970 >= startedAt + config.offerDuration
    }
}

struct LimitedOfferHomeState: Equatable {
    var hasVisitedPaywallWithoutPurchase: Bool
    var hasLegacyExposure: Bool
    var startedAt: Double
    var campaignID: String
    var isPresented: Bool
}

enum LimitedOfferHomeRules {
    static func hasUnlockedEntry(
        hasVisitedPaywallWithoutPurchase: Bool,
        hasLegacyExposure: Bool,
        forceEligible: Bool
    ) -> Bool {
        hasVisitedPaywallWithoutPurchase || hasLegacyExposure || forceEligible
    }

    static func applyingPremiumAccess(
        to state: LimitedOfferHomeState,
        hasPremiumAccess: Bool
    ) -> LimitedOfferHomeState {
        guard hasPremiumAccess else { return state }
        var updatedState = state
        updatedState.isPresented = false
        return updatedState
    }

    static func applyingDebugReset(
        to state: LimitedOfferHomeState,
        shouldReset: Bool
    ) -> LimitedOfferHomeState {
        guard shouldReset else { return state }
        return LimitedOfferHomeState(
            hasVisitedPaywallWithoutPurchase: false,
            hasLegacyExposure: false,
            startedAt: 0,
            campaignID: "",
            isPresented: state.isPresented
        )
    }

    static func applyingLegacyExposureMigration(to state: LimitedOfferHomeState) -> LimitedOfferHomeState {
        guard !state.hasLegacyExposure,
              state.startedAt > 0 || !state.campaignID.isEmpty else {
            return state
        }

        var updatedState = state
        updatedState.hasLegacyExposure = true
        return updatedState
    }

    static func applyingCampaignSync(
        to state: LimitedOfferHomeState,
        config: LimitedTimeOfferConfig
    ) -> LimitedOfferHomeState {
        guard state.campaignID.isEmpty, state.startedAt <= 0 else {
            return state
        }

        var updatedState = state
        updatedState.campaignID = config.campaignID
        return updatedState
    }

    static func applyingPaywallExitWithoutPurchase(
        to state: LimitedOfferHomeState
    ) -> LimitedOfferHomeState {
        var updatedState = state
        updatedState.hasVisitedPaywallWithoutPurchase = true
        return updatedState
    }

    static func applyingDiscountPagePresentation(
        to state: LimitedOfferHomeState,
        campaignID: String,
        now: Date
    ) -> LimitedOfferHomeState {
        var updatedState = state
        if updatedState.campaignID.isEmpty {
            updatedState.campaignID = campaignID
        }

        let timestamp = now.timeIntervalSince1970
        if updatedState.startedAt <= 0 || updatedState.startedAt > timestamp {
            updatedState.startedAt = timestamp
        }
        return updatedState
    }

    static func applyingConfirmedPurchase(
        to state: LimitedOfferHomeState
    ) -> LimitedOfferHomeState {
        LimitedOfferHomeState(
            hasVisitedPaywallWithoutPurchase: false,
            hasLegacyExposure: false,
            startedAt: 0,
            campaignID: "",
            isPresented: false
        )
    }

    static func shouldDismissPresentedOffer(
        config: LimitedTimeOfferConfig,
        appVersion: String,
        hasPremiumAccess: Bool
    ) -> Bool {
        hasPremiumAccess || !config.isEnabled(forAppVersion: appVersion)
    }
}

@MainActor
enum LimitedTimeOfferRemoteConfigService {
    private static let isEnabledKey = "ios_lifetime_early_supporter_offer_enabled"
    private static let campaignIDKey = "ios_lifetime_early_supporter_offer_campaign_id"
    private static let durationHoursKey = "ios_lifetime_early_supporter_offer_duration_hours"
    private static let minimumAppVersionKey = "ios_lifetime_early_supporter_offer_min_app_version"
#if DEBUG
    private static let debugIsEnabledKey = "debug_limited_offer_enabled"
    private static let debugCampaignIDKey = "debug_limited_offer_campaign_id"
    private static let debugDurationHoursKey = "debug_limited_offer_duration_hours"
    private static let debugMinimumAppVersionKey = "debug_limited_offer_min_app_version"
#endif

    private static var inFlightFetch: Task<LimitedTimeOfferConfig, Never>?

    static func fetchOfferConfig() async -> LimitedTimeOfferConfig {
        if let inFlightFetch {
            return await inFlightFetch.value
        }

        let fetchTask = Task {
            await fetchOfferConfigUncoalesced()
        }
        inFlightFetch = fetchTask
        let config = await fetchTask.value
        inFlightFetch = nil
        return config
    }

    private static func fetchOfferConfigUncoalesced() async -> LimitedTimeOfferConfig {
#if DEBUG
        return debugOfferConfig(overriding: .disabled)
#else
        var config = LimitedTimeOfferConfig.bundledFallback
#if canImport(FirebaseRemoteConfig)
        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 60 * 60
        settings.fetchTimeout = 10
        remoteConfig.configSettings = settings
        remoteConfig.setDefaults([
            isEnabledKey: NSNumber(value: LimitedTimeOfferConfig.bundledFallback.isEnabled),
            campaignIDKey: LimitedTimeOfferConfig.bundledFallback.campaignID as NSObject,
            durationHoursKey: NSNumber(
                value: LimitedTimeOfferConfig.bundledFallback.offerDuration / 60 / 60
            ),
            minimumAppVersionKey: LimitedTimeOfferConfig.bundledFallback.minimumAppVersion as NSObject
        ])

        do {
            _ = try await remoteConfig.fetchAndActivate()
        } catch {
            // Continue with cached/bundled values when Remote Config is unreachable.
            DiagnosticLogStore.recordWarning(
                "limited_offer.remote_config_fetch_failed",
                details: ["error": error.localizedDescription]
            )
        }

        let campaignID = sanitizedCampaignID(
            remoteConfig.configValue(forKey: campaignIDKey).stringValue
        )
        let durationHours = sanitizedDurationHours(
            remoteConfig.configValue(forKey: durationHoursKey).numberValue.doubleValue
        )
        let minimumAppVersion = sanitizedMinimumAppVersion(
            remoteConfig.configValue(forKey: minimumAppVersionKey).stringValue
        )

        config = LimitedTimeOfferConfig(
            isEnabled: remoteConfig.configValue(forKey: isEnabledKey).boolValue,
            campaignID: campaignID,
            offerDuration: durationHours * 60 * 60,
            minimumAppVersion: minimumAppVersion
        )
        DiagnosticLogStore.recordStateChange(
            "limited_offer.remote_config_resolved",
            details: [
                "enabled": "\(config.isEnabled)",
                "campaign": config.campaignID,
                "minimum_version": config.minimumAppVersion
            ]
        )
#endif

        return config
#endif
    }

    private static func sanitizedCampaignID(_ rawValue: String) -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? LimitedTimeOfferConfig.defaultCampaignID : value
    }

    private static func sanitizedDurationHours(_ rawValue: Double) -> Double {
        guard rawValue.isFinite, rawValue > 0 else {
            return LimitedTimeOfferConfig.defaultOfferDurationHours
        }
        return min(rawValue, LimitedTimeOfferConfig.defaultOfferDurationHours)
    }

    private static func sanitizedMinimumAppVersion(_ rawValue: String) -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? LimitedTimeOfferConfig.defaultMinimumAppVersion : value
    }

#if DEBUG
    private static func debugOfferConfig(overriding base: LimitedTimeOfferConfig) -> LimitedTimeOfferConfig {
        let arguments = ProcessInfo.processInfo.arguments
        let defaults = UserDefaults.standard

        let isEnabled: Bool
        if arguments.contains("-DebugLimitedOfferEnabled") {
            isEnabled = true
        } else if arguments.contains("-DebugLimitedOfferDisabled") {
            isEnabled = false
        } else if defaults.object(forKey: debugIsEnabledKey) != nil {
            isEnabled = defaults.bool(forKey: debugIsEnabledKey)
        } else {
            isEnabled = true
        }
        let rawDebugDurationHours = debugArgumentValue(for: "-DebugLimitedOfferDurationHours", in: arguments)
            .flatMap(Double.init)
            ?? (defaults.object(forKey: debugDurationHoursKey) != nil
            ? defaults.double(forKey: debugDurationHoursKey)
            : LimitedTimeOfferConfig.defaultOfferDurationHours)
        let debugDurationHours = sanitizedDurationHours(rawDebugDurationHours)
        let debugCampaignID = sanitizedCampaignID(
            debugArgumentValue(for: "-DebugLimitedOfferCampaignID", in: arguments)
                ?? defaults.string(forKey: debugCampaignIDKey)
                ?? "debug_paywall_exit_v1"
        )
        let debugMinimumAppVersion = sanitizedMinimumAppVersion(
            debugArgumentValue(for: "-DebugLimitedOfferMinAppVersion", in: arguments)
                ?? defaults.string(forKey: debugMinimumAppVersionKey)
                ?? "0.0.0"
        )

        let config = LimitedTimeOfferConfig(
            isEnabled: isEnabled,
            campaignID: debugCampaignID,
            offerDuration: debugDurationHours * 60 * 60,
            minimumAppVersion: debugMinimumAppVersion
        )
#if DEBUG
        print(
            "[LimitedOffer] Using debug config",
            "enabled=\(config.isEnabled)",
            "campaign=\(config.campaignID)",
            "hours=\(debugDurationHours)",
            "minVersion=\(config.minimumAppVersion)"
        )
#endif
        return config
    }

    private static func hasDebugOfferOverride(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        defaults: UserDefaults = .standard
    ) -> Bool {
        arguments.contains("-DebugLimitedOfferEnabled")
            || arguments.contains("-DebugLimitedOfferDisabled")
            || defaults.object(forKey: debugIsEnabledKey) != nil
    }

    private static func debugArgumentValue(for key: String, in arguments: [String]) -> String? {
        let prefix = key + "="
        guard let argument = arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        return String(argument.dropFirst(prefix.count))
    }
#endif
}

enum AppVersionComparator {
    static func isVersion(_ lhs: String, greaterThan rhs: String) -> Bool {
        compare(lhs, rhs) == .orderedDescending
    }

    static func isVersion(_ lhs: String, atLeast rhs: String) -> Bool {
        compare(lhs, rhs) != .orderedAscending
    }

    private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = lhs.split(separator: ".").map(versionPartValue)
        let rhsParts = rhs.split(separator: ".").map(versionPartValue)
        let maxCount = max(lhsParts.count, rhsParts.count)

        for index in 0..<maxCount {
            let left = index < lhsParts.count ? lhsParts[index] : 0
            let right = index < rhsParts.count ? rhsParts[index] : 0

            if left != right {
                return left > right ? .orderedDescending : .orderedAscending
            }
        }

        return .orderedSame
    }

    private static func versionPartValue(_ part: Substring) -> Int {
        let digits = part.prefix { $0.isNumber }
        return Int(digits) ?? 0
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
              AppVersionComparator.isVersion(cached.latestVersion, greaterThan: currentVersion),
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

        guard AppVersionComparator.isVersion(config.latestVersion, greaterThan: currentVersion) else {
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

                guard AppVersionComparator.isVersion(latestVersion, greaterThan: currentVersion) else {
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
            "zh-Hant": [],
            "ja": []
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
            keys = ["ja", "ja-JP", "en", "en-US"]
        case .korean:
            keys = ["ko", "ko-KR", "en", "en-US"]
        case .german:
            keys = ["de", "de-DE", "de_DE", "de-AT", "de-CH", "en", "en-US"]
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
