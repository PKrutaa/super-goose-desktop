import Foundation

/// Common surface for LLM-backed decisions. `FoundationModelClient` (on-device
/// Apple Intelligence) and `OpenAIClient` (network, gpt-4o-mini) both
/// implement this; `LLMRouter` composes them in priority order.
@MainActor
protocol LLMProvider: AnyObject {
    var status: LLMStatus { get }
    var label: String { get }

    func generateNote(systemPrompt: String, snapshot: ContextSnapshot) async -> GeneratedNote?
    func decideChill(systemPrompt: String, snapshot: ContextSnapshot, candidates: [PlaylistCandidate]) async -> ChillDecision?
}

enum LLMStatus: Sendable {
    case ready
    case unavailable(String)

    var isReady: Bool { if case .ready = self { return true } else { return false } }
}

struct GeneratedNote: Codable, Sendable {
    let title: String
    let body: String
}

struct ChillDecision: Codable, Sendable {
    let shouldChill: Bool
    let playlistURI: String
    let reason: String
}

struct PlaylistCandidate: Sendable {
    let uri: String
    let mood: String
    let name: String
}
