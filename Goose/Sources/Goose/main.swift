import AppKit

if let pathArgIndex = CommandLine.arguments.firstIndex(of: "--render-preview"),
   pathArgIndex + 1 < CommandLine.arguments.count {
    let outputPath = CommandLine.arguments[pathArgIndex + 1]
    let success = PreviewRenderer.renderToPNG(at: outputPath)
    exit(success ? 0 : 1)
}

if CommandLine.arguments.contains("--brain-dryrun") {
    let brain = GooseBrain()
    let snapshots: [ContextSnapshot] = [
        fakeSnapshot(app: "Xcode", time: 120, idle: 5, ocr: ["TODO: rewrite this", "var foo = 42", "let bar: Int"]),
        fakeSnapshot(app: "Slack", time: 30, idle: 1, ocr: ["are we still on for thursday", "@channel quick question"]),
        fakeSnapshot(app: "Safari", time: 900, idle: 4, ocr: ["how to focus", "stack overflow"]),
        fakeSnapshot(app: "Finder", time: 5, idle: 0, ocr: []),
    ]
    Task { @MainActor in
        var recent: [String] = []
        for i in 0..<20 {
            let snap = snapshots[i % snapshots.count]
            if let d = await brain.decide(snapshot: snap, recentActions: recent) {
                let line = "[\(i)] app=\(snap.frontmostAppName ?? "-") tone=\(Personality.tone(forTimeOnApp: snap.elapsedOnApp, idle: snap.idleSeconds)) → \(format(d))\n"
                FileHandle.standardOutput.write(Data(line.utf8))
                recent.append(d.action.rawValue)
                if recent.count > 4 { recent.removeFirst() }
            }
        }
        exit(0)
    }
    RunLoop.main.run()
}

if let queryIndex = CommandLine.arguments.firstIndex(of: "--browser-demo"),
   queryIndex + 1 < CommandLine.arguments.count {
    // Real implementation in Task 11.
    FileHandle.standardError.write(Data("--browser-demo not yet implemented (see Task 11)\n".utf8))
    exit(1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

@MainActor
private func fakeSnapshot(app: String, time: TimeInterval, idle: TimeInterval, ocr: [String]) -> ContextSnapshot {
    ContextSnapshot(
        timestamp: Date(),
        frontmostAppName: app,
        frontmostWindowTitle: nil,
        ocrText: ocr.joined(separator: " ").lowercased(),
        ocrTopK: ocr,
        elapsedOnApp: time,
        prevFrontmostAppName: nil,
        idleSeconds: idle,
        textHash: 0
    )
}

private func format(_ d: GooseDecision) -> String {
    switch d.action {
    case .note: return "note(\(d.noteTitle)) — \(d.noteBody.replacingOccurrences(of: "\n", with: " / "))"
    case .browse: return "browse(\(d.browseURL?.absoluteString ?? "?"))"
    default: return d.action.rawValue
    }
}
