import Foundation
import CoreHaptics
import UIKit

enum AppLanguage {
    case english
    case simplifiedChinese
    case traditionalChinese
    case japanese

    static var current: AppLanguage {
        let regionCode = currentRegionCode
        if regionCode == "HK" {
            return .english
        }
        if regionCode == "TW" {
            return .traditionalChinese
        }

        if let primaryLanguage = preferredLanguageIdentifiers.first?.lowercased() {
            if primaryLanguage.hasPrefix("zh") {
                if primaryLanguage.contains("hant") || primaryLanguage.contains("tw") {
                    return .traditionalChinese
                }
                return .simplifiedChinese
            }

            if primaryLanguage.hasPrefix("ja") {
                return .japanese
            }
        }

        if hasTaiwanLanguageHint {
            return .traditionalChinese
        }

        return .english
    }

    private static var preferredLanguageIdentifiers: [String] {
        let appleLanguages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String] ?? []
        let preferredLanguages = Locale.preferredLanguages
        let localeIdentifiers = [
            Locale.autoupdatingCurrent.identifier,
            Locale.current.identifier
        ]

        return (appleLanguages + preferredLanguages + localeIdentifiers)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static var currentRegionCode: String {
        let candidates: [String] = [
            Locale.autoupdatingCurrent.region?.identifier,
            Locale.current.region?.identifier
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        return candidates.first?.uppercased() ?? "US"
    }

    static var hasTaiwanLanguageHint: Bool {
        preferredLanguageIdentifiers
            .map { $0.lowercased() }
            .contains { identifier in
                identifier.contains("-tw") || identifier.contains("_tw") || identifier.hasSuffix("tw")
            }
    }


    static var displayLocale: Locale {
        switch current {
        case .english:
            return Locale(identifier: "en_US")
        case .simplifiedChinese:
            return Locale(identifier: "zh_Hans_CN")
        case .traditionalChinese:
            return Locale(identifier: "zh_Hant_TW")
        case .japanese:
            return Locale(identifier: "ja_JP")
        }
    }

    static var speechLocaleIdentifier: String {
        switch current {
        case .english:
            return "en-US"
        case .simplifiedChinese:
            return "zh-Hans"
        case .traditionalChinese:
            return "zh-Hant"
        case .japanese:
            return "ja-JP"
        }
    }
}

enum L10n {
    static func tr(_ english: String, zhHans: String, zhHant: String? = nil) -> String {
        switch AppLanguage.current {
        case .english:
            return english
        case .simplifiedChinese:
            return zhHans
        case .traditionalChinese:
            if let zhHant {
                return zhHant
            }
            return zhHans.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? zhHans
        case .japanese:
            return english
        }
    }

    static var widgetCountdownName: String { tr("Bingodays Countdown", zhHans: "Bingodays 倒计时") }
    static var widgetCountdownDescription: String { tr("Track your Bingo board countdown at a glance.", zhHans: "快速查看 Bingo 面板倒计时。") }
    static var widgetBoardName: String { tr("Bingodays Board", zhHans: "Bingodays 面板") }
    static var widgetBoardDescription: String { tr("See your current bingo board with the same card states as the app.", zhHans: "查看与 App 内状态同步的 Bingo 面板。") }
    static var dontForget: String { tr("DON'T FORGET!", zhHans: "别忘了任务！") }
    static var doTask: String { tr("do task", zhHans: "去完成任务") }
    static var noTimer: String { tr("No Timer", zhHans: "未设置倒计时") }
    static var totalDays: String { tr("Total Days", zhHans: "使用天数") }
    static var streakDays: String { tr("Streak Days", zhHans: "连胜天数") }
    static var bingoCount: String { tr("Bingo Count", zhHans: "完成任务") }
    static var countdownEndedTitle: String { tr("Task Countdown Ended", zhHans: "倒计时结束") }
    static var newDayResetMessage: String { tr("A new day started. Yesterday's completion states were reset, and your points were kept.", zhHans: "新的一天已开始，昨日完成状态已重置，积分已保留。") }
    static var ok: String { tr("OK", zhHans: "好的") }
    static var setBoardCountdown: String { tr("Countdown", zhHans: "倒计时") }
    static var myTasks: String { tr("My Tasks", zhHans: "我的任务") }
    static var bingoDiary: String { tr("Bingo Diary", zhHans: "Bingo 日记") }
    static var setting: String { tr("Setting", zhHans: "设置") }
    static var subscription: String { tr("Subscription", zhHans: "订阅", zhHant: "訂閱") }
    static var subscriptionStatusActive: String { tr("Premium active", zhHans: "已开通会员", zhHant: "已開通會員") }
    static var subscriptionStatusInactive: String { tr("Not subscribed", zhHans: "未订阅", zhHant: "未訂閱") }
    static var subscriptionMonthly: String { tr("Monthly", zhHans: "月订阅", zhHant: "月訂閱") }
    static var subscriptionYearly: String { tr("Yearly", zhHans: "年订阅", zhHant: "年訂閱") }
    static var subscriptionLifetime: String { tr("Lifetime", zhHans: "终身", zhHant: "終身") }
    static var subscriptionRestore: String { tr("Restore", zhHans: "恢复购买", zhHant: "恢復購買") }
    static var subscriptionRestoreSubscription: String { tr("Restore Subscription", zhHans: "恢复订阅", zhHant: "恢復訂閱") }
    static var subscriptionManage: String { tr("Manage", zhHans: "管理订阅", zhHant: "管理訂閱") }
    static var proEntryTitle: String { tr("Get Pro", zhHans: "开通Pro", zhHant: "開通Pro") }
    static var proEntrySubtitle: String { tr("Unlock more Pro features", zhHans: "解锁更多 Pro 功能", zhHant: "解鎖更多 Pro 功能") }
    static var proEntryMemberTitle: String { tr("Pro Member", zhHans: "Pro 会员", zhHant: "Pro 會員") }
    static var proEntryMemberSubtitle: String { tr("Enjoying Pro features", zhHans: "畅享 Pro 功能", zhHant: "暢享 Pro 功能") }
    static var proPaywallHeadline: String { tr("Choose your plan", zhHans: "选择你的订阅方案", zhHant: "選擇你的訂閱方案") }
    static var subscriptionPleaseWait: String { tr("Please wait...", zhHans: "请稍候...", zhHant: "請稍候...") }
    static var subscriptionProductUnavailable: String { tr("Product is unavailable.", zhHans: "商品暂不可用。", zhHant: "商品暫不可用。") }
    static var subscriptionVerificationFailed: String { tr("Verification failed.", zhHans: "购买校验失败。", zhHant: "購買校驗失敗。") }
    static var subscriptionPurchaseSucceeded: String { tr("Purchase successful.", zhHans: "购买成功。", zhHant: "購買成功。") }
    static var subscriptionPurchasePending: String { tr("Purchase is pending approval.", zhHans: "购买待确认。", zhHant: "購買待確認。") }
    static var subscriptionPurchaseCancelled: String { tr("Purchase cancelled.", zhHans: "已取消购买。", zhHant: "已取消購買。") }
    static var subscriptionUnknownResult: String { tr("Unknown purchase result.", zhHans: "未知购买结果。", zhHant: "未知購買結果。") }
    static var subscriptionPurchaseFailed: String { tr("Purchase failed. Please try again.", zhHans: "购买失败，请稍后重试。", zhHant: "購買失敗，請稍後重試。") }
    static var subscriptionRestoreSucceeded: String { tr("Restored successfully.", zhHans: "恢复购买成功。", zhHant: "恢復購買成功。") }
    static var subscriptionNotFound: String { tr("No purchase found to restore.", zhHans: "未找到可恢复的购买。", zhHant: "未找到可恢復的購買。") }
    static var subscriptionRestoreFailed: String { tr("Restore failed. Please try again.", zhHans: "恢复购买失败，请稍后重试。", zhHant: "恢復購買失敗，請稍後重試。") }
    static var subscriptionManageFailed: String { tr("Unable to open subscription settings.", zhHans: "暂时无法打开订阅管理。", zhHant: "暫時無法打開訂閱管理。") }
    static var paywallUnlockProFeatures: String { tr("Unlock Pro features", zhHans: "解锁 Pro 功能", zhHant: "解鎖 Pro 功能") }
    static var paywallUnlimitedBoards: String { tr("Unlimited Bingo boards", zhHans: "无限创建 Bingo 棋盘", zhHant: "無限建立 Bingo 棋盤") }
    static var paywallUnlimitedQuickTasksAndGroups: String { tr("Unlimited quick tasks and groups", zhHans: "无限创建快捷任务和分组", zhHant: "無限建立快捷任務與分組") }
    static var paywallUnlimitedThemesAndCustomization: String { tr("Unlimited themes and customization", zhHans: "无限主题与自定义", zhHant: "無限主題與自訂") }
    static var paywallSubscribeNow: String { tr("Subscribe Now", zhHans: "立即订阅", zhHant: "立即訂閱") }
    static var paywallPopular: String { tr("Popular", zhHans: "热门", zhHant: "熱門") }
    static var paywallOneMonth: String { tr("1 Month", zhHans: "1个月", zhHant: "1個月") }
    static var paywallOneYear: String { tr("1 Year", zhHans: "1年", zhHant: "1年") }
    static var paywallLifetime: String { tr("Lifetime", zhHans: "终身", zhHant: "終身") }
    static var paywallOneTimePayment: String { tr("One-time payment", zhHans: "一次性付款", zhHant: "一次性付款") }
    static var paywallLegalPrefix: String { tr("By continuing, you agree to our", zhHans: "继续即表示你同意我们的", zhHant: "繼續即表示你同意我們的") }
    static var paywallLegalAnd: String { tr("and", zhHans: "和", zhHant: "和") }
    static var paywallTermsOfUse: String { tr("Terms of Use", zhHans: "使用条款", zhHant: "使用條款") }
    static var paywallPrivacyPolicy: String { tr("Privacy Policy", zhHans: "隐私政策", zhHant: "隱私政策") }
    static var paywallLegalOneLine: String { tr("By continuing, you agree to Terms of Use and Privacy Policy.", zhHans: "继续即表示你同意《使用条款》和《隐私政策》。", zhHant: "繼續即表示你同意《使用條款》和《隱私政策》。") }
    static func paywallPerMonth(_ value: String) -> String {
        tr("\(value) / month", zhHans: "\(value) / 月", zhHant: "\(value) / 月")
    }
    static var haptics: String { tr("Haptics", zhHans: "震动反馈") }
    static var soundEffects: String { tr("Sound Effects", zhHans: "音效") }
    static var homeWidget: String { tr("Home Widget", zhHans: "桌面小组件") }
    static var homeWidgetInstructions: String {
        tr(
            "To add a widget: long-press the Home Screen, tap Edit or +, search Bingodays, then choose a size and tap Add Widget.",
            zhHans: "添加小组件：长按主屏幕，点击编辑或 +，搜索 Bingodays，然后选择尺寸并点击添加小组件。"
        )
    }
    static var dayStreak: String { tr("day streak", zhHans: "连胜天数") }
    static var streakGoals: String { tr("Streak Goals", zhHans: "连胜目标") }
    static var themeColor: String { tr("Theme Color", zhHans: "主题颜色") }
    static var myPoints: String { tr("My Points", zhHans: "我的积分") }
    static var stickers: String { tr("Stickers", zhHans: "贴纸") }
    static var myRewards: String { tr("Custom Rewards", zhHans: "自定义奖励") }
    static var addReward: String { tr("Add Reward", zhHans: "添加奖励") }
    static var editReward: String { tr("Edit Reward", zhHans: "编辑奖励") }
    static var rewardTitle: String { tr("Reward Title", zhHans: "奖励名称") }
    static var rewardPoints: String { tr("Required Points", zhHans: "所需积分") }
    static var rewardExampleHint: String { tr("Example: Milk Tea", zhHans: "例如：喝一杯奶茶") }
    static var rewardPointsHint: String { tr("Example: 50", zhHans: "例如：50") }
    static var noRewardsYet: String { tr("Create your own rewards and redeem them with points.", zhHans: "创建你自己的奖励，并用积分进行兑换。") }
    static var rewardRedeemed: String { tr("Redeemed", zhHans: "已兑换") }
    static func redeemedCount(_ count: Int) -> String {
        tr("Redeemed x\(count)", zhHans: "已兑换 x\(count)")
    }
    static var done: String { tr("Done", zhHans: "完成") }
    static var addToHome: String { tr("Add to Home", zhHans: "添加到首页") }
    static var redeem: String { tr("Redeem", zhHans: "兑换") }
    static var onHome: String { tr("On Home", zhHans: "已在首页") }
    static func ownedCount(_ count: Int) -> String {
        tr("Owned x\(count)", zhHans: "已拥有 x\(count)")
    }
    static var tasks: String { tr("Tasks", zhHans: "任务") }
    static var groups: String { tr("Groups", zhHans: "分组") }
    static var myTasksHint: String { tr("Edit tasks and groups here, choose what to use, then tap Save to apply to the board.", zhHans: "在这里编辑任务和分组，勾选要使用的内容，点左上角保存应用到棋盘。") }
    static var tasksSectionHint: String { tr("Save the quick tasks you use most often.", zhHans: "保存你最常用的快捷任务。") }
    static var groupsSectionHint: String { tr("Bundle a few tasks together so you can apply them in one tap.", zhHans: "把多个任务打包成分组，方便一键应用。") }
    static var noTasksYet: String { tr("You haven't added any tasks yet.", zhHans: "你还没有添加任何任务。") }
    static var noGroupsYet: String { tr("You haven't added any groups yet.", zhHans: "你还没有添加任何分组。") }
    static var addTask: String { tr("Add Task", zhHans: "添加任务") }
    static var addGroup: String { tr("Add Group", zhHans: "添加分组") }
    static var quickEdit: String { tr("Quick Edit", zhHans: "快速编辑") }
    static var blackBoxMode: String { tr("Black Box Mode", zhHans: "黑盒模式", zhHant: "黑盒模式") }
    static var blackBoxModeDescription: String {
        tr(
            "2048 x themed tasks mode is now available on this branch. Select a theme, complete tasks, and merge completed tiles into Bingo progress.",
            zhHans: "2048 x 主题任务模式已在这个分支开启。选择主题、完成任务，并把已完成格子合并成 Bingo 进度。",
            zhHant: "2048 x 主題任務模式已在這個分支開啟。選擇主題、完成任務，並把已完成格子合併成 Bingo 進度。"
        )
    }
    static var blackBoxModeFeatureTheme: String {
        tr("Generate random tasks by theme.", zhHans: "按主题生成随机任务。", zhHant: "按主題生成隨機任務。")
    }
    static var blackBoxModeFeatureMerge: String {
        tr("Merge completed tiles with 2048 rules.", zhHans: "按 2048 规则合并已完成格子。", zhHant: "按 2048 規則合併已完成格子。")
    }
    static var blackBoxModeFeatureBingo: String {
        tr("Progressively build Bingo milestones.", zhHans: "逐步构建 Bingo 里程碑。", zhHant: "逐步建立 Bingo 里程碑。")
    }
    static var blackBoxModeStart: String { tr("Start", zhHans: "开始", zhHant: "開始") }
    static var blackBoxModeHowToTitle: String { tr("How to Play", zhHans: "玩法说明", zhHant: "玩法說明") }
    static var blackBoxModeThemeTitle: String { tr("Theme", zhHans: "主题", zhHant: "主題") }
    static var blackBoxModeGridSizeTitle: String { tr("Grid", zhHans: "棋盘", zhHant: "棋盤") }
    static var blackBoxModeTapHint: String {
        tr("Tap a tile to mark task completed.", zhHans: "点击任务格可切换完成状态。", zhHant: "點擊任務格可切換完成狀態。")
    }
    static var blackBoxModeSwipeHint: String {
        tr("Swipe to move and merge completed tiles.", zhHans: "滑动棋盘可移动并合并已完成任务格。", zhHant: "滑動棋盤可移動並合併已完成任務格。")
    }
    static var blackBoxModeRestart: String { tr("Restart", zhHans: "重开", zhHant: "重開") }
    static var blackBoxModeBackToIntro: String { tr("Intro", zhHans: "简介", zhHant: "簡介") }
    static var blackBoxModeMoves: String { tr("Moves", zhHans: "步数", zhHant: "步數") }
    static var blackBoxModeMerges: String { tr("Merges", zhHans: "合并", zhHant: "合併") }
    static var blackBoxModeBingos: String { tr("Bingos", zhHans: "Bingo", zhHant: "Bingo") }
    static var blackBoxModeGameOver: String { tr("No more moves", zhHans: "无可用移动", zhHant: "無可用移動") }
    static var blackBoxModeHealthTheme: String { tr("Healthy Life", zhHans: "健康生活", zhHant: "健康生活") }
    static var blackBoxModeFocusTheme: String { tr("Focus Sprint", zhHans: "专注冲刺", zhHant: "專注衝刺") }
    static var blackBoxModeHomeTheme: String { tr("Home Reset", zhHans: "居家整理", zhHant: "居家整理") }
    static var blackBoxModeTileDetailTitle: String { tr("Tile Details", zhHans: "格子详情", zhHant: "格子詳情") }
    static var blackBoxModeContainsTasks: String { tr("Contains", zhHans: "包含任务", zhHant: "包含任務") }
    static var blackBoxModeCompletionCount: String { tr("Completion Count", zhHans: "完成次数", zhHant: "完成次數") }
    static var blackBoxModeTotalCompletions: String { tr("Total", zhHans: "总计", zhHant: "總計") }
    static func blackBoxModeTileScore(_ score: Int) -> String {
        tr("\(score) pts", zhHans: "\(score)分", zhHant: "\(score)分")
    }
    static func blackBoxModeThemeScore(themeTitle: String, score: Int) -> String {
        tr("\(themeTitle) \(score) pts", zhHans: "\(themeTitle)\(score)分", zhHant: "\(themeTitle)\(score)分")
    }
    static var updateWhatsNewTitle: String { tr("What's New", zhHans: "版本更新") }
    static func updateVersionTitle(_ version: String) -> String {
        tr("Bingodays \(version)", zhHans: "Bingodays \(version)")
    }
    static var updateItemUIRefined: String {
        tr("UI / UX improvements for easier task editing", zhHans: "UI / UX优化，更好地编辑任务", zhHant: "UI / UX 優化，更好地編輯任務")
    }
    static var updateItemBugFixes: String {
        tr("Added product onboarding pages", zhHans: "新增产品Onbording介绍页", zhHant: "新增產品 Onbording 介紹頁")
    }
    static var updatePrimaryAction: String { tr("Update Now", zhHans: "去更新") }
    static var updateSecondaryAction: String { tr("Later", zhHans: "稍后") }
    static var updateStoreOpenFailed: String {
        tr("Unable to open App Store right now.", zhHans: "暂时无法打开 App Store。")
    }
    static var onboardingMadeForADHDBrains: String { tr("Made for ADHD brains", zhHans: "Made for ADHD brains") }
    static var onboardingIntroHeadline: String { tr("Turn Daily\nLife into", zhHans: "将日常生活\n变成") }
    static var onboardingGetStarted: String { tr("Get Started", zhHans: "开始") }
    static var onboardingExistingAccount: String { tr("I already have an account", zhHans: "我已经有账号") }
    static var onboardingFooterPrefix: String { tr("By continuing you're accepting our ", zhHans: "继续即表示你同意我们的") }
    static var onboardingTermsOfService: String { tr("Terms of Service", zhHans: "服务条款") }
    static var onboardingAnd: String { tr(" and", zhHans: "和") }
    static var onboardingPrivacyPolicy: String { tr("Privacy Policy", zhHans: "隐私政策") }
    static var onboardingResearchHeadline: String { tr("Well\naccording\nto the\nresearch", zhHans: "根据一直以来\n的研究表明") }
    static var onboardingResearchBody: String {
        tr("Traditional to do list doesn't work especially\nwith ADHD", zhHans: "传统的To Do List并不适合ADHD人群")
    }
    static var onboardingNext: String { tr("Next", zhHans: "继续") }
    static var onboardingBrandHeadline: String { tr("That's\nwhy you\nshould try", zhHans: "所以我们向\n你推荐") }
    static var onboardingStressFree: String { tr("Stress-free", zhHans: "Stress-free") }
    static var onboardingSimplified: String { tr("Simplified", zhHans: "Simplified") }
    static var onboardingGridHeadline: String { tr("Turn your\nto-do list\ninto a Bingo\nboard", zhHans: "把待办清单\n变为Bingo格子") }
    static var onboardingPaceHeadline: String { tr("Complete\nTasks at\nYour Own\nPace", zhHans: "用自己的专\n属节奏打卡\n任务") }
    static var onboardingBestMode: String { tr("Best Mode", zhHans: "Best Mode") }
    static var onboardingPersonalized: String { tr("- Personalized -", zhHans: "- Personalized -") }
    static var onboardingRewardsHeadline: String { tr("Make Every\nDay a Bingo", zhHans: "把每一天都\n变成Bingo") }
    static var onboardingRewardsSubtitle: String {
        tr("Earn points and redeem your own rewards", zhHans: "积分兑换奖励，更有动力继续")
    }
    static var onboardingLetsBingo: String { tr("Let's Bingo", zhHans: "Let's Bingo") }
    static var onboardingLoginWelcomeTo: String { tr("Welcome to", zhHans: "Welcome to") }
    static var onboardingContinueWithApple: String { tr("Continue with Apple", zhHans: "使用苹果登录") }
    static var onboardingContinueWithGoogle: String { tr("Continue with Google", zhHans: "使用Google登录") }
    static var apply: String { tr("Apply", zhHans: "应用") }
    static var selectAll: String { tr("Select All", zhHans: "全选") }
    static var deselectAll: String { tr("Deselect All", zhHans: "全取消") }
    static var random: String { tr("Random", zhHans: "随机") }
    static var gridSize: String { tr("Grid Size", zhHans: "格子大小") }
    static func selectedTaskCount(_ count: Int, usedCount: Int) -> String {
        tr("Selected \(count) (\(usedCount) used for current board)", zhHans: "已选 \(count) 个（当前尺寸使用前 \(usedCount) 个）")
    }
    static func quickEditSelectionSummary(selected: Int, missing: Int) -> String {
        if missing > 0 {
            return tr("Selected \(selected), need \(missing)", zhHans: "已选\(selected)，差\(missing)")
        }
        return tr("Selected \(selected), full", zhHans: "已选\(selected)，已满")
    }
    static func quickEditAppliedSuccess(_ count: Int) -> String {
        tr("Applied \(count) tasks", zhHans: "已应用 \(count) 个任务")
    }
    static var quickEditReplaceConfirmationTitle: String {
        tr("Apply and replace current board?", zhHans: "确认应用？")
    }
    static var quickEditReplaceConfirmationMessage: String {
        tr("This will replace existing tasks on the current board.", zhHans: "将替换当前棋盘已有任务。")
    }
    static var quickEditKeptBoardWithoutSelection: String {
        tr("No selection. Kept current board.", zhHans: "未选择任务，已保留当前棋盘。")
    }
    static func quickEditNeedMoreTasks(_ count: Int) -> String {
        tr("Add \(count) more tasks to fill this grid", zhHans: "还需 \(count) 个任务可填满当前尺寸")
    }
    static var quickEditPremiumLimitMessage: String {
        tr("Upgrade to Pro for unlimited tasks and groups.", zhHans: "开通 Pro 后可无限创建任务和分组。", zhHant: "開通 Pro 後可無限建立任務與分組。")
    }
    static var taskAddedSuccess: String { tr("Task added", zhHans: "任务已添加") }
    static var groupAddedSuccess: String { tr("Group added", zhHans: "分组已添加") }
    static var tasksAndGroupsAddedSuccess: String { tr("Changes saved", zhHans: "已保存更改") }
    static var tasksSavedSuccess: String { tr("Saved successfully", zhHans: "保存成功") }
    static var deleteConfirmationTitle: String { tr("Delete", zhHans: "删除") }
    static var deleteTaskConfirmationMessage: String { tr("This task will be removed from My Tasks.", zhHans: "该任务将从「我的任务」中移除。") }
    static var deleteGroupConfirmationMessage: String { tr("This group will be removed from My Tasks.", zhHans: "该分组将从「我的任务」中移除。") }
    static var taskDeletedSuccess: String { tr("Task deleted", zhHans: "任务已删除") }
    static var groupDeletedSuccess: String { tr("Group deleted", zhHans: "分组已删除") }
    static var tasksAndGroupsDeletedSuccess: String { tr("Changes deleted", zhHans: "已删除更改") }
    static var groupName: String { tr("Group Name", zhHans: "分组名称") }
    static func taskNumber(_ index: Int) -> String { tr("Task \(index)", zhHans: "任务 \(index)") }
    static var task: String { tr("Task", zhHans: "任务") }
    static var diaryHint: String { tr("Tap a completed date to view that day's Bingo board.", zhHans: "点击已完成的日期，查看当天的 Bingo 面板。") }
    static var taskCompletions: String { tr("Completed Task Stats", zhHans: "完成任务统计") }
    static var timeoutUnfinishedStats: String { tr("Timed-out Unfinished", zhHans: "超时未完成") }
    static var completedTasksShort: String { tr("Completed Tasks", zhHans: "完成任务") }
    static var timeoutTasksShort: String { tr("Timed-out Tasks", zhHans: "超时任务") }
    static var completion: String { tr("Completion", zhHans: "完成度") }
    static var last7Days: String { tr("7 Days", zhHans: "近 7 天") }
    static var last30Days: String { tr("30 Days", zhHans: "近 30 天") }
    static var statsWeekShort: String { tr("Week", zhHans: "周") }
    static var statsMonthShort: String { tr("Month", zhHans: "月") }
    static var statsYearShort: String { tr("Year", zhHans: "年") }
    static var noTaskCompletions: String { tr("No completed tasks yet.", zhHans: "暂时还没有已完成的任务。") }
    static var noTimeoutUnfinishedTasks: String { tr("No timed-out unfinished tasks.", zhHans: "暂无超时未完成任务。") }
    static func completedTimes(_ count: Int) -> String {
        tr("\(count) times", zhHans: "\(count) 次")
    }
    static func completedTimesCompact(_ count: Int) -> String {
        tr("x\(count)", zhHans: "x\(count)")
    }
    static func completionDaysCompact(_ days: Int) -> String {
        tr("\(days) days", zhHans: "\(days)天")
    }
    static func completionPercentCompact(_ percent: Int) -> String {
        "\(percent)%"
    }
    static var pointsUnit: String { tr("pts", zhHans: "积分") }
    static var boardCountdownTitle: String { tr("Bingo Board Countdown", zhHans: "Bingo 面板倒计时") }
    static var boardCountdownDescription: String { tr("Auto-clear the entire board when time runs out.", zhHans: "时间结束后自动清空整个面板。") }
    static var boardSwitcherTitle: String { tr("Boards", zhHans: "棋盘", zhHant: "棋盤") }
    static var boardCreateTitle: String { tr("Create board", zhHans: "创建棋盘", zhHant: "建立棋盤") }
    static var boardRenameTitle: String { tr("Rename board", zhHans: "重命名棋盘", zhHant: "重新命名棋盤") }
    static var boardNamePlaceholder: String { tr("Board name", zhHans: "棋盘名称", zhHant: "棋盤名稱") }
    static var boardCreateAction: String { tr("Create", zhHans: "创建", zhHant: "建立") }
    static var boardRenameAction: String { tr("Rename", zhHans: "重命名", zhHant: "重新命名") }
    static var boardCreateButton: String { tr("New Board", zhHans: "新建棋盘", zhHant: "新增棋盤") }
    static var boardManageAction: String { tr("Manage boards", zhHans: "管理棋盘", zhHant: "管理棋盤") }
    static var boardPremiumLimitMessage: String {
        tr(
        "Pro required for multiple boards.",
        zhHans: "开通 Pro 后可创建多个棋盘。",
        zhHant: "開通 Pro 後可建立多個棋盤。"
        )
    }
    static func boardDefaultName(_ index: Int) -> String {
        tr("Board \(index)", zhHans: "棋盘\(index)", zhHant: "棋盤\(index)")
}
    static var clearBoard: String { tr("Clear Board", zhHans: "清空棋盘") }
    static var clearBoardConfirmationTitle: String { tr("Clear board?", zhHans: "清空棋盘？") }
    static var clearBoardConfirmationMessage: String { tr("This will remove all tasks and completion states on the current board.", zhHans: "这会清除当前棋盘的所有任务和完成状态。") }
    static var boardClearedSuccess: String { tr("Board cleared", zhHans: "棋盘已清空") }
    static var hours: String { tr("Hours", zhHans: "小时") }
    static var minutes: String { tr("Minutes", zhHans: "分钟") }
    static var residentDays: String { tr("Repeat Days", zhHans: "常驻时间") }
    static var alwaysVisible: String { tr("Always", zhHans: "每天") }
    static var todayOnly: String { tr("Today Only", zhHans: "仅当天") }
    static var taskScheduledTitle: String { tr("Task Scheduled", zhHans: "任务已安排") }
    static func taskScheduledMessage(_ days: String) -> String {
        tr("This task will appear on \(days).", zhHans: "此任务会在 \(days) 显示。")
    }
    static var cancel: String { tr("Cancel", zhHans: "取消") }
    static var save: String { tr("Save", zhHans: "保存") }
    static func boardWillClearIn(hours: Int, minutes: Int) -> String {
        tr("The board will clear in \(hours)h \(minutes)m.", zhHans: "面板将在 \(hours) 小时 \(minutes) 分钟后清空。")
    }
    static var boardWillClearIn24Hours: String { tr("The board will clear in 24 hours.", zhHans: "面板将在 24 小时后清空。") }
    static func hourValue(_ hour: Int) -> String { tr("\(hour)h", zhHans: "\(hour)小时") }
    static func minuteValue(_ minute: Int) -> String { tr("\(minute)m", zhHans: "\(minute)分") }
    static var estimatedCompletionTime: String { tr("Estimated Time", zhHans: "预计完成时间") }
    static var taskTimerEnabled: String { tr("Start countdown after saving", zhHans: "保存后开始倒计时") }
    static func taskTimerSummary(hours: Int, minutes: Int) -> String {
        tr("Countdown: \(hours)h \(minutes)m", zhHans: "倒计时：\(hours)小时\(minutes)分")
    }
    static var taskTimerSummary24Hours: String { tr("Countdown: 24 hours", zhHans: "倒计时：24小时") }
    static var taskTimedOutTitle: String { tr("Task timed out", zhHans: "任务超时了") }
    static func taskTimedOutHeadline(task: String, seconds: Int) -> String {
        tr("\(task) timed out by \(seconds)s", zhHans: "\(task)任务已超时\(seconds)秒")
    }
    static func boardTimedOutHeadline(seconds: Int) -> String {
        tr("Board timed out by \(seconds)s", zhHans: "面板任务已超时\(seconds)秒")
    }
    static func taskTimedOutMessage(task: String, overtime: String) -> String {
        tr("“\(task)” timed out (\(overtime)).", zhHans: "「\(task)」\(overtime)。")
    }
    static var markAsCompleted: String { tr("Completed", zhHans: "已完成") }
    static var abandonTask: String { tr("Abandon task", zhHans: "放弃此任务") }
    static func postponeTaskByMinutes(_ minutes: Int) -> String {
        tr("Delay \(minutes)m", zhHans: "延期\(minutes)分钟")
    }
    static func postponeByMinutes(_ minutes: Int) -> String {
        tr("Postpone \(minutes)m", zhHans: "延期 \(minutes) 分钟")
    }
    static var postponeDuration: String { tr("Delay duration", zhHans: "延期时长") }
    static func timedOutFor(_ duration: String) -> String {
        tr("Timed out for \(duration)", zhHans: "已超时 \(duration)")
    }
    static var taskMarkedCompletedSuccess: String { tr("Task marked completed", zhHans: "任务已标记为完成") }
    static var boardMarkedCompletedSuccess: String { tr("Board tasks marked completed", zhHans: "面板任务已标记为完成") }
    static var taskAbandonedSuccess: String { tr("Task abandoned", zhHans: "任务已放弃") }
    static func taskPostponedSuccess(_ minutes: Int) -> String {
        tr("Postponed by \(minutes)m", zhHans: "已延期 \(minutes) 分钟")
    }
    static var boardCountdownCanceledSuccess: String { tr("Countdown canceled", zhHans: "已取消倒计时") }
    static func boardCountdownPostponedSuccess(_ minutes: Int) -> String {
        tr("Board countdown postponed by \(minutes)m", zhHans: "面板倒计时已延期 \(minutes) 分钟")
    }
    static var enterTaskForDay: String { tr("Enter a task for your day...", zhHans: "输入今天要完成的任务...") }
    static var emptyBoardLongPressHint: String { tr("Long press to edit tasks", zhHans: "长按编辑任务") }
    static var forceCompletion: String { tr("Force Completion", zhHans: "强制完成") }
    static var recording: String { tr("Recording...", zhHans: "正在录音...") }
    static var quickAdd: String { tr("Quick Add", zhHans: "快速添加") }
    static var editTask: String { tr("Edit Task", zhHans: "编辑任务") }
    static var deleteTask: String { tr("Delete Task", zhHans: "删除任务") }
    static var hideTask: String { tr("Hide Task", zhHans: "隐藏任务") }
    static var showTask: String { tr("Show Task", zhHans: "显示任务") }
    static var deleteReward: String { tr("Delete Reward", zhHans: "删除奖励") }
    static var taskDeleted: String { tr("Task deleted", zhHans: "任务已删除") }
    static var undo: String { tr("Undo", zhHans: "撤销") }
    static var unableToApplyGroup: String { tr("Unable to Apply Group", zhHans: "无法应用分组") }
    static var applyGroupFailedMessage: String { tr("This group can't be applied because there aren't enough empty tiles.", zhHans: "空白格子数量不足，无法应用这个分组。") }
    static var expiredCountdownMessage: String { tr("Your Bingo board was cleared because its countdown ended.", zhHans: "你的 Bingo 面板已因倒计时结束被清空。") }
    static var groupDefaultName: String { tr("Group", zhHans: "分组") }
    static var boardInteractionGuide: String {
        tr(
            "Tap to complete. Long press and release to edit or delete. Long press and drag to reorder.",
            zhHans: "单击完成，长按松手可编辑/删除，长按拖动可排序"
        )
    }
    static var mondayShort: String { tr("Mon", zhHans: "周一") }
    static var tuesdayShort: String { tr("Tue", zhHans: "周二") }
    static var wednesdayShort: String { tr("Wed", zhHans: "周三") }
    static var thursdayShort: String { tr("Thu", zhHans: "周四") }
    static var fridayShort: String { tr("Fri", zhHans: "周五") }
    static var saturdayShort: String { tr("Sat", zhHans: "周六") }
    static var sundayShort: String { tr("Sun", zhHans: "周日") }
}

struct BingoCell: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var residentTaskText: String?
    var residentWeekdays: Set<Int>
    var oneTimeVisibleDate: Date?
    var isTaskHidden: Bool
    var isCompleted: Bool
    var isForced: Bool
    var countdownEndsAt: Date?
    var completionStreakCount: Int
    var lastCompletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case residentTaskText
        case residentWeekdays
        case oneTimeVisibleDate
        case isTaskHidden
        case isCompleted
        case isForced
        case countdownEndsAt
        case completionStreakCount
        case lastCompletedAt
    }

    init(
        id: UUID = UUID(),
        text: String = "",
        residentTaskText: String? = nil,
        residentWeekdays: Set<Int> = [],
        oneTimeVisibleDate: Date? = nil,
        isTaskHidden: Bool = false,
        isCompleted: Bool = false,
        isForced: Bool = false,
        countdownEndsAt: Date? = nil,
        completionStreakCount: Int = 0,
        lastCompletedAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.residentTaskText = residentTaskText
        self.residentWeekdays = residentWeekdays
        self.oneTimeVisibleDate = oneTimeVisibleDate
        self.isTaskHidden = isTaskHidden
        self.isCompleted = isCompleted
        self.isForced = isForced
        self.countdownEndsAt = countdownEndsAt
        self.completionStreakCount = max(completionStreakCount, 0)
        self.lastCompletedAt = lastCompletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        residentTaskText = try container.decodeIfPresent(String.self, forKey: .residentTaskText)
        residentWeekdays = try container.decodeIfPresent(Set<Int>.self, forKey: .residentWeekdays) ?? []
        oneTimeVisibleDate = try container.decodeIfPresent(Date.self, forKey: .oneTimeVisibleDate)
        isTaskHidden = try container.decodeIfPresent(Bool.self, forKey: .isTaskHidden) ?? false
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        isForced = try container.decodeIfPresent(Bool.self, forKey: .isForced) ?? false
        countdownEndsAt = try container.decodeIfPresent(Date.self, forKey: .countdownEndsAt)
        completionStreakCount = try container.decodeIfPresent(Int.self, forKey: .completionStreakCount) ?? 0
        lastCompletedAt = try container.decodeIfPresent(Date.self, forKey: .lastCompletedAt)
    }

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasStoredTask: Bool {
        !storedTaskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var storedTaskText: String {
        let recurring = residentTaskText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !recurring.isEmpty {
            return recurring
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasResidentSchedule: Bool {
        !residentWeekdays.isEmpty && !(residentTaskText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var isOneTimeTask: Bool {
        oneTimeVisibleDate != nil && !(residentTaskText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    func isResidentActive(on date: Date, calendar: Calendar = .current) -> Bool {
        guard hasResidentSchedule else { return true }
        let weekday = calendar.component(.weekday, from: date)
        return residentWeekdays.contains(weekday)
    }

    func projectedForDisplay(on date: Date, calendar: Calendar = .current) -> BingoCell {
        var projected = self
        let activeToday: Bool
        if isOneTimeTask, let oneTimeVisibleDate {
            activeToday = calendar.isDate(oneTimeVisibleDate, inSameDayAs: date)
        } else if hasResidentSchedule {
            activeToday = isResidentActive(on: date, calendar: calendar)
        } else {
            return self
        }
        projected.text = activeToday ? storedTaskText : ""
        projected.isCompleted = activeToday ? isCompleted : false
        projected.isTaskHidden = activeToday ? isTaskHidden : false
        projected.countdownEndsAt = nil
        return projected
    }
}

enum BingoLine: Hashable, Codable {
    case row(Int)
    case column(Int)
    case diagonalMain
    case diagonalAnti
}

struct SavedBoard: Codable, Equatable {
    let gridSize: Int
    let cells: [[BingoCell]]
    let completedLines: Set<BingoLine>
    let fullBoardCells: [[BingoCell]]?

    init(gridSize: Int, cells: [[BingoCell]], completedLines: Set<BingoLine>, fullBoardCells: [[BingoCell]]? = nil) {
        self.gridSize = gridSize
        self.cells = cells
        self.completedLines = completedLines
        self.fullBoardCells = fullBoardCells
    }
}

struct BingoDiaryEntry: Identifiable, Codable {
    let id: String
    let date: Date
    let board: SavedBoard
    let allTasksCompleted: Bool
}

struct DailyRewardState: Codable, Equatable {
    var dateKey: String
    var rewardedCellIDs: Set<UUID>
    var peakCompletedLineCount: Int
    var fullBoardRewardGranted: Bool

    init(
        dateKey: String,
        rewardedCellIDs: Set<UUID> = [],
        peakCompletedLineCount: Int = 0,
        fullBoardRewardGranted: Bool = false
    ) {
        self.dateKey = dateKey
        self.rewardedCellIDs = rewardedCellIDs
        self.peakCompletedLineCount = peakCompletedLineCount
        self.fullBoardRewardGranted = fullBoardRewardGranted
    }
}

struct MyTaskGroup: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var tasks: [String]

    init(id: UUID = UUID(), name: String = "", tasks: [String] = []) {
        self.id = id
        self.name = name
        self.tasks = tasks
    }
}

struct MyTasksLibrary: Codable, Equatable {
    var tasks: [String]
    var groups: [MyTaskGroup]

    init(tasks: [String] = [], groups: [MyTaskGroup] = []) {
        self.tasks = tasks
        self.groups = groups
    }
}

struct CustomReward: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var requiredPoints: Int
    var redemptionCount: Int
    var totalSpentPoints: Int
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        title: String,
        requiredPoints: Int,
        redemptionCount: Int = 0,
        totalSpentPoints: Int = 0,
        isArchived: Bool = false
    ) {
        self.id = id
        self.title = title
        self.requiredPoints = requiredPoints
        self.redemptionCount = redemptionCount
        self.totalSpentPoints = totalSpentPoints
        self.isArchived = isArchived
    }
}

enum StickerKind: String, CaseIterable, Codable, Identifiable {
    case cowCat
    case orangeCat
    case pomeranian
    case dachshund
    case toyPoodle
    case yorkshire
    case akita
    case goldenRetriever
    case ragdollCat
    case maineCoon
    case alaskanMalamute
    case chineseVillageDog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cowCat: return L10n.tr("Cow Cat", zhHans: "奶牛猫")
        case .orangeCat: return L10n.tr("Orange Cat", zhHans: "橘猫")
        case .pomeranian: return L10n.tr("Pomeranian", zhHans: "博美")
        case .dachshund: return L10n.tr("Dachshund", zhHans: "腊肠狗")
        case .toyPoodle: return L10n.tr("Toy Poodle", zhHans: "泰迪")
        case .yorkshire: return L10n.tr("Yorkshire", zhHans: "约克夏")
        case .akita: return L10n.tr("Akita", zhHans: "秋田")
        case .goldenRetriever: return L10n.tr("Golden Retriever", zhHans: "金毛")
        case .ragdollCat: return L10n.tr("Ragdoll Cat", zhHans: "布偶猫")
        case .maineCoon: return L10n.tr("Maine Coon", zhHans: "缅因猫")
        case .alaskanMalamute: return L10n.tr("Alaskan Malamute", zhHans: "阿拉斯加")
        case .chineseVillageDog: return L10n.tr("Chinese Village Dog", zhHans: "中华田园犬")
        }
    }

    var unlockedImageName: String {
        switch self {
        case .cowCat: return "CowCatSticker"
        case .orangeCat: return "OrangeCatSticker"
        case .pomeranian: return "PomeranianSticker"
        case .dachshund: return "DachshundSticker"
        case .toyPoodle: return "ToyPoodleSticker"
        case .yorkshire: return "YorkshireSticker"
        case .akita: return "AkitaSticker"
        case .goldenRetriever: return "GoldenRetrieverSticker"
        case .ragdollCat: return "RagdollCatSticker"
        case .maineCoon: return "MaineCoonSticker"
        case .alaskanMalamute: return "AlaskanMalamuteSticker"
        case .chineseVillageDog: return "ChineseVillageDogSticker"
        }
    }

    var lockedImageName: String {
        switch self {
        case .cowCat: return "CowCatStickerLocked"
        case .orangeCat: return "OrangeCatStickerLocked"
        case .pomeranian: return "PomeranianStickerLocked"
        case .dachshund: return "DachshundStickerLocked"
        case .toyPoodle: return "ToyPoodleStickerLocked"
        case .yorkshire: return "YorkshireStickerLocked"
        case .akita: return "AkitaStickerLocked"
        case .goldenRetriever: return "GoldenRetrieverStickerLocked"
        case .ragdollCat: return "RagdollCatStickerLocked"
        case .maineCoon: return "MaineCoonStickerLocked"
        case .alaskanMalamute: return "AlaskanMalamuteStickerLocked"
        case .chineseVillageDog: return "ChineseVillageDogStickerLocked"
        }
    }

    var requiredPoints: Int {
        20
    }

    var homeDisplayWidth: CGFloat {
        switch self {
        case .cowCat:
            return 86
        case .ragdollCat, .maineCoon, .alaskanMalamute, .goldenRetriever, .chineseVillageDog:
            return 100
        default:
            return 92
        }
    }

    var defaultPlacement: (xRatio: Double, yRatio: Double) {
        switch self {
        case .cowCat:
            return (0.22, 0.24)
        case .orangeCat:
            return (0.48, 0.18)
        case .pomeranian:
            return (0.78, 0.24)
        case .dachshund:
            return (0.18, 0.46)
        case .toyPoodle:
            return (0.82, 0.48)
        case .yorkshire:
            return (0.22, 0.70)
        case .akita:
            return (0.50, 0.74)
        case .goldenRetriever:
            return (0.78, 0.70)
        case .ragdollCat:
            return (0.50, 0.30)
        case .maineCoon:
            return (0.34, 0.56)
        case .alaskanMalamute:
            return (0.66, 0.56)
        case .chineseVillageDog:
            return (0.50, 0.88)
        }
    }
}

struct HomeStickerPlacement: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: StickerKind
    var xRatio: Double
    var yRatio: Double
    var scale: Double

    init(id: UUID = UUID(), kind: StickerKind, xRatio: Double, yRatio: Double, scale: Double = 1.0) {
        self.id = id
        self.kind = kind
        self.xRatio = xRatio
        self.yRatio = yRatio
        self.scale = scale
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case xRatio
        case yRatio
        case scale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(StickerKind.self, forKey: .kind)
        xRatio = try container.decode(Double.self, forKey: .xRatio)
        yRatio = try container.decode(Double.self, forKey: .yRatio)
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(xRatio, forKey: .xRatio)
        try container.encode(yRatio, forKey: .yRatio)
        try container.encode(scale, forKey: .scale)
    }

    func normalized() -> HomeStickerPlacement {
        HomeStickerPlacement(
            id: id,
            kind: kind,
            xRatio: Self.clamp(xRatio, min: 0.02, max: 0.98, fallback: 0.5),
            yRatio: Self.clamp(yRatio, min: 0.02, max: 0.98, fallback: 0.5),
            scale: Self.clamp(scale, min: 0.5, max: 1.6, fallback: 1.0)
        )
    }

    private static func clamp(_ value: Double, min lowerBound: Double, max upperBound: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return Swift.max(lowerBound, Swift.min(value, upperBound))
    }
}

enum AppSettings {
    static let hapticsEnabledKey = "haptics_enabled"
    static let soundEffectsEnabledKey = "sound_effects_enabled"
    static let themeKey = "theme_color"
    static let hasSeenOnboardingKey = "has_seen_onboarding_v2"
    static let commonTasksKey = "common_tasks"
    static let boardCountdownKey = "board_countdown_v1"
    static let totalPointsKey = "total_points_v2"
    static let lifetimePointsKey = "lifetime_points_v1"
    static let dailyRewardStateKey = "daily_reward_state_v1"
    static let redeemedStickersKey = "redeemed_stickers_v1"
    static let redeemedStickerOrderKey = "redeemed_sticker_order_v1"
    static let stickerInventoryCountsKey = "sticker_inventory_counts_v1"
    static let homeStickerPlacementsKey = "home_sticker_placements_v1"
    static let customRewardsKey = "custom_rewards_v1"
    static let maxCommonTasks = 8
    static let maxTaskGroups = 6
    static let maxTasksPerGroup = 5
    static let maxTaskLength = 20
    static let maxRewardTitleLength = 30

    static var isHapticsEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: hapticsEnabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: hapticsEnabledKey)
    }

    static var isSoundEffectsEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: soundEffectsEnabledKey) == nil {
            return true
        }
        return defaults.bool(forKey: soundEffectsEnabledKey)
    }
}

enum AppHaptics {
    private static var hapticEngine: CHHapticEngine?
    private static let completionGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let controlGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let emphasisGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private static let successGenerator = UINotificationFeedbackGenerator()

    private static func perform(_ work: @escaping () -> Void) {
        guard AppSettings.isHapticsEnabled else { return }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    static func completion() {
        perform {
            let didPlayCoreHaptic = playTransient(intensity: 0.85, sharpness: 0.5)

            // Notification feedback is more noticeable on device for "task completed".
            successGenerator.prepare()
            successGenerator.notificationOccurred(.success)
            successGenerator.prepare()

            if !didPlayCoreHaptic {
                completionGenerator.prepare()
                completionGenerator.impactOccurred(intensity: 1.0)
                completionGenerator.prepare()
            }
        }
    }

    static func control() {
        perform {
            if !playTransient(intensity: 0.55, sharpness: 0.5) {
                controlGenerator.prepare()
                controlGenerator.impactOccurred(intensity: 0.85)
                controlGenerator.prepare()
            }
        }
    }

    static func emphasis() {
        perform {
            if !playTransient(intensity: 1.0, sharpness: 0.85) {
                emphasisGenerator.prepare()
                emphasisGenerator.impactOccurred(intensity: 1.0)
                emphasisGenerator.prepare()
            }
        }
    }

    @discardableResult
    private static func playTransient(intensity: Float, sharpness: Float) -> Bool {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            return false
        }

        do {
            let engine = try preparedEngine()
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ],
                relativeTime: 0
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
            return true
        } catch {
            hapticEngine = nil
            return false
        }
    }

    private static func preparedEngine() throws -> CHHapticEngine {
        if let hapticEngine {
            try? hapticEngine.start()
            return hapticEngine
        }

        let engine = try CHHapticEngine()
        engine.isAutoShutdownEnabled = true
        engine.stoppedHandler = { _ in
            hapticEngine = nil
        }
        engine.resetHandler = {
            do {
                try engine.start()
            } catch {
                hapticEngine = nil
            }
        }
        try engine.start()
        hapticEngine = engine
        return engine
    }
}

enum StickerStore {
    static func loadInventoryCounts() -> [StickerKind: Int] {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: AppSettings.stickerInventoryCountsKey),
           let saved = try? JSONDecoder().decode([String: Int].self, from: data) {
            let normalized = saved.reduce(into: [StickerKind: Int]()) { partial, entry in
                guard let kind = StickerKind(rawValue: entry.key), entry.value > 0 else { return }
                partial[kind] = 1
            }
            saveInventoryCounts(normalized)
            return normalized
        }

        // Migrate legacy "redeemed once" state into a single owned sticker inventory.
        var migratedKinds: [StickerKind] = []
        if let data = defaults.data(forKey: AppSettings.redeemedStickerOrderKey),
           let orderedKinds = try? JSONDecoder().decode([StickerKind].self, from: data) {
            migratedKinds = orderedKinds
        } else if let data = defaults.data(forKey: AppSettings.redeemedStickersKey),
                  let kinds = try? JSONDecoder().decode([StickerKind].self, from: data) {
            migratedKinds = kinds
        }

        let migratedCounts = migratedKinds.reduce(into: [StickerKind: Int]()) { partial, kind in
            partial[kind] = 1
        }
        if !migratedCounts.isEmpty {
            saveInventoryCounts(migratedCounts)
        }
        return migratedCounts
    }

    static func saveInventoryCounts(_ counts: [StickerKind: Int]) {
        let payload = counts.reduce(into: [String: Int]()) { partial, entry in
            guard entry.value > 0 else { return }
            partial[entry.key.rawValue] = 1
        }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: AppSettings.stickerInventoryCountsKey)
    }

    static func loadPlacements() -> [HomeStickerPlacement] {
        guard let data = UserDefaults.standard.data(forKey: AppSettings.homeStickerPlacementsKey),
              let placements = try? JSONDecoder().decode([HomeStickerPlacement].self, from: data) else {
            return []
        }
        let normalized = normalizedPlacements(placements)
        savePlacements(normalized)
        return normalized
    }

    static func savePlacements(_ placements: [HomeStickerPlacement]) {
        let normalized = normalizedPlacements(placements)
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        UserDefaults.standard.set(data, forKey: AppSettings.homeStickerPlacementsKey)
    }

    static func clearPlacements() {
        UserDefaults.standard.removeObject(forKey: AppSettings.homeStickerPlacementsKey)
    }

    static func clearInventoryCounts() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AppSettings.stickerInventoryCountsKey)
        defaults.removeObject(forKey: AppSettings.redeemedStickersKey)
        defaults.removeObject(forKey: AppSettings.redeemedStickerOrderKey)
    }

    private static func normalizedPlacements(_ placements: [HomeStickerPlacement]) -> [HomeStickerPlacement] {
        var seenKinds = Set<StickerKind>()
        var result: [HomeStickerPlacement] = []
        result.reserveCapacity(placements.count)

        for placement in placements {
            let normalized = placement.normalized()
            guard !seenKinds.contains(normalized.kind) else { continue }
            seenKinds.insert(normalized.kind)
            result.append(normalized)
        }

        return result
    }
}

enum PointsStore {
    static func loadTotalPoints() -> Int? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: AppSettings.totalPointsKey) != nil else { return nil }
        return defaults.integer(forKey: AppSettings.totalPointsKey)
    }

    static func saveTotalPoints(_ points: Int) {
        UserDefaults.standard.set(points, forKey: AppSettings.totalPointsKey)
    }

    static func loadLifetimePoints() -> Int? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: AppSettings.lifetimePointsKey) != nil else { return nil }
        return defaults.integer(forKey: AppSettings.lifetimePointsKey)
    }

    static func saveLifetimePoints(_ points: Int) {
        UserDefaults.standard.set(points, forKey: AppSettings.lifetimePointsKey)
    }

    static func loadDailyRewardState() -> DailyRewardState? {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: AppSettings.dailyRewardStateKey),
              let state = try? JSONDecoder().decode(DailyRewardState.self, from: data) else {
            return nil
        }
        return state
    }

    static func saveDailyRewardState(_ state: DailyRewardState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: AppSettings.dailyRewardStateKey)
    }

    static func clearDailyRewardState() {
        UserDefaults.standard.removeObject(forKey: AppSettings.dailyRewardStateKey)
    }

    static func clearTotalPoints() {
        UserDefaults.standard.removeObject(forKey: AppSettings.totalPointsKey)
    }

    static func clearLifetimePoints() {
        UserDefaults.standard.removeObject(forKey: AppSettings.lifetimePointsKey)
    }

    static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

enum RewardStore {
    static func loadRewards() -> [CustomReward] {
        guard let data = UserDefaults.standard.data(forKey: AppSettings.customRewardsKey),
              let rewards = try? JSONDecoder().decode([CustomReward].self, from: data) else {
            return []
        }

        return rewards
    }

    static func saveRewards(_ rewards: [CustomReward]) {
        guard let data = try? JSONEncoder().encode(rewards) else { return }
        UserDefaults.standard.set(data, forKey: AppSettings.customRewardsKey)
    }

    static func clearRewards() {
        UserDefaults.standard.removeObject(forKey: AppSettings.customRewardsKey)
    }
}

struct AppUpdateInfo: Equatable {
    let latestVersion: String
    let trackViewURL: URL
    let releaseNotes: String?
}

enum AppUpdateService {
    static func fetchUpdateInfo(
        currentVersion: String,
        bundleIdentifier: String,
        countryCode: String?
    ) async -> AppUpdateInfo? {
        guard let lookupURL = buildLookupURL(bundleIdentifier: bundleIdentifier, countryCode: countryCode) else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: lookupURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }

            let payload = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
            guard let app = payload.results.first,
                  let latestVersion = app.version?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let trackViewURLString = app.trackViewUrl,
                  let trackViewURL = URL(string: trackViewURLString),
                  isVersion(latestVersion, greaterThan: currentVersion) else {
                return nil
            }

            let notes = app.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
            return AppUpdateInfo(
                latestVersion: latestVersion,
                trackViewURL: trackViewURL,
                releaseNotes: notes?.isEmpty == false ? notes : nil
            )
        } catch {
            return nil
        }
    }

#if DEBUG
    static func debugMockUpdateInfo(currentVersion: String) -> AppUpdateInfo {
        let mockVersion = currentVersion + ".1"
        let fallbackURL = URL(string: "https://apps.apple.com/us/search?term=Bingodays")!
        return AppUpdateInfo(
            latestVersion: mockVersion,
            trackViewURL: fallbackURL,
            releaseNotes: nil
        )
    }
#endif

    private static func buildLookupURL(bundleIdentifier: String, countryCode: String?) -> URL? {
        let fallbackCountry = Locale.current.region?.identifier ?? "US"
        let country = (countryCode?.isEmpty == false ? countryCode! : fallbackCountry).uppercased()

        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/lookup"
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleIdentifier),
            URLQueryItem(name: "country", value: country)
        ]
        return components.url
    }

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

enum CommonTasksStore {
    static func load() -> [String] {
        loadLibrary().tasks
    }

    static func loadLibrary() -> MyTasksLibrary {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: AppSettings.commonTasksKey),
           let saved = try? JSONDecoder().decode(MyTasksLibrary.self, from: data) {
            return sanitize(saved)
        }

        if let saved = defaults.array(forKey: AppSettings.commonTasksKey) as? [String] {
            return MyTasksLibrary(tasks: sanitizeTasks(saved), groups: [])
        }
        return MyTasksLibrary()
    }

    static func loadGroups() -> [MyTaskGroup] {
        loadLibrary().groups
    }

    static func save(_ tasks: [String]) {
        var library = loadLibrary()
        library.tasks = tasks
        saveLibrary(library)
    }

    static func saveLibrary(_ library: MyTasksLibrary) {
        let sanitized = sanitize(library)
        guard let data = try? JSONEncoder().encode(sanitized) else { return }
        UserDefaults.standard.set(data, forKey: AppSettings.commonTasksKey)
    }

    private static func sanitize(_ library: MyTasksLibrary) -> MyTasksLibrary {
        MyTasksLibrary(
            tasks: sanitizeTasks(library.tasks),
            groups: sanitizeGroups(library.groups)
        )
    }

    private static func sanitizeTasks(_ tasks: [String]) -> [String] {
        tasks
            .map { String($0.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func sanitizeGroups(_ groups: [MyTaskGroup]) -> [MyTaskGroup] {
        groups
            .compactMap { group in
                let trimmedName = String(group.name.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
                let sanitizedTasks = group.tasks
                    .map { String($0.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                guard !trimmedName.isEmpty || !sanitizedTasks.isEmpty else { return nil }
                return MyTaskGroup(
                    id: group.id,
                    name: trimmedName.isEmpty ? L10n.groupDefaultName : trimmedName,
                    tasks: sanitizedTasks
                )
            }
    }
}

enum BingoDiaryStore {
    private static let key = "bingo_diary_v1"

    static func save(board: SavedBoard, on date: Date = .now) {
        var entries = loadEntriesDictionary()
        let entry = BingoDiaryEntry(
            id: dateKey(for: date),
            date: Calendar.current.startOfDay(for: date),
            board: board,
            allTasksCompleted: boardHasAllTasksCompleted(board)
        )
        entries[entry.id] = entry
        persist(entries)
    }

    static func entry(for date: Date) -> BingoDiaryEntry? {
        loadEntriesDictionary()[dateKey(for: date)]
    }

    static func entries(inMonthContaining date: Date) -> [BingoDiaryEntry] {
        let calendar = Calendar.current
        let monthInterval = calendar.dateInterval(of: .month, for: date)

        return loadEntriesDictionary().values
            .filter { entry in
                guard let interval = monthInterval else { return false }
                return interval.contains(entry.date)
            }
            .sorted { $0.date < $1.date }
    }

    static func consecutiveBingoDays(referenceDate: Date = .now) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        let entries = loadEntriesDictionary()

        var streak = 0
        var cursor = today

        while let entry = entries[dateKey(for: cursor)], entry.allTasksCompleted {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }

        return streak
    }

    static func totalCompletedTasks() -> Int {
        loadEntriesDictionary().values.reduce(0) { partialResult, entry in
            partialResult + entry.board.cells.flatMap { $0 }.filter { $0.isCompleted && !$0.isEmpty }.count
        }
    }

    static func completedTaskCounts(lastDays: Int, referenceDate: Date = .now) -> [(task: String, count: Int)] {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: referenceDate)
        guard let startDate = calendar.date(byAdding: .day, value: -(max(lastDays, 1) - 1), to: endDate) else {
            return []
        }

        let counts = loadEntriesDictionary().values.reduce(into: [String: Int]()) { partial, entry in
            let day = calendar.startOfDay(for: entry.date)
            guard day >= startDate && day <= endDate else { return }

            for cell in entry.board.cells.flatMap({ $0 }) where cell.isCompleted && !cell.isEmpty {
                let task = cell.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !task.isEmpty else { continue }
                partial[task, default: 0] += 1
            }
        }

        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
                }
                return lhs.value > rhs.value
            }
            .map { (task: $0.key, count: $0.value) }
    }

    static func taskCompletionStats(
        lastDays: Int,
        referenceDate: Date = .now
    ) -> [(task: String, totalCount: Int, activeDays: Int, completionRate: Double, dailyCounts: [Int])] {
        let calendar = Calendar.current
        let days = max(lastDays, 1)
        let endDate = calendar.startOfDay(for: referenceDate)
        guard let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: endDate) else {
            return []
        }

        var dayIndexByKey: [String: Int] = [:]
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDate) else { continue }
            dayIndexByKey[dateKey(for: day)] = offset
        }

        let emptyDailyCounts = Array(repeating: 0, count: days)
        var taskDailyCounts: [String: [Int]] = [:]

        for entry in loadEntriesDictionary().values {
            let entryKey = dateKey(for: entry.date)
            guard let dayIndex = dayIndexByKey[entryKey] else { continue }

            for cell in entry.board.cells.flatMap({ $0 }) where cell.isCompleted && !cell.isEmpty {
                let task = cell.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !task.isEmpty else { continue }

                var counts = taskDailyCounts[task] ?? emptyDailyCounts
                counts[dayIndex] += 1
                taskDailyCounts[task] = counts
            }
        }

        return taskDailyCounts
            .map { task, dailyCounts in
                let totalCount = dailyCounts.reduce(0, +)
                let activeDays = dailyCounts.reduce(0) { $0 + ($1 > 0 ? 1 : 0) }
                let completionRate = Double(activeDays) / Double(days)
                return (task: task, totalCount: totalCount, activeDays: activeDays, completionRate: completionRate, dailyCounts: dailyCounts)
            }
            .sorted { lhs, rhs in
                if lhs.totalCount == rhs.totalCount {
                    return lhs.task.localizedCaseInsensitiveCompare(rhs.task) == .orderedAscending
                }
                return lhs.totalCount > rhs.totalCount
            }
    }

    static func loadAllEntriesDictionary() -> [String: BingoDiaryEntry] {
        loadEntriesDictionary()
    }

    static func replaceAllEntriesDictionary(_ entries: [String: BingoDiaryEntry]) {
        persist(entries)
    }

    private static func loadEntriesDictionary() -> [String: BingoDiaryEntry] {
        if let data = sharedDefaults.data(forKey: key),
           let entries = try? JSONDecoder().decode([String: BingoDiaryEntry].self, from: data) {
            return entries
        }

        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([String: BingoDiaryEntry].self, from: data) else {
            return [:]
        }
        sharedDefaults.set(data, forKey: key)
        return entries
    }

    private static func persist(_ entries: [String: BingoDiaryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        sharedDefaults.set(data, forKey: key)
        UserDefaults.standard.set(data, forKey: key)
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: BingoBoardStore.appGroupID) ?? .standard
    }

    private static func boardHasAllTasksCompleted(_ board: SavedBoard) -> Bool {
        let taskCells = board.cells.flatMap { $0 }.filter { !$0.isEmpty }
        guard !taskCells.isEmpty else { return false }
        return taskCells.allSatisfy(\.isCompleted)
    }

    private static func dateKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

enum BingoTimeoutStore {
    private static let key = "bingo_timeout_unfinished_stats_v1"

    static func recordUnfinishedTimeout(task: String, on date: Date = .now) {
        let trimmedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTask.isEmpty else { return }

        var payload = loadPayload()
        let dayKey = dateKey(for: date)
        var dayStats = payload[dayKey] ?? [:]
        dayStats[trimmedTask, default: 0] += 1
        payload[dayKey] = dayStats
        persist(payload)
    }

    static func taskTimeoutStats(
        lastDays: Int,
        referenceDate: Date = .now
    ) -> [(task: String, totalCount: Int, activeDays: Int, completionRate: Double, dailyCounts: [Int])] {
        let calendar = Calendar.current
        let days = max(lastDays, 1)
        let endDate = calendar.startOfDay(for: referenceDate)
        guard let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: endDate) else {
            return []
        }

        var dayIndexByKey: [String: Int] = [:]
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDate) else { continue }
            dayIndexByKey[dateKey(for: day)] = offset
        }

        let emptyDailyCounts = Array(repeating: 0, count: days)
        var taskDailyCounts: [String: [Int]] = [:]

        for (dayKey, taskCounts) in loadPayload() {
            guard let dayIndex = dayIndexByKey[dayKey] else { continue }
            for (task, count) in taskCounts where count > 0 {
                let trimmedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedTask.isEmpty else { continue }

                var counts = taskDailyCounts[trimmedTask] ?? emptyDailyCounts
                counts[dayIndex] += count
                taskDailyCounts[trimmedTask] = counts
            }
        }

        return taskDailyCounts
            .map { task, dailyCounts in
                let totalCount = dailyCounts.reduce(0, +)
                let activeDays = dailyCounts.reduce(0) { $0 + ($1 > 0 ? 1 : 0) }
                let completionRate = Double(activeDays) / Double(days)
                return (task: task, totalCount: totalCount, activeDays: activeDays, completionRate: completionRate, dailyCounts: dailyCounts)
            }
            .sorted { lhs, rhs in
                if lhs.totalCount == rhs.totalCount {
                    return lhs.task.localizedCaseInsensitiveCompare(rhs.task) == .orderedAscending
                }
                return lhs.totalCount > rhs.totalCount
            }
    }

    static func loadAllPayload() -> [String: [String: Int]] {
        loadPayload()
    }

    static func replacePayload(_ payload: [String: [String: Int]]) {
        persist(payload)
    }

    private static func loadPayload() -> [String: [String: Int]] {
        if let data = sharedDefaults.data(forKey: key),
           let payload = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            return payload
        }

        guard let data = UserDefaults.standard.data(forKey: key),
              let payload = try? JSONDecoder().decode([String: [String: Int]].self, from: data) else {
            return [:]
        }

        sharedDefaults.set(data, forKey: key)
        return payload
    }

    private static func persist(_ payload: [String: [String: Int]]) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        sharedDefaults.set(data, forKey: key)
        UserDefaults.standard.set(data, forKey: key)
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: BingoBoardStore.appGroupID) ?? .standard
    }

    private static func dateKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
