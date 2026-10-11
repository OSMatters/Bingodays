import SwiftUI

struct BingoDynamicIslandCompletionProgress: View {
    let snapshot: BingoBoardActivitySnapshot

    var body: some View {
        VStack(spacing: 1) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: snapshot.completionProgress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(snapshot.completedTaskCount)")
                    .font(.system(size: 8, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(1)
            .frame(width: 17, height: 17)
            Text("\(snapshot.completedTaskCount)/\(snapshot.taskCount)")
                .font(.system(size: 6, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .frame(width: 28, height: 26)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.tr("Completion progress", zhHans: "完成进度", zhHant: "完成進度", ja: "完了の進捗"))
        .accessibilityValue("\(snapshot.completedTaskCount)/\(snapshot.taskCount)")
    }
}

struct BingoBoardLiveActivityProgress: View {
    let snapshot: BingoBoardActivitySnapshot

    private var countLabel: String {
        L10n.tr("Completed", zhHans: "已完成", zhHant: "已完成", ja: "完了") + " \(snapshot.completedTaskCount)／\(snapshot.taskCount)"
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color(white: 0.45).opacity(0.4), lineWidth: 6)
            Circle()
                .trim(from: 0, to: snapshot.completionProgress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                .rotationEffect(.degrees(-90))
            Text("\(snapshot.completionPercentage)%")
                .font(.appSystem(size: 27, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .padding(10)
        .frame(width: 112, height: 112)
    }

    var body: some View {
        VStack(spacing: 8) {
            ring
            Text(countLabel)
                .font(.appSystem(size: 12, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.tr("Completion progress", zhHans: "完成进度", zhHant: "完成進度", ja: "完了の進捗"))
        .accessibilityValue("\(snapshot.completionPercentage)%, " + countLabel)
    }
}
