import SwiftUI

enum FocusedMyTaskField: Hashable {
    case task(Int)
    case groupTask(UUID, Int)
    case newTask
    case newTaskStartMonth
    case newTaskStartDay
    case newGroupName
    case editGroupName
    case taskEditorName
    case taskEditorMonth
    case taskEditorDay
}

struct QuickEditGroupNameModal: View {
    let title: String
    @Binding var groupName: String
    let focusedField: FocusState<FocusedMyTaskField?>.Binding
    let focusField: FocusedMyTaskField
    let isPadLayout: Bool
    let placeholderColor: Color
    let taskBackground: Color
    let fieldStroke: Color
    let onDismiss: () -> Void
    let onCommit: () -> Void
    @AccessibilityFocusState private var nameFieldAccessibilityFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    Text(title)
                        .font(.appSystem(size: scaled(19, pad: 24), weight: .bold, design: .rounded))
                        .foregroundStyle(NeumorphicColors.text)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 18)
                        .padding(.bottom, 16)

                    VStack(spacing: 16) {
                        TextField(
                            "",
                            text: $groupName,
                            prompt: Text(L10n.quickEditGroupNamePlaceholder)
                                .foregroundStyle(placeholderColor)
                        )
                        .accessibilityLabel(L10n.quickEditGroupNamePlaceholder)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .font(.appSystem(size: scaled(15, pad: 18), weight: .medium, design: .rounded))
                        .foregroundStyle(NeumorphicColors.text)
                        .quickEditModalTextFieldSurface(background: taskBackground, stroke: fieldStroke)
                        .focused(focusedField, equals: focusField)
                        .accessibilityFocused($nameFieldAccessibilityFocused)
                        .onSubmit(onCommit)

                        HStack(spacing: 12) {
                            Button(L10n.cancel, action: onDismiss)
                                .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                                .foregroundStyle(NeumorphicColors.text.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 44)
                                .buttonStyle(.plain)

                            QuickEditModalPrimaryButton(
                                title: L10n.save,
                                isEnabled: !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                isPadLayout: isPadLayout,
                                action: onCommit
                            )
                            .frame(width: scaled(132, pad: 156))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 16)
                }
                .frame(maxWidth: isPadLayout ? 480 : .infinity)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 16,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 16,
                        style: .continuous
                    )
                    .fill(NeumorphicColors.background)
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear {
            nameFieldAccessibilityFocused = true
        }
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }
}

struct QuickEditGroupActionsOverlayView: View {
    let isPadLayout: Bool
    let onDismiss: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private let backgroundColor = Color(hex: "FAF9F3")
    @AccessibilityFocusState private var firstActionAccessibilityFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    actionButton(
                        title: L10n.quickEditEditGroupName,
                        color: NeumorphicColors.text,
                        action: onEdit
                    )
                    .accessibilityFocused($firstActionAccessibilityFocused)
                    actionButton(
                        title: L10n.quickEditDeleteGroup,
                        color: Color.red.opacity(0.84),
                        action: onDelete
                    )
                }
                .frame(width: min(proxy.size.width - 40, isPadLayout ? 460 : 353))
                .padding(.top, 14)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 14) + 12)
                .frame(maxWidth: .infinity)
                .background(
                    backgroundColor
                        .ignoresSafeArea(edges: .bottom)
                        .onTapGesture(perform: onDismiss)
                        .accessibilityHidden(true)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear {
            firstActionAccessibilityFocused = true
        }
    }

    private func actionButton(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appSystem(size: scaled(16, pad: 18), weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(backgroundColor)
                )
        }
        .buttonStyle(.plain)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.26) : base
    }
}

struct QuickEditTaskEditorModal: View {
    let isPresented: Bool
    let isSaveEnabled: Bool
    let taskName: Binding<String>
    let startMonth: Binding<String>
    let startDay: Binding<String>
    let focusedField: FocusState<FocusedMyTaskField?>.Binding
    let isPadLayout: Bool
    let placeholderColor: Color
    let taskBackground: Color
    let fieldStroke: Color
    let onDismiss: () -> Void
    let onClearStartDate: () -> Void
    let onSave: () -> Void
    @AccessibilityFocusState private var taskNameAccessibilityFocused: Bool

    var body: some View {
        if isPresented {
            QuickEditModalShell(maxWidth: 340, onDismiss: onDismiss) {
                VStack(spacing: 14) {
                    Text(L10n.quickEditTaskEditorTitle)
                        .font(.appSystem(size: scaled(19, pad: 24), weight: .bold, design: .rounded))
                        .foregroundStyle(NeumorphicColors.text)
                        .accessibilityAddTraits(.isHeader)

                    TextField(
                        "",
                        text: taskName,
                        prompt: Text(L10n.quickEditTaskNamePlaceholder)
                            .foregroundStyle(placeholderColor)
                    )
                    .accessibilityLabel(L10n.quickEditTaskNamePlaceholder)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .font(.appSystem(size: scaled(15, pad: 18), weight: .medium, design: .rounded))
                    .foregroundStyle(NeumorphicColors.text)
                    .quickEditModalTextFieldSurface(background: taskBackground, stroke: fieldStroke)
                    .focused(focusedField, equals: .taskEditorName)
                    .accessibilityFocused($taskNameAccessibilityFocused)

                    startDateFields

                    HStack(spacing: 12) {
                        QuickEditModalSecondaryButton(title: L10n.cancel, isPadLayout: isPadLayout, action: onDismiss)

                        QuickEditModalPrimaryButton(
                            title: L10n.save,
                            isEnabled: isSaveEnabled,
                            isPadLayout: isPadLayout,
                            action: onSave
                        )
                    }
                }
            }
            .onAppear {
                taskNameAccessibilityFocused = true
            }
        }
    }

    private var startDateFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.quickEditTaskStartDate)
                .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                .foregroundStyle(NeumorphicColors.text.opacity(0.68))

            HStack(spacing: 8) {
                TextField(L10n.quickEditTaskStartMonth, text: startMonth)
                    .keyboardType(.numberPad)
                    .submitLabel(.done)
                    .multilineTextAlignment(.center)
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                    .frame(height: 40)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(taskBackground)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(fieldStroke, lineWidth: 1)
                    }
                    .focused(focusedField, equals: .taskEditorMonth)

                Text("/")
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                    .foregroundStyle(NeumorphicColors.text.opacity(0.6))

                TextField(L10n.quickEditTaskStartDay, text: startDay)
                    .keyboardType(.numberPad)
                    .submitLabel(.done)
                    .multilineTextAlignment(.center)
                    .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
                    .frame(height: 40)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(taskBackground)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(fieldStroke, lineWidth: 1)
                    }
                    .focused(focusedField, equals: .taskEditorDay)
            }

            Button(L10n.quickEditTaskNoStartDate, action: onClearStartDate)
                .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                .foregroundStyle(NeumorphicColors.text.opacity(0.66))
                .buttonStyle(.plain)
        }
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }
}

struct QuickEditToastOverlayView: View {
    let isVisible: Bool
    let message: String?
    let isPadLayout: Bool

    var body: some View {
        if isVisible, let message {
            VStack {
                IOSNativeToastView(
                    message,
                    isPadLayout: isPadLayout
                )
                Spacer()
            }
            .padding(.top, 18)
            .padding(.horizontal, 20)
            .transition(.move(edge: .top).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }
}

private struct QuickEditModalShell<Content: View>: View {
    let maxWidth: CGFloat
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)

            content()
                .padding(20)
                .frame(maxWidth: maxWidth)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(NeumorphicColors.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(NeumorphicColors.lightShadow.opacity(0.42), lineWidth: 1)
                        )
                        .shadow(color: NeumorphicColors.darkShadow.opacity(0.18), radius: 16, x: 0, y: 8)
                        .shadow(color: Color.white.opacity(0.72), radius: 10, x: -4, y: -4)
                )
                .padding(.horizontal, 28)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

private struct QuickEditModalPrimaryButton: View {
    let title: String
    let isEnabled: Bool
    let isPadLayout: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.appSystem(size: scaled(14, pad: 16), weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(NeumorphicColors.modalAccent)
                    .shadow(color: NeumorphicColors.modalAccent.opacity(0.25), radius: 10, x: 0, y: 4)
            )
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.45)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }
}

private struct QuickEditModalSecondaryButton: View {
    let title: String
    let isPadLayout: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.appSystem(size: scaled(14, pad: 16), weight: .semibold, design: .rounded))
            .foregroundStyle(NeumorphicColors.text.opacity(0.78))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.clear.neumorphicConvex(radius: 18))
            .buttonStyle(.plain)
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }
}

private extension View {
    func quickEditModalTextFieldSurface(background: Color, stroke: Color) -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(background)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            }
    }
}
