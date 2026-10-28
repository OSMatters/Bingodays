import SwiftUI

struct MacTaskPromptModifier: ViewModifier {
    @ObservedObject var workspace: MacWorkspaceStore
    func body(content: Content) -> some View {
        content
            .alert("任务已到期", isPresented: Binding(get: { workspace.model.expiredTaskEvent != nil }, set: { _ in })) {
                Button("已完成") { _ = workspace.model.resolveExpiredTask(.markAsCompleted); workspace.persist() }
                if workspace.model.expiredTaskEvent?.allowsPostpone == true {
                    Button("延长 15 分钟") { _ = workspace.model.resolveExpiredTask(.postpone(minutes: 15)); workspace.persist() }
                }
                Button("放弃任务", role: .destructive) { _ = workspace.model.resolveExpiredTask(.abandon); workspace.persist() }
            } message: { Text(workspace.model.expiredTaskEvent?.taskText ?? "") }
            .alert("棋盘倒计时已结束", isPresented: Binding(get: { workspace.model.expiredBoardCountdownEvent != nil && workspace.model.expiredTaskEvent == nil }, set: { _ in })) {
                Button("全部完成") { _ = workspace.model.resolveExpiredBoardCountdown(.markAsCompleted); workspace.persist() }
                Button("延长 15 分钟") { _ = workspace.model.resolveExpiredBoardCountdown(.postpone(minutes: 15)); workspace.persist() }
                Button("结束倒计时", role: .destructive) { _ = workspace.model.resolveExpiredBoardCountdown(.abandon); workspace.persist() }
            }
            .alert("重复任务已到新周期", isPresented: Binding(get: { workspace.model.scheduledTaskReplacementEvent != nil && workspace.model.expiredTaskEvent == nil && workspace.model.expiredBoardCountdownEvent == nil }, set: { _ in })) {
                Button("使用预设任务") { _ = workspace.model.resolveScheduledTaskReplacement(.replaceWithPreset); workspace.persist() }
                Button("保留当前任务") { _ = workspace.model.resolveScheduledTaskReplacement(.keepCurrentTask); workspace.persist() }
            } message: { Text(workspace.model.scheduledTaskReplacementEvent?.presetTaskText ?? "") }
    }
}
