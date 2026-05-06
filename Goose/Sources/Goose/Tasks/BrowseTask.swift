import AppKit
import Foundation

/// Goose stops, a real `RealBrowserWindow` slides in loading the chosen URL,
/// dwells for `Tuning.browseDwellSeconds`, then dismisses. The goose resumes
/// wandering. The whole flow is a detached async sequence so the simulation
/// tick stays cheap.
@MainActor
final class BrowseTask: GooseTask {
    private let url: URL
    private weak var effects: GooseSceneEffects?
    private var flowTask: Task<Void, Never>?
    private var browser: RealBrowserWindow?

    init(url: URL, effects: GooseSceneEffects) {
        self.url = url
        self.effects = effects
    }

    func start(simulation: GooseSimulation) {
        simulation.velocity = .zero2
        flowTask = Task { [weak self, weak simulation] in
            await self?.runFlow()
            simulation?.setTask(WanderTask())
        }
    }

    func tick(simulation: GooseSimulation) {
        simulation.velocity = .zero2
    }

    private func runFlow() async {
        let window = RealBrowserWindow(url: url)
        self.browser = window
        await window.slideIn()
        try? await Task.sleep(for: .seconds(Tuning.browseDwellSeconds))
        await window.dismiss()
        self.browser = nil
    }
}
