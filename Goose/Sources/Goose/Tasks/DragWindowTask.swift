import CoreGraphics
import Foundation

/// Goose runs off-screen, "grabs" a real native window (text or photo), drags
/// it back into view anchored to its beak, and drops it on screen. Replaces
/// the old fake sticky/notepad sprite path entirely — windows here are real
/// `NSWindow` instances dragged by repositioning their frame each frame.
@MainActor
final class DragWindowTask: GooseTask {
    enum Stage {
        case walkingOffscreen
        case draggingIn
    }

    private static let edgeArrivalDistance: CGFloat = 35
    private static let dropArrivalDistance: CGFloat = 35
    private static let mudDuration: CGFloat = 14.0
    private static let walkTimeout: CGFloat = 12.0
    private static let dragTimeout: CGFloat = 14.0

    private let windowFactory: () -> FloatingWindow?
    private weak var effects: GooseSceneEffects?

    private var stage: Stage = .walkingOffscreen
    private var dropTarget: CGPoint = .zero2
    private var stageEndTime: CGFloat = 0
    private var spawned = false

    init(effects: GooseSceneEffects, windowFactory: @escaping @MainActor () -> FloatingWindow?) {
        self.effects = effects
        self.windowFactory = windowFactory
    }

    func start(simulation: GooseSimulation) {
        simulation.setSpeed(.run)
        simulation.trackMudEndTime = max(simulation.trackMudEndTime, GameTime.time + Self.mudDuration)
        simulation.targetPos = pickEdgeTarget(simulation: simulation)
        stage = .walkingOffscreen
        stageEndTime = GameTime.time + Self.walkTimeout
    }

    func tick(simulation: GooseSimulation) {
        switch stage {
        case .walkingOffscreen:
            tickWalkingOffscreen(simulation: simulation)
        case .draggingIn:
            tickDraggingIn(simulation: simulation)
        }
    }

    private func tickWalkingOffscreen(simulation: GooseSimulation) {
        let arrived = CGPoint.distance(simulation.position, simulation.targetPos) < Self.edgeArrivalDistance
        let timedOut = GameTime.time >= stageEndTime
        guard arrived || timedOut else { return }

        guard let window = windowFactory() else {
            simulation.setTask(WanderTask())
            return
        }

        effects?.attachDraggedWindow(window, at: simulation.beakPosition, direction: simulation.direction)
        spawned = true

        dropTarget = pickDropTarget(simulation: simulation, windowSize: window.size)
        simulation.targetPos = dropTarget
        simulation.setSpeed(.run)
        stage = .draggingIn
        stageEndTime = GameTime.time + Self.dragTimeout
    }

    private func tickDraggingIn(simulation: GooseSimulation) {
        if spawned {
            effects?.updateDraggedWindowPosition(simulation.beakPosition, direction: simulation.direction)
        }

        let arrived = CGPoint.distance(simulation.position, dropTarget) < Self.dropArrivalDistance
        let timedOut = GameTime.time >= stageEndTime
        guard arrived || timedOut else { return }

        effects?.detachDraggedWindow()
        simulation.setTask(WanderTask())
    }

    private func pickEdgeTarget(simulation: GooseSimulation) -> CGPoint {
        let s = simulation.screenSize
        let goose = simulation.position
        let toLeft = goose.x
        let toRight = s.width - goose.x
        if toLeft < toRight {
            return CGPoint(x: -80, y: SamMath.lerp(goose.y, s.height / 2, 0.4))
        } else {
            return CGPoint(x: s.width + 80, y: SamMath.lerp(goose.y, s.height / 2, 0.4))
        }
    }

    private func pickDropTarget(simulation: GooseSimulation, windowSize: CGSize) -> CGPoint {
        let s = simulation.screenSize
        let marginX = windowSize.width / 2 + 40
        let marginY = windowSize.height / 2 + 60
        return CGPoint(
            x: SamMath.randomRange(marginX, s.width - marginX),
            y: SamMath.randomRange(marginY, s.height - marginY)
        )
    }
}
