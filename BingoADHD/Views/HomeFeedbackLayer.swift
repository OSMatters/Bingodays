import SwiftUI

struct HomeFeedbackLayer: View {
    @ObservedObject var viewModel: BingoViewModel
    @ObservedObject var toastStore: HomeToastStore

    let canvasSize: CGSize
    let safeAreaTop: CGFloat
    let contentWidth: CGFloat
    let isPadLayout: Bool
    let onBoardCompletionAnimationFinished: () -> Void

    var body: some View {
        ZStack {
            if viewModel.showCelebration {
                CelebrationView()
            }

            if viewModel.showBoardCompletionAnimation {
                PAGCompletionView(resourceName: "cat_bmp") {
                    onBoardCompletionAnimationFinished()
                }
                .frame(
                    width: min(canvasSize.width * 0.5, 220),
                    height: min(canvasSize.width * 0.5, 220)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .allowsHitTesting(false)
                .transition(.opacity)
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
    }
}
