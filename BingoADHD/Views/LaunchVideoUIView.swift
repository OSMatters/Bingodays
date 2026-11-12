import UIKit
import AVFoundation

final class LaunchVideoUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var readyObservation: NSKeyValueObservation?

    func configure(player: AVPlayer, onReady: @escaping @MainActor () -> Void) {
        guard let videoLayer = layer as? AVPlayerLayer else { return }
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        videoLayer.backgroundColor = UIColor.clear.cgColor
        videoLayer.videoGravity = .resizeAspectFill
        videoLayer.player = player
        readyObservation = videoLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor in onReady() }
        }
    }

    func disconnect() {
        readyObservation?.invalidate()
        readyObservation = nil
        (layer as? AVPlayerLayer)?.player = nil
    }
}
