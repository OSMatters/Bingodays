import SwiftUI

#if canImport(libpag)
import libpag
import AVFoundation
import UIKit

final class PAGRewardSoundPlayer {
    static let shared = PAGRewardSoundPlayer()

    private var audioPlayers: [String: AVAudioPlayer] = [:]

    func preload(resourceName: String, fileExtension: String = "aiff") {
        guard AppSettings.isSoundEffectsEnabled else { return }
        guard audioPlayers[resourceName] == nil,
              let url = Bundle.main.url(forResource: resourceName, withExtension: fileExtension) else { return }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            audioPlayers[resourceName] = player
        } catch {
            audioPlayers[resourceName] = nil
        }
    }

    func play(resourceName: String) {
        guard AppSettings.isSoundEffectsEnabled else { return }
        guard let audioPlayer = audioPlayers[resourceName] else { return }
        audioPlayer.currentTime = 0
        audioPlayer.play()
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
    let onFinished: () -> Void

    static func preload(resourceName: String) {
        guard let filePath = Bundle.main.path(forResource: resourceName, ofType: "pag") else { return }
        let preloadView = PAGImageView()
        preloadView.setRenderScale(0.82)
        preloadView.setCacheAllFramesInMemory(true)
        _ = preloadView.setPath(filePath, maxFrameRate: 24)
        preloadView.setCurrentFrame(0)
        PAGRewardSoundPlayer.shared.preload(resourceName: "bingo")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinished: onFinished)
    }

    func makeUIView(context: Context) -> PAGCompletionContainerView {
        let container = PAGCompletionContainerView()
        let imageView = container.imageView
        imageView.setRenderScale(0.82)
        imageView.setCacheAllFramesInMemory(true)
        imageView.setRepeatCount(1)
        imageView.add(context.coordinator)

        if let filePath = Bundle.main.path(forResource: resourceName, ofType: "pag") {
            _ = imageView.setPath(filePath, maxFrameRate: 24)
        }

        imageView.setCurrentFrame(0)
        imageView.play()
        context.coordinator.didFinish = false
        return container
    }

    func updateUIView(_ uiView: PAGCompletionContainerView, context: Context) {
        let imageView = uiView.imageView
        guard !context.coordinator.didFinish else { return }
        if !imageView.isPlaying() {
            imageView.setCurrentFrame(0)
            imageView.play()
        }
    }

    static func dismantleUIView(_ uiView: PAGCompletionContainerView, coordinator: Coordinator) {
        uiView.imageView.remove(coordinator)
        uiView.imageView.pause()
    }

    final class Coordinator: NSObject, PAGImageViewListener {
        var didFinish = false
        private let onFinished: () -> Void

        init(onFinished: @escaping () -> Void) {
            self.onFinished = onFinished
        }

        func onAnimationStart(_ pagView: PAGImageView) {
            PAGRewardSoundPlayer.shared.play(resourceName: "bingo")
        }

        func onAnimationEnd(_ pagView: PAGImageView) {
            guard !didFinish else { return }
            didFinish = true
            DispatchQueue.main.async {
                self.onFinished()
            }
        }
    }
}

#else

struct PAGCompletionView: View {
    let resourceName: String
    let onFinished: () -> Void

    var body: some View {
        Color.clear
            .onAppear {
                DispatchQueue.main.async {
                    onFinished()
                }
            }
    }
}

#endif
