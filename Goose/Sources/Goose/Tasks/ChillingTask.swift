import CoreGraphics
import Foundation

/// Goose stops, puts on headphones, fires a Spotify play (best-effort), and
/// chills for 45–90s before resuming wander. If Spotify isn't running or
/// fails, the visual chill still happens — the meme is the headphones.
@MainActor
final class ChillingTask: GooseTask {
    private static let minDuration: CGFloat = 45
    private static let maxDuration: CGFloat = 90

    private let spotifyURI: String?
    private weak var effects: GooseSceneEffects?
    private var endTime: CGFloat = 0

    init(spotifyURI: String?, effects: GooseSceneEffects) {
        self.spotifyURI = spotifyURI
        self.effects = effects
    }

    func start(simulation: GooseSimulation) {
        simulation.velocity = .zero2
        let duration = SamMath.randomRange(Self.minDuration, Self.maxDuration)
        endTime = GameTime.time + duration

        effects?.setHeadphones(visible: true)

        if let uri = spotifyURI {
            Task { @MainActor in
                _ = await SpotifyController.play(uri: uri)
            }
        }
    }

    func tick(simulation: GooseSimulation) {
        simulation.velocity = .zero2
        if GameTime.time >= endTime {
            effects?.setHeadphones(visible: false)
            simulation.setTask(WanderTask())
        }
    }
}
