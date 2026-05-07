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
    private let fmClient: FoundationModelClient

    init(personality: Personality = .default, fmClient: FoundationModelClient = FoundationModelClient()) {
        self.personality = personality
        self.fmClient = fmClient
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

        // distribution: wander 23%, note 35%, nap 5%, deepSleep 10%, chill 5%, photo 14%, browse 8%
        if roll < 0.23 {
            return GooseDecision(action: .wander)
        } else if roll < 0.58 {
            return await pickNote(bucket: bucket, tone: tone, snapshot: snapshot)
        } else if roll < 0.63 {
            return GooseDecision(action: .nap)
        } else if roll < 0.73 {
            return GooseDecision(action: .deepSleep)
        } else if roll < 0.78 {
            return pickChill(bucket: bucket)
        } else if roll < 0.92 {
            return GooseDecision(action: .photo)
        } else {
            return pickBrowse(bucket: bucket)
        }
    }

    private func pickNote(bucket: Personality.AppBucket, tone: Personality.Tone, snapshot: ContextSnapshot) async -> GooseDecision {
        if let generated = await fmClient.generateNote(systemPrompt: personality.systemPrompt, snapshot: snapshot) {
            return GooseDecision(action: .note, noteTitle: generated.title, noteBody: generated.body)
        }
        let pool = personality.notePool(tone: tone, bucket: bucket)
        let pick = pool.randomElement() ?? ("untitled.txt", "honk")
        return GooseDecision(action: .note, noteTitle: pick.title, noteBody: pick.body)
    }

    private func pickChill(bucket: Personality.AppBucket) -> GooseDecision {
        let mood = Personality.mood(for: bucket)
        let uri = personality.chillPlaylists(mood: mood).randomElement()
        return GooseDecision(action: .chill, spotifyURI: uri)
    }

    private func pickBrowse(bucket: Personality.AppBucket) -> GooseDecision {
        let choices = personality.browseChoices(bucket: bucket)
        guard let pick = choices.randomElement() else {
            return GooseDecision(action: .wander)
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
