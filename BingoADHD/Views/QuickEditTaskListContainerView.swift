import SwiftUI

struct QuickEditTaskListContainerView<Header: View, Rows: View, InlineRow: View, AddButton: View>: View {
    let isAllTasksFilter: Bool
    let hasVisibleItems: Bool
    let hasLockedHistoryPreview: Bool
    let isAddingTaskInline: Bool
    let showsAddTaskButton: Bool
    let isPadLayout: Bool
    let sectionBackground: Color
    @ViewBuilder let header: () -> Header
    @ViewBuilder let rows: () -> Rows
    @ViewBuilder let inlineRow: () -> InlineRow
    @ViewBuilder let addTaskButton: () -> AddButton

    var body: some View {
        VStack(alignment: .leading, spacing: isAllTasksFilter ? 8 : 12) {
            if !isAllTasksFilter {
                header()
            }

            if isAllTasksFilter {
                allTasksHint
            }

            if !hasVisibleItems && !isAddingTaskInline && !hasLockedHistoryPreview {
                emptyState
            }

            VStack(spacing: 10) {
                rows()

                if isAddingTaskInline {
                    inlineRow()
                }
            }

            if showsAddTaskButton {
                addTaskButton()
                    .padding(.top, 8)
            }
        }
        .padding(isPadLayout ? 22 : 18)
        .background(
            RoundedRectangle(cornerRadius: isPadLayout ? 30 : 26, style: .continuous)
                .fill(sectionBackground)
        )
    }

    private var allTasksHint: some View {
        Text(
            L10n.tr(
                "You can view and edit all your task history here.",
                zhHans: "在这里可以查看并编辑你所有的历史任务",
                zhHant: "在這裡可以查看並編輯你所有的歷史任務"
            )
        )
        .font(.appSystem(size: scaled(12, pad: 14), weight: .medium, design: .rounded))
        .foregroundColor(NeumorphicColors.text.opacity(0.55))
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        Text(L10n.quickEditNoTasksInFilter)
            .font(.appSystem(size: scaled(13, pad: 15), weight: .medium, design: .rounded))
            .foregroundColor(NeumorphicColors.text.opacity(0.56))
            .padding(.vertical, 8)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }
}
