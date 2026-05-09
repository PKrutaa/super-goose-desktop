import AppKit
import CoreGraphics
import Foundation

/// Long sleep state. Unlike the short `NapTask` (4–9s, no wake mechanic),
/// the goose stays still for 30–90s and watches for the user. If the cursor
/// approaches within 80px or the user clicks nearby, it wakes up angry and
/// chases the mouse via `NabMouseTask`.
@MainActor
final class DeepSleepTask: GooseTask {
    private static let minDuration: CGFloat = 30
    private static let maxDuration: CGFloat = 90
    private static let wakeRadius: CGFloat = 80

    private var endTime: CGFloat = 0
    private var initialMousePosition: CGPoint = .zero2
    private var hasMouseMoved = false
    private var lastLeftMouseDown = false

    func start(simulation: GooseSimulation) {
        simulation.velocity = .zero2
        simulation.targetPos = simulation.position
        let duration = SamMath.randomRange(Self.minDuration, Self.maxDuration)
        endTime = GameTime.time + duration
        initialMousePosition = NSEvent.mouseLocation
        hasMouseMoved = false
        lastLeftMouseDown = NSEvent.pressedMouseButtons & 1 != 0
    }

    func tick(simulation: GooseSimulation) {
        simulation.velocity = .zero2
        simulation.targetPos = simulation.position

        let mouse = NSEvent.mouseLocation
        let goose = simulation.position
        let distance = CGPoint.distance(mouse, goose)

        if !hasMouseMoved && CGPoint.distance(mouse, initialMousePosition) > 4 {
            hasMouseMoved = true
        }

        let leftPressed = NSEvent.pressedMouseButtons & 1 != 0
        let clickRisingEdge = leftPressed && !lastLeftMouseDown
        lastLeftMouseDown = leftPressed

        let proximityWake = hasMouseMoved && distance <= Self.wakeRadius
        let pokeWake = clickRisingEdge && distance <= Self.wakeRadius

        if proximityWake || pokeWake {
            simulation.onHonk?()
            simulation.setTask(NabMouseTask())
            return
        }

        if GameTime.time >= endTime {
            simulation.setTask(WanderTask())
        }
    }
}
