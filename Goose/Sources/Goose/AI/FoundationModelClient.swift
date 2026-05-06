import Foundation

/// Wrapper around Apple Foundation Models for generating opinionated notes.
///
/// Currently ships with `status == .unavailable("not yet wired")`. The seam
/// for the real call is marked below. `GooseBrain` is built to handle a
/// `nil` return, so the deterministic fallback runs unchanged. When ready,
/// implement the body inside the `#if canImport(FoundationModels)` block:
///
/// ```swift
/// import FoundationModels
/// let session = LanguageModelSession(instructions: systemPrompt)
/// let response = try await session.respond(to: contextString, generating: GeneratedNote.self)
/// return response.content
/// ```
///
/// All inference runs on-device. Never makes a network call.
@MainActor
final class FoundationModelClient {
    enum Status: Sendable {
        case ready
        case unavailable(String)
    }

    struct GeneratedNote: Sendable {
        let title: String
        let body: String
    }

    private(set) var status: Status

    init() {
        #if canImport(FoundationModels)
        self.status = .unavailable("not yet wired — see FoundationModelClient.swift")
        #else
        self.status = .unavailable("FoundationModels SDK not available in this toolchain")
        #endif
    }

    /// Returns nil on timeout (`Tuning.fmTimeoutSeconds`), unavailability, or
    /// any generation error. Callers MUST have a deterministic fallback ready.
    func generateNote(systemPrompt: String, snapshot: ContextSnapshot) async -> GeneratedNote? {
        guard case .ready = status else { return nil }

        let contextString = Self.buildContext(snapshot: snapshot)
        return await withTimeout(seconds: Tuning.fmTimeoutSeconds) {
            await Self.callModel(systemPrompt: systemPrompt, context: contextString)
        }
    }

    private static func callModel(systemPrompt: String, context: String) async -> GeneratedNote? {
        // SEAM: when ready, replace the `return nil` below with the real call.
        // Keep this function pure: build the request, await, return content,
        // catch errors → nil. Do not throw out of here.
        _ = systemPrompt
        _ = context
        return nil
    }

    private static func buildContext(snapshot: ContextSnapshot) -> String {
        let app = snapshot.frontmostAppName ?? "unknown"
        let prev = snapshot.prevFrontmostAppName ?? "none"
        let time = Int(snapshot.elapsedOnApp)
        let idle = Int(snapshot.idleSeconds)
        let ocr = snapshot.ocrTopK.joined(separator: "; ")
        let raw = "app=\(app) | timeOnApp=\(time)s | prev=\(prev) | idle=\(idle)s | ocr=[\(ocr)]"
        return String(raw.prefix(500))
    }
}

/// Run `op` and return its result, or nil if it doesn't finish in `seconds`.
@MainActor
private func withTimeout<T: Sendable>(seconds: TimeInterval, op: @escaping @Sendable () async -> T?) async -> T? {
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
