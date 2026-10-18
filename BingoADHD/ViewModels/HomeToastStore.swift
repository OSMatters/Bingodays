import SwiftUI

@MainActor
final class HomeToastStore: ObservableObject {
    @Published var commonMessage: String?
    @Published var isCommonVisible = false
    @Published var isContactUsCopyVisible = false
    @Published var isDailyResetVisible = false
    @Published var isCompletedSingleTaskRemovalVisible = false

    private var hideCommonTask: Task<Void, Never>?
    private var hideContactUsCopyTask: Task<Void, Never>?
    private var hideDailyResetTask: Task<Void, Never>?
    private var hideCompletedSingleTaskRemovalTask: Task<Void, Never>?

    deinit {
        hideCommonTask?.cancel()
        hideContactUsCopyTask?.cancel()
        hideDailyResetTask?.cancel()
        hideCompletedSingleTaskRemovalTask?.cancel()
    }

    func showCommon(_ message: String) {
        hideCommonTask?.cancel()
        commonMessage = message

        withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
            isCommonVisible = true
        }

        hideCommonTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(2.2)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.26)) {
                self?.isCommonVisible = false
            }
        }
    }

    func showContactUsCopy() {
        hideContactUsCopyTask?.cancel()

        withAnimation(.easeInOut(duration: 0.2)) {
            isContactUsCopyVisible = true
        }

        hideContactUsCopyTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                self?.isContactUsCopyVisible = false
            }
        }
    }

    func showDailyReset() {
        hideDailyResetTask?.cancel()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            isDailyResetVisible = true
        }

        hideDailyResetTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(2.2)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.28)) {
                self?.isDailyResetVisible = false
            }
        }
    }

    func showCompletedSingleTaskRemoval() {
        hideCompletedSingleTaskRemovalTask?.cancel()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            isCompletedSingleTaskRemovalVisible = true
        }

        hideCompletedSingleTaskRemovalTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(3.2)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.28)) {
                self?.isCompletedSingleTaskRemovalVisible = false
            }
        }
    }
}
