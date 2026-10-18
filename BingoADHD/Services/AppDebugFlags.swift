import Foundation
import os

enum AppDebugFlags {
    /// Opt-in, same-bundle icon probe. Never available in a shipping build.
    static var appIconProbeEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-DebugAppIconProbe")
#else
        false
#endif
    }

    static var tabGlassTrace: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-DebugTabGlassTrace")
#else
        false
#endif
    }

#if DEBUG
    private static let hasConsumedLimitedOfferStateReset = OSAllocatedUnfairLock(initialState: false)
#endif

    static var forceUpdatePrompt: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ForceUpdatePrompt")
#else
        false
#endif
    }

    static var forceAppReviewPrompt: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-DebugAppReviewPrompt")
#else
        false
#endif
    }

    static var simulateNextDayBoardRuleReset: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-SimulateNextDayBoardRuleReset")
#else
        false
#endif
    }

    static var prepareStreakTest: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-DebugStreakReady")
#else
        false
#endif
    }

    static var showCustomResetToast: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-DebugCustomResetToast")
#else
        false
#endif
    }

    static var forceNoPremiumAccess: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-DebugForceNoPremium")
#else
        false
#endif
    }

    /// The isolated fixture is opt-in. Keeping the production flow as the
    /// Debug default makes an Xcode install and a home-screen relaunch use the
    /// same persisted Blind Box account.
    static var blindBoxPreviewEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-DebugBlindBoxPreview")
#else
        false
#endif
    }

    /// Release and ordinary Debug builds both use the real local-first account.
    static var blindBoxLiveFlowEnabled: Bool {
#if DEBUG
        !blindBoxPreviewEnabled
#else
        true
#endif
    }

    /// Lets the development-only Blind Box preview verify the offline toast
    /// without disabling the simulator's or device's network globally.
    static var blindBoxPreviewForcesOffline: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-DebugBlindBoxOffline")
#else
        false
#endif
    }

    static var tileGestureDebugEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-DebugTileGestures")
#else
        false
#endif
    }

    static var forceBoardEditHint: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-DebugBoardEditHint")
#else
        false
#endif
    }

    static var resetLimitedOfferState: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-DebugResetLimitedOfferState")
#else
        false
#endif
    }

    static var forceLimitedOfferEligible: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-DebugLimitedOfferEligible")
#else
        false
#endif
    }

    static func consumeLimitedOfferStateResetIfNeeded() -> Bool {
#if DEBUG
        guard resetLimitedOfferState else { return false }
        return hasConsumedLimitedOfferStateReset.withLock { consumed in
            guard !consumed else { return false }
            consumed = true
            return true
        }
#else
        return false
#endif
    }
}
