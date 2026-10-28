import SwiftUI

struct MacDesktopGuideView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label("把棋盘贴到桌面", systemImage: "desktopcomputer").font(.title2.bold())
            Text("桌面只展示棋盘。点击棋盘时，再打开任务与编辑窗口。")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 16) {
                Label("在桌面空白处点右键，选择「编辑小组件」。", systemImage: "1.circle")
                Label("搜索 Bingodays，添加「桌面棋盘」。", systemImage: "2.circle")
                Label("选择小号或大号，拖到喜欢的位置。", systemImage: "3.circle")
            }
            Text("桌面棋盘跟随当前选中的棋盘、主题和皮肤。添加后即可关闭操作窗口，小组件会继续留在桌面。")
                .font(.callout).foregroundStyle(.secondary)
            HStack { Spacer(); Button("知道了") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(30).frame(width: 470)
    }
}
