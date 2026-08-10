import SwiftUI

struct HomeFeedbackLayer: View {
    @ObservedObject var viewModel: BingoViewModel
    @ObservedObject var toastStore: HomeToastStore

    let safeAreaTop: CGFloat
    let contentWidth: CGFloat
    let isPadLayout: Bool

    var body: some View {
        ZStack {
            if viewModel.showCelebration, viewModel.taskCompletionMotion == nil {
                CelebrationView()
            }

            if toastStore.isDailyResetVisible {
                DailyResetToastView(isPadLayout: isPadLayout)
                    .frame(maxWidth: min(contentWidth, 620), maxHeight: .infinity, alignment: .top)
                    .padding(.top, max(safeAreaTop, 18) + 44)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            if let commonTasksToastMessage = toastStore.commonMessage, toastStore.isCommonVisible {
                CommonTasksToastView(message: commonTasksToastMessage, isPadLayout: isPadLayout)
                    .frame(maxWidth: min(contentWidth, 520), maxHeight: .infinity, alignment: .top)
                    .padding(.top, max(safeAreaTop, 18) + 96)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
    }
}

struct BingoTopCompletionEffect: View {
    let motion: BingoViewModel.TaskCompletionMotion
    let onFinished: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTopEffectVisible = false
    @State private var bingoContinuousHaptics = AppHapticContinuousPlayer()

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())

            if isTopEffectVisible, !reduceMotion {
                PAGCompletionView(
                    resourceName: "complete_bingo_bmp",
                    playsSound: true,
                    soundResourceName: "complete_bingo",
                    soundFileExtension: "mp3",
                    playsEmphasisHaptic: true,
                    cacheAllFrames: false,
                    onFinished: {
                        bingoContinuousHaptics.stop()
                        onFinished(motion.id)
                    }
                )
                .id(motion.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            bingoContinuousHaptics.stop()
        }
        .task(id: motion.id) {
            guard !reduceMotion else {
                PAGRewardSoundPlayer.shared.play(resourceName: "complete_bingo", fileExtension: "mp3")
                AppHaptics.emphasis()
                onFinished(motion.id)
                return
            }

            PAGRewardSoundPlayer.shared.play(
                resourceName: "complete_bingo_background",
                fileExtension: "mp3"
            )
            bingoContinuousHaptics.start(
                initialIntensity: 0.25,
                peakIntensity: 0.45,
                rampDuration: 0.18,
                sharpness: 0.78
            )
            // complete_bingo_background.mp3 is 1.02 seconds, so the dedicated Bingo reveal
            // begins only after the card-edge sound has finished.
            try? await Task.sleep(nanoseconds: 1_020_000_000)
            guard !Task.isCancelled else {
                bingoContinuousHaptics.stop()
                return
            }
            bingoContinuousHaptics.stop()
            withAnimation(.easeOut(duration: 0.12)) {
                isTopEffectVisible = true
            }
        }
    }
}
