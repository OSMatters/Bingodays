import SwiftUI

struct OnboardingCoffeeStickerView: View {
    let scale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasReachedTop = false

    var body: some View {
        Image(decorative: "OnboardingCoffeeSticker")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 104 * scale, height: 66 * scale)
            .rotationEffect(.degrees(-90))
            .offset(y: reduceMotion || hasReachedTop ? 0 : 204 * scale)
            .task(id: scenePhase) {
                guard scenePhase == .active, !hasReachedTop else { return }
                guard !reduceMotion else {
                    hasReachedTop = true
                    return
                }

                do {
                    try await Task.sleep(for: .milliseconds(200))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }

                withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 1.4)) {
                    hasReachedTop = true
                }
            }
            .onChange(of: reduceMotion) { _, reduced in
                if reduced {
                    hasReachedTop = true
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}
