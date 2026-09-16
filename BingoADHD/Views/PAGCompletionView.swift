import SwiftUI
import AVFoundation
import UIKit

#if canImport(libpag)
import libpag

final class PAGRewardSoundPlayer {
    static let shared = PAGRewardSoundPlayer()

    private var audioPlayers: [String: AVAudioPlayer] = [:]

    func preload(resourceName: String, fileExtension: String = "aiff") {
        guard AppSettings.isSoundEffectsEnabled else { return }
        guard audioPlayers[resourceName] == nil,
              let url = Bundle.main.url(forResource: resourceName, withExtension: fileExtension) else { return }

        do {
            AppAudioSessionConfigurator.configureForSoundEffects()
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            audioPlayers[resourceName] = player
        } catch {
            audioPlayers[resourceName] = nil
        }
    }

    func play(resourceName: String, fileExtension: String = "aiff") {
        guard AppSettings.isSoundEffectsEnabled else { return }
        if audioPlayers[resourceName] == nil {
            preload(resourceName: resourceName, fileExtension: fileExtension)
        }
        guard let audioPlayer = audioPlayers[resourceName] else { return }
        AppAudioSessionConfigurator.configureForSoundEffects()
        audioPlayer.currentTime = 0
        audioPlayer.play()
    }
}

/// Retains decoded PAG files across transient SwiftUI views. Without this cache, a task tap has
/// to load the file again while the completion view is being created, which makes the first frame
/// feel late even for a short effect.
final class PAGCompletionAssetCache {
    static let shared = PAGCompletionAssetCache()

    private var files: [String: PAGFile] = [:]
    private var warmupViews: [String: PAGImageView] = [:]
    private var memoryWarningObserver: NSObjectProtocol?

    private init() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.releaseWarmupFrames()
        }
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    func preload(
        resourceName: String,
        filePath: String,
        cacheAllFrames: Bool,
        renderScale: Float,
        maxFrameRate: Float
    ) {
        guard let file = files[resourceName] ?? PAGFile.load(filePath) else { return }
        files[resourceName] = file

        guard cacheAllFrames, warmupViews[resourceName] == nil else { return }
        let imageView = PAGImageView()
        imageView.setRenderScale(renderScale)
        imageView.setCacheAllFramesInMemory(true)
        imageView.setComposition(file.copyOriginal(), maxFrameRate: maxFrameRate)
        imageView.setCurrentFrame(0)
        _ = imageView.flush()
        warmupViews[resourceName] = imageView
    }

    func composition(resourceName: String, filePath: String) -> PAGFile? {
        let file: PAGFile?
        if let cachedFile = files[resourceName] {
            file = cachedFile
        } else {
            file = PAGFile.load(filePath)
            if let file {
                files[resourceName] = file
            }
        }
        return file?.copyOriginal()
    }

    /// Keep lightweight source compositions available, but give memory pressure a way to drop
    /// the decoded frame cache that only exists to make the first completion effect immediate.
    private func releaseWarmupFrames() {
        warmupViews.removeAll()
    }
}

final class PAGCompletionContainerView: UIView {
    let imageView = PAGImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = false

        imageView.backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct PAGCompletionView: UIViewRepresentable {
    let resourceName: String
    let playsSound: Bool
    let soundResourceName: String?
    let soundFileExtension: String
    let playsHaptic: Bool
    let playsEmphasisHaptic: Bool
    let playsContinuousHaptics: Bool
    let cacheAllFrames: Bool
    let renderScale: Float
    let maxFrameRate: Float
    /// Full-screen compositions use the physical screen's width and height. Card effects keep
    /// their authored aspect-fit framing so surrounding particles are never cropped.
    let fillsContainer: Bool
    /// Multiplies the authored PAG speed.  A copied PAGFile is retimed per presentation, so
    /// preloaded source assets remain reusable at their original speed.
    let playbackRate: Double
    let nearEndProgress: Double?
    let onNearEnd: () -> Void
    let onFinished: () -> Void

    init(
        resourceName: String,
        playsSound: Bool = true,
        soundResourceName: String? = nil,
        soundFileExtension: String = "aiff",
        playsHaptic: Bool = false,
        playsEmphasisHaptic: Bool = false,
        playsContinuousHaptics: Bool = false,
        cacheAllFrames: Bool = true,
        renderScale: Float = 0.82,
        maxFrameRate: Float = 24,
        fillsContainer: Bool = false,
        playbackRate: Double = 1,
        nearEndProgress: Double? = nil,
        onNearEnd: @escaping () -> Void = {},
        onFinished: @escaping () -> Void
    ) {
        self.resourceName = resourceName
        self.playsSound = playsSound
        self.soundResourceName = playsSound ? (soundResourceName ?? "bingo") : nil
        self.soundFileExtension = soundFileExtension
        self.playsHaptic = playsHaptic
        self.playsEmphasisHaptic = playsEmphasisHaptic
        self.playsContinuousHaptics = playsContinuousHaptics
        self.cacheAllFrames = cacheAllFrames
        self.renderScale = renderScale
        self.maxFrameRate = maxFrameRate
        self.fillsContainer = fillsContainer
        self.playbackRate = playbackRate
        self.nearEndProgress = nearEndProgress
        self.onNearEnd = onNearEnd
        self.onFinished = onFinished
    }

    static func preload(
        resourceName: String,
        playsSound: Bool = false,
        soundResourceName: String? = nil,
        soundFileExtension: String = "aiff",
        cacheAllFrames: Bool = false,
        renderScale: Float = 0.82,
        maxFrameRate: Float = 24
    ) {
        guard let filePath = Bundle.main.path(forResource: resourceName, ofType: "pag") else { return }
        PAGCompletionAssetCache.shared.preload(
            resourceName: resourceName,
            filePath: filePath,
            cacheAllFrames: cacheAllFrames,
            renderScale: renderScale,
            maxFrameRate: maxFrameRate
        )
        if playsSound {
            PAGRewardSoundPlayer.shared.preload(
                resourceName: soundResourceName ?? "bingo",
                fileExtension: soundFileExtension
            )
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            resourceName: resourceName,
            soundResourceName: soundResourceName,
            soundFileExtension: soundFileExtension,
            playsHaptic: playsHaptic,
            playsEmphasisHaptic: playsEmphasisHaptic,
            playsContinuousHaptics: playsContinuousHaptics,
            nearEndProgress: nearEndProgress,
            onNearEnd: onNearEnd,
            onFinished: onFinished
        )
    }

    func makeUIView(context: Context) -> PAGCompletionContainerView {
        let container = PAGCompletionContainerView()
        let imageView = container.imageView
        container.clipsToBounds = fillsContainer
        imageView.contentMode = fillsContainer ? .scaleAspectFill : .scaleAspectFit
        imageView.setRenderScale(renderScale)
        imageView.setCacheAllFramesInMemory(cacheAllFrames)
        imageView.setRepeatCount(1)
        imageView.add(context.coordinator)
        context.coordinator.prepareForPresentation()

        guard let filePath = Bundle.main.path(forResource: resourceName, ofType: "pag") else {
            DiagnosticLogStore.recordWarning(
                "completion_pag_resource_missing",
                details: ["resource": resourceName]
            )
            context.coordinator.finishImmediately()
            return container
        }

        if let composition = PAGCompletionAssetCache.shared.composition(
            resourceName: resourceName,
            filePath: filePath
        ) {
            if playbackRate > 1, composition.duration() > 0 {
                composition.seTimeStretchMode(PAGTimeStretchModeScale)
                let targetDuration = max(1, Int64(Double(composition.duration()) / playbackRate))
                composition.setDuration(targetDuration)
            }
            imageView.setComposition(composition, maxFrameRate: maxFrameRate)
        } else if !imageView.setPath(filePath, maxFrameRate: maxFrameRate) {
            DiagnosticLogStore.recordWarning(
                "completion_pag_composition_load_failed",
                details: ["resource": resourceName]
            )
            context.coordinator.finishImmediately()
            return container
        }

        // PAGImageView may reset its image while assigning a composition, so apply the full-page
        // fitting rule after the composition as well. Aspect fill preserves the exported artwork
        // without stretching its raster layers.
        imageView.contentMode = fillsContainer ? .scaleAspectFill : .scaleAspectFit
        imageView.setCurrentFrame(0)
        imageView.play()
        return container
    }

    func updateUIView(_ uiView: PAGCompletionContainerView, context: Context) {
        // Playback belongs exclusively to makeUIView. SwiftUI updates this representable when
        // the board publishes its completion, points, and line state. Restarting here can send
        // a one-shot PAG back to frame zero while it is still preparing a frame, which is most
        // visible when a 4×4 Bingo starts four card effects simultaneously.
    }

    static func dismantleUIView(_ uiView: PAGCompletionContainerView, coordinator: Coordinator) {
        uiView.imageView.remove(coordinator)
        uiView.imageView.pause()
        coordinator.stopContinuousHaptics()
    }

    final class Coordinator: NSObject, PAGImageViewListener {
        var didFinish = false
        var didReportNearEnd = false
        private var didStart = false
        private let resourceName: String
        private let soundResourceName: String?
        private let soundFileExtension: String
        private let playsHaptic: Bool
        private let playsEmphasisHaptic: Bool
        private let playsContinuousHaptics: Bool
        private let continuousHaptics = AppHapticContinuousPlayer()
        private let nearEndProgress: Double?
        private let onNearEnd: () -> Void
        private let onFinished: () -> Void

        init(
            resourceName: String,
            soundResourceName: String?,
            soundFileExtension: String,
            playsHaptic: Bool,
            playsEmphasisHaptic: Bool,
            playsContinuousHaptics: Bool,
            nearEndProgress: Double?,
            onNearEnd: @escaping () -> Void,
            onFinished: @escaping () -> Void
        ) {
            self.resourceName = resourceName
            self.soundResourceName = soundResourceName
            self.soundFileExtension = soundFileExtension
            self.playsHaptic = playsHaptic
            self.playsEmphasisHaptic = playsEmphasisHaptic
            self.playsContinuousHaptics = playsContinuousHaptics
            self.nearEndProgress = nearEndProgress
            self.onNearEnd = onNearEnd
            self.onFinished = onFinished
        }

        func prepareForPresentation() {
            didFinish = false
            didReportNearEnd = false
            didStart = false
        }

        func onAnimationStart(_ pagView: PAGImageView) {
            guard !didFinish, !didStart else { return }
            didStart = true
            DiagnosticLogStore.recordStateChange(
                "completion_pag_started",
                details: [
                    "resource": resourceName,
                    "frames": "\(pagView.numFrames())"
                ]
            )
            if let soundResourceName {
                PAGRewardSoundPlayer.shared.play(
                    resourceName: soundResourceName,
                    fileExtension: soundFileExtension
                )
            }
            if playsEmphasisHaptic {
                AppHaptics.emphasis()
            } else if playsHaptic {
                AppHaptics.completion()
            }
            if playsContinuousHaptics {
                continuousHaptics.start()
            }
        }

        func onAnimationUpdate(_ pagView: PAGImageView) {
            guard let nearEndProgress,
                  !didReportNearEnd else {
                return
            }
            let frameCount = pagView.numFrames()
            guard frameCount > 1 else { return }
            let progress = Double(pagView.currentFrame()) / Double(frameCount - 1)
            guard progress >= nearEndProgress else { return }
            didReportNearEnd = true
            DispatchQueue.main.async {
                self.onNearEnd()
            }
        }

        func onAnimationEnd(_ pagView: PAGImageView) {
            DiagnosticLogStore.recordStateChange(
                "completion_pag_finished",
                details: [
                    "resource": resourceName,
                    "frame": "\(pagView.currentFrame())",
                    "frames": "\(pagView.numFrames())"
                ]
            )
            stopContinuousHaptics()
            reportNearEndIfNeeded()
            finish()
        }

        func onAnimationCancel(_ pagView: PAGImageView) {
            // A cancellation has no end callback. Finish this transient presentation once so a
            // cancelled player cannot leave the board's motion state stuck indefinitely. The
            // diagnostic distinguishes renderer/lifecycle cancellation from normal completion.
            DiagnosticLogStore.recordWarning(
                "completion_pag_cancelled",
                details: [
                    "resource": resourceName,
                    "frame": "\(pagView.currentFrame())",
                    "frames": "\(pagView.numFrames())"
                ]
            )
            stopContinuousHaptics()
            finish()
        }

        func finishImmediately() {
            stopContinuousHaptics()
            DispatchQueue.main.async {
                self.reportNearEndIfNeeded()
                self.finish()
            }
        }

        func stopContinuousHaptics() {
            continuousHaptics.stop()
        }

        private func reportNearEndIfNeeded() {
            guard nearEndProgress != nil,
                  !didReportNearEnd else {
                return
            }
            didReportNearEnd = true
            onNearEnd()
        }

        private func finish() {
            guard !didFinish else { return }
            didFinish = true
            stopContinuousHaptics()
            DispatchQueue.main.async {
                self.onFinished()
            }
        }
    }
}

#else

struct PAGCompletionView: View {
    let resourceName: String
    let playsSound: Bool
    let soundResourceName: String?
    let soundFileExtension: String
    let playsHaptic: Bool
    let playsEmphasisHaptic: Bool
    let playsContinuousHaptics: Bool
    let cacheAllFrames: Bool
    let renderScale: Float
    let maxFrameRate: Float
    let fillsContainer: Bool
    let playbackRate: Double
    let nearEndProgress: Double?
    let onNearEnd: () -> Void
    let onFinished: () -> Void

    init(
        resourceName: String,
        playsSound: Bool = true,
        soundResourceName: String? = nil,
        soundFileExtension: String = "aiff",
        playsHaptic: Bool = false,
        playsEmphasisHaptic: Bool = false,
        playsContinuousHaptics: Bool = false,
        cacheAllFrames: Bool = true,
        renderScale: Float = 0.82,
        maxFrameRate: Float = 24,
        fillsContainer: Bool = false,
        playbackRate: Double = 1,
        nearEndProgress: Double? = nil,
        onNearEnd: @escaping () -> Void = {},
        onFinished: @escaping () -> Void
    ) {
        self.resourceName = resourceName
        self.playsSound = playsSound
        self.soundResourceName = soundResourceName
        self.soundFileExtension = soundFileExtension
        self.playsHaptic = playsHaptic
        self.playsEmphasisHaptic = playsEmphasisHaptic
        self.playsContinuousHaptics = playsContinuousHaptics
        self.cacheAllFrames = cacheAllFrames
        self.renderScale = renderScale
        self.maxFrameRate = maxFrameRate
        self.fillsContainer = fillsContainer
        self.playbackRate = playbackRate
        self.nearEndProgress = nearEndProgress
        self.onNearEnd = onNearEnd
        self.onFinished = onFinished
    }

    static func preload(
        resourceName: String,
        playsSound: Bool = false,
        soundResourceName: String? = nil,
        soundFileExtension: String = "aiff",
        cacheAllFrames: Bool = false,
        renderScale: Float = 0.82,
        maxFrameRate: Float = 24
    ) {
        _ = (
            resourceName,
            playsSound,
            soundResourceName,
            soundFileExtension,
            cacheAllFrames,
            renderScale,
            maxFrameRate
        )
    }

    var body: some View {
        Color.clear
            .onAppear {
                DispatchQueue.main.async {
                    onNearEnd()
                    onFinished()
                }
            }
    }
}

#endif

/// A full-screen completion video with the same lifecycle callbacks as the PAG implementation.
/// The video owns its presentation size, which lets AVPlayer render its encoded full-resolution
/// frames without first rasterising them into a PAG frame cache.
private final class BoardCompletionVideoContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = true
        playerLayer.videoGravity = .resizeAspectFill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct BoardCompletionVideoView: UIViewRepresentable {
    let resourceName: String
    let nearEndProgress: Double
    let onNearEnd: () -> Void
    let onFinished: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            nearEndProgress: nearEndProgress,
            onNearEnd: onNearEnd,
            onFinished: onFinished
        )
    }

    func makeUIView(context: Context) -> BoardCompletionVideoContainerView {
        let container = BoardCompletionVideoContainerView()
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4") else {
            context.coordinator.finishImmediately()
            return container
        }

        let player = AVPlayer(url: url)
        // Keep the dedicated full-board Bingo track as the single source of sound feedback.
        // This avoids playing a second track when an exported MP4 happens to contain audio.
        player.isMuted = true
        player.actionAtItemEnd = .pause
        container.playerLayer.player = player
        context.coordinator.start(player: player)
        PAGRewardSoundPlayer.shared.play(resourceName: "complete_allbingo", fileExtension: "mp3")
        player.play()
        return container
    }

    func updateUIView(_ uiView: BoardCompletionVideoContainerView, context: Context) {
        guard let player = uiView.playerLayer.player,
              player.timeControlStatus != .playing,
              !context.coordinator.didFinish else {
            return
        }
        player.play()
    }

    static func dismantleUIView(_ uiView: BoardCompletionVideoContainerView, coordinator: Coordinator) {
        coordinator.invalidate()
        uiView.playerLayer.player?.pause()
        uiView.playerLayer.player = nil
    }

    final class Coordinator {
        var didFinish = false
        private var didReportNearEnd = false
        private var player: AVPlayer?
        private var progressObserver: Any?
        private var finishObserver: NSObjectProtocol?
        private let nearEndProgress: Double
        private let onNearEnd: () -> Void
        private let onFinished: () -> Void

        init(
            nearEndProgress: Double,
            onNearEnd: @escaping () -> Void,
            onFinished: @escaping () -> Void
        ) {
            self.nearEndProgress = nearEndProgress
            self.onNearEnd = onNearEnd
            self.onFinished = onFinished
        }

        func start(player: AVPlayer) {
            invalidate()
            self.player = player
            let interval = CMTime(value: 1, timescale: 30)
            progressObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                self?.reportNearEndIfNeeded(at: time)
            }
            finishObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak self] _ in
                self?.finish()
            }
        }

        func finishImmediately() {
            DispatchQueue.main.async {
                self.reportNearEndIfNeeded()
                self.finish()
            }
        }

        func invalidate() {
            if let progressObserver, let player {
                player.removeTimeObserver(progressObserver)
            }
            if let finishObserver {
                NotificationCenter.default.removeObserver(finishObserver)
            }
            progressObserver = nil
            finishObserver = nil
            player = nil
        }

        private func reportNearEndIfNeeded(at time: CMTime? = nil) {
            guard !didReportNearEnd else { return }
            guard let player,
                  let item = player.currentItem else {
                return
            }
            let duration = CMTimeGetSeconds(item.duration)
            guard duration.isFinite, duration > 0 else { return }
            let currentTime = CMTimeGetSeconds(time ?? player.currentTime())
            guard currentTime / duration >= nearEndProgress else { return }
            didReportNearEnd = true
            onNearEnd()
        }

        private func finish() {
            guard !didFinish else { return }
            didFinish = true
            reportNearEndIfNeeded()
            onFinished()
        }
    }
}

/// Full-screen PAG uses the GPU-backed PAGView rather than PAGImageView. PAGImageView is the
/// right trade-off for small UI effects, but it caches rendered image frames and is not intended
/// for a full-screen composition where preserving the exported resolution is the priority.
private struct BoardAllBingoPAGView: UIViewRepresentable {
    let resourceName: String
    let nearEndProgress: Double
    /// The bear finishes its entrance in the early part of this composition. Keep the sustained
    /// tactile feedback confined to that movement so the quiet hold before the button stays calm.
    let bearFlightEndProgress: Double
    let onNearEnd: () -> Void
    let onFinished: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            resourceName: resourceName,
            nearEndProgress: nearEndProgress,
            bearFlightEndProgress: bearFlightEndProgress,
            onNearEnd: onNearEnd,
            onFinished: onFinished
        )
    }

    func makeUIView(context: Context) -> PAGView {
        let pagView = PAGView()
        pagView.backgroundColor = .clear
        pagView.isOpaque = false
        pagView.setRepeatCount(1)
        pagView.setScaleMode(PAGScaleModeZoom)
        pagView.setCacheEnabled(true)
        pagView.setCacheScale(1)
        pagView.setUseDiskCache(false)
        pagView.setMaxFrameRate(60)
        pagView.add(context.coordinator)
        context.coordinator.reset()

        // Old full-screen renders were produced by PAGImageView and can survive app restarts.
        // Clear this rendering cache once when migrating to PAGView so no legacy frame is reused.
        BoardAllBingoPAGCacheMigration.clearLegacyImageViewCacheIfNeeded()

        guard let path = Bundle.main.path(forResource: resourceName, ofType: "pag"),
              pagView.setPath(path) else {
            context.coordinator.finishImmediately()
            return pagView
        }

        pagView.setProgress(0)
        pagView.play()
        return pagView
    }

    func updateUIView(_ pagView: PAGView, context: Context) {
        // This is a one-shot presentation. Restarting a temporarily paused or finished PAG from
        // a SwiftUI update makes the visual lifecycle diverge from the CTA lifecycle below.
    }

    static func dismantleUIView(_ pagView: PAGView, coordinator: Coordinator) {
        pagView.remove(coordinator)
        pagView.pause()
        pagView.freeCache()
        coordinator.stopContinuousHaptics()
    }

    final class Coordinator: NSObject, PAGViewListener {
        var didFinish = false
        private var didReportNearEnd = false
        private let resourceName: String
        private let nearEndProgress: Double
        private let bearFlightEndProgress: Double
        private let continuousHaptics = AppHapticContinuousPlayer()
        private let onNearEnd: () -> Void
        private let onFinished: () -> Void

        init(
            resourceName: String,
            nearEndProgress: Double,
            bearFlightEndProgress: Double,
            onNearEnd: @escaping () -> Void,
            onFinished: @escaping () -> Void
        ) {
            self.resourceName = resourceName
            self.nearEndProgress = nearEndProgress
            self.bearFlightEndProgress = bearFlightEndProgress
            self.onNearEnd = onNearEnd
            self.onFinished = onFinished
        }

        func reset() {
            didFinish = false
            didReportNearEnd = false
            stopContinuousHaptics()
        }

        func onAnimationStart(_ pagView: PAGView) {
            DiagnosticLogStore.recordStateChange(
                "board_completion_pag_started",
                details: ["resource": resourceName]
            )
            PAGRewardSoundPlayer.shared.play(resourceName: "complete_allbingo", fileExtension: "mp3")
            continuousHaptics.start(
                initialIntensity: 0.10,
                peakIntensity: 0.50,
                rampDuration: 1.7
            )
        }

        func onAnimationUpdate(_ pagView: PAGView) {
            if pagView.getProgress() >= bearFlightEndProgress {
                stopContinuousHaptics()
            }
            guard !didReportNearEnd,
                  pagView.getProgress() >= nearEndProgress else {
                return
            }
            didReportNearEnd = true
            DiagnosticLogStore.recordStateChange(
                "board_completion_pag_cta_threshold",
                details: [
                    "resource": resourceName,
                    "progress": String(format: "%.3f", pagView.getProgress())
                ]
            )
            DispatchQueue.main.async {
                self.onNearEnd()
            }
        }

        func onAnimationEnd(_ pagView: PAGView) {
            DiagnosticLogStore.recordStateChange(
                "board_completion_pag_finished",
                details: [
                    "resource": resourceName,
                    "progress": String(format: "%.3f", pagView.getProgress())
                ]
            )
            stopContinuousHaptics()
            reportNearEndIfNeeded()
            finish()
        }

        func onAnimationCancel(_ pagView: PAGView) {
            // PAG cancellation has no end callback. Preserve the completion screen and advance
            // it to its actionable state instead of leaving the user on an inert final frame.
            DiagnosticLogStore.recordWarning(
                "board_completion_pag_cancelled",
                details: [
                    "resource": resourceName,
                    "progress": String(format: "%.3f", pagView.getProgress())
                ]
            )
            stopContinuousHaptics()
            reportNearEndIfNeeded()
            finish()
        }

        func finishImmediately() {
            stopContinuousHaptics()
            DispatchQueue.main.async {
                self.reportNearEndIfNeeded()
                self.finish()
            }
        }

        func stopContinuousHaptics() {
            continuousHaptics.stop()
        }

        private func reportNearEndIfNeeded() {
            guard !didReportNearEnd else { return }
            didReportNearEnd = true
            onNearEnd()
        }

        private func finish() {
            guard !didFinish else { return }
            didFinish = true
            stopContinuousHaptics()
            DispatchQueue.main.async {
                self.onFinished()
            }
        }
    }
}

private enum BoardAllBingoPAGCacheMigration {
    private static let completedKey = "board-all-bingo-pagview-cache-migration-v1"

    static func clearLegacyImageViewCacheIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: completedKey) else { return }
        PAGDiskCache.removeAll()
        UserDefaults.standard.set(true, forKey: completedKey)
    }
}

struct BoardAllBingoCompletionView: View {
    let animationID: UUID
    let boardName: String
    let onContinue: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsContinueAction = false
    /// `complete_allbingo_bmp.pag` is 5.12 seconds. The authored quiet beat begins before the
    /// final frame, so the CTA belongs at 3.6 seconds rather than depending solely on a renderer
    /// callback that may be skipped after a PAG cancellation.
    private let continueActionFallbackNanoseconds: UInt64 = 3_600_000_000

    var body: some View {
        ZStack {
            Color(hex: "FAF9F3")
                .ignoresSafeArea()

            if !reduceMotion {
                // The geometry reader itself ignores the safe area so the UIKit PAG view is
                // given the physical window's full height, rather than only the safe-area size.
                GeometryReader { geometry in
                    BoardAllBingoPAGView(
                        resourceName: "complete_allbingo_bmp",
                        nearEndProgress: 0.68,
                        bearFlightEndProgress: 0.36,
                        onNearEnd: { showContinueAction(source: "pag_threshold") },
                        onFinished: { showContinueAction(source: "pag_finished") }
                    )
                    .id(animationID)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .allowsHitTesting(false)
                }
                .ignoresSafeArea()
            }

            if showsContinueAction {
                VStack(spacing: 18) {
                    Spacer()

                    Text(completionMessage)
                    .font(.appSystem(size: 20, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color(hex: "291E0A"))
                    .offset(y: -30)

                    Button {
                        onContinue(animationID)
                    } label: {
                        Text(L10n.tr(
                            "I'm amazing!",
                            zhHans: "我真是太厉害了！",
                            zhHant: "我真是太厲害了！",
                            ja: "私ってすごい！"
                        ))
                        .font(.appSystem(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(NeumorphicColors.accent)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("board-completion-continue")
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 30)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            guard reduceMotion else { return }
            PAGRewardSoundPlayer.shared.play(resourceName: "complete_allbingo", fileExtension: "mp3")
            showContinueAction(source: "reduce_motion")
        }
        .task(id: animationID) {
            guard !reduceMotion else { return }
            try? await Task.sleep(nanoseconds: continueActionFallbackNanoseconds)
            guard !Task.isCancelled else { return }
            showContinueAction(source: "timer_fallback")
        }
    }

    private func showContinueAction(source: String) {
        guard !showsContinueAction else { return }
        DiagnosticLogStore.recordStateChange(
            "board_completion_cta_shown",
            details: ["source": source]
        )
        AppHaptics.emphasis()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
            showsContinueAction = true
        }
    }

    private var completionMessage: String {
        L10n.tr(
            "You completed every task set for \(boardName)",
            zhHans: "你已完成\(boardName)棋盘设置的所有任务",
            zhHant: "你已完成\(boardName)棋盤設定的所有任務",
            ja: "\(boardName)ビンゴボードに設定した\nすべてのタスクを完了しました"
        )
    }
}
