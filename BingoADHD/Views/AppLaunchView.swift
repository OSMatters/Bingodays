import SwiftUI

/// Presented once per scene lifetime, including every launch after force quit.
struct AppLaunchView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playback = LaunchVideoPlayback()
    @State private var isVideoReady = false
    let onFinish: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white
                Image("AppLaunchPoster")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                LaunchVideoSurface(player: playback.player) {
                    isVideoReady = true
                }
                .opacity(isVideoReady ? 1 : 0)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task {
            guard !reduceMotion else {
                onFinish()
                return
            }
            playback.start(
                url: Bundle.main.url(forResource: "JuanjuanLaunch", withExtension: "mp4"),
                isActive: scenePhase == .active,
                onFinish: onFinish
            )
        }
        .onChange(of: scenePhase) { _, phase in
            playback.setActive(phase == .active)
        }
        .onChange(of: reduceMotion) { _, reduced in
            guard reduced else { return }
            playback.stop()
            onFinish()
        }
        .onDisappear { playback.stop() }
    }
}
