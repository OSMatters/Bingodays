import SwiftUI

struct BingoBoardLiveActivityContent: View {
    let boardID: UUID
    let snapshot: BingoBoardActivitySnapshot

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 20) {
                BingoBoardLiveActivityGrid(boardID: boardID, snapshot: snapshot)
                    .frame(width: min(140, (geometry.size.width - 48) * 0.55), height: 140)
                BingoBoardLiveActivityProgress(snapshot: snapshot)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 160)
    }
}
