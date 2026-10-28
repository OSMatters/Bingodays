import SwiftUI

struct MacTaskDragModifier: ViewModifier {
    let enabled: Bool
    let cellID: UUID
    func body(content: Content) -> some View {
        if enabled { content.draggable(cellID.uuidString) }
        else { content }
    }
}
