import Foundation

#if canImport(FirebaseRemoteConfig)
import FirebaseRemoteConfig
#endif

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
