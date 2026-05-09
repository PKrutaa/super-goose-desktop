import Foundation

/// A behavior the goose runs each frame. Tasks own their own timing state and
/// drive the simulation by reading/writing fields on `GooseSimulation`.
///
/// `stop(simulation:)` runs when this task is replaced by another via
/// `simulation.setTask(...)` — including external preemption (rage, click,
/// new agent decision). Override it to release any visual state or
/// long-lived effects that wouldn't otherwise auto-clean. Default is a no-op.
@MainActor
protocol GooseTask: AnyObject {
    func start(simulation: GooseSimulation)
    func tick(simulation: GooseSimulation)
    func stop(simulation: GooseSimulation)
}

extension GooseTask {
    func stop(simulation: GooseSimulation) {}
}
