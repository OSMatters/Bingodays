import SwiftUI

struct QuickEditEditableTaskRow: View {
    let text: Binding<String>
    let placeholder: String
    let isSelected: Bool
    let focusBinding: FocusState<FocusedMyTaskField?>.Binding
    let focusField: FocusedMyTaskField
    let isPadLayout: Bool
    let placeholderColor: Color
    let taskBackground: Color
    let fieldStroke: Color
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.appSystem(size: scaled(18, pad: 20), weight: .bold))
                    .foregroundStyle(isSelected ? NeumorphicColors.modalAccent : NeumorphicColors.text.opacity(0.38))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            TextField(
                text: text,
                prompt: Text(placeholder)
                    .foregroundStyle(placeholderColor)
            ) {
                EmptyView()
            }
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .font(.appSystem(size: scaled(15, pad: 18), weight: .medium, design: .rounded))
            .foregroundStyle(NeumorphicColors.text)
            .lineLimit(1)
            .focused(focusBinding, equals: focusField)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.appSystem(size: scaled(13, pad: 15), weight: .medium))
                    .foregroundStyle(NeumorphicColors.text.opacity(0.52))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(taskBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(fieldStroke, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }
}

struct QuickEditInlineNewTaskRow: View {
    @Binding var draftText: String
    let focusBinding: FocusState<FocusedMyTaskField?>.Binding
    let isPadLayout: Bool
    let placeholderColor: Color
    let taskBackground: Color
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField(
                "",
                text: $draftText,
                prompt: Text(L10n.quickEditTaskNamePlaceholder)
                    .foregroundStyle(placeholderColor)
            )
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .font(.appSystem(size: scaled(15, pad: 18), weight: .medium, design: .rounded))
            .foregroundStyle(NeumorphicColors.text)
            .focused(focusBinding, equals: .newTask)
            .onSubmit(onSubmit)

            Button(L10n.save, action: onSubmit)
                .font(.appSystem(size: scaled(12, pad: 14), weight: .bold, design: .rounded))
                .foregroundStyle(NeumorphicColors.modalAccent)
                .buttonStyle(.plain)
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)

            Button(L10n.cancel, action: onCancel)
                .font(.appSystem(size: scaled(12, pad: 14), weight: .semibold, design: .rounded))
                .foregroundStyle(NeumorphicColors.text.opacity(0.62))
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(taskBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(NeumorphicColors.modalAccent.opacity(0.45), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func scaled(_ base: CGFloat, pad: CGFloat? = nil) -> CGFloat {
        isPadLayout ? (pad ?? base * 1.18) : base
    }
}
