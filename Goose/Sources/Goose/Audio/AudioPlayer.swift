import AVFoundation
import Foundation

/// Plays goose sound effects from a user-provided Desktop Goose installation.
/// Audio files are never bundled in this project — they live in the user's
/// legitimately installed `Desktop Goose.app/Contents/Resources/`.
/// Configure the path via the `GOOSE_AUDIO_PATH` environment variable.
@MainActor
final class AudioPlayer {
    static let defaultInstallPath = "/Users/kruta/testes/desktop-goose-source/Desktop Goose v0.22/Desktop Goose.app/Contents/Resources"

    private let installRoot: String
    private var honks: [AVAudioPlayer] = []
    private var pats: [AVAudioPlayer] = []
    private var bite: AVAudioPlayer?
    private(set) var didLoadAnything = false

    init(installRoot: String? = nil) {
        let envPath = ProcessInfo.processInfo.environment["GOOSE_AUDIO_PATH"]
        self.installRoot = installRoot ?? envPath ?? Self.defaultInstallPath
        load()
    }

    func playHonk(volume: Float = 0.8) {
        playRandom(from: honks, volume: volume)
    }

    func playPat(volume: Float = 0.4) {
        playRandom(from: pats, volume: volume)
    }

    func playBite(volume: Float = 0.07) {
        guard let player = bite else { return }
        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    private func load() {
        honks = ["Honk1.mp3", "Honk2.mp3", "Honk3.mp3", "Honk4.mp3"].compactMap(makePlayer)
        pats = ["Pat1.wav", "Pat2.wav", "Pat3.wav"].compactMap(makePlayer)
        bite = makePlayer(filename: "BITE.mp3")
        didLoadAnything = !honks.isEmpty || !pats.isEmpty || bite != nil
    }

    private func makePlayer(filename: String) -> AVAudioPlayer? {
        let url = URL(fileURLWithPath: installRoot).appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        return player
    }

    private func playRandom(from pool: [AVAudioPlayer], volume: Float) {
        guard let player = pool.randomElement() else { return }
        player.volume = volume
        player.currentTime = 0
        player.play()
    }
}
