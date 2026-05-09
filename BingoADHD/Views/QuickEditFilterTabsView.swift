import SwiftUI

struct QuickEditGroupTab: Identifiable, Equatable {
    let id: UUID
    let title: String
}

struct QuickEditFilterTabsView: View {
    let groups: [QuickEditGroupTab]
    let selectedGroupID: UUID?
    let isPadLayout: Bool
    let fieldStroke: Color
    let onSelectAll: () -> Void
    let onSelectGroup: (UUID) -> Void
    let onLongPressGroup: (UUID) -> Void
    let onAddGroup: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterTabButton(
                        title: L10n.allTasks,
                        isSelected: selectedGroupID == nil,
                        action: onSelectAll
                    )

                    ForEach(groups) { group in
                        filterTabButton(
                            title: group.title,
                            isSelected: selectedGroupID == group.id
                        ) {
                            onSelectGroup(group.id)
                        }
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.8)
                                .onEnded { _ in
                                    onLongPressGroup(group.id)
                                }
                        )
                    }
                }
                .padding(.vertical, 2)
            }

            Button(action: onAddGroup) {
                Text("+ \(L10n.addGroup)")
                    .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                    .foregroundColor(NeumorphicColors.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.clear.neumorphicConvex(radius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    private func filterTabButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appSystem(size: scaled(13, pad: 15), weight: .semibold, design: .rounded))
                .foregroundColor(isSelected ? .white : NeumorphicColors.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? NeumorphicColors.accent : NeumorphicColors.background)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(
                            isSelected ? NeumorphicColors.accent : fieldStroke,
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }
}
