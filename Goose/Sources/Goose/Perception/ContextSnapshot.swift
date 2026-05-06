import Foundation

/// Immutable snapshot of what the goose perceived at a single moment. Produced
/// by `PerceptionEngine` and consumed by the AI brain to decide how the goose
/// should react to what the user is doing.
struct ContextSnapshot: Sendable, Equatable {
    let timestamp: Date
    let frontmostAppName: String?
    let frontmostWindowTitle: String?
    /// OCR fragments joined into a single normalized string (lowercased, trimmed).
    let ocrText: String
    /// Up to 3 distinct OCR substrings, each clamped at 80 chars. Cheap input
    /// for the brain that filters out the noisiest parts of `ocrText`.
    let ocrTopK: [String]
    /// Seconds the user has been continuously on `frontmostAppName`.
    let elapsedOnApp: TimeInterval
    /// The app the user was on immediately before `frontmostAppName`, if known.
    let prevFrontmostAppName: String?
    /// Seconds since the user's last input event (mouse or keyboard).
    let idleSeconds: TimeInterval
    /// Stable hash of `ocrText` used to dedup back-to-back identical snapshots.
    let textHash: Int

    /// Placeholder used when both screen capture and AX probing failed; lets
    /// the brain still tick instead of silently doing nothing.
    static func empty() -> ContextSnapshot {
        ContextSnapshot(
            timestamp: Date(),
            frontmostAppName: nil,
            frontmostWindowTitle: nil,
            ocrText: "",
            ocrTopK: [],
            elapsedOnApp: 0,
            prevFrontmostAppName: nil,
            idleSeconds: 0,
            textHash: 0
        )
    }
}
