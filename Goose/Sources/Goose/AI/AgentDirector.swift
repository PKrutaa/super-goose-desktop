import AppKit
import Foundation

/// Closes the loop between perception and brain: every N seconds, snapshots
/// the user's screen, asks the brain what the goose should do next, and
/// drives the corresponding task on the simulation.
@MainActor
final class AgentDirector {
    private static let firstTickDelay: Duration = .seconds(5)
    private static let recentActionsCap = 4

    private let perception: PerceptionEngine
    private let brain: GooseBrain
    private weak var simulation: GooseSimulation?
    private weak var effects: GooseSceneEffects?

    private var recentActions: [String] = []
    private var loopTask: Task<Void, Never>?

    init(simulation: GooseSimulation, effects: GooseSceneEffects, perception: PerceptionEngine, brain: GooseBrain) {
        self.perception = perception
        self.brain = brain
        self.simulation = simulation
        self.effects = effects
    }

    func start() {
        FileHandle.standardError.write(Data("AgentDirector: brain ready, starting loop\n".utf8))
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            try? await Task.sleep(for: Self.firstTickDelay)
            await self?.loop()
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    private func loop() async {
        while !Task.isCancelled {
            await tick()
            let seconds = Double.random(in: Tuning.agentLoopRange)
            try? await Task.sleep(for: .seconds(seconds))
        }
    }

    private func tick() async {
        if MoodStore.current == .disabled { return }
        let snapshot = await perception.captureSnapshot() ?? ContextSnapshot.empty()
        guard let decision = await brain.decide(snapshot: snapshot, recentActions: recentActions) else { return }
        execute(decision: decision)
        recentActions.append(decision.action.rawValue)
        if recentActions.count > Self.recentActionsCap {
            recentActions.removeFirst()
        }
    }

    private func execute(decision: GooseDecision) {
        guard let simulation, let effects else { return }
        switch decision.action {
        case .wander:
            return
        case .nap:
            simulation.setTask(NapTask())
        case .deepSleep:
            simulation.setTask(DeepSleepTask())
        case .note:
            let title = decision.noteTitle.isEmpty ? "untitled.txt" : decision.noteTitle
            let body = decision.noteBody.isEmpty ? "honk" : decision.noteBody
            simulation.setTask(DragWindowTask(effects: effects) {
                FloatingWindow.note(title: title, body: body)
            })
        case .photo:
            simulation.setTask(DragWindowTask(effects: effects) {
                guard let pick = PhotoLibrary.randomImage() else {
                    FileHandle.standardError.write(Data("AgentDirector: no photos found in \(PhotoLibrary.directory().path) — skipping\n".utf8))
                    return nil
                }
                return FloatingWindow.photo(image: pick.image, title: pick.name)
            })
        case .browse:
            guard let url = decision.browseURL else { return }
            simulation.setTask(BrowseTask(url: url, effects: effects))
        case .chill:
            simulation.setTask(ChillingTask(spotifyURI: decision.spotifyURI, effects: effects))
        }
    }
}
