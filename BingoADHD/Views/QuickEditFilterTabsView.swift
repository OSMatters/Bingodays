import SwiftUI

struct QuickEditGroupTab: Identifiable, Equatable {
    let id: UUID
    let title: String
}

struct QuickEditFilterTabsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum ScrollTarget: Hashable {
        case allTasks
        case group(UUID)
    }

    let groups: [QuickEditGroupTab]
    let selectedGroupID: UUID?
    let isPadLayout: Bool
    let onSelectAll: () -> Void
    let onSelectGroup: (UUID) -> Void
    let onLongPressGroup: (UUID) -> Void
    let onAddGroup: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterTabButton(
                            title: L10n.allTasks,
                            isSelected: selectedGroupID == nil,
                            action: onSelectAll
                        )
                        .id(ScrollTarget.allTasks)

                        ForEach(groups) { group in
                            filterTabButton(
                                title: group.title,
                                isSelected: selectedGroupID == group.id
                            ) {
                                onSelectGroup(group.id)
                            }
                            .id(ScrollTarget.group(group.id))
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
                .onAppear {
                    positionSelectedFilter(using: proxy, animated: false)
                }
                .onChange(of: selectedGroupID) { _, _ in
                    positionSelectedFilter(using: proxy, animated: true)
                }
                .onChange(of: groups) { _, _ in
                    positionSelectedFilter(using: proxy, animated: false)
                }
            }

            Button(L10n.addGroup, systemImage: "plus.circle", action: onAddGroup)
                .labelStyle(.iconOnly)
                .font(.appSystem(size: scaled(24, pad: 28), weight: .light))
                .foregroundStyle(Color(hex: "D79863"))
                .frame(width: 44, height: 44)
                .background(Color(hex: "F4F4F4"))
                .buttonStyle(.plain)
        }
    }

    private func filterTabButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appSystem(size: scaled(15, pad: 17), weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? Color(hex: "D79863") : NeumorphicColors.text)
                .underline(isSelected)
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func positionSelectedFilter(using proxy: ScrollViewProxy, animated: Bool) {
        let target: ScrollTarget
        let anchor: UnitPoint

        guard let selectedGroupID,
              let selectedIndex = groups.firstIndex(where: { $0.id == selectedGroupID }) else {
            target = .allTasks
            anchor = .leading
            scroll(to: target, anchor: anchor, using: proxy, animated: animated)
            return
        }

        target = .group(selectedGroupID)
        if selectedIndex == groups.index(before: groups.endIndex) {
            anchor = .trailing
        } else {
            anchor = .center
        }
        scroll(to: target, anchor: anchor, using: proxy, animated: animated)
    }

    private func scroll(
        to target: ScrollTarget,
        anchor: UnitPoint,
        using proxy: ScrollViewProxy,
        animated: Bool
    ) {
        DispatchQueue.main.async {
            if animated && !reduceMotion {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    proxy.scrollTo(target, anchor: anchor)
                }
            } else {
                proxy.scrollTo(target, anchor: anchor)
            }
        }
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }

}
