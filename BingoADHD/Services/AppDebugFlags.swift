import Foundation

enum AppDebugFlags {
#if DEBUG
    private static var hasConsumedLimitedOfferStateReset = false
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

    /// Enables the isolated Blind Box fixture flow for visual and interaction
    /// testing. It deliberately never reads or writes production wallet data.
    static var blindBoxPreviewEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-DebugBlindBoxPreview")
#else
        false
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
        guard !hasConsumedLimitedOfferStateReset else { return false }
        hasConsumedLimitedOfferStateReset = true
        return true
#else
        return false
#endif
    }
}
