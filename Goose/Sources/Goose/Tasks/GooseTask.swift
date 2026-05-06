import Foundation

/// A behavior the goose runs each frame. Tasks own their own timing state and
/// drive the simulation by reading/writing fields on `GooseSimulation`.
@MainActor
protocol GooseTask: AnyObject {
    func start(simulation: GooseSimulation)
    func tick(simulation: GooseSimulation)
}
