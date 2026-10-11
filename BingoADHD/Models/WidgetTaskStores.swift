import Foundation

enum BingodaysWidgetKind {
    static let countdown = "BingodaysCountdownWidget"
    static let board = "BingodaysLargeWidget"
    static let lockScreen = "BingodaysLockScreenWidget"
}

enum WidgetPanelSelectionStore {
    static let selectedPanelKey = "widget_selected_panel_id_v1"

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: BingoBoardStore.appGroupID) ?? .standard
    }

    static func loadSelectedPanelID() -> UUID? {
        guard let raw = sharedDefaults.string(forKey: selectedPanelKey) else {
            return nil
        }
        return UUID(uuidString: raw)
    }

    static func saveSelectedPanelID(_ id: UUID?) {
        guard let id else {
            sharedDefaults.removeObject(forKey: selectedPanelKey)
            sharedDefaults.synchronize()
            return
        }
        sharedDefaults.set(id.uuidString, forKey: selectedPanelKey)
        sharedDefaults.synchronize()
    }

    /// Lets a board import update the active panel in the same local persistence
    /// transaction as its named-board snapshot and App Group board mirror.
    static func persistenceStep(selectedPanelID: UUID?) -> PersistenceWriteStep {
        PersistenceWriteTransaction.userDefaultsStep(
            defaults: sharedDefaults,
            key: selectedPanelKey,
            newValue: selectedPanelID?.uuidString
        )
    }
}

/// A short-lived App Group recovery record shared by the app and widget extension.
/// It keeps a local task toggle recoverable if one process is interrupted between
/// updating the board snapshot and completing its remaining local side effects.
enum WidgetTaskSyncStore {
    private static let eventKey = "widget_task_sync_event_v1"
    private static let eventFileName = "widget_task_sync_event_v1.json"

    struct Event: Codable, Equatable {
        struct CellMutation: Codable, Equatable {
            let cellID: UUID
            let previousCell: BingoCell
            let updatedCell: BingoCell
            let row: Int?
            let col: Int?

            init(
                cellID: UUID,
                previousCell: BingoCell,
                updatedCell: BingoCell,
                row: Int? = nil,
                col: Int? = nil
            ) {
                self.cellID = cellID
                self.previousCell = previousCell
                self.updatedCell = updatedCell
                self.row = row
                self.col = col
            }
        }

        let id: UUID
        let boardID: UUID
        let board: BingoBoardStore.NamedBoard
        let savedAt: Date
        let didApplyBoardReset: Bool
        let cellMutation: CellMutation?
        /// The widget has already updated points and diary, but may still need the
        /// app process to persist the matching board snapshot. This prevents the
        /// recovery path from charging the same task a second time.
        let sideEffectsCommitted: Bool

        private enum CodingKeys: String, CodingKey {
            case id
            case boardID
            case board
            case savedAt
            case didApplyBoardReset
            case cellMutation
            case sideEffectsCommitted
        }

        init(
            id: UUID = UUID(),
            boardID: UUID,
            board: BingoBoardStore.NamedBoard,
            savedAt: Date,
            didApplyBoardReset: Bool,
            cellMutation: CellMutation? = nil,
            sideEffectsCommitted: Bool = false
        ) {
            self.id = id
            self.boardID = boardID
            self.board = board
            self.savedAt = savedAt
            self.didApplyBoardReset = didApplyBoardReset
            self.cellMutation = cellMutation
            self.sideEffectsCommitted = sideEffectsCommitted
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            boardID = try container.decode(UUID.self, forKey: .boardID)
            board = try container.decode(BingoBoardStore.NamedBoard.self, forKey: .board)
            savedAt = try container.decode(Date.self, forKey: .savedAt)
            didApplyBoardReset = try container.decodeIfPresent(
                Bool.self,
                forKey: .didApplyBoardReset
            ) ?? false
            cellMutation = try container.decodeIfPresent(
                CellMutation.self,
                forKey: .cellMutation
            )
            // Events written by builds before this field existed always wrote the
            // point/diary side effect before publishing the board snapshot. On an
            // upgrade, treating such an interrupted event as uncommitted would
            // replay its reward. Prefer a missed recovery for that historical
            // edge case over silently minting points a second time.
            sideEffectsCommitted = try container.decodeIfPresent(
                Bool.self,
                forKey: .sideEffectsCommitted
            ) ?? true
        }
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: BingoBoardStore.appGroupID) ?? .standard
    }

    private static var eventFileURL: URL {
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: BingoBoardStore.appGroupID
        ) {
            let directory = containerURL.appendingPathComponent(
                "Library/Application Support",
                isDirectory: true
            )
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory.appendingPathComponent(eventFileName)
        }

        #if targetEnvironment(simulator)
        let directory = URL(
            fileURLWithPath: "/tmp/\(BingoBoardStore.appGroupID)",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent(eventFileName)
        #else
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent(eventFileName)
        #endif
    }

    @discardableResult
    static func save(
        board: BingoBoardStore.NamedBoard,
        didApplyBoardReset: Bool,
        cellMutation: Event.CellMutation? = nil
    ) -> Bool {
        saveEvent(
            board: board,
            didApplyBoardReset: didApplyBoardReset,
            cellMutation: cellMutation
        ) != nil
    }

    static func saveEvent(
        board: BingoBoardStore.NamedBoard,
        didApplyBoardReset: Bool,
        cellMutation: Event.CellMutation? = nil
    ) -> Event? {
        let event = Event(
            boardID: board.id,
            board: board,
            savedAt: board.updatedAt,
            didApplyBoardReset: didApplyBoardReset,
            cellMutation: cellMutation
        )
        return save(event) ? event : nil
    }

    /// Marks the point/diary side of an event durable before the board snapshot is
    /// published. If the process is interrupted after this point, app recovery
    /// applies only the missing board state and never settles points again.
    static func markSideEffectsCommitted(for event: Event) -> Event? {
        guard load()?.id == event.id else { return nil }
        let committedEvent = Event(
            id: event.id,
            boardID: event.boardID,
            board: event.board,
            savedAt: event.savedAt,
            didApplyBoardReset: event.didApplyBoardReset,
            cellMutation: event.cellMutation,
            sideEffectsCommitted: true
        )
        return save(committedEvent) ? committedEvent : nil
    }

    @discardableResult
    static func save(_ event: Event) -> Bool {
        guard let data = try? JSONEncoder().encode(event),
              let fileStep = PersistenceWriteTransaction.fileDataStep(
                at: eventFileURL,
                newData: data
              ) else {
            return false
        }
        return PersistenceWriteTransaction.commit([
            fileStep,
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: eventKey,
                newValue: data
            )
        ])
    }

    static func load() -> Event? {
        let fileData = try? Data(contentsOf: eventFileURL)
        let defaultsData = sharedDefaults.data(forKey: eventKey)
        let candidates = [fileData, defaultsData]
            .compactMap { data -> (data: Data, event: Event)? in
                guard let data,
                      let event = try? JSONDecoder().decode(Event.self, from: data) else {
                    return nil
                }
                return (data, event)
            }
            .sorted { $0.event.savedAt > $1.event.savedAt }
        guard let latest = candidates.first else { return nil }

        var repairSteps: [PersistenceWriteStep] = []
        if fileData != latest.data,
           let fileStep = PersistenceWriteTransaction.fileDataStep(
            at: eventFileURL,
            newData: latest.data
           ) {
            repairSteps.append(fileStep)
        }
        if defaultsData != latest.data {
            repairSteps.append(
                PersistenceWriteTransaction.userDefaultsStep(
                    defaults: sharedDefaults,
                    key: eventKey,
                    newValue: latest.data
                )
            )
        }
        _ = PersistenceWriteTransaction.commit(repairSteps)
        return latest.event
    }

    static func loadBoard() -> SavedBoard? {
        load()?.board.board
    }

    static func loadCountdownEndsAt() -> Date? {
        load()?.board.countdownEndsAt
    }

    static func loadSavedAt() -> Date? {
        load()?.savedAt
    }

    static func clear() {
        guard let fileStep = PersistenceWriteTransaction.fileDataStep(
            at: eventFileURL,
            newData: nil
        ) else {
            return
        }
        _ = PersistenceWriteTransaction.commit([
            fileStep,
            PersistenceWriteTransaction.userDefaultsStep(
                defaults: sharedDefaults,
                key: eventKey,
                newValue: nil
            )
        ])
    }

    static func clear(ifMatching eventID: UUID) {
        guard load()?.id == eventID else { return }
        clear()
    }
}

enum WidgetTaskEventMerge {
    static func applying(
        _ event: WidgetTaskSyncStore.Event?,
        to snapshot: BingoBoardStore.NamedBoardsSnapshot,
        recoverBoard: (BingoBoardStore.NamedBoard) -> BingoBoardStore.NamedBoard = BingoBoardStore.taskRuleRecoveryBoard
    ) -> BingoBoardStore.NamedBoardsSnapshot {
        guard let event else { return snapshot }

        var mergedSnapshot = snapshot
        guard let boardIndex = mergedSnapshot.boards.firstIndex(
            where: { $0.id == event.boardID }
        ) else {
            return snapshot
        }
        if event.didApplyBoardReset {
            let recovered = recoverBoard(mergedSnapshot.boards[boardIndex])
            if recovered.board != mergedSnapshot.boards[boardIndex].board {
                DiagnosticLogStore.recordWarning("task_rule.widget_replay_source_recovered", details: [
                    "board_id": event.boardID.uuidString
                ])
                mergedSnapshot.boards[boardIndex] = recovered
            }
            guard applyResetEvent(
                event,
                to: &mergedSnapshot.boards[boardIndex]
            ) else {
                return snapshot
            }
            return mergedSnapshot
        }
        if let mutation = event.cellMutation {
            guard apply(
                mutation,
                from: event,
                to: &mergedSnapshot.boards[boardIndex]
            ) else {
                return snapshot
            }
            return mergedSnapshot
        }
        guard event.savedAt >= mergedSnapshot.boards[boardIndex].updatedAt else {
            return snapshot
        }

        mergedSnapshot.boards[boardIndex].board = event.board.board
        mergedSnapshot.boards[boardIndex].countdownEndsAt = event.board.countdownEndsAt
        mergedSnapshot.boards[boardIndex].updatedAt = event.savedAt
        return mergedSnapshot
    }

    private static func apply(
        _ mutation: WidgetTaskSyncStore.Event.CellMutation,
        from event: WidgetTaskSyncStore.Event,
        to currentBoard: inout BingoBoardStore.NamedBoard
    ) -> Bool {
        var fullBoard = BoardEngine.expandedBoardCache(from: currentBoard.board)
        guard let position = resolvedPosition(for: mutation, in: fullBoard) else {
            return false
        }

        let currentCell = fullBoard[position.row][position.col]
        if currentCell == mutation.updatedCell {
            return false
        }
        let mergedCell: BingoCell
        if currentCell == mutation.previousCell {
            mergedCell = mutation.updatedCell
        } else {
            guard hasSameTaskDefinition(currentCell, mutation.previousCell) else {
                return false
            }
            mergedCell = cellByApplyingToggleRuntime(
                from: mutation.updatedCell,
                to: currentCell
            )
            guard mergedCell != currentCell else { return false }
        }

        fullBoard[position.row][position.col] = mergedCell
        let gridSize = min(
            max(currentBoard.board.gridSize, 2),
            BoardEngine.maxGridSize
        )
        let visibleCells = BoardEngine.projectVisibleCells(
            from: fullBoard,
            size: gridSize,
            referenceDate: event.savedAt
        )
        currentBoard.board = SavedBoard(
            gridSize: gridSize,
            cells: visibleCells,
            completedLines: BoardEngine.completedLines(
                in: visibleCells,
                size: gridSize
            ),
            fullBoardCells: fullBoard
        )
        currentBoard.updatedAt = max(currentBoard.updatedAt, event.savedAt)
        return true
    }

    private static func applyResetEvent(
        _ event: WidgetTaskSyncStore.Event,
        to currentBoard: inout BingoBoardStore.NamedBoard
    ) -> Bool {
        var didChange = false
        let eventResetAt = event.board.lastTaskResetAppliedAt ?? event.savedAt
        let shouldApplyReset = currentBoard.lastTaskResetAppliedAt.map {
            $0 < eventResetAt
        } ?? true
        if shouldApplyReset {
            currentBoard.board = BoardResetRuleEngine.transformedBoardSnapshotForResetMode(
                currentBoard.board,
                mode: currentBoard.taskResetMode,
                referenceDate: event.savedAt
            )
            currentBoard.countdownEndsAt = nil
            currentBoard.lastTaskResetAppliedAt = eventResetAt
            didChange = true
        }

        if let mutation = event.cellMutation,
           apply(mutation, from: event, to: &currentBoard) {
            didChange = true
        }
        guard didChange else { return false }
        currentBoard.updatedAt = max(currentBoard.updatedAt, event.savedAt)
        return true
    }

    static func containsAppliedMutation(
        _ mutation: WidgetTaskSyncStore.Event.CellMutation,
        in board: SavedBoard
    ) -> Bool {
        let cells = BoardEngine.expandedBoardCache(from: board)
        guard let position = resolvedPosition(for: mutation, in: cells) else { return false }
        let cell = cells[position.row][position.col]
        return hasSameTaskDefinition(cell, mutation.updatedCell) &&
            cell.isCompleted == mutation.updatedCell.isCompleted &&
            cell.lastCompletedAt == mutation.updatedCell.lastCompletedAt
    }

    private static func hasSameTaskDefinition(
        _ lhs: BingoCell,
        _ rhs: BingoCell
    ) -> Bool {
        lhs.text == rhs.text &&
            lhs.residentTaskText == rhs.residentTaskText &&
            lhs.residentWeekdays == rhs.residentWeekdays &&
            lhs.oneTimeVisibleDate == rhs.oneTimeVisibleDate &&
            lhs.recurrenceRule == rhs.recurrenceRule &&
            lhs.startVisibleAt == rhs.startVisibleAt &&
            lhs.endVisibleAt == rhs.endVisibleAt &&
            lhs.usesRecurringTimeWindow == rhs.usesRecurringTimeWindow &&
            lhs.startReminderEnabled == rhs.startReminderEnabled &&
            lhs.startReminderOffsetMinutes == rhs.startReminderOffsetMinutes &&
            lhs.startVisibleMonth == rhs.startVisibleMonth &&
            lhs.startVisibleDay == rhs.startVisibleDay
    }

    static func resolvedPosition(
        for mutation: WidgetTaskSyncStore.Event.CellMutation,
        in board: SavedBoard
    ) -> (row: Int, col: Int)? {
        resolvedPosition(
            for: mutation,
            in: BoardEngine.expandedBoardCache(from: board)
        )
    }

    private static func resolvedPosition(
        for mutation: WidgetTaskSyncStore.Event.CellMutation,
        in cells: [[BingoCell]]
    ) -> (row: Int, col: Int)? {
        if let identityMatch = position(of: mutation.cellID, in: cells) {
            return identityMatch
        }

        guard let row = mutation.row,
              let col = mutation.col,
              row >= 0,
              col >= 0,
              row < cells.count,
              col < cells[row].count else {
            return nil
        }
        let candidate = cells[row][col]
        guard hasSameTaskDefinition(candidate, mutation.previousCell) ||
                hasSameTaskDefinition(candidate, mutation.updatedCell) else {
            return nil
        }
        return (row, col)
    }

    private static func cellByApplyingToggleRuntime(
        from source: BingoCell,
        to destination: BingoCell
    ) -> BingoCell {
        var result = destination
        result.isTaskHidden = source.isTaskHidden
        result.isCompleted = source.isCompleted
        result.isForced = source.isForced
        result.countdownEndsAt = source.countdownEndsAt
        result.countdownPausedRemainingSeconds = source.countdownPausedRemainingSeconds
        result.estimatedDurationMinutes = source.estimatedDurationMinutes
        result.completionStreakCount = source.completionStreakCount
        result.lastCompletedAt = source.lastCompletedAt
        result.lastVisibilityWindowTimeoutAt = source.lastVisibilityWindowTimeoutAt
        return result
    }

    private static func position(
        of cellID: UUID,
        in cells: [[BingoCell]]
    ) -> (row: Int, col: Int)? {
        for row in cells.indices {
            if let col = cells[row].firstIndex(where: { $0.id == cellID }) {
                return (row, col)
            }
        }
        return nil
    }
}
