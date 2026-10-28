import SwiftUI

@main
struct BingodaysMacApp: App {
    @StateObject private var workspace = MacWorkspaceStore()
    var body: some Scene {
        Window("Bingodays", id: "main") {
            MacWorkspaceView(workspace: workspace)
                .frame(minWidth: 740, minHeight: 560)
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button("新建棋盘") { workspace.createBoard() }.keyboardShortcut("n")
                Button("添加任务") { workspace.editFirstEmptyCell() }.keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
        Settings { MacSettingsView().frame(width: 460, height: 330) }
    }
}
