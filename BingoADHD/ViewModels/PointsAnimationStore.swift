import SwiftUI

@MainActor
final class PointsAnimationStore: ObservableObject {
    @Published var animationTrigger = 0
    @Published var floatingDelta: Int?
    @Published var isFloatingDeltaVisible = false

    private var hideFloatingDeltaTask: Task<Void, Never>?
    private var clearFloatingDeltaTask: Task<Void, Never>?

    deinit {
        hideFloatingDeltaTask?.cancel()
        clearFloatingDeltaTask?.cancel()
    }

    func handleAvailablePointsChange(
        from oldValue: Int,
        to newValue: Int,
        playsSoundEffect: Bool = true
    ) {
        let delta = newValue - oldValue
        guard delta != 0 else { return }

        hideFloatingDeltaTask?.cancel()
        clearFloatingDeltaTask?.cancel()

        animationTrigger += 1
        floatingDelta = delta

        if delta > 0, playsSoundEffect {
            PointsSoundPlayer.shared.play()
        }

        withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
            isFloatingDeltaVisible = true
        }

        hideFloatingDeltaTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(0.72)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.32)) {
                self?.isFloatingDeltaVisible = false
            }
        }

        clearFloatingDeltaTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(1.08)) } catch { return }
            guard !Task.isCancelled else { return }
            guard self?.isFloatingDeltaVisible == false else { return }
            self?.floatingDelta = nil
        }
    }
}
