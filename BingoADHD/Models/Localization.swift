import Foundation

enum AppLanguage {
    case english
    case simplifiedChinese
    case traditionalChinese
    case japanese

    static var current: AppLanguage {
        for languageIdentifier in preferredLanguageIdentifiers {
            if let resolvedLanguage = language(from: languageIdentifier) {
                return resolvedLanguage
            }
        }

        let regionCode = currentRegionCode
        if hasTaiwanLanguageHint || regionCode == "TW" || regionCode == "HK" {
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
        let bundlePreferredLocalizations = Bundle.main.preferredLocalizations
        let bundleLocalizations = Bundle.main.localizations

        // Prefer explicit system language choices before bundle fallbacks.
        return (preferredLanguages + appleLanguages + localeIdentifiers + bundlePreferredLocalizations + bundleLocalizations)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func language(from identifier: String) -> AppLanguage? {
        let normalized = identifier.lowercased()

        if normalized.hasPrefix("zh") {
            if normalized.contains("hant") || normalized.contains("tw") {
                return .traditionalChinese
            }
            return .simplifiedChinese
        }

        if normalized.hasPrefix("ja") {
            return .japanese
        }

        if normalized.hasPrefix("en") {
            return .english
        }

        return nil
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
    static func tr(_ english: String, zhHans: String, zhHant: String? = nil, ja: String? = nil) -> String {
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
            return ja ?? japaneseFallback(for: english) ?? english
        }
    }

    private static func japaneseFallback(for english: String) -> String? {
        if english.hasPrefix("Switch to "), english.hasSuffix("?") {
            let themeTitle = english
                .dropFirst("Switch to ".count)
                .dropLast()
            return "\(themeTitle)に切り替えますか？"
        }
        if english.hasPrefix("Drink "), english.hasSuffix(" cups of water") {
            let count = english
                .dropFirst("Drink ".count)
                .dropLast(" cups of water".count)
            return "水を\(count)杯飲む"
        }

        switch english {
        case "Bingo Dairy": return "Bingo日記"
        case "Tasks completed", "Completed tasks", "Completed Tasks": return "完了タスク"
        case "Expired tasks": return "期限切れタスク"
        case "Complete a few tasks and they will appear here.": return "タスクをいくつか完了すると、ここに表示されます。"
        case "None": return "なし"
        case "Task Details": return "タスク詳細"
        case "Total Completions": return "合計完了回数"
        case "This Week": return "今週"
        case "Recent Activity": return "最近の記録"
        case "No activity yet": return "記録はまだありません"
        case "See how high you can score!": return "どこまでスコアを伸ばせるか試してみよう！"
        case "Got it": return "了解"
        case "Drink 1 cup of water": return "水を1杯飲む"
        case "Eat breakfast": return "朝食を食べる"
        case "Walk 10 minutes": return "10分歩く"
        case "Stretch 10 minutes": return "10分ストレッチ"
        case "Sleep before 23:30": return "23:30までに寝る"
        case "Eat fruit": return "果物を食べる"
        case "Pomodoro 25 min": return "ポモドーロ25分"
        case "Read 10 pages": return "10ページ読む"
        case "Write task plan": return "タスク計画を書く"
        case "Finish one small task": return "小さなタスクを1つ終える"
        case "No social app 30 min": return "SNSアプリを30分使わない"
        case "Take out trash": return "ゴミを出す"
        case "Wash dishes": return "皿を洗う"
        case "Wipe desk": return "机を拭く"
        case "Laundry 1 cycle": return "洗濯を1回する"
        case "Organize one drawer": return "引き出しを1つ整理"
        case "Task": return "タスク"
        case "Confirm exit?": return "終了しますか？"
        case "Confirm restart?": return "やり直しますか？"
        case "View how to play?": return "遊び方を表示しますか？"
        case "Refresh pending tasks?": return "未完了タスクを更新しますか？"
        case "This will clear the board and generate tasks again.": return "ボードをクリアしてタスクを再生成します。"
        case "This will switch theme and reset the current board.": return "テーマを切り替えて現在のボードをリセットします。"
        case "This will open the how-to-play popup.": return "遊び方のポップアップを開きます。"
        case "Only incomplete and unmerged tiles will be refreshed.": return "未完了かつ未合成のタイルのみ更新されます。"
        case "Exit": return "終了"
        case "Restart": return "やり直す"
        case "Switch": return "切り替え"
        case "View": return "表示"
        case "Refresh": return "更新"
        case "Score": return "スコア"
        case "No history yet": return "履歴はまだありません"
        case "History": return "履歴"
        case "Discard changes?": return "変更を破棄しますか？"
        case "If you exit now, your recent edits will not be applied to the board.": return "今終了すると、直近の編集はボードに適用されません。"
        case "Delete this group?": return "このグループを削除しますか？"
        case "Long press to edit tile task": return "長押しでタイルのタスクを編集"
        case "Remove task?": return "タスクを削除しますか？"
        case "Remove": return "削除"
        case "This action cannot be undone.": return "この操作は取り消せません。"
        case "Delete Group": return "グループを削除"
        case "+ add board": return "+ ボードを追加"
        case "Board Rules": return "ボードルール"
        case "Edit": return "編集"
        case "Apply": return "適用"
        case "Delete board?": return "ボードを削除しますか？"
        case "Days": return "日"
        case "Cancel countdown": return "カウントダウンをキャンセル"
        case "Cancel countdown?": return "カウントダウンをキャンセルしますか？"
        case "Confirm": return "確認"
        case "Board Countdown": return "ボードカウントダウン"
        case "Enable countdown": return "カウントダウンを有効にする"
        case "Board task reset mode": return "ボードタスクのリセット方法"
        case "Auto reset task status every other day": return "翌日にタスク状態を自動リセット"
        case "Task status will reset to incomplete at 24:00.": return "24:00にタスク状態を未完了へ自動リセットします。"
        case "Auto clear all tiles every other day": return "翌日にすべてのタイルタスクを自動クリア"
        case "All tile tasks will be cleared on the next day.": return "翌日にすべてのタイルタスクがクリアされます。"
        case "Keep task status unchanged": return "タスク状態を変更しない"
        case "Tasks remain in their current state until you update them manually.": return "手動で変更するまでタスクは現在の状態を維持します。"
        case "Custom task status reset time": return "タスク状態のカスタムリセット時刻"
        case "Copy email": return "メールをコピー"
        case "Always": return "常に"
        case "Custom": return "カスタム"
        case "Today": return "今日"
        case "Set countdown (minutes)": return "カウントダウンを設定（分）"
        case "Start time": return "開始時刻"
        case "End time": return "終了時刻"
        case "No start time": return "開始時刻なし"
        case "No end time": return "終了時刻なし"
        case "Shuffle": return "シャッフル"
        case "Grid Size": return "グリッドサイズ"
        case "Task postpone": return "タスクを延期"
        case "Replace task": return "タスクを置換"
        case "Keep current": return "現在のまま"
        default: return nil
        }
    }

    static var widgetCountdownName: String { tr("Bingodays Countdown", zhHans: "Bingodays 倒计时", ja: "Bingodays カウントダウン") }
    static var widgetCountdownDescription: String { tr("Track your Bingo board countdown at a glance.", zhHans: "快速查看 Bingo 面板倒计时。", ja: "Bingoボードのカウントダウンをひと目で確認。") }
    static var widgetBoardName: String { tr("Bingodays Board", zhHans: "Bingodays 面板", ja: "Bingodays ボード") }
    static var widgetBoardDescription: String { tr("See your current bingo board with the same card states as the app.", zhHans: "查看与 App 内状态同步的 Bingo 面板。", ja: "アプリと同じ状態のBingoボードを確認。") }
    static var dontForget: String { tr("DON'T FORGET!", zhHans: "别忘了任务！", ja: "忘れないで！") }
    static var doTask: String { tr("do task", zhHans: "去完成任务", ja: "タスクをする") }
    static var noTimer: String { tr("No Timer", zhHans: "未设置倒计时", ja: "タイマーなし") }
    static var totalDays: String { tr("Total Days", zhHans: "使用天数", ja: "合計日数") }
    static var streakDays: String { tr("Streak Days", zhHans: "连胜天数", ja: "連続日数") }
    static var bingoCount: String { tr("Bingo Count", zhHans: "完成任务", ja: "Bingo数") }
    static var language: String { tr("Language", zhHans: "语言", zhHant: "語言", ja: "言語") }
    static var countdownEndedTitle: String { tr("Task Countdown Ended", zhHans: "倒计时结束", ja: "タスクのカウントダウン終了") }
    static var newDayResetMessage: String {
        tr(
            "Task statuses were reset based on your board rules, and your points were kept.",
            zhHans: "任务状态已按你的面板规则重置，积分已保留。",
            zhHant: "任務狀態已依你的面板規則重置，積分已保留。"
        )
    }
    static var completedSingleTaskRemovedMessage: String {
        tr(
            "Completed single tasks were removed from the board.",
            zhHans: "已完成的单次任务已从面板移除",
            zhHant: "已完成的單次任務已從面板移除",
            ja: "完了した単発タスクはボードから削除されました"
        )
    }
    static var ok: String { tr("OK", zhHans: "好的", ja: "OK") }
    static var setBoardCountdown: String { tr("Countdown", zhHans: "倒计时", ja: "カウントダウン") }
    static var myTasks: String { tr("My Tasks", zhHans: "我的任务", ja: "マイタスク") }
    static var bingoDiary: String { tr("Bingo Dairy", zhHans: "Bingo 日记", ja: "Bingo日記") }
    static var setting: String { tr("Setting", zhHans: "设置", ja: "設定") }
    static var encourageUs: String { tr("Encourage Us", zhHans: "鼓励我们", zhHant: "鼓勵我們", ja: "応援する") }
    static var contactUs: String { tr("Contact Us", zhHans: "联系我们", zhHant: "聯絡我們", ja: "お問い合わせ") }
    static var contactUsTitle: String { tr("Contact Us", zhHans: "联系我们", zhHant: "聯絡我們", ja: "お問い合わせ") }
    static var contactUsEmail: String { tr("Evalong9820@gmail.com", zhHans: "Evalong9820@gmail.com", zhHant: "Evalong9820@gmail.com", ja: "Evalong9820@gmail.com") }
    static var contactUsMessage: String {
        return tr(
            "Thank you for using Bingodays. You can report a problem or send us a feature suggestion by email.",
            zhHans: "感谢你使用 Bingodays，你可以通过邮件反馈问题或提出功能建议。",
            zhHant: "感謝你使用 Bingodays，你可以透過電子郵件回報問題或提出功能建議。",
            ja: "Bingodaysをご利用いただきありがとうございます。問題の報告や機能の提案をメールで送れます。"
        )
    }
    static var contactUsEmailLabel: String { tr("Email", zhHans: "联系邮箱", zhHant: "聯絡信箱", ja: "メール") }
    static var contactUsEmailCopied: String { tr("Email copied", zhHans: "邮箱已复制", zhHant: "信箱已複製", ja: "メールアドレスをコピーしました") }
    static var contactUsFeedbackAction: String { tr("Report a problem", zhHans: "反馈问题", zhHant: "回報問題", ja: "問題を報告する") }
    static var contactUsBugReportAction: String { tr("Report a problem", zhHans: "反馈问题", zhHant: "回報問題", ja: "問題を報告する") }
    static var contactUsFeatureSuggestionAction: String { tr("Suggest a feature", zhHans: "提功能建议", zhHant: "提出功能建議", ja: "機能を提案する") }
    static var contactUsCopyEmailAction: String { tr("Copy email", zhHans: "复制邮箱", zhHant: "複製信箱", ja: "メールをコピー") }
    static var appReviewPromptTitle: String { tr("Do you like Bingodays?", zhHans: "喜欢Bingodays吗？", zhHant: "喜歡 Bingodays 嗎？", ja: "Bingodaysは気に入りましたか？") }
    static var appReviewPromptSubtitle: String {
        tr(
            "Your support helps us improve.",
            zhHans: "您的支持是我们进步的动力",
            zhHant: "你的支持是我們進步的動力",
            ja: "応援が改善の力になります。"
        )
    }
    static var appReviewPromptRateAction: String { tr("⭐️Give us 5 stars", zhHans: "⭐️赏个5星，鼓励一下", zhHant: "⭐️給個5星，鼓勵一下", ja: "⭐️5つ星で応援する") }
    static var appReviewPromptFeedbackAction: String { tr("I have a problem to report", zhHans: "遇到问题，我要反馈", zhHant: "遇到問題，我要回報", ja: "問題をフィードバックする") }
    static var appReviewPromptDismissAction: String { tr("No, thanks", zhHans: "不，我拒绝", zhHant: "不，我拒絕", ja: "いいえ") }
    static var appReviewFeedbackEmailSubject: String { tr("Bingodays feedback", zhHans: "Bingodays 问题反馈", zhHant: "Bingodays 問題回報", ja: "Bingodays フィードバック") }
    static var featureSuggestionEmailSubject: String { tr("Bingodays feature suggestion", zhHans: "Bingodays 功能建议", zhHant: "Bingodays 功能建議", ja: "Bingodays 機能提案") }
    static func appReviewFeedbackEmailBody(
        appVersion: String,
        device: String,
        system: String,
        diagnosticLog: String
    ) -> String {
        return tr(
            """
            Hi Bingodays team,

            I ran into this problem:



            App version: \(appVersion)
            Device: \(device)
            System: \(system)

            Diagnostic log:
            \(diagnosticLog)
            """,
            zhHans:
            """
            Bingodays 团队你好，

            我遇到了这个问题：



            App 版本：\(appVersion)
            设备：\(device)
            系统：\(system)

            诊断日志：
            \(diagnosticLog)
            """,
            zhHant:
            """
            Bingodays 團隊你好，

            我遇到了這個問題：



            App 版本：\(appVersion)
            裝置：\(device)
            系統：\(system)

            診斷日誌：
            \(diagnosticLog)
            """,
            ja:
            """
            Bingodaysチームへ

            次の問題が発生しました：



            App version: \(appVersion)
            Device: \(device)
            System: \(system)

            Diagnostic log:
            \(diagnosticLog)
            """
        )
    }
    static func featureSuggestionEmailBody(
        appVersion: String,
        device: String,
        system: String,
        diagnosticMarker: String
    ) -> String {
        return tr(
            """
            Hi Bingodays team,

            I have a feature suggestion:



            App version: \(appVersion)
            Device: \(device)
            System: \(system)

            Diagnostic log:
            \(diagnosticMarker)
            """,
            zhHans:
            """
            Bingodays 团队你好，

            我有一个功能建议：



            App 版本：\(appVersion)
            设备：\(device)
            系统：\(system)

            诊断日志：
            \(diagnosticMarker)
            """,
            zhHant:
            """
            Bingodays 團隊你好，

            我有一個功能建議：



            App 版本：\(appVersion)
            裝置：\(device)
            系統：\(system)

            診斷日誌：
            \(diagnosticMarker)
            """,
            ja:
            """
            Bingodaysチームへ

            機能について提案があります：



            App version: \(appVersion)
            Device: \(device)
            System: \(system)

            Diagnostic log:
            \(diagnosticMarker)
            """
        )
    }
    static var feedbackMailOpenFailed: String {
        tr("Unable to open Mail. Please copy the email address instead.", zhHans: "暂时无法打开邮箱，请复制邮箱地址反馈。", zhHant: "暫時無法開啟信箱，請複製信箱地址回報。", ja: "メールを開けません。メールアドレスをコピーしてください。")
    }
    static var subscription: String { tr("Subscription", zhHans: "订阅", zhHant: "訂閱", ja: "サブスクリプション") }
    static var subscriptionStatusActive: String { tr("Premium active", zhHans: "已开通会员", zhHant: "已開通會員", ja: "Premium有効") }
    static var subscriptionStatusInactive: String { tr("Not subscribed", zhHans: "未订阅", zhHant: "未訂閱", ja: "未登録") }
    static var subscriptionMonthly: String { tr("Monthly", zhHans: "月订阅", zhHant: "月訂閱", ja: "月額") }
    static var subscriptionYearly: String { tr("Yearly", zhHans: "年订阅", zhHant: "年訂閱", ja: "年額") }
    static var subscriptionLifetime: String { tr("Lifetime", zhHans: "终身", zhHant: "終身", ja: "買い切り") }
    static var subscriptionRestore: String { tr("Restore", zhHans: "恢复购买", zhHant: "恢復購買", ja: "復元") }
    static var subscriptionRestoreSubscription: String { tr("Restore Subscription", zhHans: "恢复订阅", zhHant: "恢復訂閱", ja: "サブスクリプションを復元") }
    static var subscriptionManage: String { tr("Manage", zhHans: "管理订阅", zhHant: "管理訂閱", ja: "管理") }
    static var subscriptionCurrentPlan: String { tr("Current plan", zhHans: "当前方案", zhHant: "目前方案", ja: "現在のプラン") }
    static func subscriptionRenewsOn(_ date: String) -> String {
        tr("Renews on \(date)", zhHans: "将于 \(date) 续费", zhHant: "將於 \(date) 續費", ja: "\(date) に更新")
    }
    static var subscriptionLifetimeOwned: String { tr("Lifetime access is active.", zhHans: "终身会员已生效。", zhHant: "終身會員已生效。", ja: "買い切り特典が有効です。") }
    static var proEntryTitle: String { tr("Get Pro", zhHans: "开通Pro", zhHant: "開通Pro", ja: "Proを始める") }
    static var proEntrySubtitle: String { tr("Unlock more Pro features", zhHans: "解锁更多 Pro 功能", zhHant: "解鎖更多 Pro 功能", ja: "さらに多くのPro機能を解放") }
    static var proEntryMemberTitle: String { tr("Pro Member", zhHans: "Pro 会员", zhHant: "Pro 會員", ja: "Proメンバー") }
    static var proEntryMemberSubtitle: String { tr("View your plan and benefits", zhHans: "查看你的方案和权益", zhHant: "查看你的方案與權益", ja: "プランと特典を確認") }
    static var limitedOfferHomeTitle: String { tr("Limited Offer", zhHans: "限时优惠", zhHant: "限時優惠", ja: "期間限定オファー") }
    static var limitedOfferCountdownLabel: String { tr("Offer countdown", zhHans: "优惠倒计时", zhHant: "優惠倒計時", ja: "オファー終了まで") }
    static var limitedDiscountCountdownTitle: String { tr("The special offer ends soon", zhHans: "特别优惠即将结束", zhHant: "特別優惠即將結束", ja: "特別オファーはまもなく終了") }
    static var limitedDiscountHeadline: String { tr("Lifetime Membership\nEarly supporter price", zhHans: "终身会员\n早期支持者价", zhHant: "終身會員\n早期支持者價", ja: "買い切り\n初期サポーター価格") }
    static var limitedDiscountBadge: String { tr("20% OFF", zhHans: "20% OFF", zhHant: "20% OFF", ja: "20% OFF") }
    static var limitedDiscountButtonTitle: String { tr("Enjoy the discount now", zhHans: "立即享受优惠", zhHant: "立即享受優惠", ja: "今すぐ割引を受ける") }
    static var proPaywallHeadline: String { tr("Choose your plan", zhHans: "选择你的订阅方案", zhHant: "選擇你的訂閱方案", ja: "プランを選択") }
    static var paywallMembershipTitle: String { tr("Membership", zhHans: "会员中心", zhHant: "會員中心", ja: "メンバーシップ") }
    static var paywallMembershipSubtitle: String {
        tr("Review your plan, benefits, and subscription options.", zhHans: "查看当前方案、权益和可切换的会员选项。", zhHant: "查看目前方案、權益與可切換的會員方案。", ja: "現在のプラン、特典、サブスクリプションオプションを確認。")
    }
    static var subscriptionPleaseWait: String { tr("Please wait...", zhHans: "请稍候...", zhHant: "請稍候...", ja: "しばらくお待ちください...") }
    static var subscriptionProductUnavailable: String { tr("Product is unavailable.", zhHans: "商品暂不可用。", zhHant: "商品暫不可用。", ja: "商品を利用できません。") }
    static var subscriptionPriceLoading: String { tr("Loading price…", zhHans: "正在加载价格…", zhHant: "正在載入價格…", ja: "価格を読み込み中…") }
    static var subscriptionPriceUnavailable: String { tr("Price unavailable", zhHans: "价格暂不可用", zhHant: "價格暫不可用", ja: "価格を利用できません") }
    static var subscriptionVerificationFailed: String { tr("Verification failed.", zhHans: "购买校验失败。", zhHant: "購買校驗失敗。", ja: "検証に失敗しました。") }
    static var subscriptionPurchaseSucceeded: String { tr("Purchase successful.", zhHans: "购买成功。", zhHant: "購買成功。", ja: "購入が完了しました。") }
    static var subscriptionActivationPending: String {
        tr(
            "Checking purchase status. Please wait a moment.",
            zhHans: "正在确认购买状态，请稍候。",
            zhHant: "正在確認購買狀態，請稍候。",
            ja: "購入状況を確認しています。しばらくお待ちください。"
        )
    }
    static var subscriptionPurchasePending: String { tr("Purchase is pending approval.", zhHans: "购买待确认。", zhHant: "購買待確認。", ja: "購入の承認待ちです。") }
    static var subscriptionPurchaseCancelled: String { tr("Purchase cancelled.", zhHans: "已取消购买。", zhHant: "已取消購買。", ja: "購入がキャンセルされました。") }
    static var subscriptionUnknownResult: String { tr("Unknown purchase result.", zhHans: "未知购买结果。", zhHant: "未知購買結果。", ja: "購入結果を確認できませんでした。") }
    static var subscriptionPurchaseFailed: String { tr("Purchase failed. Please try again.", zhHans: "购买失败，请稍后重试。", zhHant: "購買失敗，請稍後重試。", ja: "購入に失敗しました。しばらくしてから再試行してください。") }
    static var subscriptionRestoreSucceeded: String { tr("Restored successfully.", zhHans: "恢复购买成功。", zhHant: "恢復購買成功。", ja: "復元が完了しました。") }
    static var subscriptionNotFound: String { tr("No purchase found to restore.", zhHans: "未找到可恢复的购买。", zhHant: "未找到可恢復的購買。", ja: "復元できる購入が見つかりません。") }
    static var subscriptionRestoreFailed: String { tr("Restore failed. Please try again.", zhHans: "恢复购买失败，请稍后重试。", zhHant: "恢復購買失敗，請稍後重試。", ja: "復元に失敗しました。しばらくしてから再試行してください。") }
    static var subscriptionManageFailed: String { tr("Unable to open subscription settings.", zhHans: "暂时无法打开订阅管理。", zhHant: "暫時無法打開訂閱管理。", ja: "サブスクリプション設定を開けませんでした。") }
    static var paywallUnlockProFeatures: String { tr("Access to All Features", zhHans: "解锁全部功能", zhHant: "解鎖全部功能", ja: "すべての機能にアクセス") }
    static var paywallUnlimitedBoards: String { tr("Unlimited Bingo boards", zhHans: "无限创建 Bingo 棋盘", zhHant: "無限建立 Bingo 棋盤", ja: "Bingoボードを無制限に作成") }
    static var paywallUnlimitedQuickTasksAndGroups: String { tr("Unlimited quick tasks and groups", zhHans: "无限创建快捷任务和分组", zhHant: "無限建立快捷任務與分組", ja: "クイックタスクとグループを無制限に作成") }
    static var paywallUnlimitedBoardsTasksAndGroups: String {
        tr(
            "Unlimited boards, quick tasks, and groups",
            zhHans: "无限创建棋盘、快捷任务和分组",
            zhHant: "無限建立棋盤、快捷任務與分組"
        )
    }
    static var paywallEditAllHistoryTasks: String { tr("Edit all history tasks", zhHans: "编辑所有历史任务", zhHant: "編輯所有歷史任務", ja: "すべての履歴タスクを編集") }
    static func taskCompletionHistoryPreview(_ count: Int) -> String {
        tr(
            "Previous completions: ×\(count)",
            zhHans: "历史完成次数：×\(count)",
            zhHant: "歷史完成次數：×\(count)",
            ja: "これまでの完了回数：×\(count)"
        )
    }
    static var paywallCustomResetTime: String {
        tr(
            "Custom task reset time",
            zhHans: "自定义任务重置时间",
            zhHant: "自訂任務重置時間"
        )
    }
    static var paywallFeatureUnlimitedBoards: String {
        tr(
            "Unlimited Bingo boards for every plan.",
            zhHans: "无限制Bingo 棋盘，分开管理不同计划。",
            zhHant: "無限制 Bingo 棋盤，分開管理不同計畫。",
            ja: "すべてのプランでBingoボードを無制限に利用。"
        )
    }
    static var paywallFeatureGrid5x5: String {
        tr(
            "Unlock 5x5 boards to plan more tasks at once.",
            zhHans: "解锁5×5 大棋盘，一次安排更多任务。",
            zhHant: "解鎖 5×5 大棋盤，一次安排更多任務。",
            ja: "5x5ボードを解放して、一度により多くのタスクを計画。"
        )
    }
    static var paywallFeatureUnlimitedQuickTasks: String {
        tr(
            "Add unlimited quick tasks and reuse your routines anytime.",
            zhHans: "无限添加快捷任务，常用任务随时复用。",
            zhHant: "無限新增快捷任務，常用任務隨時複用。",
            ja: "クイックタスクを無制限に追加し、いつでもルーティンを再利用。"
        )
    }
    static var paywallFeatureUnlimitedGroups: String {
        tr(
            "Create unlimited task groups to keep your library clear.",
            zhHans: "无限创建任务分组，让任务库更清晰。",
            zhHant: "無限建立任務分組，讓任務庫更清晰。",
            ja: "タスクグループを無制限に作成して、ライブラリをすっきり管理。"
        )
    }
    static var paywallFeatureCustomRewards: String {
        tr(
            "Unlimited custom reward cards. Keep growing your rewards list.",
            zhHans: "无限张自定义奖励卡片，创建专属奖励清单。",
            zhHant: "無限張自訂獎勵卡片，创建专属獎勵清單。",
            ja: "カスタム報酬カードを無制限に追加して、専用の報酬リストを作成。"
        )
    }
    static var paywallFeatureAllHistoryTasks: String {
        tr(
            "View all history tasks and edit everything in one tap.",
            zhHans: "查看全部历史任务，一键编辑所有任务。",
            zhHant: "查看全部歷史任務，一鍵編輯所有任務。",
            ja: "すべての履歴タスクを表示し、ワンタップでまとめて編集。"
        )
    }
    static var paywallFeatureCustomResetTime: String {
        tr(
            "Set a custom reset time and refresh tasks on your rhythm.",
            zhHans: "自定义任务重置时间，用专属节奏刷新任务。",
            zhHant: "自訂任務重置時間，用專屬節奏刷新任務。",
            ja: "タスクのリセット時刻を自由に設定し、自分のペースで更新。"
        )
    }
    static var paywallUnlimitedThemesAndCustomization: String { tr("Unlimited themes and customization", zhHans: "无限主题与自定义", zhHant: "無限主題與自訂", ja: "テーマとカスタマイズを無制限に利用") }
    static var paywallSubscribeNow: String { tr("Subscribe Now", zhHans: "立即订阅", zhHant: "立即訂閱", ja: "今すぐ登録") }
    static var paywallPopular: String { tr("Popular", zhHans: "热门", zhHant: "熱門", ja: "人気") }
    static var paywallOneMonth: String { tr("1 Month", zhHans: "1个月", zhHant: "1個月", ja: "1か月") }
    static var paywallOneYear: String { tr("1 Year", zhHans: "1年", zhHant: "1年", ja: "1年") }
    static var paywallLifetime: String { tr("Lifetime", zhHans: "终身", zhHant: "終身", ja: "買い切り") }
    static var paywallCurrentPlanButton: String { tr("Current Plan", zhHans: "当前方案", zhHant: "目前方案", ja: "現在のプラン") }
    static var paywallSwitchToMonthly: String { tr("Switch to Monthly", zhHans: "切换到月订阅", zhHant: "切換到月訂閱", ja: "月額プランに変更") }
    static var paywallSwitchToYearly: String { tr("Switch to Yearly", zhHans: "切换到年订阅", zhHant: "切換到年訂閱", ja: "年額プランに変更") }
    static var paywallBuyLifetime: String { tr("Buy Lifetime", zhHans: "购买终身会员", zhHant: "購買終身會員", ja: "買い切りを購入") }
    static var paywallManageSubscription: String { tr("Manage Subscription", zhHans: "管理订阅", zhHant: "管理訂閱", ja: "サブスクリプションを管理") }
    static var paywallLifetimeAutoRenewNote: String {
        tr(
            "Lifetime access does not cancel your current subscription. Manage Subscription to turn off auto-renew if needed.",
            zhHans: "购买终身会员不会自动取消当前订阅，如有需要请到“管理订阅”中关闭自动续费。",
            zhHant: "購買終身會員不會自動取消目前訂閱，如有需要請到「管理訂閱」關閉自動續費。",
            ja: "買い切りを購入しても現在のサブスクリプションは自動で解約されません。必要に応じて「サブスクリプションを管理」で自動更新を停止してください。"
        )
    }
    static var paywallLifetimePurchaseReminder: String {
        tr(
            "Lifetime access is active. If you still have an auto-renewable subscription, please manage it in the App Store to avoid future renewals.",
            zhHans: "终身会员已生效。如果你仍有自动续费订阅，请前往 App Store 管理订阅，避免后续继续续费。",
            zhHant: "終身會員已生效。如果你仍有自動續費訂閱，請前往 App Store 管理訂閱，避免後續繼續續費。",
            ja: "買い切り特典は有効です。自動更新サブスクリプションが残っている場合は、今後の更新を避けるためApp Storeで管理してください。"
        )
    }
    static var paywallOneTimePayment: String { tr("One-time payment", zhHans: "一次性付款", zhHant: "一次性付款", ja: "買い切り") }
    static var paywallLegalPrefix: String { tr("By continuing, you agree to our", zhHans: "继续即表示你同意我们的", zhHant: "繼續即表示你同意我們的", ja: "続行すると、以下に同意したことになります：") }
    static var paywallLegalAnd: String { tr("and", zhHans: "和", zhHant: "和", ja: "および") }
    static var paywallTermsOfUse: String { tr("Terms of Use", zhHans: "使用条款", zhHant: "使用條款", ja: "利用規約") }
    static var paywallPrivacyPolicy: String { tr("Privacy Policy", zhHans: "隐私政策", zhHant: "隱私政策", ja: "プライバシーポリシー") }
    static var paywallLegalOneLine: String { tr("By continuing, you agree to Terms of Use and Privacy Policy.", zhHans: "继续即表示你同意《使用条款》和《隐私政策》。", zhHant: "繼續即表示你同意《使用條款》和《隱私政策》。", ja: "続行すると、利用規約とプライバシーポリシーに同意したことになります。") }
    static func paywallPerMonth(_ value: String) -> String {
        tr("\(value) / month", zhHans: "\(value) / 月", zhHant: "\(value) / 月", ja: "\(value) / 月")
    }
    static func paywallOnlyPerMonth(_ value: String) -> String {
        tr("Only \(value) per month", zhHans: "每月仅 \(value)", zhHant: "每月僅 \(value)", ja: "月あたり \(value)")
    }
    static var paywallEarlySupporterSubtitle: String {
        tr("Early supporter exclusive", zhHans: "早期支持者限定", zhHant: "早期支持者限定", ja: "early supporter 限定")
    }
    static func paywallOnlyMonthlyPriceSubtitle(_ value: String) -> String {
        tr("Only \(value) / month", zhHans: "仅需\(value)/月", zhHant: "僅需\(value)/月", ja: "月あたり\(value)")
    }
    static var paywallMilkTeaPriceSubtitle: String {
        tr("Only the price of a milk tea", zhHans: "仅需一杯奶茶的价格", zhHant: "僅需一杯奶茶的價格", ja: "ミルクティー1杯ほどの価格")
    }
    static var paywallHeroTitle: String { tr("Unlimited Boards", zhHans: "无限棋盘", zhHant: "無限棋盤", ja: "無制限ボード") }
    static var paywallHeroSubtitle: String { tr("Manage different plans separately", zhHans: "分开管理不同计划", zhHant: "分開管理不同計畫", ja: "別々のプランを管理できます") }
    static var paywallHeroAllFeaturesTitle: String { tr("Unlock all features", zhHans: "解锁所有功能", zhHant: "解鎖所有功能", ja: "すべての機能を解放") }
    static var paywallHeroAllFeaturesSubtitle: String { tr("Unlock the full version with unlimited access", zhHans: "解锁完整版本，功能无限制使用", zhHant: "解鎖完整版本，功能無限制使用", ja: "完全版を解放し、機能を無制限に利用") }
    static var paywallHeroGridTitle: String { tr("Bigger Boards", zhHans: "更大棋盘", zhHant: "更大棋盤", ja: "大きなボード") }
    static var paywallHeroGridSubtitle: String { tr("Unlock 5x5 for more tasks", zhHans: "解锁 5×5，容纳更多任务", zhHant: "解鎖 5×5，容納更多任務", ja: "5x5でより多くのタスクを管理") }
    static var paywallHeroQuickTasksTitle: String { tr("Unlimited Quick tasks", zhHans: "无限快捷任务", zhHant: "無限快捷任務", ja: "無制限のクイックタスク") }
    static var paywallHeroQuickTasksSubtitle: String { tr("Save routines and reuse them anytime", zhHans: "保存常用任务，随时复用", zhHant: "保存常用任務，隨時複用", ja: "ルーティンを保存して再利用") }
    static var paywallHeroGroupsTitle: String { tr("Unlimited Task groups", zhHans: "无限任务分组", zhHant: "無限任務分組", ja: "無制限のタスクグループ") }
    static var paywallHeroGroupsSubtitle: String { tr("Keep your task library organized", zhHans: "让任务库保持清晰有序", zhHant: "讓任務庫保持清晰有序", ja: "タスク一覧をすっきり整理") }
    static var paywallHeroRewardsTitle: String { tr("Custom Rewards", zhHans: "自定义奖励", zhHant: "自訂獎勵", ja: "カスタム報酬") }
    static var paywallHeroRewardsSubtitle: String { tr("Create rewards that keep you motivated", zhHans: "创建专属奖励，保持动力", zhHant: "建立專屬獎勵，保持動力", ja: "自分用の報酬で意欲を維持") }
    static var paywallHeroHistoryTitle: String { tr("Task History", zhHans: "任务历史", zhHant: "任務歷史", ja: "タスク履歴") }
    static var paywallHeroHistorySubtitle: String { tr("View and edit all past tasks", zhHans: "查看并编辑全部历史任务", zhHant: "查看並編輯全部歷史任務", ja: "過去のタスクを確認・編集") }
    static var paywallHeroResetTitle: String { tr("Flexible Reset", zhHans: "弹性重置", zhHant: "彈性重置", ja: "柔軟なリセット") }
    static var paywallHeroResetSubtitle: String { tr("Refresh tasks on your rhythm", zhHans: "按你的节奏刷新任务", zhHant: "按你的節奏重新整理任務", ja: "自分のペースでタスクを更新") }
    static var paywallLastMonthSpecialOffer: String { tr("Last month of special offer", zhHans: "限时优惠最后一个月", zhHant: "限時優惠最後一個月", ja: "特別オファー最終月") }
    static var paywallSpecialOfferCountdown: String { tr("Offer countdown", zhHans: "优惠结束倒计时", zhHant: "優惠結束倒計時", ja: "オファー終了まで") }
    static var paywallGetFullAccess: String { tr("Get full Access", zhHans: "解锁全部权益", zhHant: "解鎖全部權益", ja: "全機能を利用") }
    static var paywallBenefitUnlimitedBoardsTitle: String { tr("Unlimited Boards", zhHans: "无限棋盘", zhHant: "無限棋盤", ja: "無制限ボード") }
    static var paywallBenefitUnlimitedBoardsSubtitle: String { tr("Make as many boards as you want.", zhHans: "按需创建任意数量的棋盘。", zhHant: "按需建立任意數量的棋盤。", ja: "好きなだけボードを作成できます。") }
    static var paywallBenefitBiggerBoardsTitle: String { tr("Bigger Boards", zhHans: "更大棋盘", zhHant: "更大棋盤", ja: "大きなボード") }
    static var paywallBenefitBiggerBoardsSubtitle: String { tr("Unlock 5x5 boards for more tasks.", zhHans: "解锁 5×5 棋盘，容纳更多任务。", zhHant: "解鎖 5×5 棋盤，容納更多任務。", ja: "5x5ボードでより多くのタスクを管理。") }
    static var paywallBenefitReusableTasksTitle: String { tr("Reusable Tasks", zhHans: "复用任务", zhHant: "複用任務", ja: "再利用タスク") }
    static var paywallBenefitReusableTasksSubtitle: String { tr("Save routines and add them again anytime.", zhHans: "保存日常任务，随时再次添加。", zhHant: "保存日常任務，隨時再次新增。", ja: "ルーティンを保存していつでも追加。") }
    static var paywallBenefitTaskGroupsTitle: String { tr("Task Groups", zhHans: "任务分组", zhHant: "任務分組", ja: "タスクグループ") }
    static var paywallBenefitTaskGroupsSubtitle: String { tr("Keep your task library clean and organized.", zhHans: "保持任务库清晰有序。", zhHant: "保持任務庫清晰有序。", ja: "タスク一覧をすっきり整理。") }
    static var paywallBenefitCustomRewardsTitle: String { tr("Custom Rewards", zhHans: "自定义奖励", zhHant: "自訂獎勵", ja: "カスタム報酬") }
    static var paywallBenefitCustomRewardsSubtitle: String { tr("Create unlimited rewards to stay motivated.", zhHans: "创建不限数量奖励，保持动力。", zhHant: "建立不限數量獎勵，保持動力。", ja: "報酬を自由に作成して意欲を維持。") }
    static var paywallBenefitTaskHistoryTitle: String { tr("Task History", zhHans: "任务历史", zhHant: "任務歷史", ja: "タスク履歴") }
    static var paywallBenefitTaskHistorySubtitle: String { tr("Review and edit past tasks in one tap.", zhHans: "一键查看并编辑历史任务。", zhHant: "一鍵查看並編輯歷史任務。", ja: "過去のタスクをすぐ確認、編集。") }
    static var paywallBenefitFlexibleResetTitle: String { tr("Flexible Reset", zhHans: "灵活重置", zhHant: "彈性重置", ja: "柔軟なリセット") }
    static var paywallBenefitFlexibleResetSubtitle: String { tr("Choose when your tasks refresh each day.", zhHans: "选择每天任务刷新的时间。", zhHant: "選擇每天任務重新整理的時間。", ja: "毎日の更新時刻を選択できます。") }
    static var paywallBenefitMoreFeaturesTitle: String { tr("More Features Coming", zhHans: "更多功能即将上线", zhHant: "更多功能即將上線", ja: "さらに機能追加予定") }
    static var paywallBenefitMoreFeaturesSubtitle: String { tr("We'll keep adding new features to make your Bingo experience even better.", zhHans: "我们会继续加入新功能，让 Bingo 体验更好。", zhHant: "我們會持續加入新功能，讓 Bingo 體驗更好。", ja: "Bingo体験をさらに良くする機能を追加していきます。") }
    static var haptics: String { tr("Haptics", zhHans: "震动反馈", ja: "触覚フィードバック") }
    static var soundEffects: String { tr("Sound Effects", zhHans: "音效", ja: "効果音") }
    static var homeWidget: String { tr("Home Widget", zhHans: "桌面小组件", ja: "ホームウィジェット") }
    static var homeWidgetInstructions: String {
        tr(
            "To add a widget: long-press the Home Screen, tap Edit or +, search Bingodays, then choose a size and tap Add Widget.",
            zhHans: "添加小组件：长按主屏幕，点击编辑或 +，搜索 Bingodays，然后选择尺寸并点击添加小组件。"
        )
    }
    static var dayStreak: String { tr("day streak", zhHans: "连胜天数", ja: "日連続") }
    static var streakGoals: String { tr("Streak Goals", zhHans: "连胜目标", ja: "連続目標") }
    static var themeColor: String { tr("Theme Color", zhHans: "主题颜色", ja: "テーマカラー") }
    static var myPoints: String { tr("My Points", zhHans: "我的积分", ja: "マイポイント") }
    static var stickers: String { tr("Stickers", zhHans: "贴纸", ja: "ステッカー") }
    static var myRewards: String { tr("Custom Rewards", zhHans: "自定义奖励", ja: "カスタム報酬") }
    static var addReward: String { tr("Add Reward", zhHans: "添加奖励", ja: "報酬を追加") }
    static var addRewards: String { tr("Add Rewards", zhHans: "添加奖励", zhHant: "新增獎勵", ja: "報酬を追加") }
    static var editReward: String { tr("Edit Reward", zhHans: "编辑奖励", ja: "報酬を編集") }
    static var rewardCard: String { tr("Reward Card", zhHans: "奖励卡片", zhHant: "獎勵卡片", ja: "報酬カード") }
    static var rewardTitle: String { tr("Reward Title", zhHans: "奖励名称", ja: "報酬名") }
    static var rewardNamePlaceholder: String { tr("Enter Reward Name", zhHans: "输入奖励名称", zhHant: "輸入獎勵名稱", ja: "報酬名を入力") }
    static var rewardPoints: String { tr("Required Points", zhHans: "所需积分", ja: "必要ポイント") }
    static var rewardSetRedeem: String { tr("Set redeem", zhHans: "设置兑换", zhHant: "設定兌換", ja: "交換ポイント") }
    static var rewardSetRedeemPts: String { tr("Set redeem pts", zhHans: "设置兑换 pts", zhHant: "設定兌換 pts", ja: "交換ptを設定") }
    static func rewardSetRedeemPts(_ points: String) -> String {
        tr("Set redeem \(points) pts", zhHans: "设置兑换 \(points) pts", zhHant: "設定兌換 \(points) pts", ja: "\(points) ptで交換")
    }
    static var rewardExampleHint: String { tr("Example: Milk Tea", zhHans: "例如：喝一杯奶茶", ja: "例：ミルクティー") }
    static var rewardPointsHint: String { tr("Example: 50", zhHans: "例如：50", ja: "例：50") }
    static var noRewardsYet: String { tr("Create your own rewards and redeem them with points.", zhHans: "创建你自己的奖励，并用积分进行兑换。", ja: "自分だけの報酬を作成して、ポイントで交換しましょう。") }
    static var emptyCustomRewardsMessage: String {
        tr(
            "Come and add your exclusive\nrewards to make the tasks more fun!",
            zhHans: "来添加你的专属奖励\n让任务变得更有趣！",
            zhHant: "來新增你的專屬獎勵\n讓任務變得更有趣！",
            ja: "あなただけの報酬を追加して\nタスクをもっと楽しくしよう！"
        )
    }
    static var cardSkin: String { tr("Card Skin", zhHans: "卡片皮肤", zhHant: "卡片外觀", ja: "カードスキン") }
    static var emoji: String { tr("Emoji", zhHans: "表情", zhHant: "表情", ja: "絵文字") }
    static var rewardEmojiKeyboardHint: String {
        tr("Decorate the reward card with an emoji!", zhHans: "用emoji来装饰奖励卡片吧！", zhHant: "用emoji來裝飾獎勵卡片吧！", ja: "絵文字で報酬カードをデコレーションしよう！")
    }
    static var rewardEmojiHistory: String { tr("Recently used", zhHans: "最近使用", zhHant: "最近使用", ja: "最近使用") }
    static var rewardTheme: String { tr("theme", zhHans: "主题", zhHant: "主題", ja: "テーマ") }
    static var customPhoto: String { tr("Custom Photo", zhHans: "自定义照片", zhHant: "自訂照片", ja: "カスタム写真") }
    static var rewardRedeemed: String { tr("Redeemed", zhHans: "已兑换", ja: "交換済み") }
    static func redeemedCount(_ count: Int) -> String {
        tr("Redeemed x\(count)", zhHans: "已兑换 x\(count)", ja: "交換済み x\(count)")
    }
    static var done: String { tr("Done", zhHans: "完成", ja: "完了") }
    static var addToHome: String { tr("Add to Home", zhHans: "添加到首页", ja: "ホームに追加") }
    static var redeem: String { tr("Redeem", zhHans: "兑换", ja: "交換する") }
    static var onHome: String { tr("On Home", zhHans: "已在首页", ja: "ホームに追加済み") }
    static var stickerRevokedDueToPoints: String {
        tr(
            "Some stickers were removed because your available points decreased.",
            zhHans: "可用积分减少，部分贴纸已失效。",
            zhHant: "可用積分減少，部分貼紙已失效。"
        )
    }
    static var pointRedemptionsRevokedDueToPoints: String {
        tr(
            "Some redeemed items were removed because your available points decreased.",
            zhHans: "可用积分减少，部分已兑换项目已失效。",
            zhHant: "可用積分減少，部分已兌換項目已失效。"
        )
    }
    static func ownedCount(_ count: Int) -> String {
        tr("Owned x\(count)", zhHans: "已拥有 x\(count)", ja: "所有 x\(count)")
    }
    static var tasks: String { tr("Tasks", zhHans: "任务", ja: "タスク") }
    static var groups: String { tr("Groups", zhHans: "分组", ja: "グループ") }
    static var myTasksHint: String { tr("Edit tasks and groups here, choose what to use, then tap Save to apply to the board.", zhHans: "在这里编辑任务和分组，勾选要使用的内容，点左上角保存应用到棋盘。", ja: "ここでタスクとグループを編集し、使うものを選んで保存するとボードに反映されます。") }
    static var tasksSectionHint: String { tr("Save the quick tasks you use most often.", zhHans: "保存你最常用的快捷任务。", ja: "よく使うクイックタスクを保存します。") }
    static var groupsSectionHint: String { tr("Bundle a few tasks together so you can apply them in one tap.", zhHans: "把多个任务打包成分组，方便一键应用。", ja: "複数のタスクをグループ化して、ワンタップで適用できます。") }
    static var noTasksYet: String { tr("You haven't added any tasks yet.", zhHans: "你还没有添加任何任务。", ja: "タスクはまだ追加されていません。") }
    static var noGroupsYet: String { tr("You haven't added any groups yet.", zhHans: "你还没有添加任何分组。", ja: "グループはまだ追加されていません。") }
    static var addTask: String { tr("Add Task", zhHans: "添加任务", ja: "タスクを追加") }
    static var addGroup: String { tr("Add Group", zhHans: "添加分组", ja: "グループを追加") }
    static var quickEdit: String { tr("Quick Edit", zhHans: "快速编辑", ja: "クイック編集") }
    static var updateWhatsNewTitle: String { tr("What's New", zhHans: "版本更新", zhHant: "版本更新", ja: "新機能") }
    static func updateVersionTitle(_ version: String) -> String {
        tr("Bingodays \(version)", zhHans: "Bingodays \(version)", zhHant: "Bingodays \(version)", ja: "Bingodays \(version)")
    }
    static var updateItemQuickEditImproved: String {
        tr(
            "Good news! You can now check off tasks directly from widgets. Update now to try it.",
            zhHans: "好消息！现在可以在小组件上直接打卡任务了！快更新版本体验吧",
            zhHant: "好消息！現在可以在小工具上直接打卡任務了！快更新版本體驗吧",
            ja: "朗報です！ウィジェットから直接タスクをチェックできるようになりました。今すぐ更新してお試しください。"
        )
    }
    static var updateItemKnownIssuesFixed: String {
        tr(
            "Widget task check-ins are now supported.",
            zhHans: "支持在小组件上直接打卡任务。",
            zhHant: "支援在小工具上直接打卡任務。",
            ja: "ウィジェットでのタスクチェックに対応しました。"
        )
    }
    static var updatePrimaryAction: String { tr("Update Now", zhHans: "去更新", zhHant: "去更新", ja: "今すぐ更新") }
    static var updateSecondaryAction: String { tr("Later", zhHans: "稍后", zhHant: "稍後", ja: "あとで") }
    static var updateStoreOpenFailed: String {
        tr("Unable to open App Store right now.", zhHans: "暂时无法打开 App Store。", ja: "現在App Storeを開けません。")
    }
    static var onboardingMadeForADHDBrains: String { tr("Made for ADHD brains", zhHans: "Made for ADHD brains", ja: "ADHDの脳に合わせて設計") }
    static var onboardingIntroHeadline: String { tr("Turn Daily\nLife into", zhHans: "将日常生活\n变成", ja: "毎日の生活を") }
    static var onboardingGetStarted: String { tr("Get Started", zhHans: "开始", ja: "始める") }
    static var onboardingExistingAccount: String { tr("I already have an account", zhHans: "我已经有账号", ja: "すでにアカウントを持っています") }
    static var onboardingFooterPrefix: String { tr("By continuing you're accepting our ", zhHans: "继续即表示你同意我们的", ja: "続行すると、以下に同意したことになります：") }
    static var onboardingTermsOfService: String { tr("Terms of Service", zhHans: "服务条款", ja: "利用規約") }
    static var onboardingAnd: String { tr(" and", zhHans: "和", ja: "および") }
    static var onboardingPrivacyPolicy: String { tr("Privacy Policy", zhHans: "隐私政策", ja: "プライバシーポリシー") }
    static var onboardingResearchHeadline: String { tr("Well\naccording\nto the\nresearch", zhHans: "根据一直以来\n的研究表明", ja: "研究に\nよると") }
    static var onboardingResearchBody: String {
        tr("Traditional to do list doesn't work especially\nwith ADHD", zhHans: "传统的To Do List并不适合ADHD人群", ja: "従来のToDoリストは、とくにADHDには合いにくい")
    }
    static var onboardingNext: String { tr("Next", zhHans: "继续", ja: "次へ") }
    static var onboardingBrandHeadline: String { tr("That's\nwhy you\nshould try", zhHans: "所以我们向\n你推荐", ja: "だから\n試してほしい") }
    static var onboardingStressFree: String { tr("Stress-free", zhHans: "Stress-free", ja: "ストレスフリー") }
    static var onboardingSimplified: String { tr("Simplified", zhHans: "Simplified", ja: "シンプル") }
    static var onboardingGridHeadline: String { tr("Turn your\nto-do list\ninto a Bingo\nboard", zhHans: "把待办清单\n变为Bingo格子", ja: "ToDoリストを\nBingoボードに") }
    static var onboardingPaceHeadline: String { tr("Complete\nTasks at\nYour Own\nPace", zhHans: "用自己的专\n属节奏打卡\n任务", ja: "自分のペースで\nタスクを完了") }
    static var onboardingBestMode: String { tr("Best Mode", zhHans: "Best Mode", ja: "ベストモード") }
    static var onboardingPersonalized: String { tr("- Personalized -", zhHans: "- Personalized -", ja: "- パーソナライズ -") }
    static var onboardingRewardsHeadline: String { tr("Make Every\nDay a Bingo", zhHans: "把每一天都\n变成Bingo", ja: "毎日を\nBingoに") }
    static var onboardingRewardsSubtitle: String {
        tr("Earn points and redeem your own rewards", zhHans: "积分兑换奖励，更有动力继续", ja: "ポイントを貯めて、自分だけの報酬と交換")
    }
    static var onboardingLetsBingo: String { tr("Let's Bingo", zhHans: "Let's Bingo", ja: "Bingoを始めよう") }
    static var onboardingLoginWelcomeTo: String { tr("Welcome to", zhHans: "Welcome to", ja: "ようこそ") }
    static var apply: String { tr("Apply", zhHans: "应用", ja: "適用") }
    static var selectAll: String { tr("Select All", zhHans: "全选", ja: "すべて選択") }
    static var deselectAll: String { tr("Deselect All", zhHans: "全取消", ja: "すべて解除") }
    static var random: String { tr("Random", zhHans: "随机", ja: "ランダム") }
    static var allTasks: String { tr("All Tasks", zhHans: "全部任务", ja: "すべてのタスク") }
    static func quickEditSelectedCount(selected: Int, total: Int) -> String {
        tr("\(selected)/\(total) selected", zhHans: "已选 \(selected)/\(total)", ja: "\(selected)/\(total) 選択済み")
    }
    static var quickEditNoTasksInFilter: String {
        tr("No tasks in this filter yet.", zhHans: "该筛选下还没有任务。", ja: "このフィルターにはまだタスクがありません。")
    }
    static var quickEditAddGroupTitle: String {
        tr("Add New Group", zhHans: "添加新分组", ja: "新しいグループを追加")
    }
    static var quickEditEditGroupTitle: String {
        tr("Edit Group Name", zhHans: "编辑分组名称", zhHant: "編輯分組名稱", ja: "グループ名を編集")
    }
    static var quickEditEditGroupName: String {
        tr("Edit Group Name", zhHans: "编辑分组名称", zhHant: "編輯分組名稱", ja: "グループ名を編集")
    }
    static var quickEditDeleteGroup: String {
        tr("Delete Group", zhHans: "删除分组", zhHant: "刪除分組", ja: "グループを削除")
    }
    static var quickEditGroupRenamedSuccess: String {
        tr("Group name updated", zhHans: "分组名称已更新", zhHant: "分組名稱已更新", ja: "グループ名を更新しました")
    }
    static var quickEditGroupNamePlaceholder: String {
        tr("Enter group name...", zhHans: "输入分组名称...", ja: "グループ名を入力...")
    }
    static var quickEditTaskNamePlaceholder: String {
        tr("Enter task name...", zhHans: "输入任务名称...", ja: "タスク名を入力...")
    }
    static var quickEditTaskEditorTitle: String {
        tr("Edit Task", zhHans: "编辑任务", ja: "タスクを編集")
    }
    static var quickEditTaskStartDate: String {
        tr("Start Date", zhHans: "开始时间", ja: "開始日")
    }
    static var quickEditTaskStartMonth: String {
        tr("Month", zhHans: "月", ja: "月")
    }
    static var quickEditTaskStartDay: String {
        tr("Day", zhHans: "日", ja: "日")
    }
    static var quickEditTaskNoStartDate: String {
        tr("No start date", zhHans: "不设置开始时间", ja: "開始日なし")
    }
    static var quickEditApplyGroup: String {
        tr("Apply Group", zhHans: "应用分组", ja: "グループを適用")
    }
    static var quickEditGroupAppliedToPreview: String {
        tr("Group applied to preview", zhHans: "分组已应用到预览", ja: "グループをプレビューに適用しました")
    }
    static func quickEditGroupPartiallyApplied(_ count: Int) -> String {
        tr(
            "Not enough empty tiles. \(count) tasks weren't added.",
            zhHans: "当前棋盘空位不足，\(count) 个任务未添加。",
            zhHant: "目前棋盤空位不足，\(count) 個任務未加入。",
            ja: "空きマスが足りないため、\(count)件のタスクを追加できませんでした。"
        )
    }
    static var gridSize: String { tr("Grid Size", zhHans: "格子大小", ja: "グリッドサイズ") }
    static var gridSizePremiumLimitMessage: String {
        tr("Upgrade to Pro to unlock 5x5 grid.", zhHans: "开通 Pro 后可解锁 5x5 格子。", zhHant: "開通 Pro 後可解鎖 5x5 格子。", ja: "Proにアップグレードすると5x5グリッドを解放できます。")
    }
    static func selectedTaskCount(_ count: Int, usedCount: Int) -> String {
        tr("Selected \(count) (\(usedCount) used for current board)", zhHans: "已选 \(count) 个（当前尺寸使用前 \(usedCount) 个）", ja: "\(count)件選択済み（現在のボードで\(usedCount)件使用）")
    }
    static func quickEditSelectionSummary(selected: Int, missing: Int) -> String {
        if missing > 0 {
            return tr("Selected \(selected), need \(missing)", zhHans: "已选\(selected)，差\(missing)", ja: "\(selected)件選択、あと\(missing)件必要")
        }
        return tr("Selected \(selected), full", zhHans: "已选\(selected)，已满", ja: "\(selected)件選択、満杯")
    }
    static func quickEditAppliedSuccess(_ count: Int) -> String {
        tr("Applied \(count) tasks", zhHans: "已应用 \(count) 个任务", ja: "\(count)件のタスクを適用しました")
    }
    static var quickEditReplaceConfirmationTitle: String {
        tr("Apply and replace current board?", zhHans: "确认应用？", ja: "適用して現在のボードを置き換えますか？")
    }
    static var quickEditReplaceConfirmationMessage: String {
        tr("This will replace existing tasks on the current board.", zhHans: "将替换当前棋盘已有任务。", ja: "現在のボード上の既存タスクが置き換えられます。")
    }
    static var quickEditKeptBoardWithoutSelection: String {
        tr("No selection. Kept current board.", zhHans: "未选择任务，已保留当前棋盘。", ja: "選択なし。現在のボードを保持しました。")
    }
    static func quickEditNeedMoreTasks(_ count: Int) -> String {
        tr("Add \(count) more tasks to fill this grid", zhHans: "还需 \(count) 个任务可填满当前尺寸", ja: "このグリッドを埋めるにはあと\(count)件のタスクが必要です")
    }
    static var quickEditPremiumLimitMessage: String {
        tr("Upgrade to Pro for unlimited tasks and groups.", zhHans: "开通 Pro 后可无限创建任务和分组。", zhHant: "開通 Pro 後可無限建立任務與分組。", ja: "Proにアップグレードするとタスクとグループを無制限に作成できます。")
    }
    static var quickEditHistoryPaywallHint: String {
        tr("Upgrade to view all task history.", zhHans: "升级查看所有历史任务", zhHant: "升級查看所有歷史任務", ja: "すべてのタスク履歴を表示するにはアップグレード")
    }
    static var quickEditHistoryTag: String {
        tr("History", zhHans: "历史", zhHant: "歷史", ja: "履歴")
    }
    static var taskAddedSuccess: String { tr("Task added", zhHans: "任务已添加", ja: "タスクを追加しました") }
    static var groupAddedSuccess: String { tr("Group added", zhHans: "分组已添加", ja: "グループを追加しました") }
    static var tasksAndGroupsAddedSuccess: String { tr("Changes saved", zhHans: "已保存更改", ja: "変更を保存しました") }
    static var tasksSavedSuccess: String { tr("Saved successfully", zhHans: "保存成功", ja: "保存しました") }
    static var deleteConfirmationTitle: String { tr("Delete", zhHans: "删除", ja: "削除") }
    static var deleteTaskConfirmationMessage: String { tr("This task will be removed from My Tasks.", zhHans: "该任务将从「我的任务」中移除。", ja: "このタスクは「マイタスク」から削除されます。") }
    static var deleteGroupConfirmationMessage: String { tr("This group will be removed from My Tasks.", zhHans: "该分组将从「我的任务」中移除。", ja: "このグループは「マイタスク」から削除されます。") }
    static var taskDeletedSuccess: String { tr("Task deleted", zhHans: "任务已删除", ja: "タスクを削除しました") }
    static var groupDeletedSuccess: String { tr("Group deleted", zhHans: "分组已删除", ja: "グループを削除しました") }
    static var tasksAndGroupsDeletedSuccess: String { tr("Changes deleted", zhHans: "已删除更改", ja: "変更を削除しました") }
    static var groupName: String { tr("Group Name", zhHans: "分组名称", ja: "グループ名") }
    static func taskNumber(_ index: Int) -> String { tr("Task \(index)", zhHans: "任务 \(index)", ja: "タスク \(index)") }
    static var task: String { tr("Task", zhHans: "任务", ja: "タスク") }
    static var diaryHint: String { tr("Tap a completed date to view that day's Bingo board.", zhHans: "点击已完成的日期，查看当天的 Bingo 面板。", ja: "完了した日付をタップして、その日のBingoボードを確認します。") }
    static var taskCompletions: String { tr("Completed Task Stats", zhHans: "完成任务统计", ja: "完了タスク統計") }
    static var timeoutUnfinishedStats: String { tr("Timed-out Unfinished", zhHans: "超时未完成", ja: "タイムアウト未完了") }
    static var completedTasksShort: String { tr("Completed Tasks", zhHans: "完成任务", ja: "完了タスク") }
    static var timeoutTasksShort: String { tr("Timed-out Tasks", zhHans: "超时任务", ja: "タイムアウトタスク") }
    static var completion: String { tr("Completion", zhHans: "完成度", ja: "完了率") }
    static var last7Days: String { tr("7 Days", zhHans: "近 7 天", ja: "7日間") }
    static var last30Days: String { tr("30 Days", zhHans: "近 30 天", ja: "30日間") }
    static var statsWeekShort: String { tr("Week", zhHans: "周", ja: "週") }
    static var statsMonthShort: String { tr("Month", zhHans: "月", ja: "月") }
    static var statsYearShort: String { tr("Year", zhHans: "年", ja: "年") }
    static var noTaskCompletions: String { tr("No completed tasks yet.", zhHans: "暂时还没有已完成的任务。", ja: "完了したタスクはまだありません。") }
    static var noTimeoutUnfinishedTasks: String { tr("No timed-out unfinished tasks.", zhHans: "暂无超时未完成任务。", ja: "タイムアウトした未完了タスクはありません。") }
    static func completedTimes(_ count: Int) -> String {
        tr("\(count) times", zhHans: "\(count) 次", ja: "\(count)回")
    }
    static func completedTimesCompact(_ count: Int) -> String {
        tr("x\(count)", zhHans: "x\(count)", ja: "x\(count)")
    }
    static func completionDaysCompact(_ days: Int) -> String {
        tr("\(days) days", zhHans: "\(days)天", ja: "\(days)日")
    }
    static func completionPercentCompact(_ percent: Int) -> String {
        "\(percent)%"
    }
    static var pointsUnit: String { tr("pts", zhHans: "积分", ja: "pt") }
    static var boardCountdownTitle: String { tr("Bingo Board Countdown", zhHans: "Bingo 面板倒计时", ja: "Bingoボードカウントダウン") }
    static var boardCountdownDescription: String { tr("Auto-clear the entire board when time runs out.", zhHans: "时间结束后自动清空整个面板。", ja: "時間切れになるとボード全体を自動でクリアします。") }
    static var completedTaskCountdownBlocked: String {
        tr(
            "Completed tasks cannot set countdown. Please mark it incomplete first.",
            zhHans: "已完成任务不能设置倒计时，请先取消完成。",
            zhHant: "已完成任務不能設置倒計時，請先取消完成。"
        )
    }
    static var boardSwitcherTitle: String { tr("Boards", zhHans: "棋盘", zhHant: "棋盤", ja: "ボード") }
    static var boardCreateTitle: String { tr("Create board", zhHans: "创建棋盘", zhHant: "建立棋盤", ja: "ボードを作成") }
    static var boardRenameTitle: String { tr("Rename board", zhHans: "重命名棋盘", zhHant: "重新命名棋盤", ja: "ボード名を変更") }
    static var boardNamePlaceholder: String { tr("Board name", zhHans: "棋盘名称", zhHant: "棋盤名稱", ja: "ボード名") }
    static var boardCreateAction: String { tr("Create", zhHans: "创建", zhHant: "建立", ja: "作成") }
    static var boardRenameAction: String { tr("Rename", zhHans: "重命名", zhHant: "重新命名", ja: "名前を変更") }
    static var boardCreateButton: String { tr("New Board", zhHans: "新建棋盘", zhHant: "新增棋盤", ja: "新しいボード") }
    static var boardManageAction: String { tr("Manage boards", zhHans: "管理棋盘", zhHant: "管理棋盤", ja: "ボードを管理") }
    static var boardPremiumLimitMessage: String {
        tr(
        "Pro required for multiple boards.",
        zhHans: "开通 Pro 后可创建多个棋盘。",
        zhHant: "開通 Pro 後可建立多個棋盤。",
        ja: "複数のボードを作成するにはProが必要です。"
        )
    }
    static func boardDefaultName(_ index: Int) -> String {
        tr("Board \(index)", zhHans: "棋盘\(index)", zhHant: "棋盤\(index)", ja: "ボード\(index)")
}
    static var clearBoard: String { tr("Clear Board", zhHans: "清空棋盘", ja: "ボードをクリア") }
    static var clearBoardConfirmationTitle: String { tr("Clear board?", zhHans: "清空棋盘？", ja: "ボードをクリアしますか？") }
    static var clearBoardConfirmationMessage: String { tr("This will remove all tasks and completion states on the current board.", zhHans: "这会清除当前棋盘的所有任务和完成状态。", ja: "現在のボード上のすべてのタスクと完了状態が削除されます。") }
    static var boardClearedSuccess: String { tr("Board cleared", zhHans: "棋盘已清空", ja: "ボードをクリアしました") }
    static var hours: String { tr("Hours", zhHans: "小时", ja: "時間") }
    static var minutes: String { tr("Minutes", zhHans: "分钟", ja: "分") }
    static var residentDays: String { tr("Repeat Days", zhHans: "重复天数", zhHant: "重複天數", ja: "繰り返し日") }
    static var alwaysVisible: String { tr("Always", zhHans: "每天", ja: "常に") }
    static var todayOnly: String { tr("Single", zhHans: "单次", zhHant: "單次", ja: "単発") }
    static var taskScheduledTitle: String { tr("Task Scheduled", zhHans: "任务已安排", ja: "タスクを予定しました") }
    static func taskScheduledMessage(_ days: String) -> String {
        tr("This task will appear on \(days).", zhHans: "此任务会在 \(days) 显示。", ja: "このタスクは\(days)に表示されます。")
    }
    static var cancel: String { tr("Cancel", zhHans: "取消", ja: "キャンセル") }
    static var save: String { tr("Save", zhHans: "保存", ja: "保存") }
    static func boardWillClearIn(hours: Int, minutes: Int) -> String {
        tr(
            "Countdown ends in \(hours)h \(minutes)m. You can then choose to complete, abandon, or postpone.",
            zhHans: "倒计时将在 \(hours) 小时 \(minutes) 分钟后结束。之后你可以选择完成、放弃或延后。",
            zhHant: "倒計時將在 \(hours) 小時 \(minutes) 分鐘後結束。之後你可以選擇完成、放棄或延後。",
            ja: "カウントダウンは\(hours)時間\(minutes)分後に終了します。その後、完了・放棄・延期を選べます。"
        )
    }
    static var boardWillClearIn24Hours: String {
        tr(
            "Countdown ends in 24 hours. You can then choose to complete, abandon, or postpone.",
            zhHans: "倒计时将在 24 小时后结束。之后你可以选择完成、放弃或延后。",
            zhHant: "倒計時將在 24 小時後結束。之後你可以選擇完成、放棄或延後。",
            ja: "カウントダウンは24時間後に終了します。その後、完了・放棄・延期を選べます。"
        )
    }
    static var boardCountdownMinimumOneMinute: String {
        tr("Set at least 1 minute.", zhHans: "最少设置1分钟", zhHant: "最少設置1分鐘", ja: "1分以上に設定してください。")
    }
    static func hourValue(_ hour: Int) -> String { tr("\(hour)h", zhHans: "\(hour)小时", ja: "\(hour)時間") }
    static func minuteValue(_ minute: Int) -> String { tr("\(minute)m", zhHans: "\(minute)分", ja: "\(minute)分") }
    static var estimatedCompletionTime: String { tr("Estimated Time", zhHans: "预计完成时间", ja: "予想時間") }
    static var taskTimerEnabled: String { tr("Start countdown after saving", zhHans: "保存后开始倒计时", ja: "保存後にカウントダウンを開始") }
    static func taskTimerSummary(hours: Int, minutes: Int) -> String {
        tr("Countdown: \(hours)h \(minutes)m", zhHans: "倒计时：\(hours)小时\(minutes)分", ja: "カウントダウン：\(hours)時間\(minutes)分")
    }
    static var taskTimerSummary24Hours: String { tr("Countdown: 24 hours", zhHans: "倒计时：24小时", ja: "カウントダウン：24時間") }
    static var taskTimedOutTitle: String { tr("Task timed out", zhHans: "任务超时了", ja: "タスクがタイムアウトしました") }
    static func taskTimedOutHeadline(task: String, seconds: Int) -> String {
        tr("\(task) timed out by \(seconds)s", zhHans: "\(task)任务已超时\(seconds)秒", ja: "\(task) は\(seconds)秒超過しました")
    }
    static func boardTimedOutHeadline(seconds: Int) -> String {
        tr("Board timed out by \(seconds)s", zhHans: "面板任务已超时\(seconds)秒", ja: "ボードは\(seconds)秒超過しました")
    }
    static func timeoutBoardNameLabel(_ boardName: String) -> String {
        tr("Board: \(boardName)", zhHans: "面板：\(boardName)", zhHant: "面板：\(boardName)", ja: "ボード：\(boardName)")
    }
    static var timeoutRuleReasonTaskCountdown: String {
        tr(
            "Rule: tile countdown ended",
            zhHans: "触发规则：格子倒计时已结束",
            zhHant: "觸發規則：格子倒計時已結束",
            ja: "トリガー：マスのカウントダウン終了"
        )
    }
    static var timeoutRuleReasonTaskEndTime: String {
        tr(
            "Rule: task end time reached",
            zhHans: "触发规则：任务结束时间已到",
            zhHant: "觸發規則：任務結束時間已到",
            ja: "トリガー：タスク終了時刻に到達"
        )
    }
    static var timeoutRuleReasonTaskCountdownAndEndTime: String {
        tr(
            "Rule: tile countdown and task end time both ended",
            zhHans: "触发规则：格子倒计时和任务结束时间都已到",
            zhHant: "觸發規則：格子倒計時和任務結束時間都已到",
            ja: "トリガー：マスのカウントダウンとタスク終了時刻"
        )
    }
    static var timeoutRuleReasonTask: String {
        tr(
            "Rule: task timeout",
            zhHans: "触发规则：任务超时",
            zhHant: "觸發規則：任務超時",
            ja: "トリガー：タスクのタイムアウト"
        )
    }
    static var timeoutRuleReasonBoardCountdown: String {
        tr(
            "Rule: board countdown ended",
            zhHans: "触发规则：面板倒计时已结束",
            zhHant: "觸發規則：面板倒計時已結束",
            ja: "トリガー：ボードのカウントダウン終了"
        )
    }
    static func taskTimedOutMessage(task: String, overtime: String) -> String {
        tr("“\(task)” timed out (\(overtime)).", zhHans: "「\(task)」\(overtime)。", ja: "「\(task)」がタイムアウトしました（\(overtime)）。")
    }
    static var markAsCompleted: String { tr("Completed", zhHans: "已完成", ja: "完了") }
    static var abandonTask: String { tr("Abandon task", zhHans: "放弃此任务", ja: "タスクを放棄") }
    static func postponeTaskByMinutes(_ minutes: Int) -> String {
        tr("Delay \(minutes)m", zhHans: "延期\(minutes)分钟", ja: "\(minutes)分延長")
    }
    static func postponeByMinutes(_ minutes: Int) -> String {
        tr("Postpone \(minutes)m", zhHans: "延期 \(minutes) 分钟", ja: "\(minutes)分延期")
    }
    static var postponeDuration: String { tr("Delay duration", zhHans: "延期时长", ja: "延長時間") }
    static func timedOutFor(_ duration: String) -> String {
        tr("Timed out for \(duration)", zhHans: "已超时 \(duration)", ja: "\(duration) 超過")
    }
    static var taskMarkedCompletedSuccess: String { tr("Task marked completed", zhHans: "任务已标记为完成", ja: "タスクを完了にしました") }
    static var boardMarkedCompletedSuccess: String { tr("Board tasks marked completed", zhHans: "面板任务已标记为完成", ja: "ボードのタスクを完了にしました") }
    static var taskAbandonedSuccess: String { tr("Task abandoned", zhHans: "任务已放弃", ja: "タスクを放棄しました") }
    static func taskPostponedSuccess(_ minutes: Int) -> String {
        tr("Postponed by \(minutes)m", zhHans: "已延期 \(minutes) 分钟", ja: "\(minutes)分延期しました")
    }
    static var boardCountdownCanceledSuccess: String { tr("Countdown canceled", zhHans: "已取消倒计时", ja: "カウントダウンをキャンセルしました") }
    static func boardCountdownPostponedSuccess(_ minutes: Int) -> String {
        tr("Board countdown postponed by \(minutes)m", zhHans: "面板倒计时已延期 \(minutes) 分钟", ja: "ボードのカウントダウンを\(minutes)分延期しました")
    }
    static var enterTaskForDay: String { tr("Enter a task for your day...", zhHans: "输入今天要完成的任务...", ja: "今日のタスクを入力...") }
    static var emptyBoardLongPressHint: String { tr("Long press to edit tasks", zhHans: "长按编辑任务", ja: "長押しでタスクを編集") }
    static var forceCompletion: String { tr("Force Completion", zhHans: "强制完成", ja: "強制完了") }
    static var voiceInput: String { tr("Voice input", zhHans: "语音输入", zhHant: "語音輸入", ja: "音声入力") }
    static var recording: String { tr("Recording...", zhHans: "正在录音...", ja: "録音中...") }
    static var stopRecording: String { tr("Stop recording", zhHans: "结束录制", zhHant: "結束錄製", ja: "録音を終了") }
    static var quickAdd: String { tr("Quick Add", zhHans: "快速添加", ja: "クイック追加") }
    static var editTask: String { tr("Edit Task", zhHans: "编辑任务", ja: "タスクを編集") }
    static var boardEditHintMessage: String {
        tr(
            "Long press to edit board",
            zhHans: "长按编辑面板",
            zhHant: "長按編輯面板",
            ja: "長押しでボードを編集"
        )
    }
    static var boardEditHintAcknowledge: String {
        tr("Got it", zhHans: "了解", zhHant: "了解", ja: "了解")
    }
    static var deleteTask: String { tr("Remove Task", zhHans: "移除任务", zhHant: "移除任務", ja: "タスクを削除") }
    static var hideTask: String { tr("Hide Task", zhHans: "隐藏任务", ja: "タスクを非表示") }
    static var showTask: String { tr("Show Task", zhHans: "显示任务", ja: "タスクを表示") }
    static var deleteReward: String { tr("Delete Reward", zhHans: "删除奖励", ja: "報酬を削除") }
    static var taskDeleted: String { tr("Task deleted", zhHans: "任务已删除", ja: "タスクを削除しました") }
    static var undo: String { tr("Undo", zhHans: "撤销", ja: "元に戻す") }
    static var unableToApplyGroup: String { tr("Unable to Apply Group", zhHans: "无法应用分组", ja: "グループを適用できません") }
    static var applyGroupFailedMessage: String { tr("This group can't be applied because there aren't enough empty tiles.", zhHans: "空白格子数量不足，无法应用这个分组。", ja: "空きマスが足りないため、このグループを適用できません。") }
    static var expiredCountdownMessage: String {
        tr(
            "Your Bingo board countdown ended. Choose to complete, abandon, or postpone.",
            zhHans: "你的 Bingo 面板倒计时已结束。请选择完成、放弃或延后。",
            zhHant: "你的 Bingo 面板倒計時已結束。請選擇完成、放棄或延後。",
            ja: "Bingoボードのカウントダウンが終了しました。完了・放棄・延期を選んでください。"
        )
    }
    static var groupDefaultName: String { tr("Group", zhHans: "分组", ja: "グループ") }
    static var boardInteractionGuide: String {
        tr(
            "Tap to complete. Long press and release to edit or delete. Long press and drag to reorder.",
            zhHans: "单击完成，长按松手可编辑/删除，长按拖动可排序"
        )
    }
    static var mondayShort: String { tr("Mon", zhHans: "周一", ja: "月") }
    static var tuesdayShort: String { tr("Tue", zhHans: "周二", ja: "火") }
    static var wednesdayShort: String { tr("Wed", zhHans: "周三", ja: "水") }
    static var thursdayShort: String { tr("Thu", zhHans: "周四", ja: "木") }
    static var fridayShort: String { tr("Fri", zhHans: "周五", ja: "金") }
    static var saturdayShort: String { tr("Sat", zhHans: "周六", ja: "土") }
    static var sundayShort: String { tr("Sun", zhHans: "周日", ja: "日") }
}
