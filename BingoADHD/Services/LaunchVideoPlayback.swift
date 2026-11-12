import AVFoundation

/// Owns the local, silent, one-shot launch player and its observation lifetime.
@MainActor
final class LaunchVideoPlayback {
    let player = AVPlayer()
    private var hasStarted = false
    private var hasFinished = false
    private var isActive = false
    private var onFinish: (() -> Void)?
    private var statusObservation: NSKeyValueObservation?
    private var endObservation: NSObjectProtocol?
    private var failureObservation: NSObjectProtocol?
    private var watchdog: Task<Void, Never>?

    func start(url: URL?, isActive: Bool, onFinish: @escaping () -> Void) {
        guard !hasStarted else { return }
        hasStarted = true
        self.isActive = isActive
        self.onFinish = onFinish
        guard let url else {
            finish()
            return
        }

        player.isMuted = true
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = false
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        endObservation = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.finish() }
        }
        failureObservation = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.finish() }
        }
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor [weak self] in
                guard let self, !hasFinished else { return }
                if status == .failed {
                    finish()
                } else if status == .readyToPlay, self.isActive {
                    player.play()
                }
            }
        }
        setActive(isActive)
    }

    func setActive(_ active: Bool) {
        isActive = active
        guard hasStarted, !hasFinished else { return }
        watchdog?.cancel()
        if active {
            if player.currentItem?.status == .readyToPlay { player.play() }
            // Local video failure must never trap someone on the splash screen.
            watchdog = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                self?.finish()
            }
        } else {
            player.pause()
        }
    }

    func stop() {
        hasFinished = true
        player.pause()
        onFinish = nil
        clearObservations()
    }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        player.pause()
        clearObservations()
        let completion = onFinish
        onFinish = nil
        completion?()
    }

    private func clearObservations() {
        watchdog?.cancel()
        watchdog = nil
        statusObservation?.invalidate()
        statusObservation = nil
        if let endObservation { NotificationCenter.default.removeObserver(endObservation) }
        if let failureObservation { NotificationCenter.default.removeObserver(failureObservation) }
        endObservation = nil
        failureObservation = nil
    }
}
