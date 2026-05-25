import Foundation

enum FirstStepGuideState: Int {
    case notStarted = 0
    case tracking = 1
    case finished = 2
}

enum FirstStepGuideStore {
    static let minimumGridSize = 3

    struct SeedTaskPlacement {
        let row: Int
        let col: Int
        let text: String
    }

    struct StorageState {
        let state: FirstStepGuideState
        let milestoneShown: Int
        let overlay: FirstStepGuideOverlay?
    }

    struct OverlayPresentation {
        struct PreviewCell: Identifiable {
            let id: String
            let text: String
        }

        struct Milestone {
            let imageName: String
            let message: String
        }

        let seedTasks: [String]
        let previewRows: [[PreviewCell]]
        let introTitle: String
        let introDescription: String

        func milestone(for overlay: FirstStepGuideOverlay) -> Milestone? {
            guard let imageName = FirstStepGuideStore.milestoneImageName(for: overlay) else {
                return nil
            }

            return Milestone(
                imageName: imageName,
                message: FirstStepGuideStore.milestoneMessage(for: overlay)
            )
        }
    }

    static var seedTasks: [String] {
        [
            L10n.tr("Drink a glass of water", zhHans: "喝一杯水", zhHant: "喝一杯水"),
            L10n.tr("Stand for 1 minute", zhHans: "站立1分钟", zhHant: "站立1分鐘"),
            L10n.tr("Stretch your body", zhHans: "拉伸身体", zhHant: "拉伸身體")
        ]
    }

    static var seedTaskKeys: [String] {
        seedTasks.map(normalizedTaskText)
    }

    static var seedTaskPlacements: [SeedTaskPlacement] {
        seedTaskKeys.enumerated().map { index, task in
            SeedTaskPlacement(row: 0, col: index, text: task)
        }
    }

    static var overlayPresentation: OverlayPresentation {
        OverlayPresentation(
            seedTasks: seedTasks,
            previewRows: previewRows,
            introTitle: introTitle,
            introDescription: introDescription
        )
    }

    static var previewRows: [[OverlayPresentation.PreviewCell]] {
        let placedTasks = Dictionary(
            uniqueKeysWithValues: seedTaskPlacements.map { placement in
                ("\(placement.row)-\(placement.col)", placement.text)
            }
        )

        return (0..<minimumGridSize).map { row in
            (0..<minimumGridSize).map { col in
                let id = "\(row)-\(col)"
                return OverlayPresentation.PreviewCell(id: id, text: placedTasks[id] ?? "")
            }
        }
    }

    static func installSeedTasks(in viewModel: BingoViewModel) {
        if viewModel.gridSize < minimumGridSize {
            viewModel.resizeGrid(to: minimumGridSize)
        }

        for placement in seedTaskPlacements {
            viewModel.updateTask(
                row: placement.row,
                col: placement.col,
                text: placement.text,
                isForced: false,
                residentWeekdays: [],
                isOneTimeTask: false
            )
        }
    }

    static var startedState: StorageState {
        StorageState(state: .tracking, milestoneShown: 0, overlay: nil)
    }

    static var skippedState: StorageState {
        StorageState(state: .finished, milestoneShown: 3, overlay: nil)
    }

    static var introTitle: String {
        L10n.tr("Welcome to Bingodays 👋", zhHans: "欢迎来到 Bingodays 👋", zhHant: "歡迎來到 Bingodays 👋")
    }

    static var introDescription: String {
        L10n.tr(
            "Complete these starter tasks to feel the Bingo flow.",
            zhHans: "先完成这几个任务，体验Bingo的乐趣",
            zhHant: "先完成這幾個任務，體驗 Bingo 的樂趣"
        )
    }

    static func normalizedTaskText(_ text: String) -> String {
        String(text.prefix(BingoViewModel.maxTaskLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func milestoneMessage(for overlay: FirstStepGuideOverlay) -> String {
        switch overlay {
        case .intro:
            return ""
        case .milestoneOne:
            return L10n.tr(
                "Nice! First step completed, keep going 💪",
                zhHans: "Nice！第一步已完成，继续冲吧 💪",
                zhHant: "Nice！第一步已完成，繼續衝吧 💪"
            )
        case .milestoneTwo:
            return L10n.tr(
                "One step away from Bingo. Keep it up 🚀",
                zhHans: "离Bingo就差一个了！继续加油 🚀",
                zhHant: "離 Bingo 就差一個了！繼續加油 🚀"
            )
        case .milestoneThree:
            return L10n.tr(
                "Amazing! You unlocked your first Bingo 🎉 Long-press a tile to edit tasks and start your next round!",
                zhHans: "太厉害了！你解锁了第一个Bingo🎉 长按格子编辑任务，开启下一轮挑战吧！",
                zhHant: "太厲害了！你解鎖了第一個 Bingo🎉 長按格子編輯任務，開啟下一輪挑戰吧！"
            )
        }
    }

    static func milestoneImageName(for overlay: FirstStepGuideOverlay) -> String? {
        switch overlay {
        case .intro:
            return nil
        case .milestoneOne:
            return "StarterGuideFirst"
        case .milestoneTwo:
            return "StarterGuideSecond"
        case .milestoneThree:
            return "StarterGuideThird"
        }
    }

    static func completedTaskCount(in cells: [[BingoCell]]) -> Int {
        let allCells = cells.flatMap { $0 }

        return seedTaskKeys.reduce(0) { count, task in
            let hasCompleted = allCells.contains {
                $0.isCompleted &&
                normalizedTaskText($0.storedTaskText) == task
            }
            return count + (hasCompleted ? 1 : 0)
        }
    }

    static func introState(
        state: FirstStepGuideState,
        currentOverlay: FirstStepGuideOverlay?,
        milestoneShown: Int,
        hasTaskPoolTasks: Bool
    ) -> StorageState? {
        guard state == .notStarted else { return nil }
        guard currentOverlay == nil else { return nil }
        guard !hasTaskPoolTasks else { return nil }

        return StorageState(state: state, milestoneShown: milestoneShown, overlay: .intro)
    }

    static func progressState(
        completedCount: Int,
        state: FirstStepGuideState,
        currentOverlay: FirstStepGuideOverlay?,
        milestoneShown: Int
    ) -> StorageState? {
        guard state == .tracking else { return nil }
        guard currentOverlay != .intro else { return nil }

        switch completedCount {
        case 3... where milestoneShown < 3:
            return StorageState(state: state, milestoneShown: 3, overlay: .milestoneThree)
        case 2 where milestoneShown < 2:
            return StorageState(state: state, milestoneShown: 2, overlay: .milestoneTwo)
        case 1 where milestoneShown < 1:
            return StorageState(state: state, milestoneShown: 1, overlay: .milestoneOne)
        default:
            return nil
        }
    }

    static func dismissedState(
        state: FirstStepGuideState,
        milestoneShown: Int,
        overlay: FirstStepGuideOverlay?
    ) -> StorageState {
        StorageState(
            state: overlay == .milestoneThree ? .finished : state,
            milestoneShown: milestoneShown,
            overlay: nil
        )
    }
}
