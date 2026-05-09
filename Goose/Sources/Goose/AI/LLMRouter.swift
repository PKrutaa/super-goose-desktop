import Foundation

/// Composes multiple `LLMProvider`s in priority order. Each call walks the
/// provider list trying ready providers in order, returning the first
/// non-nil response. Falls through to nil if all fail — callers must still
/// have a deterministic fallback.
@MainActor
final class LLMRouter: LLMProvider {
    let label: String
    let providers: [LLMProvider]

    init(providers: [LLMProvider]) {
        self.providers = providers
        let names = providers.map { p -> String in
            "\(p.label)[\(p.status.isReady ? "ready" : "unavailable")]"
        }.joined(separator: " → ")
        self.label = "Router(\(names))"
        FileHandle.standardError.write(Data("[Goose] LLMRouter: \(self.label)\n".utf8))
    }

    var status: LLMStatus {
        if providers.contains(where: { $0.status.isReady }) {
            return .ready
        }
        return .unavailable("no provider ready")
    }

    func generateNote(systemPrompt: String, snapshot: ContextSnapshot) async -> GeneratedNote? {
        for provider in providers where provider.status.isReady {
            if let result = await provider.generateNote(systemPrompt: systemPrompt, snapshot: snapshot) {
                return result
            }
        }
        return nil
    }

    func decideChill(systemPrompt: String, snapshot: ContextSnapshot, candidates: [PlaylistCandidate]) async -> ChillDecision? {
        for provider in providers where provider.status.isReady {
            if let result = await provider.decideChill(systemPrompt: systemPrompt, snapshot: snapshot, candidates: candidates) {
                return result
            }
        }
        return nil
    }
}
