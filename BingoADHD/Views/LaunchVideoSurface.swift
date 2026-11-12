import SwiftUI
import AVFoundation

struct LaunchVideoSurface: UIViewRepresentable {
    let player: AVPlayer
    let onReady: @MainActor () -> Void

    func makeUIView(context: Context) -> LaunchVideoUIView {
        let view = LaunchVideoUIView()
        view.configure(player: player, onReady: onReady)
        return view
    }

    func updateUIView(_ uiView: LaunchVideoUIView, context: Context) {}

    static func dismantleUIView(_ uiView: LaunchVideoUIView, coordinator: ()) {
        uiView.disconnect()
    }
}
