import AppKit
import CoreGraphics
import Foundation

/// Goose chases the cursor; once close enough it "captures" the cursor and
/// drags it across the screen using `CGWarpMouseCursorPosition`. Mirrors the
/// chase / drag staging from the original `Task_NabMouse`.
@MainActor
final class NabMouseTask: GooseTask {
    private static let captureDistance: CGFloat = 18
    private static let dropDistance: CGFloat = 30
    private static let chaseTimeout: CGFloat = 8.0
    private static let dragTimeout: CGFloat = 6.0
    private static let mudDuration: CGFloat = 12.0

    private enum Stage {
        case chase
        case drag
    }

    private var stage: Stage = .chase
    private var stageEndTime: CGFloat = 0
    private var dragTarget: CGPoint = .zero2

    func start(simulation: GooseSimulation) {
        simulation.setSpeed(.run)
        simulation.trackMudEndTime = max(simulation.trackMudEndTime, GameTime.time + Self.mudDuration)
        simulation.onHonk?()
        stage = .chase
        stageEndTime = GameTime.time + Self.chaseTimeout
    }

    func tick(simulation: GooseSimulation) {
        switch stage {
        case .chase:
            tickChase(simulation: simulation)
        case .drag:
            tickDrag(simulation: simulation)
        }
    }

    private func tickChase(simulation: GooseSimulation) {
        let mouse = NSEvent.mouseLocation
        simulation.targetPos = mouse
        let beak = simulation.beakPosition

        if CGPoint.distance(beak, mouse) < Self.captureDistance {
            stage = .drag
            stageEndTime = GameTime.time + Self.dragTimeout
            dragTarget = pickDragTarget(simulation: simulation)
            simulation.targetPos = dragTarget
            simulation.onHonk?()
            return
        }

        if GameTime.time >= stageEndTime {
            simulation.setTask(WanderTask())
        }
    }

    private func tickDrag(simulation: GooseSimulation) {
        simulation.targetPos = dragTarget
        let beak = simulation.beakPosition
        CGWarpMouseCursorPosition(globalScreenPoint(from: beak))

        let goosePos = simulation.position
        if CGPoint.distance(goosePos, dragTarget) < Self.dropDistance || GameTime.time >= stageEndTime {
            simulation.setTask(WanderTask())
        }
    }

    private func pickDragTarget(simulation: GooseSimulation) -> CGPoint {
        let s = simulation.screenSize
        let goose = simulation.position
        let candidates: [CGPoint] = [
            CGPoint(x: 60, y: 60),
            CGPoint(x: s.width - 60, y: 60),
            CGPoint(x: 60, y: s.height - 60),
            CGPoint(x: s.width - 60, y: s.height - 60),
        ]
        return candidates.max { a, b in
            CGPoint.distance(goose, a) < CGPoint.distance(goose, b)
        } ?? CGPoint(x: 80, y: 80)
    }

    /// Converts a SpriteKit scene point (y-up, scene local) to NSScreen global
    /// coordinates that `CGWarpMouseCursorPosition` accepts (y-down origin
    /// at top-left of the main display).
    private func globalScreenPoint(from scenePoint: CGPoint) -> CGPoint {
        guard let screen = NSScreen.main else { return scenePoint }
        return CGPoint(x: scenePoint.x, y: screen.frame.height - scenePoint.y)
    }
}
