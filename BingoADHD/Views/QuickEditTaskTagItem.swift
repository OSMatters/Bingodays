import Foundation

/// Presentation data only: no library locations, persistence, or subscription state.
struct QuickEditTaskTagItem: Identifiable {
    let id: String
    let title: String
    let isSelected: Bool
    let isLocked: Bool
    let canEdit: Bool
    let canMove: Bool
}
