import SwiftUI
import Foundation

struct BingoDiaryBubbleCloud: View {
    let bubbles: [BingoDiaryBubble]
    let canvasWidth: CGFloat
    let canvasHeight: CGFloat
    let globalMotionOffset: CGSize
    let isInteractionPaused: Bool
    var onBubbleTap: ((BingoDiaryBubble) -> Void)? = nil
    @StateObject private var simulator = BingoDiaryBubbleDynamicsSimulator()

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(bubbles) { bubble in
                let dynamicOffset = simulator.offset(for: bubble.id)
                BingoDiaryBubbleView(bubble: bubble)
                    .contentShape(Circle())
                    .onTapGesture {
                        onBubbleTap?(bubble)
                    }
                    .offset(
                        x: bubble.position.x - (bubble.diameter / 2) + dynamicOffset.width,
                        y: bubble.position.y - (bubble.diameter / 2) + dynamicOffset.height
                    )
            }
        }
        .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
        .onAppear {
            simulator.start()
            simulator.setPaused(isInteractionPaused)
            simulator.updateBubbles(
                bubbles,
                canvasSize: CGSize(width: canvasWidth, height: canvasHeight)
            )
            simulator.updateGravity(globalMotionOffset)
        }
        .onDisappear {
            simulator.stop()
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
        .onChange(of: globalMotionOffset) { _, newValue in
            simulator.updateGravity(newValue)
        }
        .onChange(of: isInteractionPaused) { _, newValue in
            simulator.setPaused(newValue)
        }
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
