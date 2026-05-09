import SwiftUI
import Foundation

struct BlackBoxModeEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasSeenBlackBoxRules") private var hasSeenBlackBoxRules = false
    @State private var showRulesAlert = false

    @State private var selectedTheme: BlackBoxTheme = .health
    @State private var selectedGridSize: Int = 4
    @State private var gameState = BlackBoxGameState(theme: .health, size: 4)
    @State private var analyticsSessionStartDate: Date?
    @State private var hasLoggedAnalyticsSessionEnd = false
    @State private var hasLogged2048ScoreReached = false

    private var currentScore: Int {
        gameState.board
            .flatMap { $0 }
            .compactMap { $0 }
            .filter { $0.isCompleted }
            .reduce(0) { $0 + $1.score }
    }

    private var maxTileScore: Int {
        gameState.board
            .flatMap { $0 }
            .compactMap { $0 }
            .map(\.score)
            .max() ?? 0
    }

    var body: some View {
        ZStack {
            BlackBoxClassicPalette.background.ignoresSafeArea()

            BlackBoxModeGameView(
                game: $gameState,
                selectedTheme: $selectedTheme,
                selectedGridSize: $selectedGridSize,
                onRestart: {
                    gameState = BlackBoxGameState(theme: selectedTheme, size: selectedGridSize)
                },
                onBackToIntro: {
                    dismiss()
                },
                onShowRules: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showRulesAlert = true
                    }
                }
            )

            if showRulesAlert {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRulesAlert = false
                        }
                    }

                VStack(spacing: 20) {
                    Text(L10n.blackBoxModeHowToTitle)
                        .font(.appSystem(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(BlackBoxClassicPalette.text)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("• \(L10n.blackBoxModeFeatureTheme)")
                        Text("• \(L10n.blackBoxModeFeatureMerge)")
                        Text("• \(L10n.tr("See how high you can score!", zhHans: "看看你最后能获得多少分吧！", zhHant: "看看你最後能獲得多少分吧！"))")
                    }
                    .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(BlackBoxClassicPalette.text.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRulesAlert = false
                        }
                    } label: {
                        Text(L10n.tr("Got it", zhHans: "知道了", zhHant: "知道了"))
                            .font(.appSystem(size: 18, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                    .fill(BlackBoxClassicPalette.restart)
                                    .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(0.4), radius: 4, x: 0, y: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .background(
                    RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                        .fill(BlackBoxClassicPalette.background)
                        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
                )
                .padding(.horizontal, 40)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .onAppear {
            if analyticsSessionStartDate == nil {
                analyticsSessionStartDate = Date()
                hasLoggedAnalyticsSessionEnd = false
                hasLogged2048ScoreReached = false
                AnalyticsService.logBB2048SessionStart(
                    themeID: selectedTheme.rawValue,
                    gridSize: selectedGridSize
                )
            }

            if !hasSeenBlackBoxRules {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showRulesAlert = true
                }
                hasSeenBlackBoxRules = true
            }
        }
        .onDisappear {
            log2048SessionEndIfNeeded()
        }
        .onChange(of: currentScore) { oldValue, newValue in
            guard !hasLogged2048ScoreReached else { return }
            guard oldValue < 2048, newValue >= 2048 else { return }

            hasLogged2048ScoreReached = true
            AnalyticsService.logBB2048ScoreReached(
                themeID: selectedTheme.rawValue,
                gridSize: selectedGridSize,
                score: newValue,
                maxTileScore: maxTileScore,
                moveCount: gameState.moveCount,
                mergeCount: gameState.mergeCount
            )
        }
    }

    private func log2048SessionEndIfNeeded() {
        guard !hasLoggedAnalyticsSessionEnd else { return }
        guard let sessionStart = analyticsSessionStartDate else { return }

        hasLoggedAnalyticsSessionEnd = true
        let durationSeconds = max(Int(Date().timeIntervalSince(sessionStart)), 0)
        AnalyticsService.logBB2048SessionEnd(
            themeID: selectedTheme.rawValue,
            gridSize: selectedGridSize,
            durationSeconds: durationSeconds,
            finalScore: currentScore,
            maxTileScore: maxTileScore,
            moveCount: gameState.moveCount,
            mergeCount: gameState.mergeCount,
            bingoCount: gameState.bingoCount
        )
    }
}

private enum BlackBoxDirection {
    case up
    case down
    case left
    case right
}

private enum BlackBoxTheme: String, CaseIterable, Identifiable {
    case health
    case focus
    case home

    var id: String { rawValue }

    var title: String {
        switch self {
        case .health:
            return L10n.blackBoxModeHealthTheme
        case .focus:
            return L10n.blackBoxModeFocusTheme
        case .home:
            return L10n.blackBoxModeHomeTheme
        }
    }

    var taskDefinitions: [BlackBoxTaskDefinition] {
        switch self {
        case .health:
            return [
                BlackBoxTaskDefinition(
                    id: "health_drink_water",
                    baseScore: 2,
                    baseTitle: L10n.tr("Drink 1 cup of water", zhHans: "喝1杯水", zhHant: "喝1杯水"),
                    maxCount: 8
                ),
                BlackBoxTaskDefinition(
                    id: "health_breakfast",
                    baseScore: 2,
                    baseTitle: L10n.tr("Eat breakfast", zhHans: "吃早餐", zhHant: "吃早餐"),
                    maxCount: 1
                ),
                BlackBoxTaskDefinition(
                    id: "health_walk_10",
                    baseScore: 4,
                    baseTitle: L10n.tr("Walk 10 minutes", zhHans: "散步10分钟", zhHant: "散步10分鐘"),
                    maxCount: 3
                ),
                BlackBoxTaskDefinition(
                    id: "health_stretch_10",
                    baseScore: 4,
                    baseTitle: L10n.tr("Stretch 10 minutes", zhHans: "拉伸10分钟", zhHant: "拉伸10分鐘"),
                    maxCount: 2
                ),
                BlackBoxTaskDefinition(
                    id: "health_sleep_2330",
                    baseScore: 4,
                    baseTitle: L10n.tr("Sleep before 23:30", zhHans: "23:30前睡觉", zhHant: "23:30前睡覺"),
                    maxCount: 1
                ),
                BlackBoxTaskDefinition(
                    id: "health_fruit",
                    baseScore: 2,
                    baseTitle: L10n.tr("Eat fruit", zhHans: "吃水果", zhHant: "吃水果"),
                    maxCount: 2
                )
            ]
        case .focus:
            return [
                BlackBoxTaskDefinition(id: "focus_pomodoro", baseScore: 2, baseTitle: L10n.tr("Pomodoro 25 min", zhHans: "番茄专注25分钟", zhHant: "番茄專注25分鐘"), maxCount: 4),
                BlackBoxTaskDefinition(id: "focus_read", baseScore: 2, baseTitle: L10n.tr("Read 10 pages", zhHans: "阅读10页", zhHant: "閱讀10頁"), maxCount: 3),
                BlackBoxTaskDefinition(id: "focus_plan", baseScore: 4, baseTitle: L10n.tr("Write task plan", zhHans: "写任务计划", zhHant: "寫任務計劃"), maxCount: 1),
                BlackBoxTaskDefinition(id: "focus_finish_one", baseScore: 4, baseTitle: L10n.tr("Finish one small task", zhHans: "完成一个小任务", zhHant: "完成一個小任務"), maxCount: 3),
                BlackBoxTaskDefinition(id: "focus_no_social", baseScore: 4, baseTitle: L10n.tr("No social app 30 min", zhHans: "30分钟不刷社媒", zhHant: "30分鐘不刷社群媒體"), maxCount: 2)
            ]
        case .home:
            return [
                BlackBoxTaskDefinition(id: "home_trash", baseScore: 2, baseTitle: L10n.tr("Take out trash", zhHans: "倒垃圾", zhHant: "倒垃圾"), maxCount: 1),
                BlackBoxTaskDefinition(id: "home_dishes", baseScore: 2, baseTitle: L10n.tr("Wash dishes", zhHans: "洗碗", zhHant: "洗碗"), maxCount: 2),
                BlackBoxTaskDefinition(id: "home_wipe", baseScore: 2, baseTitle: L10n.tr("Wipe desk", zhHans: "擦桌子", zhHant: "擦桌子"), maxCount: 1),
                BlackBoxTaskDefinition(id: "home_laundry", baseScore: 4, baseTitle: L10n.tr("Laundry 1 cycle", zhHans: "洗衣1轮", zhHant: "洗衣1輪"), maxCount: 1),
                BlackBoxTaskDefinition(id: "home_drawer", baseScore: 4, baseTitle: L10n.tr("Organize one drawer", zhHans: "整理一个抽屉", zhHant: "整理一個抽屜"), maxCount: 2)
            ]
        }
    }

    var definitionMap: [String: BlackBoxTaskDefinition] {
        Dictionary(uniqueKeysWithValues: taskDefinitions.map { ($0.id, $0) })
    }

    func mergedTitle(score: Int) -> String {
        title
    }
}

private enum BlackBoxClassicPalette {
    static let edgeRadius: CGFloat = 2
    static let background = Color(hex: "FAF8EF")
    static let board = Color(hex: "BBADA0")
    static let boardShadow = Color(hex: "A89C90")
    static let boardHighlight = Color(hex: "D7CCBF")
    static let emptyTile = Color(hex: "CDC1B4")
    static let text = Color(hex: "776E65")
    static let darkText = Color(hex: "F9F6F2")
    static let restart = Color(hex: "8F7A66")
}

private struct BlackBoxTaskDefinition: Identifiable, Hashable {
    let id: String
    let baseScore: Int
    let baseTitle: String
    let maxCount: Int

    init(id: String, baseScore: Int, baseTitle: String, maxCount: Int = 99) {
        self.id = id
        self.baseScore = baseScore
        self.baseTitle = baseTitle
        self.maxCount = maxCount
    }

    func title(forCount count: Int) -> String {
        guard count > 1 else { return baseTitle }
        switch id {
        case "health_drink_water":
            return L10n.tr("Drink \(count) cups of water", zhHans: "喝\(count)杯水", zhHant: "喝\(count)杯水")
        default:
            return L10n.tr("\(baseTitle) x\(count)", zhHans: "\(baseTitle) x\(count)", zhHant: "\(baseTitle) x\(count)")
        }
    }
}

private struct BlackBoxTile: Identifiable, Equatable {
    var id = UUID()
    var displayTitle: String
    var score: Int
    var isCompleted: Bool
    var components: [String: Int]
}

private struct BlackBoxLineResult {
    let line: [BlackBoxTile?]
    let mergeCount: Int
}

private struct BlackBoxGameSnapshot {
    let board: [[BlackBoxTile?]]
    let moveCount: Int
    let mergeCount: Int
    let bingoCount: Int
    let isGameOver: Bool
}

private struct BlackBoxGameState {
    let theme: BlackBoxTheme
    let size: Int
    var board: [[BlackBoxTile?]]
    var moveCount: Int
    var mergeCount: Int
    var bingoCount: Int
    var isGameOver: Bool
    var history: [BlackBoxGameSnapshot]

    init(theme: BlackBoxTheme, size: Int) {
        self.theme = theme
        self.size = size
        self.board = Array(repeating: Array(repeating: nil, count: size), count: size)
        self.moveCount = 0
        self.mergeCount = 0
        self.bingoCount = 0
        self.isGameOver = false
        self.history = []
        spawnRandomTile()
        spawnRandomTile()
    }

    mutating func toggleCompletion(row: Int, col: Int) {
        guard row >= 0, row < size, col >= 0, col < size else { return }
        guard var tile = board[row][col] else { return }
        pushHistory()
        tile.isCompleted.toggle()
        board[row][col] = tile
        isGameOver = !hasMoveAvailable()
    }

    mutating func undoLastAction() {
        guard let snapshot = history.popLast() else { return }
        board = snapshot.board
        moveCount = snapshot.moveCount
        mergeCount = snapshot.mergeCount
        bingoCount = snapshot.bingoCount
        isGameOver = snapshot.isGameOver
    }

    mutating func swipe(_ direction: BlackBoxDirection) {
        guard !isGameOver else { return }

        var nextBoard = board
        var mergedTiles = 0

        switch direction {
        case .left, .right:
            for row in 0..<size {
                let processed = processLine(board[row], reverse: direction == .right)
                nextBoard[row] = processed.line
                mergedTiles += processed.mergeCount
            }
        case .up, .down:
            for col in 0..<size {
                let line = (0..<size).map { board[$0][col] }
                let processed = processLine(line, reverse: direction == .down)
                for row in 0..<size {
                    nextBoard[row][col] = processed.line[row]
                }
                mergedTiles += processed.mergeCount
            }
        }

        guard nextBoard != board else { return }

        pushHistory()
        board = nextBoard
        moveCount += 1
        mergeCount += mergedTiles
        bingoCount += mergedTiles
        spawnStrategicTile()
        isGameOver = !hasMoveAvailable()
    }

    mutating func refreshPendingTiles() {
        var targets: [(row: Int, col: Int)] = []
        for row in 0..<size {
            for col in 0..<size {
                guard let tile = board[row][col] else { continue }
                // Keep merged or completed tiles untouched.
                if tile.isCompleted || tile.components.count > 1 {
                    continue
                }
                targets.append((row, col))
            }
        }

        guard !targets.isEmpty else { return }
        pushHistory()

        for target in targets {
            guard let tile = board[target.row][target.col] else { continue }
            let task = taskDefinition(forScore: tile.score)
            board[target.row][target.col] = BlackBoxTile(
                displayTitle: task.title(forCount: 1),
                score: task.baseScore,
                isCompleted: false,
                components: [task.id: 1]
            )
        }
        isGameOver = !hasMoveAvailable()
    }

    private mutating func spawnRandomTile() {
        spawnStrategicTile(preferredScore: theme.taskDefinitions.map(\.baseScore).min())
    }

    private mutating func spawnStrategicTile(preferredScore: Int? = nil) {
        let emptyCoordinates = allEmptyCoordinates()
        guard !emptyCoordinates.isEmpty else { return }

        let targetScore = chooseSpawnScore(preferredScore: preferredScore)
        let preferredCoordinates = preferredScore.map { preferredSpawnCoordinates(for: $0) } ?? []
        let targetCoordinates = preferredCoordinates.isEmpty ? emptyCoordinates : preferredCoordinates
        guard let randomCoordinate = targetCoordinates.randomElement() else { return }

        let task = taskDefinition(forScore: targetScore)
        board[randomCoordinate.row][randomCoordinate.col] = BlackBoxTile(
            displayTitle: task.title(forCount: 1),
            score: task.baseScore,
            isCompleted: false,
            components: [task.id: 1]
        )
    }

    private func allEmptyCoordinates() -> [(row: Int, col: Int)] {
        var result: [(row: Int, col: Int)] = []
        for row in 0..<size {
            for col in 0..<size where board[row][col] == nil {
                result.append((row, col))
            }
        }
        return result
    }

    private func hasMoveAvailable() -> Bool {
        if board.flatMap(\.self).contains(where: { $0 == nil }) {
            return true
        }

        for row in 0..<size {
            for col in 0..<size {
                guard let current = board[row][col] else { continue }
                if row + 1 < size,
                   let nextRow = board[row + 1][col],
                   nextRow.score == current.score,
                   current.isCompleted,
                   nextRow.isCompleted {
                    return true
                }
                if col + 1 < size,
                   let nextCol = board[row][col + 1],
                   nextCol.score == current.score,
                   current.isCompleted,
                   nextCol.isCompleted {
                    return true
                }
            }
        }

        return false
    }

    private mutating func pushHistory() {
        history.append(
            BlackBoxGameSnapshot(
                board: board,
                moveCount: moveCount,
                mergeCount: mergeCount,
                bingoCount: bingoCount,
                isGameOver: isGameOver
            )
        )
        if history.count > 24 {
            history.removeFirst(history.count - 24)
        }
    }

    private func chooseSpawnScore(preferredScore: Int? = nil) -> Int {
        let completedCounts = completedScoreCounts()
        if let preferredScore, completedCounts[preferredScore] != nil {
            return preferredScore
        }

        if let bestExisting = completedCounts
            .sorted(by: { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            })
            .first?
            .key {
            return bestExisting
        }

        return theme.taskDefinitions.map(\.baseScore).min() ?? 2
    }

    private func completedScoreCounts() -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for row in board {
            for case let tile? in row where tile.isCompleted {
                counts[tile.score, default: 0] += 1
            }
        }
        return counts
    }

    private func preferredSpawnCoordinates(for score: Int) -> [(row: Int, col: Int)] {
        var coordinates: [(row: Int, col: Int)] = []
        for row in 0..<size {
            for col in 0..<size {
                guard let tile = board[row][col], tile.isCompleted, tile.score == score else { continue }
                coordinates.append(contentsOf: adjacentEmptyCoordinates(row: row, col: col))
            }
        }
        return uniqueCoordinates(coordinates)
    }

    private func adjacentEmptyCoordinates(row: Int, col: Int) -> [(row: Int, col: Int)] {
        var result: [(row: Int, col: Int)] = []
        let neighbors = [
            (row - 1, col),
            (row + 1, col),
            (row, col - 1),
            (row, col + 1)
        ]

        for neighbor in neighbors where neighbor.0 >= 0 && neighbor.0 < size && neighbor.1 >= 0 && neighbor.1 < size {
            if board[neighbor.0][neighbor.1] == nil {
                result.append(neighbor)
            }
        }

        return result
    }

    private func uniqueCoordinates(_ coordinates: [(row: Int, col: Int)]) -> [(row: Int, col: Int)] {
        var seen = Set<String>()
        var result: [(row: Int, col: Int)] = []
        for coordinate in coordinates {
            let key = "\(coordinate.row)-\(coordinate.col)"
            if seen.insert(key).inserted {
                result.append(coordinate)
            }
        }
        return result
    }

    private func taskDefinition(forScore score: Int) -> BlackBoxTaskDefinition {
        let boardTaskCounts = boardTaskCounts()
        let matches = theme.taskDefinitions.filter { $0.baseScore == score }
        let available = matches.filter { def in
            let currentCount = boardTaskCounts[def.id] ?? 0
            return currentCount < def.maxCount
        }
        return available.randomElement() ?? matches.randomElement() ?? theme.taskDefinitions.first ?? BlackBoxTaskDefinition(
            id: "fallback",
            baseScore: score,
            baseTitle: L10n.tr("Task", zhHans: "任务", zhHant: "任務")
        )
    }

    private func boardTaskCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for row in board {
            for case let tile? in row {
                for (taskID, count) in tile.components {
                    counts[taskID, default: 0] += count
                }
            }
        }
        return counts
    }

    private func processLine(_ line: [BlackBoxTile?], reverse: Bool) -> BlackBoxLineResult {
        let normalizedLine = reverse ? Array(line.reversed()) : line
        let compacted = normalizedLine.compactMap { $0 }

        var mergedLine: [BlackBoxTile] = []
        var mergeCount = 0
        var index = 0

        while index < compacted.count {
            if index + 1 < compacted.count {
                let first = compacted[index]
                let second = compacted[index + 1]
                if first.score == second.score, first.isCompleted, second.isCompleted {
                    let mergedComponents = mergeComponents(first.components, second.components)
                    let mergedScore = first.score * 2
                    mergedLine.append(
                        BlackBoxTile(
                            displayTitle: titleForMergedTile(components: mergedComponents, score: mergedScore),
                            score: mergedScore,
                            isCompleted: true,
                            components: mergedComponents
                        )
                    )
                    mergeCount += 1
                    index += 2
                    continue
                }
            }

            mergedLine.append(compacted[index])
            index += 1
        }

        var filledLine: [BlackBoxTile?] = mergedLine.map { $0 }
        while filledLine.count < size {
            filledLine.append(nil)
        }

        if reverse {
            filledLine.reverse()
        }

        return BlackBoxLineResult(line: filledLine, mergeCount: mergeCount)
    }

    private func mergeComponents(_ lhs: [String: Int], _ rhs: [String: Int]) -> [String: Int] {
        var merged = lhs
        for (key, value) in rhs {
            merged[key, default: 0] += value
        }
        return merged
    }

    private func titleForMergedTile(components: [String: Int], score: Int) -> String {
        if components.count == 1, let (taskID, count) = components.first, let definition = theme.definitionMap[taskID] {
            return definition.title(forCount: count)
        }
        return theme.mergedTitle(score: score)
    }
}

private struct BlackBoxHistoryRecord: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let themeRawValue: String
    let gridSize: Int
    let score: Int
    let moves: Int
    let merges: Int
    let completedTiles: Int

    var themeTitle: String {
        BlackBoxTheme(rawValue: themeRawValue)?.title ?? themeRawValue
    }
}

private enum BlackBoxHistoryStore {
    private static let key = "blackBox2048HistoryRecords.v1"

    static func load() -> [BlackBoxHistoryRecord] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([BlackBoxHistoryRecord].self, from: data)) ?? []
    }

    static func append(_ record: BlackBoxHistoryRecord, keep maxCount: Int = 50) {
        var records = load()
        records.insert(record, at: 0)
        if records.count > maxCount {
            records.removeLast(records.count - maxCount)
        }
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private struct BlackBoxModeGameView: View {
    private enum ConfirmAction: Identifiable {
        case exit
        case restart
        case switchTheme(BlackBoxTheme)
        case showRules
        case refreshPendingTasks

        var id: String {
            switch self {
            case .exit:
                return "exit"
            case .restart:
                return "restart"
            case .switchTheme(let theme):
                return "theme-\(theme.rawValue)"
            case .showRules:
                return "rules"
            case .refreshPendingTasks:
                return "refresh-pending"
            }
        }

        var title: String {
            switch self {
            case .exit:
                return L10n.tr("Confirm exit?", zhHans: "确认退出?", zhHant: "確認退出?")
            case .restart:
                return L10n.tr("Confirm restart?", zhHans: "确认重开?", zhHant: "確認重開?")
            case .switchTheme(let theme):
                return L10n.tr("Switch to \(theme.title)?", zhHans: "切换到\(theme.title)?", zhHant: "切換到\(theme.title)?")
            case .showRules:
                return L10n.tr("View how to play?", zhHans: "查看玩法说明?", zhHant: "查看玩法說明?")
            case .refreshPendingTasks:
                return L10n.tr("Refresh pending tasks?", zhHans: "刷新未完成任务?", zhHant: "刷新未完成任務?")
            }
        }

        var message: String {
            switch self {
            case .exit:
                return L10n.tr("You'll leave 2048 mode and current board progress won't be kept.", zhHans: "会离开 2048 模式，当前棋盘进度不会保留。", zhHant: "會離開 2048 模式，當前棋盤進度不會保留。")
            case .restart:
                return L10n.tr("This will clear the board and generate tasks again.", zhHans: "会清空当前棋盘并重新生成任务。", zhHant: "會清空當前棋盤並重新生成任務。")
            case .switchTheme:
                return L10n.tr("This will switch theme and reset the current board.", zhHans: "会切换主题并重置当前棋盘。", zhHant: "會切換主題並重置當前棋盤。")
            case .showRules:
                return L10n.tr("This will open the how-to-play popup.", zhHans: "将打开玩法说明弹窗。", zhHant: "將打開玩法說明彈窗。")
            case .refreshPendingTasks:
                return L10n.tr("Only incomplete and unmerged tiles will be refreshed.", zhHans: "仅刷新未完成且未合并的任务格。", zhHant: "僅刷新未完成且未合併的任務格。")
            }
        }

        var confirmTitle: String {
            switch self {
            case .exit:
                return L10n.tr("Exit", zhHans: "退出", zhHant: "退出")
            case .restart:
                return L10n.tr("Restart", zhHans: "重开", zhHant: "重開")
            case .switchTheme:
                return L10n.tr("Switch", zhHans: "切换", zhHant: "切換")
            case .showRules:
                return L10n.tr("View", zhHans: "查看", zhHant: "查看")
            case .refreshPendingTasks:
                return L10n.tr("Refresh", zhHans: "刷新", zhHant: "刷新")
            }
        }
    }

    @Binding var game: BlackBoxGameState
    @Binding var selectedTheme: BlackBoxTheme
    @Binding var selectedGridSize: Int
    let onRestart: () -> Void
    let onBackToIntro: () -> Void
    let onShowRules: () -> Void
    @State private var selectedDetail: BlackBoxTileDetailContext?
    @State private var confirmAction: ConfirmAction?
    @State private var isHistoryPresented = false
    @State private var historyRecords: [BlackBoxHistoryRecord] = BlackBoxHistoryStore.load()

    private var currentScore: Int {
        game.board.flatMap { $0 }.compactMap { $0 }.filter { $0.isCompleted }.reduce(0) { $0 + $1.score }
    }

    var body: some View {
        GeometryReader { geo in
            let safeBoardSide = min(geo.size.width - 32, geo.size.height * 0.55)

            ZStack {
                VStack(spacing: 24) {
                    Spacer(minLength: 16)

                    HStack(alignment: .center) {
                        HStack(spacing: 8) {
                            Text("2048")
                                .font(.appSystem(size: 44, weight: .heavy, design: .rounded))
                                .foregroundColor(BlackBoxClassicPalette.text)
                                .padding(.vertical, 8)

                            Button {
                                requestConfirmation(.showRules)
                            } label: {
                                Image(systemName: "questionmark.circle.fill")
                                    .font(.appSystem(size: 24))
                                    .foregroundColor(BlackBoxClassicPalette.text.opacity(0.3))
                            }

                            Button {
                                historyRecords = BlackBoxHistoryStore.load()
                                isHistoryPresented = true
                            } label: {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.appSystem(size: 21, weight: .bold))
                                    .foregroundColor(BlackBoxClassicPalette.text.opacity(0.3))
                            }
                        }

                        Spacer()

                        scoreBox(title: L10n.tr("Score", zhHans: "分数", zhHant: "分數"), value: "\(currentScore)")
                    }

                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            neumorphicButton(title: L10n.tr("Exit", zhHans: "退出", zhHant: "退出"), action: {
                                requestConfirmation(.exit)
                            })
                            Spacer()
                            neumorphicButton(title: L10n.undo, action: {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.92)) {
                                    game.undoLastAction()
                                }
                            })
                            neumorphicButton(title: L10n.tr("Restart", zhHans: "重新开始", zhHant: "重新開始"), action: {
                                requestConfirmation(.restart)
                            })
                        }

                        HStack(spacing: 10) {
                            ForEach(BlackBoxTheme.allCases) { theme in
                                Button {
                                    guard selectedTheme != theme else { return }
                                    requestConfirmation(.switchTheme(theme))
                                } label: {
                                    Text(theme.title)
                                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(selectedTheme == theme ? .white : BlackBoxClassicPalette.darkText)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 40)
                                        .background(
                                            RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                                .fill(selectedTheme == theme ? BlackBoxClassicPalette.restart : BlackBoxClassicPalette.emptyTile)
                                                .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(selectedTheme == theme ? 0.4 : 0.1), radius: 4, x: 0, y: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Spacer(minLength: 20)

                    VStack(spacing: 8) {
                        BlackBoxBoardGridView(game: $game) { row, col, tile in
                            if tile.components.count > 1 {
                                selectedDetail = BlackBoxTileDetailContext(tile: tile, theme: game.theme)
                            } else {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                                    game.toggleCompletion(row: row, col: col)
                                }
                            }
                        }
                        .frame(width: safeBoardSide, height: safeBoardSide)
                        .gesture(
                            DragGesture(minimumDistance: 22)
                                .onEnded { value in
                                    guard let direction = swipeDirection(for: value.translation) else { return }
                                    withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                                        game.swipe(direction)
                                    }
                                }
                        )

                        if game.isGameOver {
                            Text(L10n.blackBoxModeGameOver)
                                .font(.appSystem(size: 16, weight: .heavy, design: .rounded))
                                .foregroundColor(BlackBoxClassicPalette.text)
                                .padding(.top, 8)
                        }
                    }
                    .offset(y: -45)

                    HStack {
                        HStack(spacing: 8) {
                            ForEach([3, 4, 5], id: \.self) { size in
                                Button {
                                    saveCurrentHistoryIfNeeded()
                                    selectedGridSize = size
                                    onRestart()
                                } label: {
                                    Text("\(size)x\(size)")
                                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(selectedGridSize == size ? .white : BlackBoxClassicPalette.darkText)
                                        .frame(width: 52, height: 32)
                                        .background(
                                            RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                                .fill(selectedGridSize == size ? BlackBoxClassicPalette.restart : BlackBoxClassicPalette.emptyTile)
                                                .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(selectedGridSize == size ? 0.4 : 0.1), radius: 4, x: 0, y: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Spacer()

                        Button {
                            requestConfirmation(.refreshPendingTasks)
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.appSystem(size: 16, weight: .heavy))
                                .foregroundColor(BlackBoxClassicPalette.darkText)
                                .frame(width: 42, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                        .fill(BlackBoxClassicPalette.restart)
                                        .shadow(color: BlackBoxClassicPalette.boardHighlight.opacity(0.65), radius: 5, x: -2, y: -2)
                                        .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(0.35), radius: 5, x: 2, y: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: safeBoardSide)
                    .offset(y: -34)

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
                .sheet(item: $selectedDetail) { context in
                    BlackBoxTileDetailSheet(context: context)
                        .presentationDetents([.fraction(0.44), .medium])
                        .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $isHistoryPresented) {
                    BlackBoxHistorySheet(records: historyRecords)
                        .presentationDetents([.fraction(0.4), .medium, .large])
                        .presentationDragIndicator(.visible)
                }

            }
        }
        .alert(
            confirmAction?.title ?? "",
            isPresented: Binding(
                get: { confirmAction != nil },
                set: { isPresented in
                    if !isPresented {
                        confirmAction = nil
                    }
                }
            ),
            presenting: confirmAction
        ) { action in
            Button(L10n.cancel, role: .cancel) {}
            Button(action.confirmTitle, role: .destructive) {
                performConfirmedAction(action)
            }
        } message: { action in
            Text(action.message)
        }
    }

    private func swipeDirection(for translation: CGSize) -> BlackBoxDirection? {
        let x = translation.width
        let y = translation.height
        guard max(abs(x), abs(y)) > 24 else { return nil }
        if abs(x) > abs(y) { return x > 0 ? .right : .left }
        return y > 0 ? .down : .up
    }

    private func neumorphicButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(BlackBoxClassicPalette.darkText)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                        .fill(BlackBoxClassicPalette.restart)
                        .shadow(color: BlackBoxClassicPalette.boardHighlight.opacity(0.65), radius: 5, x: -2, y: -2)
                        .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(0.35), radius: 5, x: 2, y: 2)
                )
        }
        .buttonStyle(.plain)
    }

    private func scoreBox(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.appSystem(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
            Text(value)
                .font(.appSystem(size: 24, weight: .heavy, design: .rounded))
                .foregroundColor(Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
        }
        .frame(minWidth: 88)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                .fill(BlackBoxClassicPalette.board)
                .shadow(color: BlackBoxClassicPalette.boardHighlight.opacity(0.5), radius: 4, x: -2, y: -2)
                .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(0.2), radius: 4, x: 2, y: 2)
        )
    }

    private func requestConfirmation(_ action: ConfirmAction) {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
            confirmAction = action
        }
    }

    private func dismissConfirmation() {
        withAnimation(.easeInOut(duration: 0.18)) {
            confirmAction = nil
        }
    }

    private func performConfirmedAction(_ action: ConfirmAction) {
        dismissConfirmation()
        switch action {
        case .exit:
            saveCurrentHistoryIfNeeded()
            onBackToIntro()
        case .restart:
            saveCurrentHistoryIfNeeded()
            selectedDetail = nil
            withAnimation(.easeInOut(duration: 0.2)) {
                onRestart()
            }
        case .switchTheme(let theme):
            saveCurrentHistoryIfNeeded()
            selectedTheme = theme
            onRestart()
        case .showRules:
            onShowRules()
        case .refreshPendingTasks:
            withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                game.refreshPendingTiles()
            }
        }
    }

    private func saveCurrentHistoryIfNeeded() {
        let completedTiles = game.board.flatMap { $0 }.compactMap { $0 }.filter { $0.isCompleted }.count
        let hasProgress = game.moveCount > 0 || game.mergeCount > 0 || currentScore > 0 || completedTiles > 0
        guard hasProgress else { return }

        BlackBoxHistoryStore.append(
            BlackBoxHistoryRecord(
                id: UUID(),
                createdAt: Date(),
                themeRawValue: game.theme.rawValue,
                gridSize: game.size,
                score: currentScore,
                moves: game.moveCount,
                merges: game.mergeCount,
                completedTiles: completedTiles
            )
        )
    }

}

private struct BlackBoxBoardGridView: View {
    @Binding var game: BlackBoxGameState
    let onTileTap: (_ row: Int, _ col: Int, _ tile: BlackBoxTile) -> Void

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 10
            let outerPadding: CGFloat = 10
            let totalSpacing = CGFloat(game.size - 1) * spacing
            let side = min(geo.size.width, geo.size.height)
            let cellSide = (side - (outerPadding * 2) - totalSpacing) / CGFloat(game.size)

            ZStack {
                RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                    .fill(BlackBoxClassicPalette.board)
                    .shadow(color: BlackBoxClassicPalette.boardHighlight.opacity(0.72), radius: 8, x: -4, y: -4)
                    .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(0.32), radius: 8, x: 4, y: 4)

                VStack(spacing: spacing) {
                    ForEach(0..<game.size, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(0..<game.size, id: \.self) { col in
                                BlackBoxTileCellView(tile: game.board[row][col])
                                    .frame(width: cellSide, height: cellSide)
                                    .contentShape(RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous))
                                    .onTapGesture {
                                        guard let tile = game.board[row][col] else { return }
                                        onTileTap(row, col, tile)
                                    }
                            }
                        }
                    }
                }
                .padding(outerPadding)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

private struct BlackBoxTileCellView: View {
    let tile: BlackBoxTile?

    var body: some View {
        ZStack {
            if let tile {
                RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                    .fill(tileBackground(for: tile))
                    .shadow(color: tile.isCompleted ? BlackBoxClassicPalette.boardShadow.opacity(0.2) : BlackBoxClassicPalette.boardShadow.opacity(0.1), radius: 4, x: 0, y: 2)

                VStack(spacing: 2) {
                    Text("\(tile.score)")
                        .font(.appSystem(size: tile.score >= 1000 ? 24 : 32, weight: .heavy, design: .rounded))
                        .foregroundColor(tileTextColor(for: tile))
                        .minimumScaleFactor(0.5)

                    if tile.score < 2048 {
                        Text(tile.displayTitle)
                            .font(.appSystem(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(tileTextColor(for: tile).opacity(0.8))
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                    .fill(BlackBoxClassicPalette.emptyTile)
                    .shadow(color: Color.white.opacity(0.3), radius: 4, x: -2, y: -2)
                    .shadow(color: BlackBoxClassicPalette.boardShadow.opacity(0.1), radius: 4, x: 2, y: 2)
            }
        }
    }

    private func tileBackground(for tile: BlackBoxTile) -> Color {
        guard tile.isCompleted else { return BlackBoxClassicPalette.emptyTile.opacity(0.9) }
        switch tile.score {
        case ..<4:
            return Color(hex: "EEE4DA")
        case 4:
            return Color(hex: "EDE0C8")
        case 8:
            return Color(hex: "F2B179")
        case 16:
            return Color(hex: "F59563")
        case 32:
            return Color(hex: "F67C5F")
        case 64:
            return Color(hex: "F65E3B")
        case 128:
            return Color(hex: "EDCF72")
        case 256:
            return Color(hex: "EDCC61")
        case 512:
            return Color(hex: "EDC850")
        case 1024:
            return Color(hex: "EDC53F")
        case 2048:
            return Color(hex: "EDC22E")
        default:
            return Color(hex: "3C3A32")
        }
    }

    private func tileTextColor(for tile: BlackBoxTile) -> Color {
        if !tile.isCompleted {
            return BlackBoxClassicPalette.text
        }
        return tile.score >= 8 ? BlackBoxClassicPalette.darkText : BlackBoxClassicPalette.text
    }
}

private struct BlackBoxTileDetailContext: Identifiable {
    let id = UUID()
    let tile: BlackBoxTile
    let theme: BlackBoxTheme
}

private struct BlackBoxTileDetailSheet: View {
    let context: BlackBoxTileDetailContext

    var body: some View {
        NavigationStack {
            ZStack {
                BlackBoxClassicPalette.background
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(context.tile.displayTitle)
                                .font(.appSystem(size: 24, weight: .heavy, design: .rounded))
                                .foregroundColor(BlackBoxClassicPalette.text)
                                .lineLimit(2)
                        }

                        Spacer()
                    }

                    Text(L10n.blackBoxModeContainsTasks)
                        .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(BlackBoxClassicPalette.text.opacity(0.84))

                    ForEach(componentRows, id: \.id) { row in
                        HStack {
                            Text(row.title)
                                .font(.appSystem(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(BlackBoxClassicPalette.text)
                            Spacer()
                            Text("x\(row.count)")
                                .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(BlackBoxClassicPalette.restart)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                .fill(Color.white.opacity(0.32))
                        )
                    }

                    Divider()
                        .overlay(BlackBoxClassicPalette.text.opacity(0.15))

                    HStack {
                        Text(L10n.blackBoxModeCompletionCount)
                            .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(BlackBoxClassicPalette.text.opacity(0.84))
                        Spacer()
                        Text("\(L10n.blackBoxModeTotalCompletions) \(totalCompletions)")
                            .font(.appSystem(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(BlackBoxClassicPalette.text)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle(L10n.blackBoxModeTileDetailTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var componentRows: [(id: String, title: String, count: Int)] {
        context.tile.components
            .sorted { $0.key < $1.key }
            .map { key, count in
                let title = context.theme.definitionMap[key]?.baseTitle ?? key
                return (id: key, title: title, count: count)
            }
    }

    private var totalCompletions: Int {
        context.tile.components.values.reduce(0, +)
    }
}

private struct BlackBoxHistorySheet: View {
    let records: [BlackBoxHistoryRecord]

    var body: some View {
        NavigationStack {
            ZStack {
                BlackBoxClassicPalette.background
                    .ignoresSafeArea()

                if records.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.appSystem(size: 28, weight: .bold))
                            .foregroundColor(BlackBoxClassicPalette.text.opacity(0.5))
                        Text(L10n.tr("No history yet", zhHans: "暂无历史记录", zhHant: "暫無歷史記錄"))
                            .font(.appSystem(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(BlackBoxClassicPalette.text.opacity(0.75))
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(records) { record in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.themeTitle)
                                            .font(.appSystem(size: 15, weight: .bold, design: .rounded))
                                            .foregroundColor(BlackBoxClassicPalette.text)
                                        Text("\(record.gridSize)x\(record.gridSize) · \(record.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundColor(BlackBoxClassicPalette.text.opacity(0.7))
                                    }

                                    Spacer(minLength: 8)

                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("\(L10n.tr("Score", zhHans: "分数", zhHant: "分數")) \(record.score)")
                                            .font(.appSystem(size: 15, weight: .heavy, design: .rounded))
                                            .foregroundColor(BlackBoxClassicPalette.restart)
                                        Text("\(L10n.blackBoxModeMoves) \(record.moves) · \(L10n.blackBoxModeMerges) \(record.merges)")
                                            .font(.appSystem(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundColor(BlackBoxClassicPalette.text.opacity(0.72))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                        .fill(BlackBoxClassicPalette.board.opacity(0.12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: BlackBoxClassicPalette.edgeRadius, style: .continuous)
                                                .stroke(BlackBoxClassicPalette.board.opacity(0.24), lineWidth: 1)
                                        )
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle(L10n.tr("History", zhHans: "历史记录", zhHant: "歷史記錄"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}



