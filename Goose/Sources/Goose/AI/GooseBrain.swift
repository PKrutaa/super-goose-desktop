import Foundation

/// Hybrid brain. Roulette over actions for everything except `.note`, which
/// tries Foundation Models with a deterministic fallback.
///
/// Honks are NOT in this distribution — `HonkTicker` owns honk cadence.
@MainActor
final class GooseBrain {
    enum Status: Sendable {
        case ready
        case unavailable(String)
    }

    private let personality: Personality
    private let llm: LLMProvider
    private var recentNoteTitles: [String] = []
    private static let recentNoteCap = 5

    init(personality: Personality = .default, llm: LLMProvider = FoundationModelClient()) {
        self.personality = personality
        self.llm = llm
    }

    /// Brain is always ready — the FM-unavailability case is handled by falling
    /// back to deterministic pools. Read `fmClient.status` for FM diagnostics.
    var status: Status { .ready }

    /// Returns a decision, or nil only if `recentActions` filtering rejected
    /// every reroll (extremely unlikely — we cap retries at 3).
    func decide(snapshot: ContextSnapshot, recentActions: [String]) async -> GooseDecision? {
        for _ in 0..<3 {
            if let candidate = await rollOnce(snapshot: snapshot) {
                let key = summary(of: candidate)
                if recentActions.last == key { continue }
                return candidate
            }
        }
        return await rollOnce(snapshot: snapshot)
    }

    private func rollOnce(snapshot: ContextSnapshot) async -> GooseDecision? {
        let bucket = Personality.bucket(for: snapshot.frontmostAppName)
        let tone = Personality.tone(forTimeOnApp: snapshot.elapsedOnApp, idle: snapshot.idleSeconds)
        let roll = Double.random(in: 0..<1)

        // distribution: wander 35%, note 35%, nap 5%, deepSleep 9%, photo 8%, browse 8%
        // (chill is owned exclusively by ChillingTicker — keeps brain from
        // fighting the ticker's cooldown and cutting songs short)
        if roll < 0.35 {
            return GooseDecision(action: .wander)
        } else if roll < 0.70 {
            return await pickNote(bucket: bucket, tone: tone, snapshot: snapshot)
        } else if roll < 0.75 {
            return GooseDecision(action: .nap)
        } else if roll < 0.84 {
            return GooseDecision(action: .deepSleep)
        } else if roll < 0.92 {
            return GooseDecision(action: .photo)
        } else {
            return pickBrowse(bucket: bucket)
        }
    }

    private func pickNote(bucket: Personality.AppBucket, tone: Personality.Tone, snapshot: ContextSnapshot) async -> GooseDecision {
        if let generated = await llm.generateNote(systemPrompt: personality.systemPrompt, snapshot: snapshot) {
            rememberNote(title: generated.title)
            return GooseDecision(action: .note, noteTitle: generated.title, noteBody: generated.body)
        }
        let pool = personality.notePool(tone: tone, bucket: bucket)
        // Anti-repetition: prefer entries not in the recent ring buffer.
        let fresh = pool.filter { !recentNoteTitles.contains($0.title) }
        let candidates = fresh.isEmpty ? pool : fresh
        let pick = candidates.randomElement() ?? ("untitled.txt", "honk")
        rememberNote(title: pick.title)
        return GooseDecision(action: .note, noteTitle: pick.title, noteBody: pick.body)
    }

    private func rememberNote(title: String) {
        recentNoteTitles.append(title)
        if recentNoteTitles.count > Self.recentNoteCap {
            recentNoteTitles.removeFirst()
        }
    }

    private var recentBrowseURLs: [String] = []

    private func pickBrowse(bucket: Personality.AppBucket) -> GooseDecision {
        let choices = personality.browseChoices(bucket: bucket)
        let fresh = choices.filter { !recentBrowseURLs.contains($0.url.absoluteString) }
        let candidates = fresh.isEmpty ? choices : fresh
        guard let pick = candidates.randomElement() else {
            return GooseDecision(action: .wander)
        }
        recentBrowseURLs.append(pick.url.absoluteString)
        if recentBrowseURLs.count > Self.recentNoteCap {
            recentBrowseURLs.removeFirst()
        }
        return GooseDecision(action: .browse, browseURL: pick.url)
    }

    private func summary(of decision: GooseDecision) -> String {
        switch decision.action {
        case .wander: return "wander"
        case .nap: return "nap"
        case .deepSleep: return "deepSleep"
        case .note: return "note(\(decision.noteTitle.prefix(30)))"
        case .photo: return "photo"
        case .browse: return "browse(\(decision.browseURL?.absoluteString.prefix(40) ?? ""))"
        case .chill: return "chill(\(decision.spotifyURI?.suffix(20) ?? ""))"
        }
    }
}
