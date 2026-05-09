import SwiftUI
import UniformTypeIdentifiers

struct QuickEditPreviewDropDelegate: DropDelegate {
    let targetSlotID: UUID
    @Binding var previewSlots: [QuickEditView.PreviewSlot]
    @Binding var dragSourceID: UUID?
    @Binding var dropTargetID: UUID?

    func dropEntered(info: DropInfo) {
        guard dragSourceID != nil else { return }
        dropTargetID = targetSlotID
    }

    func dropExited(info: DropInfo) {
        if dropTargetID == targetSlotID {
            dropTargetID = nil
        }

        let sourceAtExit = dragSourceID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            guard dropTargetID == nil, dragSourceID == sourceAtExit else { return }
            dragSourceID = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [UTType.text.identifier, UTType.plainText.identifier])
        if let provider = providers.first {
            provider.loadObject(ofClass: NSString.self) { object, _ in
                let rawID = (object as? NSString).map(String.init)
                guard let rawID, let sourceID = UUID(uuidString: rawID) else {
                    DispatchQueue.main.async {
                        dropTargetID = nil
                        dragSourceID = nil
                    }
                    return
                }

                DispatchQueue.main.async {
                    swapSlotsIfNeeded(sourceID: sourceID)
                    dropTargetID = nil
                    dragSourceID = nil
                }
            }
            return true
        }

        if let sourceID = dragSourceID {
            swapSlotsIfNeeded(sourceID: sourceID)
        }

        dropTargetID = nil
        dragSourceID = nil
        return true
    }

    private func swapSlotsIfNeeded(sourceID: UUID) {
        guard sourceID != targetSlotID,
              let sourceIndex = previewSlots.firstIndex(where: { $0.id == sourceID }),
              let destinationIndex = previewSlots.firstIndex(where: { $0.id == targetSlotID }) else {
            return
        }

        let sourceCellState = previewSlots[sourceIndex].cellState
        let sourceKey = previewSlots[sourceIndex].sourceTaskKey
        previewSlots[sourceIndex].cellState = previewSlots[destinationIndex].cellState
        previewSlots[sourceIndex].sourceTaskKey = previewSlots[destinationIndex].sourceTaskKey
        previewSlots[destinationIndex].cellState = sourceCellState
        previewSlots[destinationIndex].sourceTaskKey = sourceKey
    }
}
