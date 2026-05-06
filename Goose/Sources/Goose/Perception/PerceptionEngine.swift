import CoreGraphics
import Foundation

/// Tiny stderr logger shared across the Perception layer. We deliberately avoid
/// `OSLog` so warnings show up in the terminal when the app is run from a
/// shell — the AI brain (and the developer) can scan stderr for permission
/// problems without opening Console.app.
enum PerceptionLog {
    static func warn(_ message: String) {
        let line = "[Goose] " + message + "\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}

/// Top-level orchestrator for the Perception layer. Glues together
/// `ScreenCapturer` (eyes), `OCRRecognizer` (reading), and `AccessibilityProbe`
/// (foreground app awareness) into a single async `captureSnapshot()` call,
/// and keeps a small ring buffer of recent snapshots for the brain to read.
@MainActor
final class PerceptionEngine {
    private static let bufferCapacity = 6

    private let capturer: ScreenCapturer
    private let recognizer: OCRRecognizer
    private let probe: AccessibilityProbe

    private var buffer: [ContextSnapshot] = []
    private var lastSeenAppName: String?
    private var lastSnapshotTime: Date?
    private var elapsedOnCurrentApp: TimeInterval = 0

    /// Most recent frontmost-app name as observed by `captureSnapshot`. Used by
    /// `HonkTicker` to detect app changes without holding a snapshot reference.
    private(set) var lastFrontmostAppName: String?

    init(
        capturer: ScreenCapturer = ScreenCapturer(),
        recognizer: OCRRecognizer = OCRRecognizer(),
        probe: AccessibilityProbe = AccessibilityProbe()
    ) {
        self.capturer = capturer
        self.recognizer = recognizer
        self.probe = probe
    }

    /// Snapshots in chronological order, oldest first. Bounded by `bufferCapacity`.
    func recentSnapshots() -> [ContextSnapshot] {
        buffer
    }

    /// The most recently produced snapshot, or `nil` if none yet.
    func mostRecent() -> ContextSnapshot? {
        buffer.last
    }

    /// Triggers the macOS permission prompts for Accessibility and Screen
    /// Recording, and reports anything that still looks denied to stderr.
    /// Safe to call multiple times — both prompts are idempotent.
    func requestPermissions() async {
        let axGranted = AccessibilityProbe.promptForAccessibility()
        if !axGranted {
            PerceptionLog.warn("Accessibility permission not granted — window titles will be unavailable until you allow Goose in System Settings → Privacy & Security → Accessibility")
        }
        let probeImage = try? await capturer.captureMainDisplay()
        if probeImage == nil {
            PerceptionLog.warn("Screen Recording permission not granted — OCR will be unavailable until you allow Goose in System Settings → Privacy & Security → Screen Recording")
        }
    }

    /// Captures one perception frame: foreground context + screenshot + OCR.
    /// Returns `nil` only if capture failed and no previous snapshot exists.
    /// When a fresh capture is identical (same OCR text + same app) to the
    /// last snapshot, the previous snapshot is returned unchanged so callers
    /// can cheaply detect "nothing new happened".
    func captureSnapshot() async -> ContextSnapshot? {
        let now = Date()
        let context = probe.currentContext()
        let appName = context.appName
        let windowTitle = context.windowTitle

        let image = try? await capturer.captureMainDisplay()

        let fragments: [String]
        if let image {
            do {
                fragments = try await recognizer.recognize(in: image)
            } catch {
                PerceptionLog.warn("PerceptionEngine: OCR failed (\(error.localizedDescription))")
                fragments = []
            }
        } else {
            fragments = []
        }

        let normalizedText = normalize(fragments: fragments)
        let textHash = normalizedText.hashValue
        let topK = pickTopK(fragments: fragments)
        let idle = currentIdleSeconds()

        if let previous = buffer.last,
           previous.textHash == textHash,
           previous.frontmostAppName == appName {
            return previous
        }

        let prevApp = lastSeenAppName
        if appName != lastSeenAppName {
            elapsedOnCurrentApp = 0
        } else if let last = lastSnapshotTime {
            elapsedOnCurrentApp += now.timeIntervalSince(last)
        }
        lastSeenAppName = appName
        lastFrontmostAppName = appName
        lastSnapshotTime = now

        let snapshot = ContextSnapshot(
            timestamp: now,
            frontmostAppName: appName,
            frontmostWindowTitle: windowTitle,
            ocrText: normalizedText,
            ocrTopK: topK,
            elapsedOnApp: elapsedOnCurrentApp,
            prevFrontmostAppName: prevApp,
            idleSeconds: idle,
            textHash: textHash
        )

        buffer.append(snapshot)
        if buffer.count > Self.bufferCapacity {
            buffer.removeFirst(buffer.count - Self.bufferCapacity)
        }
        return snapshot
    }

    private func pickTopK(fragments: [String]) -> [String] {
        let cleaned = fragments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 4 }
            .map { String($0.prefix(80)) }
        var seen = Set<String>()
        var unique: [String] = []
        for s in cleaned where seen.insert(s.lowercased()).inserted {
            unique.append(s)
        }
        return Array(unique.sorted { $0.count > $1.count }.prefix(3))
    }

    private func currentIdleSeconds() -> TimeInterval {
        // kCGAnyInputEventType in C; not bridged as a CGEventType case, so build by raw value.
        let anyInput = CGEventType(rawValue: ~0) ?? .null
        let v = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        return v.isFinite && v >= 0 ? v : 0
    }

    private func normalize(fragments: [String]) -> String {
        fragments
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
