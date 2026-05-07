import CoreGraphics
import Foundation

/// Goose stops, puts on headphones, fires a Spotify play (best-effort), and
/// chills for 45–90s before resuming wander. If Spotify isn't running or
/// fails, the visual chill still happens — the meme is the headphones.
@MainActor
final class ChillingTask: GooseTask {
    // Long enough to outlast a typical song (~3min). Goose stays put with
    // headphones while the playlist plays through naturally.
    private static let minDuration: CGFloat = 180
    private static let maxDuration: CGFloat = 300

    private let spotifyURI: String?
    private weak var effects: GooseSceneEffects?
    private var endTime: CGFloat = 0
    private var lockedPosition: CGPoint = .zero2
    private var lockedDirection: CGFloat = 90

    init(spotifyURI: String?, effects: GooseSceneEffects) {
        self.spotifyURI = spotifyURI
        self.effects = effects
    }

    func start(simulation: GooseSimulation) {
        // Snapshot the goose's current state and lock to it for the duration of
        // the chill. Without this, the rig's direction/target drifts each tick
        // (normalize(zero) → atan2(0,0) → 0) and the headphones jitter.
        lockedPosition = simulation.position
        lockedDirection = simulation.direction
        simulation.velocity = .zero2
        simulation.targetPos = lockedPosition

        let duration = SamMath.randomRange(Self.minDuration, Self.maxDuration)
        endTime = GameTime.time + duration

        effects?.setHeadphones(visible: true)
        effects?.setMusicNotes(active: true)
        effects?.setDancing(active: true)

        if let uri = spotifyURI {
            Task { @MainActor in
                _ = await SpotifyController.play(uri: uri)
            }
        }
    }

    func tick(simulation: GooseSimulation) {
        // Hard-lock state so the rig (and headphones) sit perfectly still.
        simulation.velocity = .zero2
        simulation.position = lockedPosition
        simulation.direction = lockedDirection
        simulation.targetPos = lockedPosition

        if GameTime.time >= endTime {
            effects?.setHeadphones(visible: false)
            effects?.setMusicNotes(active: false)
            effects?.setDancing(active: false)
            simulation.setTask(WanderTask())
        }
    }
}
