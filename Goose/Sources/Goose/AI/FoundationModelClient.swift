import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device LLM wrapper. Wires `LanguageModelSession` from `FoundationModels`
/// when the SDK is available and the user has Apple Intelligence enabled;
/// falls back to `nil` returns otherwise so callers can use deterministic
/// fallbacks.
///
/// We deliberately avoid `@Generable` macros (per the comment in
/// `GooseAction.swift` they hung the build for 7+ minutes). Instead we ask
/// the model for strict JSON and decode with `JSONDecoder`.
@MainActor
final class FoundationModelClient {
    enum Status: Sendable {
        case ready
        case unavailable(String)
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

    private(set) var status: Status
    private var consecutiveAssetFailures = 0
    private static let assetFailureThreshold = 2

    init() {
        self.status = Self.computeStatus()
        switch self.status {
        case .ready:
            FileHandle.standardError.write(Data("[Goose] FoundationModelClient: ready\n".utf8))
        case .unavailable(let reason):
            FileHandle.standardError.write(Data("[Goose] FoundationModelClient: unavailable (\(reason))\n".utf8))
        }
    }

    // MARK: - Public API

    func generateNote(systemPrompt: String, snapshot: ContextSnapshot) async -> GeneratedNote? {
        guard case .ready = status else { return nil }
        let user = Self.notePrompt(snapshot: snapshot)
        let raw = await runWithTimeout(seconds: Tuning.fmTimeoutSeconds) {
            await self.callJSON(systemPrompt: systemPrompt, prompt: user)
        }
        return Self.decode(GeneratedNote.self, from: raw)
    }

    func decideChill(systemPrompt: String, snapshot: ContextSnapshot, candidates: [PlaylistCandidate]) async -> ChillDecision? {
        guard case .ready = status else { return nil }
        let user = Self.chillPrompt(snapshot: snapshot, candidates: candidates)
        let raw = await runWithTimeout(seconds: Tuning.fmTimeoutSeconds) {
            await self.callJSON(systemPrompt: systemPrompt, prompt: user)
        }
        guard let decision = Self.decode(ChillDecision.self, from: raw) else { return nil }
        // Validate that the model picked one of the candidate URIs.
        guard candidates.contains(where: { $0.uri == decision.playlistURI }) else {
            FileHandle.standardError.write(Data("[Goose] FM picked unknown URI \(decision.playlistURI), discarding\n".utf8))
            return nil
        }
        return decision
    }

    // MARK: - LLM call

    private func callJSON(systemPrompt: String, prompt: String) async -> String? {
        #if canImport(FoundationModels)
        do {
            let instructions = systemPrompt + "\n\nWhen asked to make a decision, respond with strict JSON only. No prose, no markdown fences, no commentary."
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            consecutiveAssetFailures = 0
            return Self.extractText(from: response)
        } catch {
            let desc = "\(error)"
            FileHandle.standardError.write(Data("[Goose] FM call failed: \(desc)\n".utf8))
            if desc.contains("assetsUnavailable") || desc.contains("Model is unavailable") {
                consecutiveAssetFailures += 1
                if consecutiveAssetFailures >= Self.assetFailureThreshold {
                    status = .unavailable("model assets unavailable — using deterministic fallback")
                    FileHandle.standardError.write(Data("[Goose] FoundationModelClient: downgraded to unavailable after \(consecutiveAssetFailures) asset failures\n".utf8))
                }
            }
            return nil
        }
        #else
        _ = systemPrompt
        _ = prompt
        return nil
        #endif
    }

    #if canImport(FoundationModels)
    /// Pulls the text out of whatever shape `respond(to:)` returned. Handles
    /// the common `Response<String>` shape where `.content` is the answer.
    private static func extractText(from response: Any) -> String? {
        let mirror = Mirror(reflecting: response)
        for child in mirror.children where child.label == "content" {
            if let s = child.value as? String { return s }
        }
        if let s = response as? String { return s }
        return String(describing: response)
    }
    #endif

    // MARK: - Status

    private static func computeStatus() -> Status {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return .ready
        case .unavailable(let reason):
            return .unavailable("\(reason)")
        @unknown default:
            return .unavailable("unknown availability")
        }
        #else
        return .unavailable("FoundationModels SDK not available in this toolchain")
        #endif
    }

    // MARK: - Prompts

    private static func notePrompt(snapshot: ContextSnapshot) -> String {
        let context = contextLine(snapshot: snapshot)
        return """
        \(context)

        Write a short opinionated sticky note for the user about what they're doing right now.
        Title is a filename like "untitled.txt" or "todo.md". Body is 2-4 lines max, lower case, no emojis.

        Respond with strict JSON only:
        {"title": "<filename>", "body": "<note body, can have \\n>"}
        """
    }

    private static func chillPrompt(snapshot: ContextSnapshot, candidates: [PlaylistCandidate]) -> String {
        let context = contextLine(snapshot: snapshot)
        let candidateList = candidates.map { "- \($0.uri) (\($0.name) — \($0.mood))" }.joined(separator: "\n")
        return """
        \(context)

        candidate playlists (all heavy — metal, punk, grunge):
        \(candidateList)

        Decide whether the goose should put on headphones and slam music for the user RIGHT NOW.
        The goose is feral. Every option is loud — there is no chill. Strongly default to YES
        unless the user is clearly mid-call or recording. Pick whichever vibe most disrupts the
        user's task: emails → death metal, coding → punk, browsing → grunge, etc. The goose
        loves antagonizing the soundtrack.

        Respond with strict JSON only. The playlistURI MUST be exactly one of the candidates above.
        {"shouldChill": <true|false>, "playlistURI": "<one of the candidate URIs>", "reason": "<one short phrase>"}
        """
    }

    private static func contextLine(snapshot: ContextSnapshot) -> String {
        let app = snapshot.frontmostAppName ?? "unknown"
        let prev = snapshot.prevFrontmostAppName ?? "none"
        let time = Int(snapshot.elapsedOnApp)
        let idle = Int(snapshot.idleSeconds)
        let ocr = snapshot.ocrTopK.joined(separator: "; ")
        let raw = "context: app=\(app) | timeOnApp=\(time)s | prev=\(prev) | idle=\(idle)s | ocr=[\(ocr)]"
        return String(raw.prefix(500))
    }

    // MARK: - JSON decoding

    private static func decode<T: Decodable>(_ type: T.Type, from raw: String?) -> T? {
        guard let raw else { return nil }
        let cleaned = stripJSONFences(raw)
        guard let data = cleaned.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Models sometimes wrap JSON in ```json ... ``` despite instructions.
    /// Strip the fences and surrounding whitespace.
    private static func stripJSONFences(_ s: String) -> String {
        var out = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.hasPrefix("```") {
            if let firstNewline = out.firstIndex(of: "\n") {
                out = String(out[out.index(after: firstNewline)...])
            }
            if out.hasSuffix("```") {
                out = String(out.dropLast(3))
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Run `op` and return its result, or nil if it doesn't finish in `seconds`.
@MainActor
private func runWithTimeout<T: Sendable>(seconds: TimeInterval, op: @escaping @Sendable () async -> T?) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await op() }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first ?? nil
    }
}
