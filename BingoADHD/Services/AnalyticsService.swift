import Foundation
import FirebaseAnalytics
import StoreKit

enum PremiumAnalyticsFeature: String {
    case boards
    case tasks
    case groupTasks = "group_tasks"
    case groups
    case tasksGroups = "tasks_groups"
    case grid5x5 = "grid_5x5"
    case customRewards = "custom_rewards"
    case history
    case customResetTime = "custom_reset_time"
    case limitedOffer = "limited_offer"
    case memberCenter = "member_center"
    case other
}

enum CustomRewardVisualAnalyticsAction: String {
    case create
    case update
}

enum NativeICloudAnalyticsOperation: String {
    case enable
    case manualSync = "manual_sync"
    case backgroundPush = "background_push"
}

enum NativeICloudAnalyticsResult: String {
    case success
    case waiting
    case noData = "no_data"
    case failed
}

/// The blind-box feature emits only aggregated, product-level events. In
/// particular, it never sends a draw request UUID, a CloudKit record ID, a
/// sticker image name or an individual ownership history.
enum BlindBoxAnalyticsAction: String {
    case open
    case pointExchange = "point_exchange"
}

enum BlindBoxAnalyticsFailureReason: String {
    case offline
    case connectionChecking = "connection_checking"
    case insufficientTickets = "insufficient_tickets"
    case soldOut = "sold_out"
    case positionAlreadyOpened = "position_already_opened"
    case accountUnavailable = "account_unavailable"
    case accountContention = "account_contention"
    case pointBalance = "point_balance"
    case ticketCap = "ticket_cap"
    case grantDayLimit = "grant_day_limit"
    case requestFailed = "request_failed"
}

struct CustomRewardVisualAnalyticsDescriptor: Equatable {
    let type: String
    let id: String
}

enum AnalyticsEventContract {
    static func customRewardVisual(
        emoji: String,
        themeImageName: String?
    ) -> CustomRewardVisualAnalyticsDescriptor {
        if let themeImageName {
            for themeID in 1...9 where themeImageName == "CustomRewardTheme\(themeID)" {
                return CustomRewardVisualAnalyticsDescriptor(
                    type: "theme",
                    id: "theme_\(themeID)"
                )
            }
            return CustomRewardVisualAnalyticsDescriptor(type: "theme", id: "theme_unknown")
        }

        let firstEmoji = emoji
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .first
            .map(String.init) ?? ""
        let normalizedEmoji = firstEmoji
            .replacingOccurrences(of: "\u{FE0E}", with: "")
            .replacingOccurrences(of: "\u{FE0F}", with: "")
        let knownEmojiIDs = [
            "😊": "emoji_smiling_face",
            "🎁": "emoji_gift",
            "⭐": "emoji_star",
            "🏆": "emoji_trophy",
            "🎉": "emoji_party_popper",
            "🍰": "emoji_cake"
        ]
        return CustomRewardVisualAnalyticsDescriptor(
            type: "emoji",
            id: knownEmojiIDs[normalizedEmoji] ?? "emoji_custom"
        )
    }

    static func premiumTasksGroupsFeature(forSource source: String) -> PremiumAnalyticsFeature {
        let normalizedSource = source.lowercased()
        if normalizedSource.contains("group_task") {
            return .groupTasks
        }
        if normalizedSource.contains("standalone_task") || normalizedSource.contains("task_limit") {
            return .tasks
        }
        if normalizedSource.contains("group_limit") {
            return .groups
        }
        return .tasksGroups
    }

    static func premiumFeature(forSource source: String) -> PremiumAnalyticsFeature {
        let normalizedSource = source.lowercased()
        if normalizedSource.contains("limited_offer") {
            return .limitedOffer
        }
        if normalizedSource.contains("reset") {
            return .customResetTime
        }
        if normalizedSource.contains("custom_reward") || normalizedSource.contains("reward") {
            return .customRewards
        }
        if normalizedSource.contains("history") {
            return .history
        }
        if normalizedSource.contains("grid") || normalizedSource.contains("5x5") {
            return .grid5x5
        }
        if normalizedSource.contains("group_task") {
            return .groupTasks
        }
        if normalizedSource.contains("standalone_task") || normalizedSource.contains("task_limit") {
            return .tasks
        }
        if normalizedSource.contains("group_limit") {
            return .groups
        }
        if normalizedSource.contains("boards_limit") {
            return .boards
        }
        if normalizedSource.contains("member_center") || normalizedSource.contains("me_pro") {
            return .memberCenter
        }
        if normalizedSource.contains("quick_edit") {
            return .tasksGroups
        }
        return .other
    }
}

enum AnalyticsService {
    private static let loggedStoreKitTransactionIDsKey = "analytics.logged_storekit_transaction_ids"
    private static let offerBannerViewLock = NSLock()
    private static var viewedOfferBannerCampaignIDs = Set<String>()

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

    static func logBlindBoxLobbyViewed(
        ticketBalance: Int,
        candidateCount: Int,
        hasPremiumAccess: Bool
    ) {
        logCustomEvent("blind_box_lobby_viewed", parameters: [
            "ticket_balance": max(ticketBalance, 0),
            "candidate_count": max(candidateCount, 0),
            "is_premium": hasPremiumAccess ? 1 : 0
        ])
    }

    static func logBlindBoxBatchViewed(_ batch: BlindBoxCandidateBatch) {
        logCustomEvent("blind_box_batch_viewed", parameters: [
            "theme_id": sanitizedBlindBoxThemeID(batch.plan.themeID.rawValue),
            "catalog_version": batch.plan.catalogVersion,
            "remaining_positions": batch.remainingPositionCount,
            "probability_mode": batch.plan.probabilityMode.rawValue
        ])
    }

    static func logBlindBoxCollectionViewed(themeCount: Int, ownedStickerTypeCount: Int) {
        logCustomEvent("blind_box_collection_viewed", parameters: [
            "theme_count": max(themeCount, 0),
            "owned_sticker_type_count": max(ownedStickerTypeCount, 0)
        ])
    }

    static func logBlindBoxRulesViewed() {
        logCustomEvent("blind_box_rules_viewed", parameters: [:])
    }

    static func logBlindBoxOpened(
        request: BlindBoxDrawRequest,
        result: BlindBoxOpenResult,
        theme: BlindBoxThemeDefinition,
        probabilityMode: BlindBoxProbabilityMode,
        didCompleteTheme: Bool
    ) {
        let hiddenStickerID = theme.hiddenSticker?.id
        let hiddenCount = result.openedStickers.reduce(into: 0) { count, openedSticker in
            if openedSticker.stickerID == hiddenStickerID {
                count += 1
            }
        }
        let duplicateCount = result.openedStickers.filter(\.isDuplicate).count

        logCustomEvent("blind_box_opened", parameters: [
            "theme_id": sanitizedBlindBoxThemeID(theme.id.rawValue),
            "catalog_version": theme.catalogVersion,
            "draw_mode": request.mode.rawValue,
            "probability_mode": probabilityMode.rawValue,
            "opened_sticker_count": result.openedStickers.count,
            "duplicate_sticker_count": duplicateCount,
            "hidden_sticker_count": hiddenCount,
            "ticket_cost": result.ticketCost,
            "ticket_balance_after": result.resultingTicketBalance,
            "theme_completed": didCompleteTheme ? 1 : 0
        ])
    }

    static func logBlindBoxPointTicketExchanged(result: BlindBoxPointExchangeResult) {
        logCustomEvent("blind_box_point_ticket_exchanged", parameters: [
            "point_cost": result.deductedPoints,
            "ticket_count": result.grantedTickets,
            "ticket_balance_after": result.resultingTicketBalance
        ])
    }

    static func logBlindBoxActionFailed(
        action: BlindBoxAnalyticsAction,
        reason: BlindBoxAnalyticsFailureReason
    ) {
        logCustomEvent("blind_box_action_failed", parameters: [
            "action": action.rawValue,
            "reason": reason.rawValue
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

    static func logCustomRewardVisualUsed(
        action: CustomRewardVisualAnalyticsAction,
        emoji: String,
        themeImageName: String?
    ) {
        let visual = AnalyticsEventContract.customRewardVisual(
            emoji: emoji,
            themeImageName: themeImageName
        )
        logCustomEvent("custom_reward_visual_used", parameters: [
            "action": action.rawValue,
            "visual_type": visual.type,
            "visual_id": visual.id
        ])
    }

    static func logOfferBannerViewed(campaignID: String, countdownStarted: Bool) {
        let campaignID = sanitizedCampaignID(campaignID)
        offerBannerViewLock.lock()
        let isFirstViewThisSession = viewedOfferBannerCampaignIDs.insert(campaignID).inserted
        offerBannerViewLock.unlock()
        guard isFirstViewThisSession else { return }

        logCustomEvent("offer_banner_viewed", parameters: [
            "campaign_id": campaignID,
            "countdown_started": countdownStarted ? 1 : 0
        ])
    }

    static func logOfferBannerClicked(campaignID: String, countdownStarted: Bool) {
        logCustomEvent("offer_banner_clicked", parameters: [
            "campaign_id": sanitizedCampaignID(campaignID),
            "countdown_started": countdownStarted ? 1 : 0
        ])
    }

    static func logICloudSyncToggled(isEnabled: Bool) {
        let enabledValue = isEnabled ? "true" : "false"
        Analytics.setUserProperty(enabledValue, forName: "icloud_sync_enabled")
        logCustomEvent("icloud_sync_toggled", parameters: [
            "enabled": isEnabled ? 1 : 0
        ])
    }

    static func logICloudSyncResult(
        operation: NativeICloudAnalyticsOperation,
        result: NativeICloudAnalyticsResult,
        failureStage: String? = nil
    ) {
        var parameters: [String: Any] = [
            "operation": operation.rawValue,
            "result": result.rawValue
        ]
        if let failureStage {
            parameters["failure_stage"] = failureStage
        }
        logCustomEvent("icloud_sync_result", parameters: parameters)
    }

    static func logPremiumRestoreStarted() {
        logCustomEvent("premium_restore_started", parameters: [:])
    }

    static func logPremiumRestoreResult(_ result: String) {
        logCustomEvent("premium_restore_result", parameters: ["result": result])
    }

    static func logPremiumBoardsLimitHit(currentBoardCount: Int, source: String) {
        Analytics.logEvent("premium_limit_boards_hit", parameters: [
            "current_board_count": currentBoardCount,
            "source": source
        ])
        logPremiumGateTriggered(feature: .boards, source: source)
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
        logPremiumGateTriggered(
            feature: AnalyticsEventContract.premiumTasksGroupsFeature(forSource: source),
            source: source
        )
    }

    static func logPremiumGrid5x5LimitHit(currentGridSize: Int, source: String) {
        Analytics.logEvent("premium_limit_grid_5x5_hit", parameters: [
            "current_grid_size": currentGridSize,
            "source": source
        ])
        logPremiumGateTriggered(feature: .grid5x5, source: source)
    }

    static func logPremiumCustomRewardsLimitHit(currentRewardCount: Int, source: String) {
        Analytics.logEvent("premium_limit_custom_rewards_hit", parameters: [
            "current_reward_count": currentRewardCount,
            "source": source
        ])
        logPremiumGateTriggered(feature: .customRewards, source: source)
    }

    static func logPremiumHistoryLimitHit(visibleHistoryCount: Int, totalHistoryCount: Int, source: String) {
        Analytics.logEvent("premium_limit_history_hit", parameters: [
            "visible_history_count": visibleHistoryCount,
            "total_history_count": totalHistoryCount,
            "source": source
        ])
        logPremiumGateTriggered(feature: .history, source: source)
    }

    static func logPremiumCustomResetTimeLimitHit(source: String) {
        Analytics.logEvent("premium_limit_custom_reset_time_hit", parameters: [
            "source": source
        ])
        logPremiumGateTriggered(feature: .customResetTime, source: source)
    }

    private static func logPremiumGateTriggered(feature: PremiumAnalyticsFeature, source: String) {
        logCustomEvent("premium_gate_triggered", parameters: [
            "feature": feature.rawValue,
            "source": source
        ])
    }

    static func logPremiumFeaturePurchaseSuccess(
        source: String,
        plan: String,
        productID: String,
        transactionID: String? = nil,
        purchaseAttemptID: String? = nil,
        attributionAgeSeconds: Int? = nil,
        value: Double? = nil,
        currency: String? = nil
    ) {
        var parameters: [String: Any] = [
            "source": source,
            "feature": AnalyticsEventContract.premiumFeature(forSource: source).rawValue,
            "plan": plan,
            "product_id": productID
        ]
        if let transactionID {
            parameters["transaction_id"] = transactionID
        }
        if let purchaseAttemptID {
            parameters["purchase_attempt_id"] = purchaseAttemptID
        }
        if let attributionAgeSeconds {
            parameters["attribution_age_seconds"] = attributionAgeSeconds
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
        transaction: StoreKit.Transaction,
        purchaseAttemptID: String? = nil,
        attributionAgeSeconds: Int? = nil
    ) {
        guard logStoreKitTransactionIfNeeded(transaction) else { return }
        logPremiumFeaturePurchaseSuccess(
            source: source,
            plan: plan,
            productID: transaction.productID,
            transactionID: String(transaction.id),
            purchaseAttemptID: purchaseAttemptID,
            attributionAgeSeconds: attributionAgeSeconds,
            value: NSDecimalNumber(decimal: product.price).doubleValue,
            currency: product.priceFormatStyle.currencyCode
        )
    }

    static func logPremiumTransactionUpdate(
        source: String,
        plan: String,
        transaction: StoreKit.Transaction,
        purchaseAttemptID: String? = nil,
        attributionAgeSeconds: Int? = nil
    ) {
        guard logStoreKitTransactionIfNeeded(transaction) else { return }
        logPremiumFeaturePurchaseSuccess(
            source: source,
            plan: plan,
            productID: transaction.productID,
            transactionID: String(transaction.id),
            purchaseAttemptID: purchaseAttemptID,
            attributionAgeSeconds: attributionAgeSeconds
        )
    }

    static func logOnboardingCompleted() {
        Analytics.logEvent("onboarding_completed", parameters: nil)
    }

    static func logPremiumPaywallViewed(source: String, isMemberCenter: Bool) {
        Analytics.logEvent("premium_paywall_viewed", parameters: [
            "source": source,
            "feature": AnalyticsEventContract.premiumFeature(forSource: source).rawValue,
            "is_member_center": isMemberCenter ? 1 : 0
        ])
    }

    static func logPremiumPurchaseAttempt(
        source: String,
        plan: String,
        productID: String,
        purchaseAttemptID: String? = nil
    ) {
        var parameters: [String: Any] = [
            "source": source,
            "feature": AnalyticsEventContract.premiumFeature(forSource: source).rawValue,
            "plan": plan,
            "product_id": productID
        ]
        if let purchaseAttemptID {
            parameters["purchase_attempt_id"] = purchaseAttemptID
        }
        Analytics.logEvent("premium_purchase_attempt", parameters: parameters)
    }

    static func logPremiumPurchaseResult(
        source: String,
        plan: String,
        productID: String,
        result: String,
        purchaseAttemptID: String? = nil,
        attributionAgeSeconds: Int? = nil
    ) {
        var parameters: [String: Any] = [
            "source": source,
            "feature": AnalyticsEventContract.premiumFeature(forSource: source).rawValue,
            "plan": plan,
            "product_id": productID,
            "result": result
        ]
        if let purchaseAttemptID {
            parameters["purchase_attempt_id"] = purchaseAttemptID
        }
        if let attributionAgeSeconds {
            parameters["attribution_age_seconds"] = attributionAgeSeconds
        }
        Analytics.logEvent("premium_purchase_result", parameters: parameters)
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

    private static func syncThemeUserProperty(_ theme: AppTheme) {
        Analytics.setUserProperty(theme.rawValue, forName: "selected_theme_color")
    }

    private static func sanitizedCampaignID(_ campaignID: String) -> String {
        let trimmed = campaignID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : String(trimmed.prefix(100))
    }

    private static func sanitizedBlindBoxThemeID(_ themeID: String) -> String {
        let trimmed = themeID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : String(trimmed.prefix(100))
    }

    private static func logCustomEvent(_ name: String, parameters: [String: Any]) {
#if DEBUG
        let summary = parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        print("[Analytics] \(name) \(summary)")
#endif
        Analytics.logEvent(name, parameters: parameters)
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
