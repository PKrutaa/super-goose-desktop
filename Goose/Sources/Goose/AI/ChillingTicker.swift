import Foundation

/// Independent chill cadence — decoupled from the agent decision loop.
///
/// Two parallel tasks:
/// 1. Base ticker: sleeps 90–180s, then evaluates whether to chill.
/// 2. App-change watcher: polls `perception.lastFrontmostAppName` every 3s; on
///    change with ≥60s since last bonus, evaluates an extra chill opportunity.
///
/// On each tick:
/// - If the goose is already on a long-running task (chill, deep sleep, drag),
///   skip.
/// - Try `FoundationModelClient.decideChill` — pass in a candidate URI list,
///   let the on-device LLM pick the right playlist for the current context.
/// - If FM unavailable or returns nil, fall back: 60% chance, mood from
///   `Personality.mood(for:)`, random URI from that mood's pool.
///
/// Ownership: caller (typically `GooseScene`) holds an instance and calls
/// `start()` after wiring the simulation. `stop()` cancels both tasks.
@MainActor
final class ChillingTicker {
    // Slow enough that two chills in a row aren't back-to-back music interruptions.
    // Combined with ChillingTask's 180–300s duration, this gives the user breathing
    // room between sessions.
    private static let baseRange: ClosedRange<TimeInterval> = 240...480
    private static let appChangeDebounce: TimeInterval = 180
    private static let fallbackChillProbability: Double = 0.55
    private static let postChillCooldown: TimeInterval = 120

    private weak var simulation: GooseSimulation?
    private weak var perception: PerceptionEngine?
    private weak var effects: GooseSceneEffects?
    private let personality: Personality
    private let llm: LLMProvider

    private var baseTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private var lastBonus: Date = .distantPast
    private var lastChillEnded: Date = .distantPast
    private var wasChilling = false
    private var lastSeenApp: String?
    private var recentURIs: [String] = []
    private static let recentURICap = 3

    init(simulation: GooseSimulation,
         perception: PerceptionEngine,
         effects: GooseSceneEffects,
         personality: Personality,
         llm: LLMProvider) {
        self.simulation = simulation
        self.perception = perception
        self.effects = effects
        self.personality = personality
        self.llm = llm
    }

    func start() {
        stop()
        baseTask = Task { [weak self] in
            while !Task.isCancelled {
                let seconds = Double.random(in: Self.baseRange)
                try? await Task.sleep(for: .seconds(seconds))
                if Task.isCancelled { return }
                await self?.tickOnce(reason: "base")
            }
        }
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { return }
                await self?.checkAppChange()
            }
        }
    }

    func stop() {
        baseTask?.cancel()
        watchTask?.cancel()
        baseTask = nil
        watchTask = nil
    }

    private func checkAppChange() async {
        if let sim = simulation {
            updateChillTracking(simulation: sim)
        }
        let current = perception?.lastFrontmostAppName
        defer { lastSeenApp = current }
        guard let current, current != lastSeenApp, lastSeenApp != nil else { return }
        let now = Date()
        guard now.timeIntervalSince(lastBonus) >= Self.appChangeDebounce else { return }
        lastBonus = now
        await tickOnce(reason: "app-change")
    }

    private func tickOnce(reason: String) async {
        guard let simulation, let effects else { return }
        updateChillTracking(simulation: simulation)
        if isBusy(simulation: simulation) { return }

        // Cooldown is measured from when the previous chill *ended*, not when
        // it started — chill duration (180–300s) is longer than the cooldown
        // (120s), so basing on "started" would expire mid-chill and let an
        // app-change trigger a back-to-back chill seconds after exit.
        let sinceLastEnd = Date().timeIntervalSince(lastChillEnded)
        if sinceLastEnd < Self.postChillCooldown {
            FileHandle.standardError.write(Data("[Goose] ChillingTicker(\(reason)): cooldown — \(Int(sinceLastEnd))s since chill ended, need \(Int(Self.postChillCooldown))s\n".utf8))
            return
        }

        let snapshot = await perception?.captureSnapshot() ?? ContextSnapshot.empty()
        let allCands = allCandidates()
        let candidates: [PlaylistCandidate] = {
            let fresh = allCands.filter { !recentURIs.contains($0.uri) }
            return fresh.isEmpty ? allCands : fresh
        }()

        if let decision = await llm.decideChill(
            systemPrompt: personality.systemPrompt,
            snapshot: snapshot,
            candidates: candidates
        ) {
            FileHandle.standardError.write(Data("[Goose] ChillingTicker(\(reason)): LLM \(decision.shouldChill ? "yes" : "no"): \(decision.reason)\n".utf8))
            if decision.shouldChill {
                rememberURI(decision.playlistURI)
                simulation.setTask(ChillingTask(spotifyURI: decision.playlistURI, effects: effects))
                wasChilling = true
            }
            return
        }

        guard Double.random(in: 0..<1) < Self.fallbackChillProbability else {
            FileHandle.standardError.write(Data("[Goose] ChillingTicker(\(reason)): fallback rolled no-chill\n".utf8))
            return
        }
        let pick = candidates.randomElement()
        FileHandle.standardError.write(Data("[Goose] ChillingTicker(\(reason)): fallback chill \(pick?.name ?? "?")\n".utf8))
        if let uri = pick?.uri { rememberURI(uri) }
        simulation.setTask(ChillingTask(spotifyURI: pick?.uri, effects: effects))
        wasChilling = true
    }

    /// Track when the previous chill ended so the cooldown is measured from
    /// the right baseline. Polled from `tickOnce` and `checkAppChange`.
    private func updateChillTracking(simulation: GooseSimulation) {
        let currentlyChilling = simulation.currentTask is ChillingTask
        if wasChilling && !currentlyChilling {
            lastChillEnded = Date()
        }
        wasChilling = currentlyChilling
    }

    private func rememberURI(_ uri: String) {
        recentURIs.append(uri)
        if recentURIs.count > Self.recentURICap {
            recentURIs.removeFirst()
        }
    }

    private func isBusy(simulation: GooseSimulation) -> Bool {
        guard let task = simulation.currentTask else { return false }
        return task is ChillingTask || task is DeepSleepTask || task is DragWindowTask || task is BrowseTask || task is NabMouseTask
    }

    private func allCandidates() -> [PlaylistCandidate] {
        personality.metalPlaylists().map {
            PlaylistCandidate(uri: $0.uri, mood: $0.vibe, name: $0.name)
        }
    }
}
