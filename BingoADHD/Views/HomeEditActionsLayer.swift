import SwiftUI

struct HomeEditActionsLayer: View {
    let isEditActionsExpanded: Bool
    let isPadLayout: Bool
    let onDismiss: () -> Void
    let onShuffle: () -> Void
    let onClearBoard: () -> Void
    let onGridSize: () -> Void
    let onQuickEdit: () -> Void

    var body: some View {
        if isEditActionsExpanded {
            EditActionsFullscreenOverlay(
                isPadLayout: isPadLayout,
                onDismiss: onDismiss,
                onShuffle: onShuffle,
                onClearBoard: onClearBoard,
                onGridSize: onGridSize,
                onQuickEdit: onQuickEdit
            )
            .transition(.opacity)
            .zIndex(12)
        }
    }
}

struct HomeGridSizeSheet: View {
    let gridSize: Int
    let isPadLayout: Bool
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        GridSizeAdjustmentSheet(
            gridSize: gridSize,
            isPadLayout: isPadLayout,
            onDecrease: onDecrease,
            onIncrease: onIncrease
        )
    }
}
