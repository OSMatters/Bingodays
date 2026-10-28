import ActivityKit
import SwiftUI
import WidgetKit

struct BingoBoardLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BingoBoardActivityAttributes.self) { context in
            if let snapshot = context.state.snapshot {
                BingoBoardLiveActivityContent(boardID: context.attributes.boardID, snapshot: snapshot)
                    .environment(\.locale, AppLanguage.displayLocale)
                    .activityBackgroundTint(.clear)
                    .activitySystemActionForegroundColor(Color(hex: "291E0A"))
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    BingoDynamicIslandIcon(size: 32)
                }
            } compactLeading: {
                BingoDynamicIslandIcon()
            } compactTrailing: {
                if let snapshot = context.state.snapshot {
                    BingoDynamicIslandCompletionProgress(snapshot: snapshot)
                }
            } minimal: {
                if let snapshot = context.state.snapshot {
                    BingoDynamicIslandCompletionProgress(snapshot: snapshot)
                }
            }
        }
    }
}

struct BingoBoardLiveActivityGrid: View {
    let boardID: UUID
    let snapshot: BingoBoardActivitySnapshot

    var body: some View {
        GeometryReader { geometry in
            let count = snapshot.gridSize
            let side = min(geometry.size.width, geometry.size.height) - 4
            let scale = side / 320
            let spacing = CGFloat(count <= 3 ? 15 : count == 4 ? 10 : 8) * scale
            let cellSide = (side - spacing * CGFloat(count - 1)) / CGFloat(count)
            let size = CGSize(width: cellSide, height: cellSide)
            VStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<count, id: \.self) { col in
                            let index = row * count + col
                            if snapshot.cells.indices.contains(index) {
                                BingoBoardLiveActivityCell(
                                    boardID: boardID, cell: snapshot.cells[index],
                                    theme: AppTheme(rawValue: snapshot.theme) ?? .concise, size: size, scale: scale
                                )
                            }
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}
