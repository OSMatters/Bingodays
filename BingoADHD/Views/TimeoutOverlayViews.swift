import SwiftUI

struct TimeoutDialogBackdrop: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .blur(radius: 14)
            Color.black.opacity(0.62)
        }
        .ignoresSafeArea()
    }
}

struct TimeoutDialogCard: View {
    let headline: String
    let ruleReason: String?
    let boardNameLabel: String?
    let isPadLayout: Bool
    let showsSecondaryAction: Bool
    let bottomActionTitle: String?
    let onPrimaryAction: () -> Void
    let onSecondaryAction: () -> Void
    let onBottomAction: (() -> Void)?

    init(
        headline: String,
        ruleReason: String? = nil,
        boardNameLabel: String?,
        isPadLayout: Bool,
        showsSecondaryAction: Bool = true,
        bottomActionTitle: String? = nil,
        onPrimaryAction: @escaping () -> Void,
        onSecondaryAction: @escaping () -> Void,
        onBottomAction: (() -> Void)? = nil
    ) {
        self.headline = headline
        self.ruleReason = ruleReason
        self.boardNameLabel = boardNameLabel
        self.isPadLayout = isPadLayout
        self.showsSecondaryAction = showsSecondaryAction
        self.bottomActionTitle = bottomActionTitle
        self.onPrimaryAction = onPrimaryAction
        self.onSecondaryAction = onSecondaryAction
        self.onBottomAction = onBottomAction
    }

    var body: some View {
        VStack(spacing: 0) {
            Image("ClockTimeout")
                .resizable()
                .scaledToFit()
                .frame(width: scaled(300, pad: 344), height: scaled(170, pad: 190))
                .padding(.top, -8)

            Text(headline)
                .font(.appSystem(size: scaled(20, pad: 24), weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.20, green: 0.14, blue: 0.09))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .minimumScaleFactor(0.75)
                .padding(.top, 18)
                .padding(.horizontal, 14)

            if let ruleReason, !ruleReason.isEmpty {
                Text(ruleReason)
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                    .foregroundColor(Color(red: 0.20, green: 0.14, blue: 0.09).opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .padding(.top, 10)
                    .padding(.horizontal, 18)
            }

            if let boardNameLabel, !boardNameLabel.isEmpty {
                Text(boardNameLabel)
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .padding(.top, 10)
                    .padding(.horizontal, 18)
            }

            Button(action: onPrimaryAction) {
                Text(L10n.markAsCompleted)
                    .font(.appSystem(size: scaled(18, pad: 21), weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: scaled(56, pad: 62))
                    .background(
                        Capsule(style: .continuous)
                            .fill(NeumorphicColors.accent)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 36)

            if showsSecondaryAction {
                Button(action: onSecondaryAction) {
                    Text(L10n.tr("Task postpone", zhHans: "任务延期", zhHant: "任務延期"))
                        .font(.appSystem(size: scaled(18, pad: 21), weight: .semibold, design: .rounded))
                        .foregroundColor(Color(red: 0.20, green: 0.14, blue: 0.09))
                        .padding(.vertical, 26)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }

            if let bottomActionTitle, let onBottomAction {
                Button(action: onBottomAction) {
                    Text(bottomActionTitle)
                        .font(.appSystem(size: scaled(17, pad: 20), weight: .semibold, design: .rounded))
                        .foregroundColor(Color.black.opacity(0.46))
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.top, showsSecondaryAction ? -4 : 14)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .frame(maxWidth: isPadLayout ? 460 : 420)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.96, green: 0.95, blue: 0.94))
        )
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.26) : base
    }
}

struct ScheduledTaskReplacementDialogCard: View {
    let currentTaskText: String
    let presetTaskText: String
    let isPadLayout: Bool
    let onClose: () -> Void
    let onReplace: () -> Void
    let onKeepCurrent: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.appSystem(size: scaled(18, pad: 20), weight: .semibold))
                        .foregroundColor(Color.black.opacity(0.82))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            Image("ClockTimeout")
                .resizable()
                .scaledToFit()
                .frame(width: scaled(264, pad: 296), height: scaled(142, pad: 160))
                .padding(.top, -6)

            Text(headline)
                .font(.appSystem(size: scaled(20, pad: 24), weight: .bold, design: .rounded))
                .foregroundColor(Color(red: 0.20, green: 0.14, blue: 0.09))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .minimumScaleFactor(0.75)
                .padding(.top, 8)
                .padding(.horizontal, 14)

            Text(detail)
                .font(.appSystem(size: scaled(15, pad: 17), weight: .medium, design: .rounded))
                .foregroundColor(Color.black.opacity(0.62))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 10)
                .padding(.horizontal, 14)

            Button(action: onReplace) {
                Text(L10n.tr("Replace task", zhHans: "替换任务", zhHant: "替換任務"))
                    .font(.appSystem(size: scaled(18, pad: 21), weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: scaled(56, pad: 62))
                    .background(
                        Capsule(style: .continuous)
                            .fill(NeumorphicColors.accent)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 32)

            Button(action: onKeepCurrent) {
                Text(L10n.tr("Keep current", zhHans: "保留当前", zhHant: "保留目前"))
                    .font(.appSystem(size: scaled(18, pad: 21), weight: .semibold, design: .rounded))
                    .foregroundColor(Color(red: 0.20, green: 0.14, blue: 0.09))
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: isPadLayout ? 460 : 420)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.96, green: 0.95, blue: 0.94))
        )
    }

    private var headline: String {
        L10n.tr(
            "A preset task is ready. Replace the current task in this tile?",
            zhHans: "预设任务已到时间，是否替换当前格子任务？",
            zhHant: "預設任務已到時間，是否替換目前格子任務？"
        )
    }

    private var detail: String {
        L10n.tr(
            "Current: \(currentTaskText)\nPreset: \(presetTaskText)",
            zhHans: "当前：\(currentTaskText)\n预设：\(presetTaskText)",
            zhHant: "目前：\(currentTaskText)\n預設：\(presetTaskText)"
        )
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.26) : base
    }
}

struct TimeoutDelayPickerOverlay: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    let isPadLayout: Bool
    let onDismiss: () -> Void
    let onApply: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            TimeoutDialogBackdrop()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: onApply) {
                        Text(L10n.tr("Apply", zhHans: "应用", zhHant: "套用"))
                            .font(.appSystem(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(NeumorphicColors.accent)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                HStack(spacing: 10) {
                    timeoutPickerColumn(
                        title: L10n.hours,
                        selection: $hours,
                        values: Array(0...24),
                        formatter: { L10n.hourValue($0) }
                    )

                    timeoutPickerColumn(
                        title: L10n.minutes,
                        selection: $minutes,
                        values: Array(1...60),
                        formatter: { L10n.minuteValue($0) }
                    )
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
            }
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 0.96, green: 0.95, blue: 0.94))
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 0)
        }
    }

    private func timeoutPickerColumn(
        title: String,
        selection: Binding<Int>,
        values: [Int],
        formatter: @escaping (Int) -> String
    ) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                .foregroundColor(Color.black.opacity(0.66))

            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text(formatter(value))
                        .foregroundColor(.black)
                        .tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.wheel)
            .frame(height: 90)
            .clipped()
            .tint(Color(red: 0.20, green: 0.14, blue: 0.09))
        }
        .frame(maxWidth: .infinity)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.26) : base
    }
}
