import Foundation
import Testing
import UIKit
@testable import Bingodays

@MainActor
struct AppIconManagerTests {
    @MainActor
    private final class SystemStub {
        let suiteName: String
        let defaults: UserDefaults
        let entitlements: AppIconEntitlementStore

        init(legacy: Bool = true) {
            let name = "AppIconTests." + UUID().uuidString
            suiteName = name
            let store = UserDefaults(suiteName: name)!
            defaults = store
            if legacy { store.set(true, forKey: "has_seen_onboarding_v2") }
            entitlements = AppIconEntitlementStore(defaults: store)
        }

        deinit { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        var currentName: String?
        var isActive = true
        var supportsIcons = true
        var primaryName = "AppIconHalloween"
        var registeredNames = Set(AppIconOption.allCases.map(\.iconAssetName))
        var requests: [String?] = []
        var retryWaits = 0
        var feedbackCount = 0
        var change: (@MainActor (String?) async throws -> Void)?
        var wait: (@MainActor () async throws -> Void)?
        var retryStarted: CheckedContinuation<Void, Never>?

        var client: AppIconManager.Client {
            .init(
                currentIconName: { self.currentName },
                isActive: { self.isActive },
                supportsAlternateIcons: { self.supportsIcons },
                primaryIconName: primaryName,
                alternateIconNames: registeredNames,
                changeIcon: { name in
                    self.requests.append(name)
                    if let change = self.change { try await change(name) }
                    else { self.currentName = name }
                },
                waitBeforeRetry: {
                    self.retryWaits += 1
                    self.retryStarted?.resume()
                    self.retryStarted = nil
                    if let wait = self.wait { try await wait() }
                },
                feedback: { self.feedbackCount += 1 }
            )
        }

        func waitUntilRetryStarts() async {
            if retryWaits > 0 { return }
            await withCheckedContinuation { retryStarted = $0 }
        }
    }

    @Test
    func newInstallStaysIneligibleAfterRecordingUsage() async {
        let system = SystemStub(legacy: false)
        system.primaryName = "AppIcon"
        let manager = AppIconManager(client: system.client, entitlements: system.entitlements)
        #expect(!manager.visibleOptions.contains(.halloween))
        system.defaults.set(true, forKey: "has_seen_onboarding_v2")
        let reloaded = AppIconEntitlementStore(defaults: system.defaults)
        #expect(!reloaded.ownsHalloween)
        let result = await manager.setIcon(.halloween)
        #expect(!result.succeeded)
        #expect(system.requests.isEmpty)
    }

    @Test
    func legacyPrimaryBecomesDefaultWithoutSystemSwitch() async {
        let system = SystemStub()
        system.primaryName = "AppIcon"
        let manager = AppIconManager(client: system.client, entitlements: system.entitlements)
        await manager.migrateSeasonalIconIfNeeded()
        #expect(manager.isCurrent(.default))
        #expect(system.requests.isEmpty)
        #expect(system.entitlements.ownsHalloween)
        #expect(!system.entitlements.pendingResetFromHalloween)
    }

    @Test
    func explicitHalloweenResetsOnceAndCanBeSelectedAgain() async {
        let system = SystemStub()
        system.primaryName = "AppIcon"
        system.currentName = "AppIconHalloween"
        let manager = AppIconManager(client: system.client, entitlements: system.entitlements)
        await manager.migrateSeasonalIconIfNeeded()
        #expect(manager.isCurrent(.default))
        #expect(system.entitlements.ownsHalloween)
        #expect(await manager.setIcon(.halloween) == .changed)
        let reloaded = AppIconEntitlementStore(defaults: system.defaults)
        let restarted = AppIconManager(client: system.client, entitlements: reloaded)
        await restarted.migrateSeasonalIconIfNeeded()
        #expect(restarted.isCurrent(.halloween))
        #expect(system.requests.count == 2)
    }

    @Test(arguments: [AppIconOption.days10, .days20, .days30, .premium])
    func migrationPreservesOtherSelections(_ option: AppIconOption) async {
        let system = SystemStub()
        system.primaryName = "AppIcon"
        system.currentName = option.iconAssetName
        let manager = AppIconManager(client: system.client, entitlements: system.entitlements)
        await manager.migrateSeasonalIconIfNeeded()
        #expect(manager.isCurrent(option))
        #expect(system.requests.isEmpty)
        #expect(!system.entitlements.pendingResetFromHalloween)
    }

    @Test
    func failedMigrationRetriesOnNextActivation() async {
        let system = SystemStub()
        system.primaryName = "AppIcon"
        system.currentName = "AppIconHalloween"
        system.change = { _ in throw NSError(domain: "Test", code: 1) }
        let manager = AppIconManager(client: system.client, entitlements: system.entitlements)
        await manager.migrateSeasonalIconIfNeeded()
        #expect(system.entitlements.pendingResetFromHalloween)
        system.change = nil
        await manager.migrateSeasonalIconIfNeeded()
        #expect(manager.isCurrent(.default))
        #expect(!system.entitlements.pendingResetFromHalloween)
    }

    @Test
    func explicitSelectionCancelsPendingResetEvenIfAlreadyCurrent() async {
        let system = SystemStub()
        system.primaryName = "AppIcon"
        system.currentName = "AppIconHalloween"
        let manager = AppIconManager(client: system.client, entitlements: system.entitlements)
        #expect(await manager.setIcon(.halloween) == .alreadyCurrent)
        await manager.migrateSeasonalIconIfNeeded()
        #expect(manager.isCurrent(.halloween))
        #expect(!system.entitlements.pendingResetFromHalloween)
    }

    @Test(arguments: ["app_open_streak_state_v1", "bingo_board_v1", "bingo_boards_v1"])
    func releasedUsageKeysGrantOwnership(_ key: String) {
        let system = SystemStub()
        system.defaults.removeObject(forKey: AppIconEntitlementStore.storageKey)
        system.defaults.removeObject(forKey: "has_seen_onboarding_v2")
        system.defaults.set(Data("{}".utf8), forKey: key)
        let store = AppIconEntitlementStore(defaults: system.defaults)
        #expect(store.ownsHalloween)
    }

    @Test
    func appGroupUsageAlsoGrantsOwnership() {
        let local = SystemStub(legacy: false)
        let shared = SystemStub(legacy: false)
        local.defaults.removeObject(forKey: AppIconEntitlementStore.storageKey)
        shared.defaults.set(Data("{}".utf8), forKey: "bingo_board_v1")
        let store = AppIconEntitlementStore(defaults: local.defaults, sharedDefaults: shared.defaults)
        #expect(store.ownsHalloween)
    }

    @Test
    func inactiveMigrationWaitsWithoutFinishing() async {
        let system = SystemStub()
        system.primaryName = "AppIcon"
        system.currentName = "AppIconHalloween"
        system.isActive = false
        let manager = AppIconManager(client: system.client, entitlements: system.entitlements)
        await manager.migrateSeasonalIconIfNeeded()
        #expect(system.requests.isEmpty)
        #expect(system.entitlements.pendingResetFromHalloween)
        system.isActive = true
        await manager.migrateSeasonalIconIfNeeded()
        #expect(manager.isCurrent(.default))
        #expect(!system.entitlements.pendingResetFromHalloween)
    }

    private var temporaryError: NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(EAGAIN))
    }

    @Test
    func diagnosticLaunchDoesNotConstructProductionServices() {
        var constructions = 0
        let services = AppServices(isIconProbe: true) {
            constructions += 1
            return AppServices.Production()
        }
        #expect(services.production == nil)
        #expect(constructions == 0)
    }

    @Test
    func diagnosticTraceIncludesUnderlyingSourceButNotUnrelatedUserInfo() {
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: Int(EAGAIN), userInfo: [
            "_LSFile": "LSIconAlertManager.m",
            "_LSLine": 113,
            "_LSFunction": "iconChangeAlertTokenForIdentity:error:",
            "unrelatedSecret": "must-not-be-logged"
        ])
        let error = NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [NSUnderlyingErrorKey: underlying])
        let trace = AppIconManager.diagnosticTrace(error)
        #expect(trace.contains("NSCocoaErrorDomain/4"))
        #expect(trace.contains("NSPOSIXErrorDomain/\(EAGAIN)"))
        #expect(trace.contains("_LSFile=LSIconAlertManager.m"))
        #expect(trace.contains("_LSLine=113"))
        #expect(!trace.contains("must-not-be-logged"))
    }

    @Test
    func diagnosticTraceBoundsNestedErrors() {
        var error = NSError(domain: "depth0", code: 0)
        for depth in 1...8 {
            error = NSError(domain: "depth\(depth)", code: depth, userInfo: [NSUnderlyingErrorKey: error])
        }
        let trace = AppIconManager.diagnosticTrace(error)
        #expect(trace.components(separatedBy: " <- ").count == 4)
        #expect(trace.contains("depth8/8"))
        #expect(!trace.contains("depth4/4"))
    }

    @Test
    func previewsAreDistinctAndDefaultIsNotHalloween() {
        #expect(AppIconOption.default.previewAssetName == "AppIconPreviewDefault")
        #expect(AppIconOption.halloween.previewAssetName == "AppIconPreviewHalloween")
        #expect(Set(AppIconOption.allCases.map(\.previewAssetName)).count == 6)
        #expect(UIImage(named: AppIconOption.default.previewAssetName)?.pngData()
            != UIImage(named: AppIconOption.halloween.previewAssetName)?.pngData())
    }

    @Test(arguments: AppIconOption.allCases)
    func packagedPreviewAndRegistrationExist(option: AppIconOption) {
        let client = AppIconManager.Client.live
        #expect(UIImage(named: option.previewAssetName) != nil)
        #expect(client.primaryIconName == option.iconAssetName
            || client.alternateIconNames.contains(option.iconAssetName))
    }

    @Test(arguments: AppIconOption.allCases)
    func eachIconUsesItsOwnRegisteredIdentity(option: AppIconOption) async {
        let system = SystemStub()
        if option == .halloween { system.currentName = "AppIcon" }
        let manager = AppIconManager(client: system.client, entitlements: system.entitlements)
        #expect(await manager.setIcon(option) == .changed)
        #expect(system.requests.count == 1)
        #expect(system.requests.first == .some(option.alternateIconName(primaryIconName: system.primaryName)))
        #expect(manager.isCurrent(option))
    }

    @Test
    func primaryIconIdentityCanChangeWithoutBreakingDefaultOrHalloween() async {
        let system = SystemStub()
        system.primaryName = "AppIcon"
        let manager = AppIconManager(client: system.client, entitlements: system.entitlements)
        #expect(manager.isCurrent(.default))
        #expect(!manager.isCurrent(.halloween))
        #expect(await manager.setIcon(.halloween) == .changed)
        #expect(system.currentName == "AppIconHalloween")
        #expect(await manager.setIcon(.default) == .changed)
        #expect(system.currentName == nil)
        #expect(manager.isCurrent(.default))
    }

    @Test
    func alreadySelectedIconDoesNotCallSystem() async {
        let system = SystemStub()
        let manager = AppIconManager(client: system.client, entitlements: system.entitlements)
        #expect(await manager.setIcon(.halloween) == .alreadyCurrent)
        #expect(system.requests.isEmpty)
        #expect(system.feedbackCount == 0)
    }

    @Test
    func missingRegistrationDoesNotCallSystem() async {
        let system = SystemStub()
        system.registeredNames.remove("AppIcon")
        let manager = AppIconManager(client: system.client, entitlements: system.entitlements)
        let result = await manager.setIcon(.default)
        guard case .failed = result else { Issue.record("Missing registration must fail"); return }
        #expect(system.requests.isEmpty)
        #expect(!manager.isChanging)
    }

    @Test(arguments: [true, false])
    func inactiveOrUnsupportedDeviceNeverCallsSystem(inactive: Bool) async {
        let system = SystemStub()
        system.isActive = !inactive
        system.supportsIcons = inactive
        let manager = AppIconManager(client: system.client, entitlements: system.entitlements)
        let result = await manager.setIcon(.default)
        guard case .failed = result else { Issue.record("Preflight must fail"); return }
        #expect(system.requests.isEmpty)
    }

    @Test
    func temporaryFailureRetriesAndCanRecoverOnThirdAttempt() async {
        let system = SystemStub()
        let failure = temporaryError
        system.change = { name in
            if system.requests.count < 3 { throw failure }
            system.currentName = name
        }
        let manager = AppIconManager(client: system.client, entitlements: system.entitlements)
        #expect(await manager.setIcon(.default) == .changed)
        #expect(system.requests.count == 3)
        #expect(system.retryWaits == 2)
        #expect(system.feedbackCount == 1)
        #expect(!manager.isChanging)
    }

    @Test
    func persistentTemporaryFailureStopsAfterThreeAttempts() async {
        let system = SystemStub()
        let failure = temporaryError
        system.change = { _ in throw failure }
        let manager = AppIconManager(client: system.client, entitlements: system.entitlements)
        let result = await manager.setIcon(.days20)
        guard case let .failed(message) = result else { Issue.record("Persistent failure must be reported"); return }
        #expect(message.contains("iOS"))
        #expect(system.requests.count == 3)
        #expect(system.retryWaits == 2)
        #expect(system.feedbackCount == 0)
        #expect(!manager.isCurrent(.days20))
        #expect(!manager.isChanging)
    }

    @Test
    func otherErrorDomainsAreNotRetried() async {
        let system = SystemStub()
        system.change = { _ in throw NSError(domain: NSCocoaErrorDomain, code: Int(EAGAIN)) }
        let manager = AppIconManager(client: system.client, entitlements: system.entitlements)
        _ = await manager.setIcon(.default)
        #expect(system.requests.count == 1)
        #expect(system.retryWaits == 0)
    }

    @Test
    func allEntrypointsShareTheGateIncludingDuringRetryDelay() async {
        let system = SystemStub()
        let failure = temporaryError
        system.change = { _ in throw failure }
        var finishRetry: CheckedContinuation<Void, Never>?
        system.wait = {
            if system.retryWaits == 1 {
                await withCheckedContinuation { finishRetry = $0 }
            }
        }
        let manager = AppIconManager(client: system.client, entitlements: system.entitlements)
        let first = Task { await manager.setIcon(.default, source: .settings) }
        await system.waitUntilRetryStarts()
        #expect(manager.isChanging)
        #expect(await manager.setIcon(.days10, source: .milestone) == .busy)
        #expect(system.requests.count == 1)
        finishRetry?.resume()
        _ = await first.value
        #expect(system.requests.count == 3)
        #expect(!manager.isChanging)
    }

    @Test
    func foregroundIsRecheckedAfterRetryDelay() async {
        let system = SystemStub()
        let failure = temporaryError
        system.change = { _ in throw failure }
        system.wait = { system.isActive = false }
        let manager = AppIconManager(client: system.client, entitlements: system.entitlements)
        _ = await manager.setIcon(.default)
        #expect(system.requests.count == 1)
        #expect(system.retryWaits == 1)
        #expect(!manager.isChanging)
    }

    @Test
    func systemSuccessWithoutActualChangeIsNotReportedAsSuccess() async {
        let system = SystemStub()
        system.change = { _ in }
        let manager = AppIconManager(client: system.client, entitlements: system.entitlements)
        #expect(!(await manager.setIcon(.default)).succeeded)
        #expect(system.feedbackCount == 0)
        #expect(manager.isCurrent(.halloween))
    }

    @Test
    func cancelledRequestNeverCallsSystem() async {
        let system = SystemStub()
        let manager = AppIconManager(client: system.client, entitlements: system.entitlements)
        let request = Task { await manager.setIcon(.default) }
        request.cancel()
        #expect(await request.value == .cancelled)
        #expect(system.requests.isEmpty)
    }

    @Test
    func cancellingRetryReleasesGate() async {
        let system = SystemStub()
        let failure = temporaryError
        system.change = { _ in throw failure }
        system.wait = { throw CancellationError() }
        let manager = AppIconManager(client: system.client, entitlements: system.entitlements)
        #expect(await manager.setIcon(.default) == .cancelled)
        #expect(system.requests.count == 1)
        #expect(!manager.isChanging)
    }

    @Test
    func expirationRestoreDoesNotLoopButExplicitSwitchStillWorks() async {
        let system = SystemStub()
        system.currentName = "AppIconPremium"
        let failure = temporaryError
        system.change = { _ in throw failure }
        let manager = AppIconManager(client: system.client, entitlements: system.entitlements)
        await manager.restoreDefaultIfPremiumExpired()
        await manager.restoreDefaultIfPremiumExpired()
        await manager.restoreDefaultIfPremiumExpired()
        #expect(system.requests.count == 3)
        system.change = nil
        #expect(await manager.setIcon(.default) == .changed)
        #expect(system.requests.count == 4)
        system.currentName = "AppIconPremium"
        manager.premiumAccessRestored()
        await manager.restoreDefaultIfPremiumExpired()
        #expect(system.requests.count == 5)
        #expect(manager.isCurrent(.default))
    }

    @Test
    func inactiveExpirationRestoreCanWaitForForeground() async {
        let system = SystemStub()
        system.currentName = "AppIconPremium"
        system.isActive = false
        let manager = AppIconManager(client: system.client, entitlements: system.entitlements)
        await manager.restoreDefaultIfPremiumExpired()
        #expect(system.requests.isEmpty)
        system.isActive = true
        await manager.restoreDefaultIfPremiumExpired()
        #expect(system.requests.count == 1)
    }
}
