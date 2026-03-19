import Foundation
import CoreHaptics
import UIKit

enum AppLanguage {
    case english
    case simplifiedChinese

    static var current: AppLanguage {
        if let primaryLanguage = preferredLanguageIdentifiers.first?.lowercased(),
           primaryLanguage.hasPrefix("zh") {
            return .simplifiedChinese
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

    static var displayLocale: Locale {
        switch current {
        case .english:
            return Locale(identifier: "en_US")
        case .simplifiedChinese:
            return Locale(identifier: "zh_Hans_CN")
        }
    }

    static var speechLocaleIdentifier: String {
        switch current {
        case .english:
            return "en-US"
        case .simplifiedChinese:
            return "zh-Hans"
        }
    }
}

enum L10n {
    static func tr(_ english: String, zhHans: String) -> String {
        switch AppLanguage.current {
        case .english:
            return english
        case .simplifiedChinese:
            return zhHans
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
    static var myRewards: String { tr("My Rewards", zhHans: "我的奖励") }
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
    static func quickEditNeedMoreTasks(_ count: Int) -> String {
        tr("Add \(count) more tasks to fill this grid", zhHans: "还需 \(count) 个任务可填满当前尺寸")
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
    static var taskCompletions: String { tr("Task Completions", zhHans: "任务完成次数") }
    static var completion: String { tr("Completion", zhHans: "完成度") }
    static var last7Days: String { tr("7 Days", zhHans: "近 7 天") }
    static var last30Days: String { tr("30 Days", zhHans: "近 30 天") }
    static var noTaskCompletions: String { tr("No completed tasks yet.", zhHans: "暂时还没有已完成的任务。") }
    static func completedTimes(_ count: Int) -> String {
        tr("\(count) times", zhHans: "\(count) 次")
    }
    static var pointsUnit: String { tr("pts", zhHans: "积分") }
    static var boardCountdownTitle: String { tr("Bingo Board Countdown", zhHans: "Bingo 面板倒计时") }
    static var boardCountdownDescription: String { tr("Auto-clear the entire board when time runs out.", zhHans: "时间结束后自动清空整个面板。") }
    static var clearBoard: String { tr("Clear Board", zhHans: "清空棋盘") }
    static var clearBoardConfirmationTitle: String { tr("Clear board?", zhHans: "清空棋盘？") }
    static var clearBoardConfirmationMessage: String { tr("This will remove all tasks and completion states on the current board.", zhHans: "这会清除当前棋盘的所有任务和完成状态。") }
    static var boardClearedSuccess: String { tr("Board cleared", zhHans: "棋盘已清空") }
    static var hours: String { tr("Hours", zhHans: "小时") }
    static var minutes: String { tr("Minutes", zhHans: "分钟") }
    static var residentDays: String { tr("Repeat Days", zhHans: "常驻时间") }
    static var alwaysVisible: String { tr("Always", zhHans: "每天") }
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
    static var enterTaskForDay: String { tr("Enter a task for your day...", zhHans: "输入今天要完成的任务...") }
    static var forceCompletion: String { tr("Force Completion", zhHans: "强制完成") }
    static var recording: String { tr("Recording...", zhHans: "正在录音...") }
    static var quickAdd: String { tr("Quick Add", zhHans: "快速添加") }
    static var editTask: String { tr("Edit Task", zhHans: "编辑任务") }
    static var deleteTask: String { tr("Delete Task", zhHans: "删除任务") }
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
    var isCompleted: Bool
    var isForced: Bool
    var countdownEndsAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case residentTaskText
        case residentWeekdays
        case isCompleted
        case isForced
        case countdownEndsAt
    }

    init(
        id: UUID = UUID(),
        text: String = "",
        residentTaskText: String? = nil,
        residentWeekdays: Set<Int> = [],
        isCompleted: Bool = false,
        isForced: Bool = false,
        countdownEndsAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.residentTaskText = residentTaskText
        self.residentWeekdays = residentWeekdays
        self.isCompleted = isCompleted
        self.isForced = isForced
        self.countdownEndsAt = countdownEndsAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        residentTaskText = try container.decodeIfPresent(String.self, forKey: .residentTaskText)
        residentWeekdays = try container.decodeIfPresent(Set<Int>.self, forKey: .residentWeekdays) ?? []
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        isForced = try container.decodeIfPresent(Bool.self, forKey: .isForced) ?? false
        countdownEndsAt = try container.decodeIfPresent(Date.self, forKey: .countdownEndsAt)
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

    func isResidentActive(on date: Date, calendar: Calendar = .current) -> Bool {
        guard hasResidentSchedule else { return true }
        let weekday = calendar.component(.weekday, from: date)
        return residentWeekdays.contains(weekday)
    }

    func projectedForDisplay(on date: Date, calendar: Calendar = .current) -> BingoCell {
        guard hasResidentSchedule else { return self }

        var projected = self
        let activeToday = isResidentActive(on: date, calendar: calendar)
        projected.text = activeToday ? storedTaskText : ""
        projected.isCompleted = activeToday ? isCompleted : false
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

struct SavedBoard: Codable {
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
}

enum AppSettings {
    static let hapticsEnabledKey = "haptics_enabled"
    static let soundEffectsEnabledKey = "sound_effects_enabled"
    static let themeKey = "theme_color"
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
        var seenKinds = Set<StickerKind>()
        let normalized = placements.filter { placement in
            if seenKinds.contains(placement.kind) {
                return false
            }
            seenKinds.insert(placement.kind)
            return true
        }
        savePlacements(normalized)
        return normalized
    }

    static func savePlacements(_ placements: [HomeStickerPlacement]) {
        guard let data = try? JSONEncoder().encode(placements) else { return }
        UserDefaults.standard.set(data, forKey: AppSettings.homeStickerPlacementsKey)
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
            .prefix(AppSettings.maxCommonTasks)
            .map { $0 }
    }

    private static func sanitizeGroups(_ groups: [MyTaskGroup]) -> [MyTaskGroup] {
        groups
            .prefix(AppSettings.maxTaskGroups)
            .compactMap { group in
                let trimmedName = String(group.name.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines)
                let sanitizedTasks = group.tasks
                    .map { String($0.prefix(AppSettings.maxTaskLength)).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .prefix(AppSettings.maxTasksPerGroup)
                    .map { $0 }

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
