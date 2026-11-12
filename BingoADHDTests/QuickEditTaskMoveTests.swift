import XCTest
@testable import Bingodays

final class QuickEditTaskMoveTests: XCTestCase {
    func testMovePreservesIdentityAndRulesWithoutAffectingOtherTasks() {
        let task = MyTaskItem(text: "Read", startMonth: 11, startDay: 9, recurrenceRule: TaskRecurrenceRule(kind: .weekly))
        let other = MyTaskItem(text: "Read")
        let destination = MyTaskGroup(name: "Week")
        var library = MyTasksLibrary(tasks: [task, other], groups: [destination])

        XCTAssertEqual(quickEditMoveTask(key: task.id.uuidString, to: destination.id, isPremiumUser: true, library: &library), .moved)
        XCTAssertEqual(library.tasks, [other])
        XCTAssertEqual(library.groups[0].tasks, [task])
        XCTAssertEqual(quickEditTaskKey(library.groups[0].tasks[0]), task.id.uuidString)

        XCTAssertEqual(quickEditMoveTask(key: task.id.uuidString, to: nil, isPremiumUser: true, library: &library), .moved)
        XCTAssertEqual(library.tasks, [other, task])
        XCTAssertTrue(library.groups[0].tasks.isEmpty)
    }

    func testMoveBetweenGroupsKeepsPreviewSelectionAndRuntimeState() {
        let task = MyTaskItem(text: "Drink water")
        let source = MyTaskGroup(name: "Source", tasks: [task])
        let destination = MyTaskGroup(name: "Destination")
        var library = MyTasksLibrary(groups: [source, destination])
        let cell = BingoCell(text: task.text, isCompleted: true)
        let slots = [QuickEditPreviewSlot(cellState: cell, sourceTaskKey: task.id.uuidString)]

        XCTAssertEqual(quickEditMoveTask(key: task.id.uuidString, to: destination.id, isPremiumUser: true, library: &library), .moved)
        let candidates = Dictionary(uniqueKeysWithValues: quickEditAllTaskCandidates(library: library, unlockedHistoryRecords: []).map { ($0.id, $0.task) })
        let synced = quickEditSyncPreviewSlotsWithLibrary(currentSlots: slots, candidateTaskMap: candidates, totalGridSlots: 1)
        XCTAssertEqual(synced[0].sourceTaskKey, task.id.uuidString)
        XCTAssertEqual(synced[0].cellState?.id, cell.id)
        XCTAssertEqual(synced[0].cellState?.isCompleted, true)
    }

    func testMembershipChangesDoNotTriggerBoardDefinitionSync() {
        let task = MyTaskItem(text: "Read", recurrenceRule: TaskRecurrenceRule(kind: .daily))
        let group = MyTaskGroup(name: "Daily")
        var library = MyTasksLibrary(tasks: [task], groups: [group])
        let original = library
        _ = quickEditMoveTask(key: task.id.uuidString, to: group.id, isPremiumUser: true, library: &library)
        XCTAssertTrue(quickEditHasSameTaskDefinitions(original, library))
        library.groups[0].name = "Renamed"
        XCTAssertTrue(quickEditHasSameTaskDefinitions(original, library))
        library.groups[0].tasks[0].recurrenceRule = TaskRecurrenceRule(kind: .weekly, weekdays: [2])
        XCTAssertFalse(quickEditHasSameTaskDefinitions(original, library))
    }

    func testFullDestinationDoesNotRemoveSourceTask() {
        let task = MyTaskItem(text: "Keep me")
        let full = MyTaskGroup(name: "Full", tasks: (0..<AppSettings.maxTasksPerGroup).map { MyTaskItem(text: "Task \($0)") })
        var library = MyTasksLibrary(tasks: [task], groups: [full])
        let original = library
        XCTAssertEqual(quickEditMoveTask(key: task.id.uuidString, to: full.id, isPremiumUser: false, library: &library), .limitReached)
        XCTAssertEqual(library, original)
    }

    func testFullStandaloneDestinationDoesNotRemoveGroupedTask() {
        let task = MyTaskItem(text: "Keep me")
        let source = MyTaskGroup(name: "Source", tasks: [task])
        var library = MyTasksLibrary(
            tasks: (0..<AppSettings.maxCommonTasks).map { MyTaskItem(text: "Task \($0)") },
            groups: [source]
        )
        let original = library
        XCTAssertEqual(quickEditMoveTask(key: task.id.uuidString, to: nil, isPremiumUser: false, library: &library), .limitReached)
        XCTAssertEqual(library, original)
    }

    func testMissingDestinationAndSameGroupLeaveLibraryUnchanged() {
        let task = MyTaskItem(text: "Keep me")
        let group = MyTaskGroup(name: "Daily", tasks: [task])
        var library = MyTasksLibrary(groups: [group])
        let original = library
        XCTAssertEqual(quickEditMoveTask(key: task.id.uuidString, to: UUID(), isPremiumUser: true, library: &library), .invalid)
        XCTAssertEqual(quickEditMoveTask(key: task.id.uuidString, to: group.id, isPremiumUser: true, library: &library), .unchanged)
        XCTAssertEqual(library, original)
    }
    func testInitialBoardAssociatesLibraryTaskWithoutChangingRuntimeState() {
        let task = MyTaskItem(text: "Read", recurrenceRule: TaskRecurrenceRule(kind: .daily))
        let cell = BingoCell(text: task.text, recurrenceRule: task.recurrenceRule, startReminderEnabled: true, isCompleted: true, isForced: true, customCompletionPoints: 7)
        let result = quickEditInitialTaskPool(cells: [cell, nil], candidates: [QuickEditTaskCandidate(id: task.id.uuidString, task: task)], totalSlots: 4)
        XCTAssertEqual(result.slots.count, 4)
        XCTAssertEqual(result.slots[0].sourceTaskKey, task.id.uuidString)
        XCTAssertEqual(result.slots[0].cellState, cell)
        XCTAssertNil(result.slots[1].sourceTaskKey)
        XCTAssertTrue(result.supplementalTasks.isEmpty)
        let synced = quickEditSyncPreviewSlotsWithLibrary(currentSlots: result.slots, candidateTaskMap: [task.id.uuidString: task], totalGridSlots: 4)
        XCTAssertEqual(synced[0].cellState, cell)
    }

    func testBoardOnlyTasksRemainInSessionPoolAfterDeselectAndReselect() throws {
        let cell = BingoCell(text: "Drink water", isCompleted: true, isForced: true, customCompletionPoints: 9)
        let result = quickEditInitialTaskPool(cells: [cell], candidates: [], totalSlots: 4)
        let key = try XCTUnwrap(result.slots[0].sourceTaskKey)
        XCTAssertEqual(result.supplementalTasks[key]?.id, cell.id)
        var drafts: [String: QuickEditDeselectedTaskDraft] = [:]
        let removed = quickEditRemovePreviewTask(key: key, currentSlots: result.slots, candidateTaskMap: result.supplementalTasks, deselectedTaskDrafts: &drafts)
        XCTAssertNil(removed[0].task)
        let restored = quickEditAddPreviewTask(key: key, candidateTaskMap: result.supplementalTasks, currentSlots: removed, deselectedTaskDrafts: &drafts)
        XCTAssertTrue(restored.wasAdded)
        XCTAssertEqual(restored.updatedSlots[0].cellState, cell)
    }

    func testSameTitleWithDifferentRuleIsNotAssociatedWithWrongTag() {
        let daily = MyTaskItem(text: "Read", recurrenceRule: TaskRecurrenceRule(kind: .daily))
        let weeklyCell = BingoCell(text: "Read", recurrenceRule: TaskRecurrenceRule(kind: .weekly, weekdays: [2]))
        let result = quickEditInitialTaskPool(cells: [weeklyCell], candidates: [QuickEditTaskCandidate(id: daily.id.uuidString, task: daily)], totalSlots: 1)
        XCTAssertNotEqual(result.slots[0].sourceTaskKey, daily.id.uuidString)
        XCTAssertEqual(result.supplementalTasks.count, 1)
    }

    func testDuplicateBoardTasksGetIndependentSelectionKeys() {
        let task = MyTaskItem(text: "Read")
        let result = quickEditInitialTaskPool(cells: [BingoCell(text: "Read"), BingoCell(text: "Read")], candidates: [QuickEditTaskCandidate(id: task.id.uuidString, task: task)], totalSlots: 4)
        let keys = result.slots.compactMap(\.sourceTaskKey)
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(Set(keys).count, 2)
        XCTAssertEqual(result.supplementalTasks.count, 1)
    }

    func testPoolImportHonorsLimitsAndPreservesTaskDefinition() {
        let task = MyTaskItem(text: "Board only", recurrenceRule: TaskRecurrenceRule(kind: .weekly, weekdays: [3]))
        let group = MyTaskGroup(name: "Weekly")
        var library = MyTasksLibrary(groups: [group])
        XCTAssertEqual(quickEditMovePoolTask(key: "board:\(task.id)", task: task, to: group.id, isPremiumUser: false, library: &library), .moved)
        XCTAssertEqual(library.groups[0].tasks, [task])
        var fullLibrary = MyTasksLibrary(tasks: (0..<AppSettings.maxCommonTasks).map { MyTaskItem(text: "Task \($0)") })
        let original = fullLibrary
        XCTAssertEqual(quickEditMovePoolTask(key: "board:\(task.id)", task: task, to: nil, isPremiumUser: false, library: &fullLibrary), .limitReached)
        XCTAssertEqual(fullLibrary, original)
    }

    func testRemovingLastInitialTaskProducesAnEmptyBoardForApply() throws {
        let cell = BingoCell(text: "Last task", recurrenceRule: TaskRecurrenceRule(kind: .daily), isForced: true)
        let initial = quickEditInitialTaskPool(cells: [cell], candidates: [], totalSlots: 4)
        let key = try XCTUnwrap(initial.slots[0].sourceTaskKey)
        var drafts: [String: QuickEditDeselectedTaskDraft] = [:]
        let removed = quickEditRemovePreviewTask(key: key, currentSlots: initial.slots, candidateTaskMap: initial.supplementalTasks, deselectedTaskDrafts: &drafts)
        let applied = BoardOrderedCellsRuleEngine.apply(BoardOrderedCellsRuleInput(
            orderedCells: removed.map(\.cellState), targetGridSize: 2, minimumGridSize: 2,
            maximumGridSize: 5, maxTaskLength: AppSettings.maxTaskLength,
            referenceDate: .now, calendar: .current
        ))
        XCTAssertTrue(applied.fullBoardCells.flatMap { $0 }.allSatisfy { !$0.hasStoredTask })
        XCTAssertTrue(removed.compactMap(\.sourceTaskKey).isEmpty)
    }

    func testDetailedCreationKeepsChosenRuleAndRestoresCompleteConfigurationOnSelection() throws {
        let group = MyTaskGroup(name: "Daily")
        var library = MyTasksLibrary(groups: [group])
        let cell = BingoCell(text: "Read", recurrenceRule: TaskRecurrenceRule(kind: .weekly, weekdays: [2, 4]), startReminderEnabled: true, isForced: true, customCompletionPoints: 7)
        let result = quickEditCommitDetailedTask(cell: cell, destination: .group(group.id), isPremiumUser: true, library: &library)
        guard case .appended(let task) = result else { return XCTFail("Expected saved task") }
        XCTAssertEqual(library.groups[0].tasks, [task])
        XCTAssertEqual(task.recurrenceRule, cell.effectiveRecurrenceRule)
        XCTAssertEqual(task.id, cell.id)
        let key = quickEditTaskKey(task)
        var drafts = [key: QuickEditDeselectedTaskDraft(sourceTask: task, cellState: cell)]
        let selected = quickEditAddPreviewTask(key: key, candidateTaskMap: [key: task], currentSlots: quickEditEmptyPreviewSlots(count: 4), deselectedTaskDrafts: &drafts)
        XCTAssertTrue(selected.wasAdded)
        XCTAssertEqual(selected.updatedSlots[0].cellState, cell)
    }

    func testDetailedCreationRechecksCapacityAtSaveTime() {
        let cell = BingoCell(text: "Draft")
        let group = MyTaskGroup(name: "Full", tasks: (0..<AppSettings.maxTasksPerGroup).map { MyTaskItem(text: "Task \($0)") })
        var library = MyTasksLibrary(groups: [group])
        let original = library
        guard case .paywall = quickEditCommitDetailedTask(cell: cell, destination: .group(group.id), isPremiumUser: false, library: &library) else {
            return XCTFail("Expected existing group limit")
        }
        XCTAssertEqual(library, original)
    }

    func testDetailedCreationDoesNotRedirectToStandaloneWhenGroupDisappears() {
        var library = MyTasksLibrary()
        let result = quickEditCommitDetailedTask(cell: BingoCell(text: "Draft"), destination: .group(UUID()), isPremiumUser: true, library: &library)
        guard case .resetFilterToAll = result else { return XCTFail("Expected missing destination") }
        XCTAssertTrue(library.tasks.isEmpty)
        XCTAssertTrue(library.groups.isEmpty)
    }

}
