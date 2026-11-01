import Foundation
import Combine
import UIKit
import os

@MainActor
final class AppIconManager: ObservableObject {
    enum RequestSource: String {
        case settings, milestone, premiumExpiration, migration
    }

    enum ChangeResult: Equatable {
        case changed, alreadyCurrent, busy, cancelled
        case failed(String)

        var succeeded: Bool {
            self == .changed || self == .alreadyCurrent
        }
    }

    /// Injectable system calls let tests exercise failures without changing real icons.
    struct Client {
        var currentIconName: @MainActor () -> String?
        var isActive: @MainActor () -> Bool
        var supportsAlternateIcons: @MainActor () -> Bool
        var primaryIconName: String?
        var alternateIconNames: Set<String>
        var changeIcon: @MainActor (String?) async throws -> Void
        var waitBeforeRetry: @MainActor () async throws -> Void
        var feedback: @MainActor () -> Void

        @MainActor static var live: Self {
            let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
            let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
            let alternates = icons?["CFBundleAlternateIcons"] as? [String: Any] ?? [:]
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            let primaryName = primary?["CFBundleIconName"] as? String ?? "missing"
            AppIconManager.logger.notice("Icon configuration: bundle=\(Bundle.main.bundleIdentifier ?? "unknown", privacy: .public), version=\(version, privacy: .public), build=\(build, privacy: .public), iOS=\(UIDevice.current.systemVersion, privacy: .public), primary=\(primaryName, privacy: .public), alternates=\(alternates.keys.sorted().joined(separator: ","), privacy: .public)")
            return Self(
                currentIconName: { UIApplication.shared.alternateIconName },
                isActive: { UIApplication.shared.applicationState == .active },
                supportsAlternateIcons: { UIApplication.shared.supportsAlternateIcons },
                primaryIconName: primary?["CFBundleIconName"] as? String,
                alternateIconNames: Set(alternates.keys),
                changeIcon: { try await UIApplication.shared.setAlternateIconName($0) },
                waitBeforeRetry: { try await Task.sleep(for: .seconds(1)) },
                feedback: { AppHaptics.control() }
            )
        }
    }

    private static let logger = Logger(subsystem: "com.bingoday.app", category: "AppIconSwitch")
    private static let maxTemporaryFailureAttempts = 3

    /// Only diagnostic source keys are included; never dump arbitrary userInfo.
    /// Bound traversal so malformed nested errors cannot flood the device log.
    static func diagnosticTrace(_ error: NSError) -> String {
        var trace: [String] = []
        var current: NSError? = error
        var seen: Set<ObjectIdentifier> = []
        while let failure = current, trace.count < 4,
              seen.insert(ObjectIdentifier(failure)).inserted {
            var fields = ["\(failure.domain)/\(failure.code)"]
            for key in ["_LSFile", "_LSLine", "_LSFunction"] {
                if let value = failure.userInfo[key] as? String {
                    fields.append("\(key)=\(value)")
                } else if let value = failure.userInfo[key] as? Int {
                    fields.append("\(key)=\(value)")
                }
            }
            trace.append(fields.joined(separator: " "))
            current = failure.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return trace.joined(separator: " <- ")
    }
    private let client: Client
    private let entitlements: AppIconEntitlementStore
    // Don't loop automatic restores when a system alert reactivates the scene.
    private var hasAttemptedPremiumRestore = false
    @Published private(set) var currentAlternateIconName: String?
    @Published private(set) var isChanging = false

    convenience init() {
        self.init(client: .live, entitlements: .shared)
    }

    init(client: Client, entitlements: AppIconEntitlementStore) {
        self.entitlements = entitlements
        self.client = client
        currentAlternateIconName = client.currentIconName()
    }

    func refresh() {
        currentAlternateIconName = client.currentIconName()
    }

    func isCurrent(_ option: AppIconOption) -> Bool {
        let actualName = currentAlternateIconName ?? client.primaryIconName
        return actualName == option.iconAssetName
    }

    var visibleOptions: [AppIconOption] { entitlements.visibleOptions }

    /// Runs under the same switch gate as settings and Premium expiration.
    func migrateSeasonalIconIfNeeded() async {
        guard entitlements.pendingResetFromHalloween, !isChanging,
              client.isActive(), !Task.isCancelled else { return }
        refresh()
        guard isCurrent(.halloween) else {
            entitlements.finishReset()
            return
        }
        let result = await setIcon(.default, source: .migration)
        if result.succeeded { entitlements.finishReset() }
    }

    func premiumAccessRestored() {
        hasAttemptedPremiumRestore = false
    }

    func restoreDefaultIfPremiumExpired() async {
        refresh()
        guard !hasAttemptedPremiumRestore, !isChanging, client.isActive(),
              !Task.isCancelled, isCurrent(.premium) else { return }
        hasAttemptedPremiumRestore = true
        // The caller confirmed expiration. Automatic failures are logged, not
        // presented by unrelated views; explicit user selections can still retry.
        _ = await setIcon(.default, source: .premiumExpiration)
    }

    func setIcon(_ option: AppIconOption, source: RequestSource = .settings) async -> ChangeResult {
        guard !isChanging else { return .busy }
        guard entitlements.allows(option) else {
            return .failed(L10n.tr(
                "This seasonal icon is no longer available to new users.",
                zhHans: "此节日图标已停止向新用户开放。",
                zhHant: "此節日圖標已停止向新用戶開放。",
                ja: "この季節限定アイコンは新規ユーザーには提供されていません。"
            ))
        }
        // An explicit choice supersedes a pending automatic reset, even if iOS
        // later refuses the selection. Never overwrite that choice on next launch.
        if source == .settings { entitlements.finishReset() }
        refresh()
        guard !Task.isCancelled else { return .cancelled }
        guard !isCurrent(option) else { return .alreadyCurrent }

        let requestID = UUID().uuidString
        let targetName = option.alternateIconName(primaryIconName: client.primaryIconName)
        let target = targetName ?? "primary"
        guard client.primaryIconName != nil,
              targetName == nil || client.alternateIconNames.contains(option.iconAssetName) else {
            Self.logger.error("Icon configuration missing: request=\(requestID, privacy: .public), target=\(target, privacy: .public)")
            return .failed(L10n.tr(
                "This icon isn't available in this app version. Please update Bingodays.",
                zhHans: "此版本暂不支持这个图标，请更新 Bingodays。",
                zhHant: "此版本暫不支援這個圖標，請更新 Bingodays。",
                ja: "このバージョンではこのアイコンを利用できません。Bingodaysを更新してください。"
            ))
        }

        isChanging = true
        defer { isChanging = false }

        // Keep the shared gate held across the API call and bounded retry delay.
        // LaunchServices can remain busy briefly after an icon transaction or
        // scene transition, so do not make the user repeat the tap immediately.
        for attempt in 1...Self.maxTemporaryFailureAttempts {
            guard !Task.isCancelled else { return .cancelled }
            refresh()
            if isCurrent(option) { return .alreadyCurrent }
            guard client.supportsAlternateIcons() else {
                return .failed(L10n.tr(
                    "This device doesn't support changing app icons.",
                    zhHans: "此设备不支持更换应用图标。", zhHant: "此裝置不支援更換應用程式圖標。",
                    ja: "このデバイスではアプリアイコンを変更できません。"
                ))
            }
            guard client.isActive() else {
                return .failed(L10n.tr(
                    "Please return to Bingodays and try again.",
                    zhHans: "请返回 Bingodays 后再试。", zhHant: "請返回 Bingodays 後再試。",
                    ja: "Bingodaysに戻ってから、もう一度お試しください。"
                ))
            }

            Self.logger.notice("Icon switch requested: request=\(requestID, privacy: .public), source=\(source.rawValue, privacy: .public), target=\(target, privacy: .public), attempt=\(attempt)")
            do {
                try await client.changeIcon(targetName)
                refresh()
                guard isCurrent(option) else {
                    Self.logger.error("Icon API returned without applying target: request=\(requestID, privacy: .public), target=\(target, privacy: .public)")
                    return .failed(L10n.tr(
                        "The icon hasn't changed. Please try again later.",
                        zhHans: "图标尚未更换，请稍后再试。", zhHant: "圖標尚未更換，請稍後再試。",
                        ja: "アイコンは変更されていません。しばらくしてからお試しください。"
                    ))
                }
                Self.logger.notice("Icon switch succeeded: request=\(requestID, privacy: .public), target=\(target, privacy: .public)")
                client.feedback()
                return .changed
            } catch {
                refresh()
                if isCurrent(option) { return .alreadyCurrent }
                let failure = error as NSError
                Self.logger.error("Icon switch failed: request=\(requestID, privacy: .public), source=\(source.rawValue, privacy: .public), target=\(target, privacy: .public), attempt=\(attempt), domain=\(failure.domain, privacy: .public), code=\(failure.code), active=\(self.client.isActive()), current=\(self.currentAlternateIconName ?? "primary", privacy: .public), trace=\(Self.diagnosticTrace(failure), privacy: .public), description=\(failure.localizedDescription, privacy: .public)")
                guard !Task.isCancelled, !(error is CancellationError) else { return .cancelled }
                let isTemporaryFailure = failure.domain == NSPOSIXErrorDomain && failure.code == Int(EAGAIN)
                if attempt < Self.maxTemporaryFailureAttempts, isTemporaryFailure, client.isActive() {
                    Self.logger.notice("Icon switch retry scheduled: request=\(requestID, privacy: .public), delaySeconds=1")
                    do {
                        try await client.waitBeforeRetry()
                    } catch {
                        return .cancelled
                    }
                    continue
                }
                if isTemporaryFailure {
                    return .failed(L10n.tr(
                        "iOS is temporarily unable to change the app icon. Please try again later. If the problem continues, restart your device.",
                        zhHans: "iOS 暂时无法更换应用图标，请稍后再试。若持续失败，请重启设备后再试。",
                        zhHant: "iOS 暫時無法更換應用程式圖標，請稍後再試。若持續失敗，請重新啟動裝置後再試。",
                        ja: "iOSが一時的にアプリアイコンを変更できません。しばらくしてからお試しください。問題が続く場合はデバイスを再起動してください。"
                    ))
                }
                return .failed(failure.localizedDescription)
            }
        }
        return .cancelled
    }
}
