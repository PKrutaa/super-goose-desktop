import CoreGraphics
import Foundation

/// Goose sits still for a random short interval, doing nothing visible.
@MainActor
final class NapTask: GooseTask {
    private var endTime: CGFloat = 0

    func start(simulation: GooseSimulation) {
        simulation.velocity = .zero2
        simulation.targetPos = simulation.position
        let duration = SamMath.randomRange(4, 9)
        endTime = GameTime.time + duration
    }

    func tick(simulation: GooseSimulation) {
        simulation.velocity = .zero2
        simulation.targetPos = simulation.position
        if GameTime.time >= endTime {
            simulation.setTask(WanderTask())
        }
    }
}
