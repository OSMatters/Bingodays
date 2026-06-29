import SwiftUI

struct HomeStickerLayer: View {
    @ObservedObject var pointsFeatureStore: PointsFeatureStore

    @Binding var selectedStickerID: UUID?

    let canvasSize: CGSize

    var body: some View {
        ZStack {
            ForEach(pointsFeatureStore.homeStickerPlacements) { placement in
                EditableHomeStickerView(
                    placement: placement,
                    canvasSize: canvasSize,
                    isEditing: selectedStickerID == placement.id,
                    onSelect: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            selectedStickerID = selectedStickerID == placement.id ? nil : placement.id
                        }
                    },
                    onUpdate: { updatedPlacement in
                        pointsFeatureStore.updateStickerPlacement(updatedPlacement)
                    },
                    onDelete: {
                        pointsFeatureStore.deleteStickerPlacement(id: placement.id)
                        if selectedStickerID == placement.id {
                            selectedStickerID = nil
                        }
                    }
                )
            }
        }
    }
}
