import AVFoundation

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
        player.currentTime = 0
        player.play()
    }
}
