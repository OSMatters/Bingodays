import SwiftUI
import Foundation

struct BingoDiaryBubbleCloud: View {
    let bubbles: [BingoDiaryBubble]
    let canvasWidth: CGFloat
    let canvasHeight: CGFloat
    let isInteractionPaused: Bool
    let isActive: Bool
    var onBubbleTap: ((BingoDiaryBubble) -> Void)? = nil
    @StateObject private var simulator = BingoDiaryBubbleDynamicsSimulator()
    @StateObject private var gravityMonitor = BingoDiaryGravityMonitor()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(bubbles) { bubble in
                BingoDiaryBubbleCloudItem(
                    bubble: bubble,
                    motionState: simulator.motionState(for: bubble.id),
                    onTap: { onBubbleTap?(bubble) }
                )
            }
        }
        .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
        .onAppear {
            isVisible = true
            configureMotion()
        }
        .onDisappear {
            isVisible = false
            simulator.stop()
            gravityMonitor.stop()
        }
        .onChange(of: bubblesSignature) {
            simulator.updateBubbles(
                bubbles,
                canvasSize: CGSize(width: canvasWidth, height: canvasHeight)
            )
        }
        .onChange(of: canvasSignature) {
            simulator.updateBubbles(
                bubbles,
                canvasSize: CGSize(width: canvasWidth, height: canvasHeight)
            )
        }
        .onChange(of: isInteractionPaused) { _, newValue in
            simulator.setPaused(newValue)
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced {
                simulator.stop()
                gravityMonitor.stop()
            } else {
                configureMotion()
            }
        }
        .onChange(of: scenePhase) { _, _ in
            configureMotion()
        }
        .onChange(of: isActive) { _, _ in
            configureMotion()
        }
    }

    private func configureMotion() {
        guard isVisible, isActive, !reduceMotion, scenePhase == .active else {
            simulator.stop()
            gravityMonitor.stop()
            return
        }
        simulator.updateBubbles(
            bubbles,
            canvasSize: CGSize(width: canvasWidth, height: canvasHeight)
        )
        gravityMonitor.onOffsetChange = { [weak simulator = self.simulator] offset in
            simulator?.updateGravity(offset)
        }
        gravityMonitor.start()
        simulator.setPaused(isInteractionPaused)
        simulator.start()
    }

    private var bubblesSignature: String {
        bubbles
            .map { "\($0.id)|\($0.diameter)|\($0.motionFactor)" }
            .joined(separator: "||")
    }

    private var canvasSignature: String {
        "\(Int(canvasWidth.rounded()))x\(Int(canvasHeight.rounded()))"
    }
}

private struct BingoDiaryBubbleCloudItem: View {
    let bubble: BingoDiaryBubble
    @ObservedObject var motionState: BingoDiaryBubbleMotionState
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            BingoDiaryBubbleView(bubble: bubble)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(bubble.task)
        .accessibilityValue(
            L10n.tr(
                "Completed \(bubble.count) times",
                zhHans: "已完成 \(bubble.count) 次",
                zhHant: "已完成 \(bubble.count) 次",
                ja: "\(bubble.count) 回完了"
            )
        )
        .accessibilityHint(L10n.tr("Opens task details", zhHans: "打开任务详情", zhHant: "開啟任務詳細資料", ja: "タスクの詳細を開きます"))
        .contentShape(Circle())
        .offset(
            x: bubble.position.x - (bubble.diameter / 2) + motionState.offset.width,
            y: bubble.position.y - (bubble.diameter / 2) + motionState.offset.height
        )
    }
}

struct BingoDiaryBubbleCloudSection: View {
    let bubbles: [BingoDiaryBubble]
    let width: CGFloat
    let height: CGFloat
    let isHorizontallyOverflowing: Bool
    let isActive: Bool
    let onBubbleTap: (BingoDiaryBubble) -> Void

    @State private var isInteracting = false

    var body: some View {
        let cloud = BingoDiaryBubbleCloud(
            bubbles: bubbles,
            canvasWidth: width,
            canvasHeight: height,
            isInteractionPaused: isInteracting,
            isActive: isActive,
            onBubbleTap: onBubbleTap
        )

        Group {
            if isHorizontallyOverflowing {
                ScrollView(.horizontal, showsIndicators: false) {
                    cloud
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { _ in
                            if !isInteracting {
                                isInteracting = true
                            }
                        }
                        .onEnded { _ in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                isInteracting = false
                            }
                        }
                )
                .frame(height: height)
                .clipped()
            } else {
                cloud
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            }
        }
    }
}
