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
    private let fmClient: FoundationModelClient

    private var baseTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private var lastBonus: Date = .distantPast
    private var lastChillStarted: Date = .distantPast
    private var lastSeenApp: String?

    init(simulation: GooseSimulation,
         perception: PerceptionEngine,
         effects: GooseSceneEffects,
         personality: Personality,
         fmClient: FoundationModelClient) {
        self.simulation = simulation
        self.perception = perception
        self.effects = effects
        self.personality = personality
        self.fmClient = fmClient
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
        if isBusy(simulation: simulation) { return }

        // Cooldown: don't fire a new chill right after one ended/started, so
        // we don't cut songs short with a fresh playlist.
        let sinceLastChill = Date().timeIntervalSince(lastChillStarted)
        if sinceLastChill < Self.postChillCooldown {
            FileHandle.standardError.write(Data("[Goose] ChillingTicker(\(reason)): cooldown — \(Int(sinceLastChill))s since last chill, need \(Int(Self.postChillCooldown))s\n".utf8))
            return
        }

        let snapshot = await perception?.captureSnapshot() ?? ContextSnapshot.empty()
        let bucket = Personality.bucket(for: snapshot.frontmostAppName)

        let candidates = allCandidates()

        if let decision = await fmClient.decideChill(
            systemPrompt: personality.systemPrompt,
            snapshot: snapshot,
            candidates: candidates
        ) {
            FileHandle.standardError.write(Data("[Goose] ChillingTicker(\(reason)): FM \(decision.shouldChill ? "yes" : "no"): \(decision.reason)\n".utf8))
            if decision.shouldChill {
                lastChillStarted = Date()
                simulation.setTask(ChillingTask(spotifyURI: decision.playlistURI, effects: effects))
            }
            return
        }

        // Fallback: deterministic context-aware
        guard Double.random(in: 0..<1) < Self.fallbackChillProbability else {
            FileHandle.standardError.write(Data("[Goose] ChillingTicker(\(reason)): fallback rolled no-chill\n".utf8))
            return
        }
        let mood = Personality.mood(for: bucket)
        let uri = personality.chillPlaylists(mood: mood).randomElement()
        FileHandle.standardError.write(Data("[Goose] ChillingTicker(\(reason)): fallback chill mood=\(mood)\n".utf8))
        lastChillStarted = Date()
        simulation.setTask(ChillingTask(spotifyURI: uri, effects: effects))
    }

    private func isBusy(simulation: GooseSimulation) -> Bool {
        guard let task = simulation.currentTask else { return false }
        return task is ChillingTask || task is DeepSleepTask || task is DragWindowTask || task is BrowseTask || task is NabMouseTask
    }

    private func allCandidates() -> [FoundationModelClient.PlaylistCandidate] {
        let moods: [(Personality.Mood, String)] = [
            (.punk, "punk"),
            (.metal, "metal"),
            (.chaos, "chaos"),
        ]
        var out: [FoundationModelClient.PlaylistCandidate] = []
        for (mood, label) in moods {
            for uri in personality.chillPlaylists(mood: mood) {
                out.append(.init(uri: uri, mood: label, name: friendlyName(for: uri)))
            }
        }
        return out
    }

    private func friendlyName(for uri: String) -> String {
        switch uri {
        case "spotify:playlist:37i9dQZF1DXa9wYJr1oMFq": return "Punk"
        case "spotify:playlist:37i9dQZF1DX1spT6G94GFC": return "Pop Punk Powerhouses"
        case "spotify:playlist:37i9dQZF1DWWMOmoXKqHTD": return "Punk Unleashed"
        case "spotify:playlist:37i9dQZF1DWXIcbzpLauPS": return "Metal"
        case "spotify:playlist:37i9dQZF1DWWOmm0DtxLLR": return "Kickass Metal"
        case "spotify:playlist:37i9dQZF1DX9qNs32fujYe": return "New Metal Tracks"
        case "spotify:playlist:37i9dQZF1DXcfZ6moR6J0G": return "The Heaviest"
        case "spotify:playlist:37i9dQZF1DWY4lFlS4Pnso": return "Grunge Forever"
        case "spotify:playlist:37i9dQZF1DXdzhNPybPCRX": return "Modern Rock Hits"
        default: return uri
        }
    }
}
