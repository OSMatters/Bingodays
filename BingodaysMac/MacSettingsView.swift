import SwiftUI

struct MacSettingsView: View {
    @ObservedObject private var coordinator = NativeICloudSyncCoordinator.shared
    @AppStorage(AppSettings.soundEffectsEnabledKey) private var sound = true
    @AppStorage("mac_task_reminders_enabled") private var reminders = false
    @State private var changing = false
    @State private var showMobile = false
    private var cloudAvailable: Bool { BingoBoardStore.hasMacEntitlement("com.apple.developer.icloud-container-identifiers", containing: NativeICloudConfiguration.containerIdentifier) }
    var body: some View {
        Form {
            Section("iCloud") {
                Toggle("与移动端同步", isOn: Binding(get: { NativeICloudPreferences.isEnabled }, set: { enabled in
                    changing = true
                    Task { await coordinator.setEnabled(enabled); changing = false }
                })).disabled(changing || !cloudAvailable)
                if !cloudAvailable { Text("此开发构建尚未配置 iCloud 签名权限，任务保存在本机。").font(.caption).foregroundStyle(.secondary) }
                Text(status).font(.caption).foregroundStyle(.secondary)
                Button("立即同步") { Task { await coordinator.syncNow() } }.disabled(changing || !cloudAvailable || !NativeICloudPreferences.isEnabled)
                if coordinator.pendingAccountChange != nil {
                    Text("iCloud 账号已变化，请选择如何处理本机数据。")
                    Button("保留本机数据，关闭同步") { resolve(.keepLocalOnly) }
                    Button("使用当前账号的云端数据") { resolve(.useCurrentAccountCloud) }
                    Button("将本机数据复制到空云端") { resolve(.copyLocalDataToEmptyCurrentAccount) }
                }
            }
            Section("任务反馈") {
                Toggle("完成任务时播放音效", isOn: $sound)
                Toggle("允许任务开始提醒", isOn: $reminders)
                    .onChange(of: reminders) { _, _ in Task { await MacReminderService.sync(boards: BingoBoardStore.loadNamedBoardsSnapshot().boards) } }
            }
            Section {
                Button("在移动端体验更多") { showMobile = true }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showMobile) { MacMobileFeaturesView() }
    }
    private func resolve(_ resolution: NativeICloudSyncCoordinator.AccountChangeResolution) {
        Task { await coordinator.resolveAccountChange(resolution) }
    }
    private var status: String {
        switch coordinator.state {
        case .disabled: "同步已关闭，任务保存在本机。"
        case .preparing: "正在准备 iCloud…"
        case .syncing: "正在同步…"
        case .waitingForCloud: "等待 iCloud 更新。"
        case .ready: "已连接 iCloud。"
        case .accountChangeRequiresDecision: "需要确认 iCloud 账号变化。"
        case .unavailable(let message), .failed(let message): message
        }
    }
}
