import AVFoundation

enum AppAudioSessionConfigurator {
    static func configureForSoundEffects() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Keep completion and reward sounds alongside audio the person was already
            // listening to. Deliberately do not activate the session here: activation is
            // unnecessary for short UI sounds and can take ownership from another player.
            try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        } catch {
            // Sound effects are non-critical; never block app flow on audio session setup.
        }
    }

    static func deactivateRecordingSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            configureForSoundEffects()
        } catch {
            configureForSoundEffects()
        }
    }
}

final class PointsSoundPlayer {
    static let shared = PointsSoundPlayer()

    private var players: [String: AVAudioPlayer] = [:]

    func preload() {
        preload(resourceName: "get1point")
        preload(resourceName: "CatReward")
    }

    private func preload(resourceName: String, fileExtension: String = "aiff") {
        guard AppSettings.isSoundEffectsEnabled else { return }
        guard players[resourceName] == nil,
              let url = Bundle.main.url(forResource: resourceName, withExtension: fileExtension) else { return }

        do {
            AppAudioSessionConfigurator.configureForSoundEffects()
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.prepareToPlay()
            players[resourceName] = audioPlayer
        } catch {
            players[resourceName] = nil
        }
    }

    func play() {
        play(resourceName: "get1point")
    }

    func playRewardRedeemed() {
        play(resourceName: "CatReward")
    }

    private func play(resourceName: String) {
        guard AppSettings.isSoundEffectsEnabled else { return }
        if players[resourceName] == nil {
            preload(resourceName: resourceName)
        }
        guard let player = players[resourceName] else { return }
        AppAudioSessionConfigurator.configureForSoundEffects()
        player.currentTime = 0
        player.play()
    }
}
