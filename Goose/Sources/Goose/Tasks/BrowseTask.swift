import Foundation

/// STUB — full implementation lands in Task 11. This exists so the build
/// passes for the intermediate `--brain-dryrun` task.
@MainActor
final class BrowseTask: GooseTask {
    init(url: URL, effects: GooseSceneEffects) {
        _ = url
        _ = effects
    }

    func start(simulation: GooseSimulation) {
        simulation.setTask(WanderTask())
    }

    func tick(simulation: GooseSimulation) {}
}
