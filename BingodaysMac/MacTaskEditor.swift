import SwiftUI

struct MacTaskEditor: View {
    @ObservedObject var workspace: MacWorkspaceStore
    let cell: BingoCell
    let row: Int
    let col: Int
    @State private var text: String
    @State private var isForced: Bool
    @State private var recurrence: TaskRecurrenceRule.Kind
    @State private var weekdays: Set<Int>
    @State private var interval: Int
    @State private var monthDay: Int
    @State private var anchorDate: Date
    @State private var hasStart: Bool
    @State private var hasEnd: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var reminder: Bool
    @State private var reminderOffset: Int
    @State private var estimatedMinutes: Int
    @State private var error: String?
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    init(workspace: MacWorkspaceStore, cell: BingoCell, row: Int, col: Int) {
        self.workspace = workspace; self.cell = cell; self.row = row; self.col = col
        let rule = cell.effectiveRecurrenceRule
        _text = State(initialValue: cell.storedTaskText)
        _isForced = State(initialValue: cell.isForced)
        _recurrence = State(initialValue: rule?.kind ?? .none)
        _weekdays = State(initialValue: rule?.weekdays ?? cell.residentWeekdays)
        _interval = State(initialValue: max(2, rule?.interval ?? 2))
        _monthDay = State(initialValue: rule?.monthDay ?? Calendar.current.component(.day, from: .now))
        _anchorDate = State(initialValue: rule?.anchorDate ?? .now)
        _hasStart = State(initialValue: cell.startVisibleAt != nil)
        _hasEnd = State(initialValue: cell.endVisibleAt != nil)
        _start = State(initialValue: cell.startVisibleAt ?? .now)
        _end = State(initialValue: cell.endVisibleAt ?? .now.addingTimeInterval(3600))
        _reminder = State(initialValue: cell.startReminderEnabled)
        _reminderOffset = State(initialValue: cell.startReminderOffsetMinutes)
        _estimatedMinutes = State(initialValue: cell.estimatedDurationMinutes ?? 0)
    }
    private var isValid: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (!hasStart || !hasEnd || end > start) && (recurrence != .weekly || !weekdays.isEmpty)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(cell.hasStoredTask ? "编辑任务" : "添加任务").font(.headline)
                Spacer()
                Button("关闭", systemImage: "xmark") { workspace.editingCellID = nil }
                    .labelStyle(.iconOnly).buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            Form {
                Section("任务") {
                    TextField("做一件小事…", text: $text, axis: .vertical)
                        .lineLimit(2...4).focused($nameFocused)
                        .onChange(of: text) { _, value in text = String(value.prefix(AppSettings.maxTaskLength)) }
                    Text("\(text.count) / \(AppSettings.maxTaskLength)").font(.caption).foregroundStyle(.secondary)
                    Toggle("强制任务", isOn: $isForced)
                    Stepper(estimatedMinutes == 0 ? "预计时长：未设置" : "预计时长：\(estimatedMinutes) 分钟", value: $estimatedMinutes, in: 0...1440, step: 5).disabled(cell.isCompleted || recurrence != .none)
                }
                Section("重复") {
                    Picker("频率", selection: $recurrence) {
                        Text("不重复").tag(TaskRecurrenceRule.Kind.none)
                        Text("每天").tag(TaskRecurrenceRule.Kind.daily)
                        Text("每周").tag(TaskRecurrenceRule.Kind.weekly)
                        Text("每月").tag(TaskRecurrenceRule.Kind.monthlyDay)
                        Text("每隔几天").tag(TaskRecurrenceRule.Kind.everyNDays)
                    }
                    if recurrence == .weekly {
                        HStack(spacing: 4) {
                            ForEach(1...7, id: \.self) { day in
                                Button(["日", "一", "二", "三", "四", "五", "六"][day - 1]) {
                                    if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                                }.buttonStyle(.bordered).tint(weekdays.contains(day) ? .accentColor : .secondary)
                            }
                        }
                    }
                    if recurrence == .monthlyDay { Stepper("每月 \(monthDay) 日", value: $monthDay, in: 1...31) }
                    if recurrence == .everyNDays {
                        Stepper("每隔 \(interval) 天", value: $interval, in: 2...30)
                        DatePicker("起始日期", selection: $anchorDate, displayedComponents: .date)
                    }
                }
                Section("时间与提醒") {
                    if cell.isCompleted { Text("已完成任务需先取消完成，才能修改时间。").font(.caption).foregroundStyle(.secondary) }
                    Toggle("设置开始时间", isOn: $hasStart).disabled(cell.isCompleted || recurrence != .none)
                    if hasStart { DatePicker("开始", selection: $start).disabled(cell.isCompleted || recurrence != .none) }
                    Toggle("设置结束时间", isOn: $hasEnd).disabled(cell.isCompleted || recurrence != .none)
                    if hasEnd { DatePicker("结束", selection: $end).disabled(cell.isCompleted || recurrence != .none) }
                    if hasStart && hasEnd && recurrence == .none {
                        Toggle("开始前提醒", isOn: $reminder)
                        if reminder {
                            Picker("提前", selection: $reminderOffset) {
                                ForEach([5, 10, 30], id: \.self) { Text("\($0) 分钟").tag($0) }
                            }
                        }
                    }
                    if hasStart && hasEnd && end <= start { Text("结束时间应晚于开始时间").foregroundStyle(.red).font(.caption) }
                }
                if let error { Text(error).foregroundStyle(.red).font(.callout) }
                Section {
                    Button("保存任务", action: save).buttonStyle(.borderedProminent).disabled(!isValid).keyboardShortcut("s")
                    if cell.hasStoredTask { Button("删除任务", role: .destructive) { confirmDelete = true } }
                }
            }.formStyle(.grouped)
        }
        .task { nameFocused = true }
        .confirmationDialog("删除这个任务？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除任务", role: .destructive) {
                workspace.model.clearTask(row: row, col: col)
                workspace.persist()
                workspace.editingCellID = nil
            }
        }
    }
    private func save() {
        guard workspace.model.cells[row][col].id == cell.id else { error = "任务已发生变化，请重新打开编辑。"; return }
        // Keep legacy unspecified recurrence unchanged when editing only its text.
        let preserveLegacyRule = cell.hasStoredTask && cell.effectiveRecurrenceRule == nil && recurrence == .none && !hasStart && !hasEnd
        let rule: TaskRecurrenceRule? = preserveLegacyRule ? nil : TaskRecurrenceRule(
            kind: recurrence, interval: recurrence == .everyNDays ? interval : 1,
            weekdays: recurrence == .weekly ? weekdays : [],
            monthDay: recurrence == .monthlyDay ? monthDay : nil,
            anchorDate: anchorDate
        )
        let saved = workspace.model.updateTask(
            row: row, col: col, text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            isForced: isForced, residentWeekdays: recurrence == .weekly ? weekdays : [],
            isOneTimeTask: recurrence == .none && (hasStart || hasEnd || cell.isOneTimeTask),
            recurrenceRule: rule, estimatedDurationMinutes: estimatedMinutes > 0 ? estimatedMinutes : nil,
            startVisibleAt: hasStart ? start : nil, endVisibleAt: hasEnd ? end : nil,
            startReminderEnabled: reminder, startReminderOffsetMinutes: reminderOffset, editSource: "mac_editor"
        )
        guard saved else { error = "任务未能保存，请重试。"; return }
        workspace.persist()
        workspace.editingCellID = nil
        Task { await MacReminderService.sync(boards: workspace.boards.namedBoards) }
    }
}
