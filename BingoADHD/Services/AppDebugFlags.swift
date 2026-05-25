import Foundation

enum AppDebugFlags {
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
}
