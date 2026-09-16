import SwiftUI

@MainActor
final class HomeToastStore: ObservableObject {
    @Published var commonMessage: String?
    @Published var isCommonVisible = false
    @Published var isContactUsCopyVisible = false
    @Published var isDailyResetVisible = false
    @Published var isCompletedSingleTaskRemovalVisible = false

    private var hideCommonWorkItem: DispatchWorkItem?
    private var hideContactUsCopyWorkItem: DispatchWorkItem?
    private var hideDailyResetWorkItem: DispatchWorkItem?
    private var hideCompletedSingleTaskRemovalWorkItem: DispatchWorkItem?

    deinit {
        hideCommonWorkItem?.cancel()
        hideContactUsCopyWorkItem?.cancel()
        hideDailyResetWorkItem?.cancel()
        hideCompletedSingleTaskRemovalWorkItem?.cancel()
    }

    func showCommon(_ message: String) {
        hideCommonWorkItem?.cancel()
        commonMessage = message

        withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
            isCommonVisible = true
        }

        let workItem = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.26)) {
                self?.isCommonVisible = false
            }
        }
        hideCommonWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: workItem)
    }

    func showContactUsCopy() {
        hideContactUsCopyWorkItem?.cancel()

        withAnimation(.easeInOut(duration: 0.2)) {
            isContactUsCopyVisible = true
        }

        let workItem = DispatchWorkItem { [weak self] in
            withAnimation(.easeInOut(duration: 0.2)) {
                self?.isContactUsCopyVisible = false
            }
        }
        hideContactUsCopyWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: workItem)
    }

    func showDailyReset() {
        hideDailyResetWorkItem?.cancel()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            isDailyResetVisible = true
        }

        let workItem = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.28)) {
                self?.isDailyResetVisible = false
            }
        }
        hideDailyResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: workItem)
    }

    func showCompletedSingleTaskRemoval() {
        hideCompletedSingleTaskRemovalWorkItem?.cancel()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            isCompletedSingleTaskRemovalVisible = true
        }

        let workItem = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.28)) {
                self?.isCompletedSingleTaskRemovalVisible = false
            }
        }
        hideCompletedSingleTaskRemovalWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: workItem)
    }
}
