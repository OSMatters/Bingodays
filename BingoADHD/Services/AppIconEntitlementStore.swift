import Foundation

/// Captured before production services write this launch's onboarding/streak data.
/// Local ownership survives ordinary upgrades; it is not an account entitlement.
@MainActor
final class AppIconEntitlementStore {
    static let storageKey = "app_icon_entitlement_migration_v1"
    static let shared = AppIconEntitlementStore(
        defaults: .standard,
        sharedDefaults: UserDefaults(suiteName: "group.com.bingoday.app")
    )

    private struct State: Codable {
        var schemaVersion = 1
        var ownsHalloween: Bool
        var pendingResetFromHalloween: Bool
    }

    private let defaults: UserDefaults
    private var state: State

    init(defaults: UserDefaults, sharedDefaults: UserDefaults? = nil) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        } else {
            // These keys exist in released builds. Do not use arbitrary defaults:
            // framework preferences and current-launch defaults aren't usage proof.
            let hasUsage = defaults.bool(forKey: "has_seen_onboarding_v2")
                || defaults.data(forKey: "app_open_streak_state_v1") != nil
                || [defaults, sharedDefaults].compactMap { $0 }.contains { store in
                    store.data(forKey: "bingo_board_v1") != nil
                        || store.data(forKey: "bingo_boards_v1") != nil
                }
            state = State(ownsHalloween: hasUsage, pendingResetFromHalloween: hasUsage)
            save()
        }
    }

    var ownsHalloween: Bool { state.ownsHalloween }
    var pendingResetFromHalloween: Bool { state.pendingResetFromHalloween }

    var visibleOptions: [AppIconOption] {
        AppIconOption.allCases.filter { allows($0) }
    }

    func allows(_ option: AppIconOption) -> Bool {
        option != .halloween || ownsHalloween
    }

    func finishReset() {
        state.pendingResetFromHalloween = false
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
