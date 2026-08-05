import AVFoundation

@MainActor
final class GameAudio {
    static let shared = GameAudio()

    private var players = [AVAudioPlayer]()

    private init() {}

    func play(
        _ resource: String,
        enabled: Bool,
        interrupt: Bool = true,
        loops: Bool = false,
        volume: Float = 0.82
    ) {
        guard enabled,
              let url = Bundle.main.url(
                forResource: resource,
                withExtension: "m4a"
              ) else { return }

        if interrupt {
            stop()
        } else {
            players.removeAll { !$0.isPlaying }
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = min(1, max(0, volume))
            player.numberOfLoops = loops ? -1 : 0
            player.prepareToPlay()
            player.play()
            players.append(player)
        } catch {
            // Audio is decorative; gameplay must continue if playback fails.
        }
    }

    func stop() {
        players.forEach { $0.stop() }
        players.removeAll()
    }
}
