import Foundation

enum QuickEditTaskMoveResult: Equatable {
    case moved
    case unchanged
    case invalid
    case limitReached
}

/// Mutates only group membership. Task identity, rules, and board state are untouched.
func quickEditMoveTask(
    key: String,
    to destinationGroupID: UUID?,
    isPremiumUser: Bool,
    library: inout MyTasksLibrary
) -> QuickEditTaskMoveResult {
    guard let source = quickEditTaskLocation(forTaskKey: key, in: library),
          let task = quickEditTask(for: source, in: library) else { return .invalid }

    let sourceGroupID: UUID?
    switch source {
    case .standalone: sourceGroupID = nil
    case .group(let groupID, _): sourceGroupID = groupID
    }
    guard sourceGroupID != destinationGroupID else { return .unchanged }

    if let destinationGroupID {
        guard let group = library.groups.first(where: { $0.id == destinationGroupID }) else { return .invalid }
        guard quickEditCanAddTask(to: group, isPremiumUser: isPremiumUser) else { return .limitReached }
    } else {
        guard quickEditCanAddStandaloneTask(isPremiumUser: isPremiumUser, library: library) else { return .limitReached }
    }

    switch source {
    case .standalone(let index): library.tasks.remove(at: index)
    case .group(let groupID, let index):
        guard let groupIndex = library.groups.firstIndex(where: { $0.id == groupID }) else { return .invalid }
        library.groups[groupIndex].tasks.remove(at: index)
    }
    if let destinationGroupID,
       let groupIndex = library.groups.firstIndex(where: { $0.id == destinationGroupID }) {
        library.groups[groupIndex].tasks.append(task)
    } else {
        library.tasks.append(task)
    }
    return .moved
}

/// Group names, membership, and ordering are presentation changes, not task edits.
func quickEditHasSameTaskDefinitions(_ lhs: MyTasksLibrary, _ rhs: MyTasksLibrary) -> Bool {
    func definitions(_ library: MyTasksLibrary) -> [MyTaskItem] {
        (library.tasks + library.groups.flatMap(\.tasks)).sorted { $0.id.uuidString < $1.id.uuidString }
    }
    return definitions(lhs) == definitions(rhs)
}

/// Importing a board/history task happens only after an explicit move action.
func quickEditMovePoolTask(
    key: String, task: MyTaskItem, to groupID: UUID?,
    isPremiumUser: Bool, library: inout MyTasksLibrary
) -> QuickEditTaskMoveResult {
    if quickEditTaskLocation(forTaskKey: key, in: library) != nil {
        return quickEditMoveTask(key: key, to: groupID, isPremiumUser: isPremiumUser, library: &library)
    }
    if let groupID {
        guard let index = library.groups.firstIndex(where: { $0.id == groupID }) else { return .invalid }
        guard quickEditCanAddTask(to: library.groups[index], isPremiumUser: isPremiumUser) else { return .limitReached }
        library.groups[index].tasks.append(task)
    } else {
        guard quickEditCanAddStandaloneTask(isPremiumUser: isPremiumUser, library: library) else { return .limitReached }
        library.tasks.append(task)
    }
    return .moved
}
