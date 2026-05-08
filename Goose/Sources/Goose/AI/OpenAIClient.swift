import Foundation

/// OpenAI chat-completion client. Opt-in: only `.ready` if an API key is found
/// in `OPENAI_API_KEY` env var or at `~/.config/goose/openai-key`.
///
/// Uses gpt-5-mini with `response_format: json_object` so the model is
/// forced to return strict JSON, which we parse back into typed responses.
///
/// Privacy note: this sends snapshot context (app name, OCR snippets, idle
/// time) to OpenAI servers. Off by default. The on-device Apple Foundation
/// Models path is preferred when available.
@MainActor
final class OpenAIClient: LLMProvider {
    static let model = "gpt-5-mini"
    static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    // gpt-5 family is a reasoning model — generation takes longer than 4o
    // because it spends tokens on internal reasoning before emitting the
    // final answer. 30s is generous; the goose can wait.
    static let timeoutSeconds: TimeInterval = 30

    let label = "OpenAI(gpt-5-mini)"
    private(set) var status: LLMStatus
    private let apiKey: String?

    init() {
        let key = Self.resolveAPIKey()
        self.apiKey = key
        if let key, !key.isEmpty {
            self.status = .ready
            FileHandle.standardError.write(Data("[Goose] OpenAIClient: ready (key=...\(key.suffix(4)))\n".utf8))
        } else {
            self.status = .unavailable("no API key (set OPENAI_API_KEY or ~/.config/goose/openai-key)")
            FileHandle.standardError.write(Data("[Goose] OpenAIClient: unavailable — no API key\n".utf8))
        }
    }

    // MARK: - LLMProvider

    func generateNote(systemPrompt: String, snapshot: ContextSnapshot) async -> GeneratedNote? {
        guard case .ready = status else { return nil }
        let user = OpenAIClient.notePrompt(snapshot: snapshot)
        guard let raw = await call(systemPrompt: systemPrompt + " Respond with strict JSON only.", userPrompt: user) else {
            return nil
        }
        return Self.decode(GeneratedNote.self, from: raw)
    }

    func decideChill(systemPrompt: String, snapshot: ContextSnapshot, candidates: [PlaylistCandidate]) async -> ChillDecision? {
        guard case .ready = status else { return nil }
        let user = OpenAIClient.chillPrompt(snapshot: snapshot, candidates: candidates)
        guard let raw = await call(systemPrompt: systemPrompt + " Respond with strict JSON only.", userPrompt: user) else {
            return nil
        }
        guard let decision = Self.decode(ChillDecision.self, from: raw) else { return nil }
        guard candidates.contains(where: { $0.uri == decision.playlistURI }) else {
            FileHandle.standardError.write(Data("[Goose] OpenAI picked unknown URI \(decision.playlistURI), discarding\n".utf8))
            return nil
        }
        return decision
    }

    // MARK: - HTTP

    private func call(systemPrompt: String, userPrompt: String) async -> String? {
        guard let apiKey else { return nil }

        // gpt-5 family: temperature is locked to default and `max_tokens` is
        // replaced by `max_completion_tokens`. Set reasoning_effort: "low" so
        // the model doesn't burn 30s thinking about a sticky note.
        // The token budget covers both reasoning + final JSON.
        let body: [String: Any] = [
            "model": Self.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
            "response_format": ["type": "json_object"],
            "max_completion_tokens": 1500,
            "reasoning_effort": "low",
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let snippet = String(data: data.prefix(200), encoding: .utf8) ?? "<unreadable>"
                FileHandle.standardError.write(Data("[Goose] OpenAI HTTP \(http.statusCode): \(snippet)\n".utf8))
                return nil
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                FileHandle.standardError.write(Data("[Goose] OpenAI: unexpected response shape\n".utf8))
                return nil
            }
            return content
        } catch {
            FileHandle.standardError.write(Data("[Goose] OpenAI request failed: \(error)\n".utf8))
            return nil
        }
    }

    // MARK: - Key resolution

    private static func resolveAPIKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".config/goose/openai-key"),
            home.appendingPathComponent(".goose/openai-key"),
        ]
        for url in candidates {
            if let data = try? String(contentsOf: url, encoding: .utf8) {
                let trimmed = data.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    // MARK: - Prompts (mirrors FoundationModelClient.style for consistency)

    private static func notePrompt(snapshot: ContextSnapshot) -> String {
        let context = contextLine(snapshot: snapshot)
        return """
        \(context)

        Write a short opinionated sticky note from a sarcastic-cynical desktop goose
        about what the user is doing right now. Title is a filename like "untitled.txt"
        or "todo.md" or "honk.txt" (be creative — it's a goose). Body is 2-4 lines max,
        lower case, no emojis, no exclamation points except 'honk'. Be specific to the
        context — reference the app, the OCR, the idle time. The goose is feral,
        observant, and dry. Vary your output every time — never repeat past notes.

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

        Decide whether the goose should put on headphones and slam music for the user
        RIGHT NOW. Every option is loud — there is no chill. Default to YES unless the
        user is mid-call or recording. Pick whichever vibe most disrupts the user's task.
        Be unpredictable — don't always pick the same playlist.

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

    // MARK: - JSON decode

    private static func decode<T: Decodable>(_ type: T.Type, from raw: String) -> T? {
        let cleaned = stripJSONFences(raw)
        guard let data = cleaned.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

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
