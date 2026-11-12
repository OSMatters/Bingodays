import Foundation
import Testing
@testable import Bingodays

@Suite struct TaskCompletionRewardTests {
    private let now = Date(timeIntervalSince1970: 1_793_836_800)

    private func settle(
        _ previous: BingoCell, _ current: BingoCell,
        total: Int = 0, lifetime: Int = 0, state: DailyRewardState? = nil, floor: Int = 0,
        previousLines: Set<BingoLine> = [], currentLines: Set<BingoLine> = [], full: Bool = false
    ) -> BingoRewardSettlementOutput {
        BingoRewardSettlement.settleTaskToggle(
            date: now, previousCells: [[previous]], previousCompletedLines: previousLines,
            previousIsBoardFullyCompleted: false, currentCells: [[current]],
            currentCompletedLines: currentLines, currentIsBoardFullyCompleted: full,
            totalPoints: total, lifetimePoints: lifetime,
            dailyRewardState: state ?? BingoRewardSettlement.emptyDailyRewardState(for: now),
            taskIsNowCompleted: current.isCompleted, minimumTotalPoints: floor
        )
    }

    @Test(arguments: [1, 2, 3, 5, 10, 99])
    func completionAwardsConfiguredAmount(points: Int) {
        let previous = BingoCell(text: "Read", customCompletionPoints: points)
        var current = previous
        current.isCompleted = true
        let result = settle(previous, current)
        #expect(result.totalPoints == points)
        #expect(result.lifetimePoints == points)
        #expect(points == 1 ? result.taskRewardReceipts.isEmpty : result.taskRewardReceipts[current.id]?.awardedPoints == points)
    }

    @Test func lineAndFullBoardBonusesStayUnchanged() {
        let previous = BingoCell(text: "Read", customCompletionPoints: 3)
        var current = previous
        current.isCompleted = true
        let result = settle(previous, current, currentLines: [.row(0)], full: true)
        #expect(result.totalPoints == 18)
        #expect(result.lifetimePoints == 18)
    }

    @Test(arguments: [0, 2, 5])
    func undoAndRecompletionRestoreOnlyActuallyDeductedPoints(available: Int) throws {
        let previous = BingoCell(text: "Read", customCompletionPoints: 5)
        var completed = previous
        completed.isCompleted = true
        let first = settle(previous, completed)
        completed.taskRewardReceipt = try #require(first.taskRewardReceipts[completed.id])
        var undone = completed
        undone.isCompleted = false
        let undo = settle(completed, undone, total: 20 + available, lifetime: 5, floor: 20)
        #expect(undo.totalPoints == 20)
        #expect(undo.lifetimePoints == 5)
        #expect(undo.dailyRewardState.taskReversalCredits[completed.id.uuidString.lowercased()] == nil)
        undone.taskRewardReceipt = try #require(undo.taskRewardReceipts[completed.id])
        #expect(undone.taskRewardReceipt?.reversalCredit?.points == available)
        // Editing the NEXT occurrence to 99 must not inflate this restoration.
        undone.customCompletionPoints = 99
        var redone = undone
        redone.isCompleted = true
        let restore = settle(undone, redone, total: 20, lifetime: 5, state: undo.dailyRewardState, floor: 20)
        #expect(restore.totalPoints == 20 + available)
        #expect(restore.lifetimePoints == 5 + available)
        #expect(restore.taskRewardReceipts[redone.id]?.awardedPoints == 5)
        #expect(restore.taskRewardReceipts[redone.id]?.reversalCredit == nil)
    }

    @Test func editingCompletedLegacyTaskKeepsItsOriginalOnePoint() {
        let legacy = BingoCell(text: "Read", isCompleted: true)
        let edited = TaskCompletionRewardRules.applyingEdit(.custom(10), previous: legacy, updated: legacy, dateKey: "today")
        #expect(edited.customCompletionPoints == 10)
        #expect(edited.taskRewardReceipt?.awardedPoints == 1)
        var undone = edited
        undone.isCompleted = false
        #expect(settle(edited, undone, total: 20).totalPoints == 19)
    }

    @Test(arguments: [0, 1])
    func legacyUndoCreditSurvivesFirstCustomConfiguration(credit: Int) {
        let legacy = BingoCell(text: "Read")
        let dateKey = PointsStore.dateKey(for: now)
        let edited = TaskCompletionRewardRules.applyingEdit(
            .custom(10), previous: legacy, updated: legacy, legacyReversalCredit: credit, dateKey: dateKey
        )
        var current = edited
        current.isCompleted = true
        let state = DailyRewardState(dateKey: dateKey, taskReversalCredits: [legacy.id.uuidString.lowercased(): credit])
        let result = settle(edited, current, state: state)
        #expect(result.totalPoints == credit)
        #expect(result.taskRewardReceipts[current.id]?.awardedPoints == 1)
    }

    @Test func configurationOnlyChangesDoNotSettlePoints() {
        let previous = BingoCell(text: "Read", customCompletionPoints: 3)
        var edited = previous
        edited.customCompletionPoints = 10
        let result = settle(previous, edited, total: 12, lifetime: 25)
        #expect(result.totalPoints == 12)
        #expect(result.lifetimePoints == 25)
        #expect(result.taskRewardReceipts.isEmpty)
    }

    @Test func resetClearsOnlyReceiptAndUsesNextConfiguration() throws {
        var cell = BingoCell(text: "Read", isCompleted: true, customCompletionPoints: 10,
                             taskRewardReceipt: .init(awardedPoints: 3))
        let board = SavedBoard(gridSize: 2, cells: [[cell, BingoCell()], [BingoCell(), BingoCell()]], completedLines: [])
        let reset = BoardResetRuleEngine.transformedBoardSnapshotForResetMode(board, mode: .resetStatusNextDay, referenceDate: now)
        cell = try #require(reset.fullBoardCells?[0][0])
        #expect(cell.customCompletionPoints == 10)
        #expect(cell.taskRewardReceipt == nil)
        #expect(!cell.isCompleted)
        var completed = cell
        completed.isCompleted = true
        #expect(settle(cell, completed).totalPoints == 10)
        let kept = BoardResetRuleEngine.transformedBoardSnapshotForResetMode(board, mode: .keepTaskStatus, referenceDate: now)
        #expect(kept.fullBoardCells?[0][0].taskRewardReceipt?.awardedPoints == 3)
    }

    @Test func receiptsTravelWithBoardAndSurviveSerialization() throws {
        let cell = BingoCell(text: "Read", isCompleted: true, customCompletionPoints: 10,
                             taskRewardReceipt: .init(awardedPoints: 3, reversalCredit: .init(dateKey: "day", points: 0)))
        let board = SavedBoard(gridSize: 2, cells: [[cell]], completedLines: [])
        let decoded = try JSONDecoder().decode(SavedBoard.self, from: JSONEncoder().encode(board))
        #expect(decoded.cells[0][0] == cell)
        #expect(BoardEngine.boardScore(cells: [[cell]], completedLines: []) == 13) // 3 + existing full-board bonus
        let oldCompleted = BingoCell(text: "Old", isCompleted: true)
        #expect(BoardEngine.boardScore(cells: [[oldCompleted]], completedLines: []) == 11)
    }

    @Test func legacyCellDecodesAndDoesNotAcquireNewState() throws {
        let original = BingoCell(text: "Read", isCompleted: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BingoCell.self, from: data)
        #expect(decoded == original)
        #expect(decoded.customCompletionPoints == nil)
        #expect(decoded.taskRewardReceipt == nil)
        var undone = decoded
        undone.isCompleted = false
        let result = settle(decoded, undone, total: 10)
        #expect(result.totalPoints == 9)
        #expect(result.taskRewardReceipts.isEmpty)
        #expect(result.dailyRewardState.taskReversalCredits[decoded.id.uuidString.lowercased()] == 1)
    }

    @Test func permissionAndUnchangedEditsPreserveExpiredMembersSettings() {
        #expect(!TaskCompletionRewardRules.allows(.custom(3), hasPremiumAccess: false))
        #expect(!TaskCompletionRewardRules.allows(.custom(100), hasPremiumAccess: true))
        #expect(TaskCompletionRewardRules.allows(.useDefault, hasPremiumAccess: false))
        #expect(TaskCompletionRewardRules.allows(.unchanged, hasPremiumAccess: false))
        let cell = BingoCell(text: "Read", customCompletionPoints: 7)
        let unchanged = TaskCompletionRewardRules.applyingEdit(.unchanged, previous: cell, updated: cell, dateKey: "day")
        #expect(unchanged == cell)
        let cleared = TaskCompletionRewardRules.applyingEdit(.unchanged, previous: cell, updated: BingoCell(), dateKey: "day")
        #expect(cleared.customCompletionPoints == nil)
        #expect(cleared.taskRewardReceipt == nil)
    }

    @Test func freshCustomOccurrenceDoesNotRestoreStaleLegacyCredit() {
        let cell = BingoCell(text: "Read", customCompletionPoints: 10)
        var completed = cell
        completed.isCompleted = true
        let state = DailyRewardState(dateKey: PointsStore.dateKey(for: now), taskReversalCredits: [cell.id.uuidString.lowercased(): 0])
        #expect(settle(cell, completed, state: state).totalPoints == 10)
    }

    @Test func removedCustomTaskUsesOriginalReceiptAmount() {
        let previous = BingoCell(text: "Read", isCompleted: true, customCompletionPoints: 10,
                                 taskRewardReceipt: .init(awardedPoints: 3))
        let result = BingoRewardSettlement.settleBoardTransition(
            date: now, previousCells: [[previous]], previousCompletedLines: [], previousIsBoardFullyCompleted: false,
            currentCells: [[BingoCell()]], currentCompletedLines: [], currentIsBoardFullyCompleted: false,
            totalPoints: 20, lifetimePoints: 30, dailyRewardState: BingoRewardSettlement.emptyDailyRewardState(for: now)
        )
        #expect(result.totalPoints == 17)
        #expect(result.lifetimePoints == 30)
    }

    @Test func cloudSnapshotRoundTripPreservesConfigurationAndReceipt() throws {
        let cell = BingoCell(text: "Read", isCompleted: true, customCompletionPoints: 10,
                             taskRewardReceipt: .init(awardedPoints: 3))
        let board = SavedBoard(gridSize: 2, cells: [[cell]], completedLines: [])
        let named = BingoBoardStore.NamedBoard(name: "Points", board: board, updatedAt: now)
        let snapshot = NativeICloudPrimaryStateSnapshot(
            boards: [named], points: .init(totalPoints: 3, lifetimePoints: 3, dailyRewardState: nil),
            diaryEntries: [:], timeoutPayload: [:], customRewards: [], redemptionHistory: [],
            stickerInventory: [:], stickerPlacements: []
        )
        let decoded = try JSONDecoder().decode(NativeICloudPrimaryStateSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded.boards[0].board.cells[0][0] == cell)
        #expect(decoded.hasSameUserState(as: snapshot))
        var changed = named
        var changedCell = cell
        changedCell.customCompletionPoints = 20
        changed.board = SavedBoard(gridSize: 2, cells: [[changedCell]], completedLines: [])
        let changedSnapshot = NativeICloudPrimaryStateSnapshot(
            boards: [changed], points: snapshot.points, diaryEntries: [:], timeoutPayload: [:],
            customRewards: [], redemptionHistory: [], stickerInventory: [:], stickerPlacements: []
        )
        #expect(!changedSnapshot.hasSameUserState(as: snapshot))
    }

    @Test func remoteUndoCreditDoesNotDependOnLocalDailyCache() {
        let dateKey = PointsStore.dateKey(for: now)
        let undone = BingoCell(text: "Read", customCompletionPoints: 10,
                              taskRewardReceipt: .init(awardedPoints: 5, reversalCredit: .init(dateKey: dateKey, points: 0)))
        var completed = undone
        completed.isCompleted = true
        #expect(settle(undone, completed).totalPoints == 0)
    }

    @Test func expiredReversalCreditFollowsExistingRewardDayPolicy() {
        let undone = BingoCell(text: "Read", customCompletionPoints: 10,
                              taskRewardReceipt: .init(awardedPoints: 5, reversalCredit: .init(dateKey: "previous-day", points: 0)))
        var completed = undone
        completed.isCompleted = true
        #expect(settle(undone, completed).totalPoints == 5)
    }
}
