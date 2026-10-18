import SwiftUI

struct HomeTimeoutOverlayLayer: View {
    @ObservedObject var viewModel: BingoViewModel
    let countdownNow: Date
    let selectedBoardName: String
    let isPadLayout: Bool
    @Binding var taskTimeoutDelayMinutes: Int
    @Binding var boardTimeoutDelayMinutes: Int
    @Binding var timeoutDelayPickerContext: TimeoutDelayPickerContext?
    @Binding var timeoutDelayPickerHours: Int
    @Binding var timeoutDelayPickerMinutes: Int
    let onToast: (String) -> Void

    private var isShowingOverlay: Bool {
        viewModel.expiredTaskEvent != nil ||
            viewModel.expiredBoardCountdownEvent != nil ||
            viewModel.scheduledTaskReplacementEvent != nil ||
            timeoutDelayPickerContext != nil
    }

    var body: some View {
        ZStack {
            if let expiredTaskEvent = viewModel.expiredTaskEvent {
                taskTimeoutOverlay(for: expiredTaskEvent)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(30)
            }

            if let expiredBoardEvent = viewModel.expiredBoardCountdownEvent {
                boardTimeoutOverlay(for: expiredBoardEvent)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(30)
            }

            if let scheduledEvent = viewModel.scheduledTaskReplacementEvent {
                scheduledTaskReplacementOverlay(for: scheduledEvent)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(30)
            }

            if timeoutDelayPickerContext != nil {
                timeoutDelayPickerOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(40)
            }
        }
        .allowsHitTesting(isShowingOverlay)
    }

    @ViewBuilder
    private func taskTimeoutOverlay(for event: BingoViewModel.ExpiredTaskEvent) -> some View {
        ZStack {
            TimeoutDialogBackdrop()

            adaptiveScrollableDialog {
                VStack(spacing: 0) {
                    let overtimeSeconds = max(Int(countdownNow.timeIntervalSince(event.expiredAt)), 0)
                    let taskText = event.taskText.isEmpty ? L10n.task : event.taskText

                    TimeoutDialogCard(
                        headline: L10n.taskTimedOutHeadline(task: taskText, seconds: overtimeSeconds),
                        ruleReason: taskTimeoutRuleReason(for: event),
                        boardNameLabel: L10n.timeoutBoardNameLabel(selectedBoardName),
                        isPadLayout: isPadLayout,
                        showsSecondaryAction: event.allowsPostpone,
                        bottomActionTitle: L10n.tr("Remove task", zhHans: "删除任务", zhHant: "刪除任務"),
                        onPrimaryAction: {
                            if let message = viewModel.resolveExpiredTask(.markAsCompleted, now: countdownNow) {
                                onToast(message)
                            }
                        },
                        onSecondaryAction: {
                            openTimeoutDelayPicker(for: .task, presetMinutes: taskTimeoutDelayMinutes)
                        },
                        onBottomAction: {
                            if let message = viewModel.resolveExpiredTask(.abandon, now: countdownNow) {
                                onToast(message)
                            }
                        }
                    )
                }
                .padding(.horizontal, 24)
            }
        }
    }

    @ViewBuilder
    private func boardTimeoutOverlay(for event: BingoViewModel.ExpiredBoardCountdownEvent) -> some View {
        ZStack {
            TimeoutDialogBackdrop()

            adaptiveScrollableDialog {
                VStack(spacing: 0) {
                    let overtimeSeconds = max(Int(countdownNow.timeIntervalSince(event.expiredAt)), 0)

                    TimeoutDialogCard(
                        headline: L10n.boardTimedOutHeadline(seconds: overtimeSeconds),
                        ruleReason: L10n.timeoutRuleReasonBoardCountdown,
                        boardNameLabel: L10n.timeoutBoardNameLabel(selectedBoardName),
                        isPadLayout: isPadLayout,
                        bottomActionTitle: L10n.tr("Cancel countdown", zhHans: "取消倒计时", zhHant: "取消倒計時"),
                        onPrimaryAction: {
                            if let message = viewModel.resolveExpiredBoardCountdown(.markAsCompleted, now: countdownNow) {
                                onToast(message)
                            }
                        },
                        onSecondaryAction: {
                            openTimeoutDelayPicker(for: .board, presetMinutes: boardTimeoutDelayMinutes)
                        },
                        onBottomAction: {
                            if let message = viewModel.resolveExpiredBoardCountdown(.abandon, now: countdownNow) {
                                onToast(message)
                            }
                        }
                    )
                }
                .padding(.horizontal, 24)
            }
        }
    }

    @ViewBuilder
    private func scheduledTaskReplacementOverlay(for event: BingoViewModel.ScheduledTaskReplacementEvent) -> some View {
        ZStack {
            TimeoutDialogBackdrop()

            adaptiveScrollableDialog {
                VStack(spacing: 20) {
                    ScheduledTaskReplacementDialogCard(
                        currentTaskText: event.currentTaskText,
                        presetTaskText: event.presetTaskText,
                        isPadLayout: isPadLayout,
                        onClose: {
                            viewModel.dismissScheduledTaskReplacementPrompt()
                        },
                        onReplace: {
                            if let message = viewModel.resolveScheduledTaskReplacement(.replaceWithPreset, now: countdownNow) {
                                onToast(message)
                            }
                        },
                        onKeepCurrent: {
                            if let message = viewModel.resolveScheduledTaskReplacement(.keepCurrentTask, now: countdownNow) {
                                onToast(message)
                            }
                        }
                    )
                }
                .padding(.horizontal, 24)
            }
        }
    }

    @ViewBuilder
    private var timeoutDelayPickerOverlay: some View {
        if timeoutDelayPickerContext != nil {
            TimeoutDelayPickerOverlay(
                hours: $timeoutDelayPickerHours,
                minutes: $timeoutDelayPickerMinutes,
                isPadLayout: isPadLayout,
                onDismiss: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        timeoutDelayPickerContext = nil
                    }
                },
                onApply: applyTimeoutDelayPickerSelection
            )
        }
    }

    @ViewBuilder
    private func adaptiveScrollableDialog<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        let dialogContent = content()
        GeometryReader { proxy in
            ViewThatFits(in: .vertical) {
                dialogContent
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView {
                    dialogContent
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxHeight: max(0, proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom - 32))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func openTimeoutDelayPicker(for context: TimeoutDelayPickerContext, presetMinutes: Int) {
        let components = TimeoutDelayPickerStore.pickerComponents(
            from: presetMinutes,
            maxMinutes: BingoViewModel.maxCountdownMinutes
        )
        timeoutDelayPickerHours = components.hours
        timeoutDelayPickerMinutes = components.minutes
        timeoutDelayPickerContext = context
    }

    private func applyTimeoutDelayPickerSelection() {
        guard let context = timeoutDelayPickerContext else { return }
        let selectedMinutes = TimeoutDelayPickerStore.totalMinutes(
            hours: timeoutDelayPickerHours,
            minutes: timeoutDelayPickerMinutes,
            maxMinutes: BingoViewModel.maxCountdownMinutes
        )
        timeoutDelayPickerContext = nil
        let applyNow = Date()

        switch context {
        case .task:
            taskTimeoutDelayMinutes = selectedMinutes
            if let message = viewModel.resolveExpiredTask(.postpone(minutes: selectedMinutes), now: applyNow) {
                onToast(message)
            } else {
                onToast(L10n.tr("Postpone failed. Please try again.", zhHans: "延期失败，请重试", zhHant: "延期失敗，請重試"))
            }
        case .board:
            boardTimeoutDelayMinutes = selectedMinutes
            if let message = viewModel.resolveExpiredBoardCountdown(.postpone(minutes: selectedMinutes), now: applyNow) {
                onToast(message)
            } else {
                onToast(L10n.tr("Postpone failed. Please try again.", zhHans: "延期失败，请重试", zhHant: "延期失敗，請重試"))
            }
        }
    }

    private func taskTimeoutRuleReason(for event: BingoViewModel.ExpiredTaskEvent) -> String {
        switch (event.expiredByCountdown, event.expiredByVisibilityWindow) {
        case (true, true):
            return L10n.timeoutRuleReasonTaskCountdownAndEndTime
        case (true, false):
            return L10n.timeoutRuleReasonTaskCountdown
        case (false, true):
            return L10n.timeoutRuleReasonTaskEndTime
        case (false, false):
            return L10n.timeoutRuleReasonTask
        }
    }

}
