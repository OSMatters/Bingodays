import SwiftUI
import Combine
import AppKit

@MainActor
final class MacWorkspaceStore: ObservableObject {
    let model = BingoViewModel()
    let boards = BoardManagementStore()
    @Published var editingCellID: UUID?
    @Published var isOrganizing = false
    @Published var errorMessage: String?
    private var lastResetEvaluation = ""
    private var lastResetCheck = Date.distantPast
    private var completionSound: NSSound?
    private var observations: Set<AnyCancellable> = []

    init() {
        if let board = boards.loadIfNeeded(initialBoard: model.makeSavedBoardSnapshot(), countdownEndsAt: model.boardCountdownEndsAt) { apply(board) }
        if let url = Bundle.main.url(forResource: "get1point", withExtension: "aiff") { completionSound = NSSound(contentsOf: url, byReference: true) }
        evaluateResets()
        model.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &observations)
        boards.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &observations)
    }
    var editingCoordinate: (row: Int, col: Int)? {
        for row in model.cells.indices {
            for col in model.cells[row].indices where model.cells[row][col].id == editingCellID { return (row, col) }
        }
        return nil
    }
    func persist() {
        guard let id = boards.selectedBoardID else { return }
        _ = boards.persistBoardState(for: id, board: model.makeSavedBoardSnapshot(), countdownEndsAt: model.boardCountdownEndsAt)
        if !boards.hasDurableSelectedBoardState() { errorMessage = "保存未完成，请重试。"; return }
        publishDesktopBoard()
    }
    func select(_ id: UUID) {
        persist()
        guard let result = boards.selectBoard(id, currentBoard: model.makeSavedBoardSnapshot(), currentCountdownEndsAt: model.boardCountdownEndsAt) else { errorMessage = "切换棋盘失败，请重试。"; return }
        apply(result.selectedBoard)
    }
    func createBoard() {
        persist()
        guard let result = boards.createBoard(nameDraft: "", currentBoard: model.makeSavedBoardSnapshot(), currentCountdownEndsAt: model.boardCountdownEndsAt) else { errorMessage = "创建棋盘失败，请重试。"; return }
        apply(result.selectedBoard)
    }
    func deleteBoard(_ id: UUID) {
        persist()
        guard let result = boards.deleteBoard(id, allowsDeletingFirstBoard: true) else { errorMessage = "请至少保留一个棋盘。"; return }
        apply(result.selectedBoard)
    }
    func apply(_ board: BingoBoardStore.NamedBoard) {
        editingCellID = nil
        model.applySavedBoardSnapshot(board.board, countdownEndsAt: board.countdownEndsAt, reloadPersistedPoints: true, persist: false)
        publishDesktopBoard()
    }
    func refresh() {
        if let board = boards.reloadPersistedSnapshotIfNewer() { apply(board) }
        model.applyForegroundCleanup()
        evaluateResets()
        Task { await MacReminderService.sync(boards: boards.namedBoards) }
    }
    func toggle(row: Int, col: Int) {
        if isOrganizing || !model.cells[row][col].hasStoredTask { editingCellID = model.cells[row][col].id; return }
        let wasCompleted = model.cells[row][col].isCompleted
        model.toggleComplete(row: row, col: col)
        if !wasCompleted && model.cells[row][col].isCompleted && AppSettings.isSoundEffectsEnabled { completionSound?.play() }
        persist()
    }
    func tick(now: Date = .now) {
        if now.timeIntervalSince(lastResetCheck) >= 30 { evaluateResets(now: now) }
        let before = model.makeSavedBoardSnapshot()
        model.processExpiredCountdowns(now: now)
        _ = model.refreshVisibilityWindowsIfNeeded(now: now)
        model.processScheduledTaskReplacementConflicts(now: now)
        if before != model.makeSavedBoardSnapshot() { persist() }
    }
    func evaluateResets(now: Date = .now) {
        lastResetCheck = now
        boards.reconcileTaskRulesBeforeReset()
        var coordinator = BoardResetCoordinator(
            namedBoards: boards.namedBoards, selectedBoardID: boards.selectedBoardID,
            lastEvaluationDateKey: lastResetEvaluation,
            hasAppliedDebugSimulatedResetThisLaunch: false, lastCustomResetDebugToastKey: "",
            debugConfiguration: BoardResetDebugConfiguration(simulateNextDayReset: false, prepareStreakTest: false, showCustomResetToast: false)
        )
        let result = coordinator.evaluate(now: now, source: "mac")
        if result.didReset {
            guard boards.commitResetBoards(coordinator.namedBoards) else { errorMessage = "每日重置未能保存，请重试。"; return }
            if result.didResetActiveBoard, let board = boards.selectedBoardSnapshot {
                let hadCountdown = model.boardCountdownEndsAt != nil
                apply(board)
                model.finalizePostResetState(now: now, didBoardCountdownExist: hadCountdown, clearedCompletedTaskCount: result.clearedCompletedTaskCount)
                persist()
            }
        }
        lastResetEvaluation = coordinator.lastEvaluationDateKey
    }
    func editFirstEmptyCell() {
        for row in model.cells.indices {
            for col in model.cells[row].indices where !model.cells[row][col].hasStoredTask { editingCellID = model.cells[row][col].id; return }
        }
        errorMessage = "棋盘已满，可以编辑现有任务或扩大棋盘。"
    }
}
