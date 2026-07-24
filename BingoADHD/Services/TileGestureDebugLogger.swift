import Foundation

enum TileGestureDebugLogger {
    struct OverlayState {
        var isSidebarPresented = false
        var isEditActionsExpanded = false
        var hasFirstStepGuideOverlay = false
        var isUpdatePromptPresented = false
        var hasBoardActionSheet = false
        var hasExpiredTaskEvent = false
        var hasExpiredBoardCountdownEvent = false
        var hasScheduledTaskReplacementEvent = false
        var hasTimeoutDelayPicker = false
        var isBoardRulesPresented = false
        var isBoardCountdownPresented = false
        var isGridSizeSheetPresented = false

        var blockers: [String] {
            [
                isSidebarPresented ? "sidebar" : nil,
                isEditActionsExpanded ? "quick_edit_overlay" : nil,
                hasFirstStepGuideOverlay ? "starter_guide" : nil,
                isUpdatePromptPresented ? "update_prompt" : nil,
                hasBoardActionSheet ? "board_action_sheet" : nil,
                hasExpiredTaskEvent ? "task_timeout" : nil,
                hasExpiredBoardCountdownEvent ? "board_timeout" : nil,
                hasScheduledTaskReplacementEvent ? "scheduled_replace" : nil,
                hasTimeoutDelayPicker ? "timeout_delay_picker" : nil,
                isBoardRulesPresented ? "board_rules_sheet" : nil,
                isBoardCountdownPresented ? "board_countdown_sheet" : nil,
                isGridSizeSheetPresented ? "grid_size_sheet" : nil
            ].compactMap { $0 }
        }
    }

    static func logOverlayBlockers(source: String, state: OverlayState) {
        let blockers = state.blockers
        if !blockers.isEmpty {
            DiagnosticLogStore.recordWarning(
                "tile_gesture.overlay_blockers",
                details: [
                    "source": source,
                    "blockers": blockers.joined(separator: ",")
                ]
            )
        }
#if DEBUG
        guard AppDebugFlags.tileGestureDebugEnabled else { return }
        let summary = blockers.isEmpty ? "none" : blockers.joined(separator: ",")
        print("[TileGestureDebug][Overlay][\(source)] \(summary)")
#else
        _ = source
        _ = state
#endif
    }
}
