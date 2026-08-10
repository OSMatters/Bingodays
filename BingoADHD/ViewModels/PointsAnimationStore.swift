import SwiftUI

@MainActor
final class PointsAnimationStore: ObservableObject {
    @Published var animationTrigger = 0
    @Published var floatingDelta: Int?
    @Published var isFloatingDeltaVisible = false

    private var hideFloatingDeltaWorkItem: DispatchWorkItem?
    private var clearFloatingDeltaWorkItem: DispatchWorkItem?

    deinit {
        hideFloatingDeltaWorkItem?.cancel()
        clearFloatingDeltaWorkItem?.cancel()
    }

    func handleAvailablePointsChange(
        from oldValue: Int,
        to newValue: Int,
        playsSoundEffect: Bool = true
    ) {
        let delta = newValue - oldValue
        guard delta != 0 else { return }

        hideFloatingDeltaWorkItem?.cancel()
        clearFloatingDeltaWorkItem?.cancel()

        animationTrigger += 1
        floatingDelta = delta

        if delta > 0, playsSoundEffect {
            PointsSoundPlayer.shared.play()
        }

        withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
            isFloatingDeltaVisible = true
        }

        let hideWorkItem = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.32)) {
                self?.isFloatingDeltaVisible = false
            }
        }
        hideFloatingDeltaWorkItem = hideWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.72, execute: hideWorkItem)

        let clearWorkItem = DispatchWorkItem { [weak self] in
            guard self?.isFloatingDeltaVisible == false else { return }
            self?.floatingDelta = nil
        }
        clearFloatingDeltaWorkItem = clearWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.08, execute: clearWorkItem)
    }
}
