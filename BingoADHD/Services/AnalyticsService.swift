import Foundation
import FirebaseAnalytics
import StoreKit

enum AnalyticsService {
    private static let loggedStoreKitTransactionIDsKey = "analytics.logged_storekit_transaction_ids"

    static func setCollectionEnabled(_ isEnabled: Bool) {
        Analytics.setAnalyticsCollectionEnabled(isEnabled)
    }

    static func bootstrap() {
        syncThemeUserProperty(AppTheme(rawValue: UserDefaults.standard.string(forKey: AppSettings.themeKey) ?? AppTheme.concise.rawValue) ?? .concise)
    }

    static func logStickerRedeemed(_ kind: StickerKind) {
        Analytics.logEvent("sticker_redeemed", parameters: [
            "sticker_id": kind.rawValue,
            "required_points": kind.requiredPoints
        ])
    }

    static func logBingoCompleted(boardSize: Int, completedLineCount: Int, filledTaskCount: Int) {
        Analytics.logEvent("bingo_completed", parameters: [
            "board_size": boardSize,
            "completed_line_count": completedLineCount,
            "filled_task_count": filledTaskCount
        ])
    }

    static func logThemeColorSelected(_ theme: AppTheme) {
        Analytics.logEvent("theme_color_selected", parameters: [
            "theme_color_id": theme.rawValue
        ])
        syncThemeUserProperty(theme)
    }

    static func logPremiumBoardsLimitHit(currentBoardCount: Int) {
        Analytics.logEvent("premium_limit_boards_hit", parameters: [
            "current_board_count": currentBoardCount
        ])
    }

    static func logPremiumTasksGroupsLimitHit(
        source: String,
        taskCount: Int,
        groupCount: Int,
        groupTaskCount: Int
    ) {
        Analytics.logEvent("premium_limit_tasks_groups_hit", parameters: [
            "source": source,
            "task_count": taskCount,
            "group_count": groupCount,
            "group_task_count": groupTaskCount
        ])
    }

    static func logPremiumGrid5x5LimitHit(currentGridSize: Int, source: String) {
        Analytics.logEvent("premium_limit_grid_5x5_hit", parameters: [
            "current_grid_size": currentGridSize,
            "source": source
        ])
    }

    static func logPremiumCustomRewardsLimitHit(currentRewardCount: Int, source: String) {
        Analytics.logEvent("premium_limit_custom_rewards_hit", parameters: [
            "current_reward_count": currentRewardCount,
            "source": source
        ])
    }

    static func logPremiumHistoryLimitHit(visibleHistoryCount: Int, totalHistoryCount: Int, source: String) {
        Analytics.logEvent("premium_limit_history_hit", parameters: [
            "visible_history_count": visibleHistoryCount,
            "total_history_count": totalHistoryCount,
            "source": source
        ])
    }

    static func logPremiumCustomResetTimeLimitHit(source: String) {
        Analytics.logEvent("premium_limit_custom_reset_time_hit", parameters: [
            "source": source
        ])
    }

    static func logPremiumFeaturePurchaseSuccess(
        source: String,
        plan: String,
        productID: String,
        transactionID: String? = nil,
        value: Double? = nil,
        currency: String? = nil
    ) {
        var parameters: [String: Any] = [
            "source": source,
            "plan": plan,
            "product_id": productID
        ]
        if let transactionID {
            parameters["transaction_id"] = transactionID
        }
        if let value {
            parameters["value"] = value
        }
        if let currency {
            parameters["currency"] = currency
        }
        Analytics.logEvent("premium_feature_purchase_success", parameters: parameters)
    }

    static func logPremiumPurchaseSuccess(
        source: String,
        plan: String,
        product: Product,
        transaction: StoreKit.Transaction
    ) {
        guard logStoreKitTransactionIfNeeded(transaction) else { return }
        logPremiumFeaturePurchaseSuccess(
            source: source,
            plan: plan,
            productID: transaction.productID,
            transactionID: String(transaction.id),
            value: NSDecimalNumber(decimal: product.price).doubleValue,
            currency: product.priceFormatStyle.currencyCode
        )
    }

    static func logPremiumTransactionUpdate(source: String, plan: String, transaction: StoreKit.Transaction) {
        guard logStoreKitTransactionIfNeeded(transaction) else { return }
        logPremiumFeaturePurchaseSuccess(
            source: source,
            plan: plan,
            productID: transaction.productID,
            transactionID: String(transaction.id)
        )
    }

    static func logOnboardingCompleted() {
        Analytics.logEvent("onboarding_completed", parameters: nil)
    }

    static func logPremiumPaywallViewed(source: String, isMemberCenter: Bool) {
        Analytics.logEvent("premium_paywall_viewed", parameters: [
            "source": source,
            "is_member_center": isMemberCenter ? 1 : 0
        ])
    }

    static func logPremiumPurchaseAttempt(source: String, plan: String, productID: String) {
        Analytics.logEvent("premium_purchase_attempt", parameters: [
            "source": source,
            "plan": plan,
            "product_id": productID
        ])
    }

    static func logPremiumPurchaseResult(source: String, plan: String, productID: String, result: String) {
        Analytics.logEvent("premium_purchase_result", parameters: [
            "source": source,
            "plan": plan,
            "product_id": productID,
            "result": result
        ])
    }

    static func logTemplateShareOpen(source: String, gridSize: Int, isPremium: Bool) {
        Analytics.logEvent("template_share_open", parameters: [
            "source": source,
            "grid_size": gridSize,
            "is_premium": isPremium ? 1 : 0
        ])
    }

    static func logTemplateShareSaveImageClick(source: String, gridSize: Int, isPremium: Bool) {
        Analytics.logEvent("template_share_save_image_click", parameters: [
            "source": source,
            "grid_size": gridSize,
            "is_premium": isPremium ? 1 : 0
        ])
    }

    static func logTemplateImportPageOpen(source: String, gridSize: Int, createsNewBoard: Bool) {
        Analytics.logEvent("template_import_page_open", parameters: [
            "source": source,
            "grid_size": gridSize,
            "creates_new_board": createsNewBoard ? 1 : 0
        ])
    }

    static func logTemplateImportSuccess(source: String, gridSize: Int, createsNewBoard: Bool) {
        Analytics.logEvent("template_import_success", parameters: [
            "source": source,
            "grid_size": gridSize,
            "creates_new_board": createsNewBoard ? 1 : 0
        ])
    }

    static func syncMyTasksLibrary(_ library: MyTasksLibrary, shouldLogEvent: Bool = true) {
        let taskCount = library.tasks.count
        let groupCount = library.groups.count
        let groupTaskCount = library.groups.reduce(0) { $0 + $1.tasks.count }

        if shouldLogEvent {
            Analytics.logEvent("my_tasks_library_updated", parameters: [
                "task_count": taskCount,
                "group_count": groupCount,
                "group_task_count": groupTaskCount
            ])
        }

        Analytics.setUserProperty(String(taskCount), forName: "my_tasks_count")
        Analytics.setUserProperty(String(groupCount), forName: "my_group_count")
        Analytics.setUserProperty(String(groupTaskCount), forName: "my_group_task_count")
    }

    static func logBB2048SessionStart(themeID: String, gridSize: Int) {
        Analytics.logEvent("bb2048_session_start", parameters: [
            "theme_id": themeID,
            "grid_size": gridSize
        ])
    }

    static func logBB2048SessionEnd(
        themeID: String,
        gridSize: Int,
        durationSeconds: Int,
        finalScore: Int,
        maxTileScore: Int,
        moveCount: Int,
        mergeCount: Int,
        bingoCount: Int
    ) {
        Analytics.logEvent("bb2048_session_end", parameters: [
            "theme_id": themeID,
            "grid_size": gridSize,
            "duration_seconds": max(durationSeconds, 0),
            "final_score": finalScore,
            "max_tile_score": maxTileScore,
            "move_count": moveCount,
            "merge_count": mergeCount,
            "bingo_count": bingoCount
        ])
    }

    static func logBB2048ScoreReached(
        themeID: String,
        gridSize: Int,
        score: Int,
        maxTileScore: Int,
        moveCount: Int,
        mergeCount: Int
    ) {
        Analytics.logEvent("bb2048_score_2048", parameters: [
            "theme_id": themeID,
            "grid_size": gridSize,
            "score": score,
            "max_tile_score": maxTileScore,
            "move_count": moveCount,
            "merge_count": mergeCount
        ])
    }

    private static func syncThemeUserProperty(_ theme: AppTheme) {
        Analytics.setUserProperty(theme.rawValue, forName: "selected_theme_color")
    }

    @discardableResult
    private static func logStoreKitTransactionIfNeeded(_ transaction: StoreKit.Transaction) -> Bool {
        let transactionID = String(transaction.id)
        var loggedIDs = UserDefaults.standard.stringArray(forKey: loggedStoreKitTransactionIDsKey) ?? []
        guard !loggedIDs.contains(transactionID) else { return false }

        Analytics.logTransaction(transaction)
        loggedIDs.append(transactionID)
        if loggedIDs.count > 200 {
            loggedIDs = Array(loggedIDs.suffix(200))
        }
        UserDefaults.standard.set(loggedIDs, forKey: loggedStoreKitTransactionIDsKey)
        return true
    }
}
