import SwiftUI

struct BingoDiaryCorrectionDraft: Identifiable, Equatable {
    let task: String
    let date: Date
    let originalCount: Int

    var id: String {
        "\(task)#\(date.timeIntervalSinceReferenceDate)"
    }
}

struct BingoDiaryCorrectionSheet: View {
    let draft: BingoDiaryCorrectionDraft
    let onSave: (Int) -> Bool

    @State private var correctedCount: Int
    @State private var isSaveErrorPresented = false

    init(draft: BingoDiaryCorrectionDraft, onSave: @escaping (Int) -> Bool) {
        self.draft = draft
        self.onSave = onSave
        _correctedCount = State(initialValue: draft.originalCount)
    }

    var body: some View {
        HStack(spacing: 28) {
            Button(
                L10n.tr("Decrease", zhHans: "减少", zhHant: "減少", ja: "減らす", ko: "줄이기"),
                systemImage: "minus",
                action: decrement
            )
            .labelStyle(.iconOnly)
            .font(.title2.bold())
            .frame(width: 56, height: 56)
            .background(Circle().fill(Color.white.opacity(0.92)))
            .disabled(correctedCount == 0)

            Text("\(correctedCount)")
                .font(.largeTitle.bold().monospacedDigit())
                .foregroundStyle(Color(hex: "121A2B"))
                .frame(minWidth: 72)
                .contentTransition(.numericText())

            Button(
                L10n.tr("Increase", zhHans: "增加", zhHant: "增加", ja: "増やす", ko: "늘리기"),
                systemImage: "plus",
                action: increment
            )
            .labelStyle(.iconOnly)
            .font(.title2.bold())
            .frame(width: 56, height: 56)
            .background(Circle().fill(Color.white.opacity(0.92)))
            .disabled(correctedCount == 999)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .accessibilityElement(children: .contain)
        .alert(
            L10n.tr(
                "Couldn't save the correction",
                zhHans: "无法保存更正",
                zhHant: "無法儲存更正",
                ja: "修正を保存できませんでした",
                ko: "수정 내용을 저장할 수 없습니다"
            ),
            isPresented: $isSaveErrorPresented
        ) {
            Button(L10n.done, role: .cancel) {}
        }
        .presentationDetents([.height(150)])
        .presentationDragIndicator(.visible)
        .presentationBackground(NeumorphicColors.background)
    }

    private func decrement() {
        updateCount(to: max(correctedCount - 1, 0))
    }

    private func increment() {
        updateCount(to: min(correctedCount + 1, 999))
    }

    private func updateCount(to newCount: Int) {
        guard newCount != correctedCount else { return }
        guard onSave(newCount) else {
            isSaveErrorPresented = true
            return
        }

        withAnimation(.snappy(duration: 0.2)) {
            correctedCount = newCount
        }
    }
}
