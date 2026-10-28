import SwiftUI

struct MacWorkspaceView: View {
    @ObservedObject var workspace: MacWorkspaceStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettings.themeKey) private var themeRaw = AppTheme.concise.rawValue
    @AppStorage(AppSettings.homeBackgroundKey) private var skinRaw = HomeBackgroundOption.none.rawValue
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var windowWidth: CGFloat = 1100
    @State private var automaticallyHidSidebar = false
    @State private var showAppearance = false
    @State private var showMobile = false
    @State private var showDesktopGuide = false
    @State private var renameID: UUID?
    @State private var nameDraft = ""
    @State private var deleteID: UUID?
    @State private var confirmReset = false
    @State private var confirmClear = false
    @State private var showCountdown = false
    @State private var countdownMinutes = 25
    private var cloudAvailable: Bool { BingoBoardStore.hasMacEntitlement("com.apple.developer.icloud-container-identifiers", containing: NativeICloudConfiguration.containerIdentifier) }
    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .concise }
    private var skin: HomeBackgroundOption { HomeBackgroundOption(rawValue: skinRaw) ?? .none }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                List {
                    Section("我的棋盘") {
                        ForEach(workspace.boards.namedBoards) { board in
                            Button { workspace.select(board.id) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "square.grid.3x3").foregroundStyle(theme.color)
                                    Text(board.name).lineLimit(1)
                                    Spacer()
                                    if workspace.boards.selectedBoardID == board.id {
                                        Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(theme.color)
                                    }
                                }
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(workspace.boards.selectedBoardID == board.id ? theme.color.opacity(0.14) : Color.clear)
                            .contextMenu {
                                Button("重命名") { renameID = board.id; nameDraft = board.name }
                                Button("删除棋盘", role: .destructive) { deleteID = board.id }
                                    .disabled(workspace.boards.namedBoards.count < 2)
                            }
                        }
                        .onMove { source, destination in
                            var ids = workspace.boards.namedBoards.map(\.id)
                            ids.move(fromOffsets: source, toOffset: destination)
                            if !workspace.boards.reorderBoards(ids) { workspace.errorMessage = "排序保存失败，请重试。" }
                        }
                        Button("新建棋盘", systemImage: "plus") { workspace.createBoard() }.padding(.vertical, 6)
                    }
                }
                Divider()
                Button { showMobile = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "iphone").font(.title2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("在移动端体验更多").font(.callout.weight(.medium))
                            Text("日记 · 奖励 · 贴纸盲盒").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(16).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            .navigationTitle("Bingodays")
            .navigationSplitViewColumnWidth(min: 185, ideal: 215, max: 280)
        } detail: {
            boardDetail
                .frame(minWidth: 360)
                .navigationTitle(workspace.boards.selectedBoardName)
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("桌面棋盘", systemImage: "desktopcomputer") { showDesktopGuide = true }
                        Button("外观", systemImage: "paintpalette") { showAppearance.toggle() }
                            .popover(isPresented: $showAppearance) { MacAppearanceView().frame(width: 380, height: 490) }
                        Toggle(isOn: $workspace.isOrganizing) { Label("整理", systemImage: "square.and.pencil") }
                            .toggleStyle(.button).help("整理棋盘：编辑和拖动任务")
                        Menu {
                            Button("添加任务", systemImage: "plus") { workspace.editFirstEmptyCell() }
                            Menu("棋盘大小") {
                                ForEach(2...5, id: \.self) { size in
                                    Button("\(size) × \(size)") { workspace.editingCellID = nil; workspace.model.resizeGrid(to: size); workspace.persist() }
                                }
                            }
                            Button("棋盘倒计时") { showCountdown = true }
                            Button("打乱排列") { workspace.editingCellID = nil; workspace.model.shuffleBoard(); workspace.persist() }
                            Divider()
                            Button("重置完成状态") { confirmReset = true }
                            Button("清空任务", role: .destructive) { confirmClear = true }
                        } label: { Label("更多", systemImage: "ellipsis.circle") }
                    }
                }
                .inspector(isPresented: Binding(get: { workspace.editingCellID != nil }, set: { if !$0 { workspace.editingCellID = nil } })) {
                    if let coordinate = workspace.editingCoordinate,
                       let cell = workspace.model.editingCell(row: coordinate.row, col: coordinate.col) {
                        MacTaskEditor(workspace: workspace, cell: cell, row: coordinate.row, col: coordinate.col)
                            .id(cell.id)
                            .inspectorColumnWidth(min: 280, ideal: 310, max: 370)
                    }
                }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            windowWidth = width
            if width < 1000 && workspace.editingCellID != nil && columnVisibility != .detailOnly {
                columnVisibility = .detailOnly
                automaticallyHidSidebar = true
            }
        }
        .onChange(of: workspace.editingCellID) { _, id in
            if id != nil && windowWidth < 1000 {
                columnVisibility = .detailOnly
                automaticallyHidSidebar = true
            } else if id == nil && automaticallyHidSidebar {
                columnVisibility = .all
                automaticallyHidSidebar = false
            }
        }
        .onOpenURL { url in
            guard url.scheme == "bingodays-mac", url.host == "board" else { return }
            workspace.refresh()
            if let id = MacDesktopBoardSnapshot.boardID(from: url),
               workspace.boards.namedBoards.contains(where: { $0.id == id }),
               workspace.boards.selectedBoardID != id {
                workspace.select(id)
            }
            openWindow(id: "main")
        }
        .onChange(of: themeRaw) { _, _ in workspace.publishDesktopBoard() }
        .onChange(of: skinRaw) { _, _ in workspace.publishDesktopBoard() }
        .tint(theme.color)
        .sheet(isPresented: $showDesktopGuide) { MacDesktopGuideView() }
        .sheet(isPresented: $showMobile) { MacMobileFeaturesView() }
        .sheet(isPresented: $showCountdown) {
            VStack(alignment: .leading, spacing: 20) {
                Text("棋盘倒计时").font(.title2.bold())
                Stepper("\(countdownMinutes) 分钟", value: $countdownMinutes, in: 1...1440)
                HStack {
                    Button("取消倒计时") { workspace.model.setBoardCountdown(totalMinutes: nil); workspace.persist(); showCountdown = false }
                    Spacer()
                    Button("开始") { workspace.model.setBoardCountdown(totalMinutes: countdownMinutes); workspace.persist(); showCountdown = false }.keyboardShortcut(.defaultAction)
                }
            }.padding(28).frame(width: 390)
        }
        .alert("重命名棋盘", isPresented: Binding(get: { renameID != nil }, set: { if !$0 { renameID = nil } })) {
            TextField("棋盘名称", text: $nameDraft)
            Button("取消", role: .cancel) { renameID = nil }
            Button("保存") {
                if let id = renameID, workspace.boards.renameBoard(id, nameDraft: nameDraft) == .persistenceFailed { workspace.errorMessage = "名称保存失败。" }
                renameID = nil
            }
        }
        .confirmationDialog("删除这个棋盘及其中的任务？", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } }), titleVisibility: .visible) {
            Button("删除棋盘", role: .destructive) { if let id = deleteID { workspace.deleteBoard(id) }; deleteID = nil }
        }
        .confirmationDialog("重置棋盘的完成状态？任务内容会保留。", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("重置完成状态", role: .destructive) { _ = workspace.model.resetBoard(); workspace.persist() }
        }
        .confirmationDialog("清空当前棋盘的所有任务？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空任务", role: .destructive) {
                workspace.editingCellID = nil
                for row in workspace.model.cells.indices {
                    for col in workspace.model.cells[row].indices { workspace.model.clearTask(row: row, col: col) }
                }
                workspace.persist()
            }
        }
        .alert("操作未完成", isPresented: Binding(get: { workspace.errorMessage != nil }, set: { if !$0 { workspace.errorMessage = nil } })) {
            Button("好") { workspace.errorMessage = nil }
        } message: { Text(workspace.errorMessage ?? "") }
        .modifier(MacTaskPromptModifier(workspace: workspace))
        .task {
            if cloudAvailable { NativeICloudSyncCoordinator.shared.startIfEnabled() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                workspace.refresh()
                Task { if cloudAvailable { await NativeICloudSyncCoordinator.shared.refreshWhenAppBecomesActive() } }
            } else { workspace.persist() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nativeICloudRuntimeDidImport)) { _ in workspace.refresh() }
        .task {
            while !Task.isCancelled {
                workspace.tick()
                try? await Task.sleep(for: .seconds(workspace.model.requiresLiveCountdownTicks() ? 1 : 15))
            }
        }
    }

    private var boardDetail: some View {
        GeometryReader { proxy in
            ZStack {
                Color(hex: "FAF7F2")
                if let image = skin.imageName {
                    Image(image).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped()
                }
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            Text(workspace.boards.selectedBoardName)
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                            Text(workspace.isOrganizing ? "点击编辑任务，拖动调整位置" : "把今天的小事，一格一格完成")
                                .font(.callout).opacity(0.65)
                        }.foregroundStyle(skin.isDarkTone ? .white : theme.textColor)
                        MacBoardGrid(workspace: workspace, theme: theme)
                            .frame(width: max(280, min(proxy.size.width - 64, proxy.size.height - 230, 610)))
                        HStack(spacing: 12) {
                            let tasks = workspace.model.cells.flatMap { $0 }.filter { !$0.isEmpty }
                            let count = tasks.filter(\.isCompleted).count
                            Image(systemName: count > 0 && count == tasks.count ? "checkmark.seal.fill" : "circle.dotted")
                            Text("已完成 \(count) / \(tasks.count)")
                            if workspace.model.completedLines.count > 0 {
                                Text("·  \(workspace.model.completedLines.count) 条 Bingo")
                            }
                        }
                        .font(.callout.weight(.medium))
                        .foregroundStyle(skin.isDarkTone ? .white : theme.textColor)
                        if let deadline = workspace.model.boardCountdownEndsAt {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(deadline > context.date ? "剩余 \(Int(deadline.timeIntervalSince(context.date)) / 60) 分钟" : "倒计时已结束")
                                    .font(.caption.monospacedDigit())
                            }
                        }
                    }
                    .padding(.vertical, 36)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
            }
        }
    }
}
