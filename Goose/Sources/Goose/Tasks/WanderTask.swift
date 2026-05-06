import CoreGraphics
import Foundation

/// Goose roams the screen, pausing briefly between random walks. Mirrors the
/// `Task_Wander` state machine from the original game.
@MainActor
final class WanderTask: GooseTask {
    private static let minWanderingTime: CGFloat = 20
    private static let maxWanderingTime: CGFloat = 40
    private static let arrivalThreshold: CGFloat = 20

    private var wanderingStartTime: CGFloat = 0
    private var wanderingDuration: CGFloat = 0
    private var pauseStartTime: CGFloat = -1
    private var pauseDuration: CGFloat = 0

    func start(simulation: GooseSimulation) {
        simulation.setSpeed(.walk)
        wanderingStartTime = GameTime.time
        wanderingDuration = Self.randomWanderDuration()
        pauseStartTime = -1
    }

    func tick(simulation: GooseSimulation) {
        if GameTime.time - wanderingStartTime > wanderingDuration {
            start(simulation: simulation)
            return
        }

        if pauseStartTime > 0 {
            tickPause(simulation: simulation)
        } else {
            tickWalk(simulation: simulation)
        }
    }

    private func tickPause(simulation: GooseSimulation) {
        if GameTime.time - pauseStartTime > pauseDuration {
            pauseStartTime = -1
            pickNextTarget(simulation: simulation)
        } else {
            simulation.velocity = .zero2
        }
    }

    private func tickWalk(simulation: GooseSimulation) {
        if CGPoint.distance(simulation.position, simulation.targetPos) < Self.arrivalThreshold {
            pauseStartTime = GameTime.time
            pauseDuration = Self.randomPauseDuration()
        }
    }

    private func pickNextTarget(simulation: GooseSimulation) {
        let maxDistance = Self.randomWalkTime() * simulation.currentSpeed
        let candidate = CGPoint(
            x: SamMath.randomRange(0, simulation.screenSize.width),
            y: SamMath.randomRange(0, simulation.screenSize.height)
        )
        if CGPoint.distance(simulation.position, candidate) > maxDistance {
            let direction = CGPoint.normalize(candidate - simulation.position)
            simulation.targetPos = simulation.position + direction * maxDistance
        } else {
            simulation.targetPos = candidate
        }
    }

    private static func randomWanderDuration() -> CGFloat {
        guard GameTime.time >= 1 else { return minWanderingTime }
        return SamMath.randomRange(minWanderingTime, maxWanderingTime)
    }

    private static func randomWalkTime() -> CGFloat {
        SamMath.randomRange(1, 6)
    }

    private static func randomPauseDuration() -> CGFloat {
        1 + CGFloat.random(in: 0...1)
    }
}
