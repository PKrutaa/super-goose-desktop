import Foundation

/// Independent honk cadence — decoupled from the agent decision loop.
///
/// Two parallel tasks:
/// 1. Base ticker: sleeps `Tuning.honkBaseRange`, fires `simulation.onHonk?()`.
/// 2. App-change watcher: polls `perception.lastFrontmostAppName` every 2s; on
///    change, fires a bonus honk if `Tuning.honkAppChangeDebounce` has passed
///    since the last bonus.
///
/// Ownership: caller (typically `GooseScene`) holds an instance and calls
/// `start()` once after wiring `simulation.onHonk`. `stop()` cancels both tasks.
@MainActor
final class HonkTicker {
    private weak var simulation: GooseSimulation?
    private weak var perception: PerceptionEngine?
    private var baseTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private var lastBonusHonk: Date = .distantPast
    private var lastSeenApp: String?

    init(simulation: GooseSimulation, perception: PerceptionEngine) {
        self.simulation = simulation
        self.perception = perception
    }

    func start() {
        stop()
        baseTask = Task { [weak self] in
            while !Task.isCancelled {
                let seconds = Double.random(in: Tuning.honkBaseRange)
                try? await Task.sleep(for: .seconds(seconds))
                if Task.isCancelled { return }
                self?.simulation?.onHonk?()
            }
        }
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                self?.checkAppChange()
            }
        }
    }

    func stop() {
        baseTask?.cancel()
        watchTask?.cancel()
        baseTask = nil
        watchTask = nil
    }

    private func checkAppChange() {
        let current = perception?.lastFrontmostAppName
        defer { lastSeenApp = current }
        guard let current, current != lastSeenApp, lastSeenApp != nil else { return }
        let now = Date()
        guard now.timeIntervalSince(lastBonusHonk) >= Tuning.honkAppChangeDebounce else { return }
        lastBonusHonk = now
        simulation?.onHonk?()
    }
}
