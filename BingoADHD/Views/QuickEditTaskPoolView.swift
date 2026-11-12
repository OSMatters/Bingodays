import SwiftUI

struct QuickEditTaskPoolView: View {
    let items: [QuickEditTaskTagItem]
    let filterID: String
    let onAdd: () -> Void
    let onToggle: (String) -> Void
    let onEdit: (String) -> Void
    let onMove: (String) -> Void
    let onDelete: (String) -> Void
    let onUnlock: () -> Void
    @ScaledMetric(relativeTo: .body) private var rowHeight = 44

    @ScaledMetric(relativeTo: .body) private var fontSize = 16

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                QuickEditThreeRowLayout(spacing: 12, minimumRowHeight: rowHeight) {
                    Button(action: onAdd) {
                        Text("+ \(L10n.addTask)")
                            .font(.appSystem(size: fontSize, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(hex: "D79863"))
                            .padding(.horizontal, 15)
                            .frame(minHeight: rowHeight)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .id("quick-edit-pool-start")

                    ForEach(items) { item in
                        QuickEditTaskTagView(
                            item: item,
                            onToggle: { onToggle(item.id) },
                            onEdit: { onEdit(item.id) },
                            onMove: { onMove(item.id) },
                            onDelete: { onDelete(item.id) },
                            onUnlock: onUnlock
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .onChange(of: filterID) { _, _ in
                proxy.scrollTo("quick-edit-pool-start", anchor: .leading)
            }
        }
    }
}
