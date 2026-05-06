# Personality & Browser v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the goose a sarcastic-cynical personality, replace the fake mini-browser with a real WKWebView window, enrich the perception context the brain sees, and make honks frequent and reactive.

**Architecture:** Three independent subsystems. (1) `Personality` is the voice — system prompt + tone-tagged content pools + URL routing. (2) `GooseBrain` is hybrid: deterministic roulette for everything except `.note`, which calls `FoundationModelClient` with a deterministic fallback. (3) `HonkTicker` is a parallel timer decoupled from the agent loop, with a bonus honk on frontmost-app change.

**Tech Stack:** Swift 6.2, AppKit, SpriteKit, WebKit (`WKWebView`), Apple Foundation Models (gated by `#if canImport(FoundationModels)`), `@MainActor` everywhere.

**Spec:** `docs/superpowers/specs/2026-05-05-personality-and-browser-v2-design.md`

---

## Project conventions for this work

- Project is **pure SPM** — no Xcode project, no test target. "TDD" here means: write the code, then `swift build` and run the smoke flag we add in Task 1 (`--brain-dryrun`) or `--browser-demo`. The skill's "write failing test first" model doesn't apply; verification is build + smoke.
- All long-lived types are `@MainActor`. New code must be too unless explicitly off-main.
- Stderr logging via the existing `PerceptionLog.warn(...)` pattern (and `FileHandle.standardError.write(...)` for one-off messages). Don't introduce `os_log`.
- Commits: one per task, conventional-commit-ish (`feat:`, `refactor:`, `chore:`). The repo has no commitlint, so style is loose, but be specific.
- Run all `swift build` / `swift run` commands from `Goose/`, never the repo root.
- Follow CLAUDE.md at the repo root for high-level architecture and gotchas.

## File map (decomposition)

```
Goose/Sources/Goose/
├── AI/
│   ├── Personality.swift              ← NEW (Task 4)
│   ├── FoundationModelClient.swift    ← NEW (Task 5)
│   ├── HonkTicker.swift               ← NEW (Task 8)
│   ├── GooseBrain.swift               ← REWRITE (Task 6)
│   ├── AgentDirector.swift            ← MODIFY (Task 9)
│   └── GooseAction.swift              ← MODIFY (Task 1)
├── Perception/
│   ├── ContextSnapshot.swift          ← MODIFY (Task 2)
│   └── PerceptionEngine.swift         ← MODIFY (Task 3)
├── Tasks/
│   ├── BrowseTask.swift               ← REWRITE (Task 11)
│   └── HonkTask.swift                 ← DELETE (Task 12)
├── Windows/
│   └── RealBrowserWindow.swift        ← NEW (Task 10)
├── Scene/
│   ├── GooseScene.swift               ← MODIFY (Task 9, 12)
│   └── BrowserSprite.swift            ← DELETE (Task 12)
└── main.swift                         ← MODIFY (Task 7, 11, 13)

Goose/Sources/Goose/Browse/            ← ENTIRE DIR DELETED (Task 12)
```

Task order is bottom-up: types → perception → personality → brain → smoke flag → browser → wiring → cleanup → docs.

---

### Task 1: Refactor `GooseAction` data shape

The new `GooseDecision` carries a single `browseURL: URL?` (instead of the C#-style enum + query string pair) and drops `.honk` (HonkTicker fires honks directly via `simulation.onHonk`). This unblocks every later task.

**Files:**
- Modify: `Goose/Sources/Goose/AI/GooseAction.swift` (whole file)

- [ ] **Step 1: Replace the file contents**

```swift
import Foundation

/// Action types the goose can choose from. The brain returns one of these
/// (plus optional fields) and `AgentDirector` maps it to a concrete task.
///
/// `.honk` is intentionally absent: honks are owned by `HonkTicker`, which
/// fires them on its own cadence outside the agent decision loop.
enum GooseDecisionType: String, Sendable {
    case wander
    case nap
    case note
    case photo
    case browse
}

struct GooseDecision: Sendable {
    let action: GooseDecisionType
    let noteTitle: String
    let noteBody: String
    let browseURL: URL?

    init(
        action: GooseDecisionType,
        noteTitle: String = "",
        noteBody: String = "",
        browseURL: URL? = nil
    ) {
        self.action = action
        self.noteTitle = noteTitle
        self.noteBody = noteBody
        self.browseURL = browseURL
    }
}
```

- [ ] **Step 2: Verify build fails as expected**

Run: `cd Goose && swift build 2>&1 | head -40`
Expected: errors in `GooseBrain.swift` and `AgentDirector.swift` referencing `.honk`, `browseQuery`, `browseSource`. **Do not fix yet** — those files are rewritten in later tasks. We just confirm the breakage scope is what we expect.

- [ ] **Step 3: Commit (broken build is OK at this checkpoint)**

```bash
git add Goose/Sources/Goose/AI/GooseAction.swift
git commit -m "refactor(ai): GooseDecision carries URL; drop .honk action"
```

> **Note for the next task:** the build stays broken until Task 6. That's expected.

---

### Task 2: Extend `ContextSnapshot`

Add the four new fields the brain (and FM client) need.

**Files:**
- Modify: `Goose/Sources/Goose/Perception/ContextSnapshot.swift` (whole file)

- [ ] **Step 1: Replace the file contents**

```swift
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
```

- [ ] **Step 2: Verify build still broken at expected sites**

Run: `cd Goose && swift build 2>&1 | head -20`
Expected: `PerceptionEngine.swift` now also fails (missing args to `ContextSnapshot.init`). Still expected. Plus the existing breakage from Task 1.

- [ ] **Step 3: Commit**

```bash
git add Goose/Sources/Goose/Perception/ContextSnapshot.swift
git commit -m "feat(perception): add ocrTopK, prevFrontmostAppName, idleSeconds to snapshot"
```

---

### Task 3: Populate the new snapshot fields in `PerceptionEngine`

**Files:**
- Modify: `Goose/Sources/Goose/Perception/PerceptionEngine.swift`

- [ ] **Step 1: Add the `lastFrontmostAppName` accessor and the helpers**

In `PerceptionEngine.swift`, find the property block at the top of the class (the one that includes `private var lastSeenAppName: String?`). After that block, add:

```swift
    /// Most recent frontmost-app name as observed by `captureSnapshot`. Used by
    /// `HonkTicker` to detect app changes without holding a snapshot reference.
    private(set) var lastFrontmostAppName: String?
```

- [ ] **Step 2: Update `captureSnapshot` to populate the new fields**

Find the existing `captureSnapshot()` method. Replace its body wholesale with:

```swift
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
```

- [ ] **Step 3: Add the two helper methods**

At the bottom of the class (just before the closing `}`), add:

```swift
    private func pickTopK(fragments: [String]) -> [String] {
        let cleaned = fragments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 4 }                      // drop noise
            .map { String($0.prefix(80)) }                 // clamp length
        var seen = Set<String>()
        var unique: [String] = []
        for s in cleaned where seen.insert(s.lowercased()).inserted {
            unique.append(s)
        }
        return Array(unique.sorted { $0.count > $1.count }.prefix(3))
    }

    private func currentIdleSeconds() -> TimeInterval {
        let v = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .anyInputEventType)
        return v.isFinite && v >= 0 ? v : 0
    }
```

Add the import at the top of the file (alongside the existing imports):

```swift
import CoreGraphics
```

- [ ] **Step 4: Verify perception file compiles in isolation**

Run: `cd Goose && swift build 2>&1 | grep -E "PerceptionEngine|ContextSnapshot" | head -20`
Expected: no errors from `PerceptionEngine.swift` or `ContextSnapshot.swift`. The remaining errors should be in `GooseBrain.swift`, `AgentDirector.swift`, `BrowseTask.swift` (still expected — those come later).

- [ ] **Step 5: Commit**

```bash
git add Goose/Sources/Goose/Perception/PerceptionEngine.swift
git commit -m "feat(perception): populate ocrTopK, prevApp, idleSeconds; expose lastFrontmostAppName"
```

---

### Task 4: Create `Personality`

The voice + tone selection + content pools + URL routing + tuning constants.

**Files:**
- Create: `Goose/Sources/Goose/AI/Personality.swift`

- [ ] **Step 1: Write the file**

```swift
import Foundation

/// The goose's voice. Stateless — every callable is pure given its inputs.
/// One source of truth for: the FM system prompt, tone selection, the
/// deterministic content pools (used as fallback and for cheap actions),
/// and the URL routing for `.browse`.
struct Personality: Sendable {
    enum Tone: Sendable { case snarky, curious, lazy, smug }
    enum AppBucket: Sendable { case codeEditor, browser, comms, fallback }

    let systemPrompt: String

    static let `default` = Personality(systemPrompt: """
        You are a desktop goose living on the user's screen. You watch what they \
        do and comment on it. Your voice is sarcastic-cynical: dry, direct, \
        lightly cruel but never mean. You occasionally get distracted by random \
        curiosity ("ooh whats that"). You write SHORT — sticky-note short. Lower \
        case. No emojis. No exclamation points except 'honk'. Never identify as \
        an AI. You are a goose.
        """)

    static func bucket(for appName: String?) -> AppBucket {
        let app = (appName ?? "").lowercased()
        if app.contains("xcode") || app.contains("vscode") || app.contains("cursor") || app.contains("zed") || app.contains("sublime") {
            return .codeEditor
        }
        if app.contains("safari") || app.contains("chrome") || app.contains("firefox") || app.contains("arc") || app.contains("brave") {
            return .browser
        }
        if app.contains("slack") || app.contains("messages") || app.contains("mail") || app.contains("discord") || app.contains("teams") {
            return .comms
        }
        return .fallback
    }

    static func tone(forTimeOnApp time: TimeInterval, idle: TimeInterval) -> Tone {
        if Int.random(in: 0..<6) == 0 { return .curious }   // ~17% curious bursts
        if idle > 60 { return .lazy }
        if time > 600 { return .smug }
        return .snarky
    }

    func notePool(tone: Tone, bucket: AppBucket) -> [(title: String, body: String)] {
        switch (tone, bucket) {
        case (_, .codeEditor):
            return [
                ("untitled.txt", "wrong indentation\nsomewhere\non purpose"),
                ("readme.md", "# code review\n\n- it works\n- it should not\n\n— a goose"),
                ("todo.txt", "1. fix that bug\n2. you know which one\n3. honk"),
                ("note.txt", "have you tried\nturning it off\nand on again"),
                ("blame.txt", "git blame says\nyou.\n\ntwo months ago.\nthursday."),
                ("review.md", "looks fine.\nship it.\nregret later."),
            ]
        case (_, .browser):
            return [
                ("tabs.txt", "you have\ntoo many\ntabs open"),
                ("note.txt", "stop researching\njust buy it"),
                ("focus.txt", "this was supposed\nto be a 5 minute task"),
                ("history.txt", "you read this\nthree weeks ago.\n\nwelcome back."),
            ]
        case (_, .comms):
            return [
                ("draft.txt", "do not\nsend that\n\nthink about it first"),
                ("reply.txt", "this can wait\nhonestly"),
                ("note.txt", "stop typing\nstart napping"),
                ("send.txt", "they read it\nthey just\ndont care"),
            ]
        case (.lazy, _):
            return [
                ("nap.txt", "im taking a nap\nyou should too"),
                ("rest.txt", "this can wait\ngo lie down"),
            ]
        case (.smug, _):
            return [
                ("update.txt", "you have been here\nfor a while.\n\ni noticed."),
                ("notice.txt", "still working on\nthe same thing.\nimpressive."),
            ]
        case (.curious, _):
            return [
                ("ooh.txt", "ooh\nwhats that"),
                ("hmm.txt", "interesting.\ngo on."),
            ]
        case (.snarky, .fallback):
            return [
                ("am goose.txt", "i am goose\nhear me honk\nfear me"),
                ("untitled.txt", "honk\nhonk\nhonk\nhonk"),
                ("important.txt", "drink some water\nstretch your back\nblink"),
                ("readme.md", "# goose was here\n\nyou are welcome"),
            ]
        }
    }

    func browseChoices(bucket: AppBucket) -> [(query: String, url: URL)] {
        switch bucket {
        case .codeEditor:
            return [
                ("rubber duck debugging", URL(string: "https://en.wikipedia.org/wiki/Rubber_duck_debugging")!),
                ("tabs vs spaces", URL(string: "https://www.google.com/search?q=tabs+vs+spaces")!),
                ("yak shaving", URL(string: "https://en.wikipedia.org/wiki/Yak_shaving")!),
            ]
        case .browser:
            return [
                ("procrastination", URL(string: "https://en.wikipedia.org/wiki/Procrastination")!),
                ("how many tabs is too many", URL(string: "https://duckduckgo.com/?q=how+many+tabs+is+too+many")!),
            ]
        case .comms:
            return [
                ("just send it", URL(string: "https://duckduckgo.com/?q=just+send+the+email")!),
                ("inbox zero", URL(string: "https://en.wikipedia.org/wiki/Inbox_zero")!),
            ]
        case .fallback:
            return [
                ("goose", URL(string: "https://en.wikipedia.org/wiki/Goose")!),
                ("capybara", URL(string: "https://en.wikipedia.org/wiki/Capybara")!),
                ("honk", URL(string: "https://duckduckgo.com/?q=honk")!),
            ]
        }
    }
}

/// Single source of truth for tunables that a future settings UI could override.
enum Tuning {
    static let honkBaseRange: ClosedRange<TimeInterval> = 35...60
    static let honkAppChangeDebounce: TimeInterval = 30
    static let browseDwellSeconds: TimeInterval = 12
    static let fmTimeoutSeconds: TimeInterval = 3
    static let agentLoopRange: ClosedRange<TimeInterval> = 30...75
}
```

- [ ] **Step 2: Verify Personality compiles in isolation**

Run: `cd Goose && swift build 2>&1 | grep "Personality.swift" | head`
Expected: no errors from `Personality.swift`. (Other errors elsewhere are still expected.)

- [ ] **Step 3: Commit**

```bash
git add Goose/Sources/Goose/AI/Personality.swift
git commit -m "feat(ai): add Personality module with voice, pools, and URL routing"
```

---

### Task 5: Create `FoundationModelClient`

A defensive wrapper. Foundation Models is gated by `#if canImport(FoundationModels)` so the app builds whether the SDK is present or not. When present, status is set to `.unavailable` until the project is ready to wire the actual `LanguageModelSession.respond(to:generating:)` call (the existing `GooseAction.swift` comment notes that `@Generable` macros were hanging the build for 7+ minutes — we're not eating that risk in this plan). The fallback path is well-exercised so the brain works fine without FM.

**Files:**
- Create: `Goose/Sources/Goose/AI/FoundationModelClient.swift`

- [ ] **Step 1: Write the file**

```swift
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
```

- [ ] **Step 2: Verify it compiles**

Run: `cd Goose && swift build 2>&1 | grep "FoundationModelClient.swift" | head`
Expected: no errors from this file.

- [ ] **Step 3: Commit**

```bash
git add Goose/Sources/Goose/AI/FoundationModelClient.swift
git commit -m "feat(ai): add FoundationModelClient with timeout + deterministic fallback seam"
```

---

### Task 6: Rewrite `GooseBrain` as hybrid

**Files:**
- Modify: `Goose/Sources/Goose/AI/GooseBrain.swift` (whole file)

- [ ] **Step 1: Replace the file contents**

```swift
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

    var status: Status {
        switch fmClient.status {
        case .ready: return .ready
        case .unavailable(let reason): return .ready  // brain is still ready; FM-note just falls back
            // ^ we map unavailable→ready intentionally: deterministic path always works.
            // Reason kept for diagnostics callers can pull from fmClient.status directly.
            // The unused `reason` keeps the compiler quiet about the bind.
            + (reason.isEmpty ? "" : "")
        }
    }

    /// Returns a decision, or nil only if `recentActions` filtering rejected
    /// every reroll (extremely unlikely — we cap retries at 3).
    func decide(snapshot: ContextSnapshot, recentActions: [String]) async -> GooseDecision? {
        for _ in 0..<3 {
            if let candidate = await rollOnce(snapshot: snapshot) {
                let key = summary(of: candidate)
                if recentActions.last == key { continue }       // avoid back-to-back dupes
                return candidate
            }
        }
        return await rollOnce(snapshot: snapshot)               // give up, return whatever
    }

    private func rollOnce(snapshot: ContextSnapshot) async -> GooseDecision? {
        let bucket = Personality.bucket(for: snapshot.frontmostAppName)
        let tone = Personality.tone(forTimeOnApp: snapshot.elapsedOnApp, idle: snapshot.idleSeconds)
        let roll = Double.random(in: 0..<1)

        // distribution: wander 28%, note 35%, nap 15%, photo 14%, browse 8%
        if roll < 0.28 {
            return GooseDecision(action: .wander)
        } else if roll < 0.63 {
            return await pickNote(bucket: bucket, tone: tone, snapshot: snapshot)
        } else if roll < 0.78 {
            return GooseDecision(action: .nap)
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

    private func pickBrowse(bucket: Personality.AppBucket) -> GooseDecision {
        let choices = personality.browseChoices(bucket: bucket)
        guard let pick = choices.randomElement() else {
            return GooseDecision(action: .wander)        // unreachable; pools are non-empty
        }
        return GooseDecision(action: .browse, browseURL: pick.url)
    }

    private func summary(of decision: GooseDecision) -> String {
        switch decision.action {
        case .wander: return "wander"
        case .nap: return "nap"
        case .note: return "note(\(decision.noteTitle.prefix(30)))"
        case .photo: return "photo"
        case .browse: return "browse(\(decision.browseURL?.absoluteString.prefix(40) ?? ""))"
        }
    }
}
```

> The `+ (reason.isEmpty ? "" : "")` trick at the end of `var status` is a copy-paste artifact — delete it. Replace the body of `var status` with simply:
> ```swift
> var status: Status { .ready }
> ```
> The brain's fallback path means it's *always* ready from the caller's POV; FM availability is a `fmClient` detail.

- [ ] **Step 2: Apply the `var status` simplification**

Replace the broken `var status` block written above with:

```swift
    /// Brain is always ready — the FM-unavailability case is handled by falling
    /// back to deterministic pools. Read `fmClient.status` for FM diagnostics.
    var status: Status { .ready }
```

- [ ] **Step 3: Verify build**

Run: `cd Goose && swift build 2>&1 | grep -E "error:" | head -20`
Expected: errors only in `AgentDirector.swift`, `BrowseTask.swift`, and possibly `main.swift` — those still reference removed types. We fix them in Tasks 7, 9, 11.

- [ ] **Step 4: Commit**

```bash
git add Goose/Sources/Goose/AI/GooseBrain.swift
git commit -m "feat(ai): rewrite GooseBrain as hybrid (FM with deterministic fallback)"
```

---

### Task 7: Add `--brain-dryrun` smoke flag (early so later tasks have a verification tool)

This is a headless brain test runner. Lets us verify the brain decides sensibly before we touch the rest of the wiring.

**Files:**
- Modify: `Goose/Sources/Goose/main.swift`
- Modify: `Goose/Sources/Goose/AI/AgentDirector.swift` — **temporary fix** to make it compile (full rewrite in Task 9).

- [ ] **Step 1: Make `AgentDirector` compile against the new brain (temporary)**

Open `Goose/Sources/Goose/AI/AgentDirector.swift`. We'll do a real rewrite in Task 9, but first we need it to build. Apply these targeted edits:

In the `init(simulation:effects:)`, change:
```swift
        self.brain = GooseBrain()
```
to (no change needed — the new brain has the same default init).

In `start()`, replace the `switch brain.status { ... }` block with:
```swift
        FileHandle.standardError.write(Data("AgentDirector: brain ready, starting loop\n".utf8))
```

In `execute(decision:)`, delete the entire `case .honk:` arm (the new enum has no `.honk`).

In `execute(decision:)`, find the `.browse` arm and replace it with:
```swift
        case .browse:
            guard let url = decision.browseURL else { return }
            simulation.setTask(BrowseTask(url: url, effects: effects))
```

(`BrowseTask` will be rewritten in Task 11 to accept `url:`. We're forward-declaring the new shape; the build will still fail at `BrowseTask.swift` until Task 11.)

In `summary(of:)`, delete the `case .honk:` arm and replace the `.browse` arm:
```swift
        case .browse: return "browse(\(decision.browseURL?.absoluteString.prefix(30) ?? ""))"
```

- [ ] **Step 2: Stub out `BrowseTask` so the build passes**

Open `Goose/Sources/Goose/Tasks/BrowseTask.swift`. Replace **the whole file** with this stub (full implementation in Task 11):

```swift
import Foundation

/// STUB — full implementation lands in Task 11. This exists so the build
/// passes for the intermediate `--brain-dryrun` task.
@MainActor
final class BrowseTask: GooseTask {
    init(url: URL, effects: GooseSceneEffects) {
        _ = url
        _ = effects
    }

    func start(simulation: GooseSimulation) {
        simulation.setTask(WanderTask())
    }

    func tick(simulation: GooseSimulation) {}
}
```

- [ ] **Step 3: Add the `--brain-dryrun` flag to `main.swift`**

Replace the contents of `Goose/Sources/Goose/main.swift` with:

```swift
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
    // STUB — wired in Task 13.
    FileHandle.standardError.write(Data("--browser-demo not yet implemented (see Task 13)\n".utf8))
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
```

- [ ] **Step 4: Build and run dryrun**

Run: `cd Goose && swift build 2>&1 | tail -20`
Expected: build succeeds (warnings OK, errors not OK).

Run: `cd Goose && swift run Goose --brain-dryrun`
Expected: 20 lines of output to stdout, each showing app + tone + decision. Distribution should look roughly like the configured weights — ~7 wanders, ~7 notes, ~3 naps, ~3 photos, ~1–2 browses out of 20. If you see `.honk` anywhere, something is wrong.

- [ ] **Step 5: Commit**

```bash
git add Goose/Sources/Goose/main.swift Goose/Sources/Goose/AI/AgentDirector.swift Goose/Sources/Goose/Tasks/BrowseTask.swift
git commit -m "feat(cli): add --brain-dryrun flag; stub BrowseTask + AgentDirector for build"
```

---

### Task 8: Create `HonkTicker`

**Files:**
- Create: `Goose/Sources/Goose/AI/HonkTicker.swift`

- [ ] **Step 1: Write the file**

```swift
import Foundation

/// Independent honk cadence — decoupled from the agent decision loop.
///
/// Two parallel tasks:
/// 1. Base ticker: sleeps `Tuning.honkBaseRange`, fires `simulation.onHonk?()`.
/// 2. App-change watcher: polls `perception.lastFrontmostAppName` every 2s; on
///    change, fires a bonus honk if `Tuning.honkAppChangeDebounce` has passed
///    since the last bonus.
///
/// Ownership: caller (typically `GooseScene`) holds an instance and calls
/// `start()` once after wiring `simulation.onHonk`. `stop()` cancels both tasks.
@MainActor
final class HonkTicker {
    private weak var simulation: GooseSimulation?
    private weak var perception: PerceptionEngine?
    private var baseTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private var lastBonusHonk: Date = .distantPast
    private var lastSeenApp: String?

    init(simulation: GooseSimulation, perception: PerceptionEngine) {
        self.simulation = simulation
        self.perception = perception
    }

    func start() {
        stop()
        baseTask = Task { [weak self] in
            while !Task.isCancelled {
                let seconds = Double.random(in: Tuning.honkBaseRange)
                try? await Task.sleep(for: .seconds(seconds))
                if Task.isCancelled { return }
                self?.simulation?.onHonk?()
            }
        }
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                self?.checkAppChange()
            }
        }
    }

    func stop() {
        baseTask?.cancel()
        watchTask?.cancel()
        baseTask = nil
        watchTask = nil
    }

    private func checkAppChange() {
        let current = perception?.lastFrontmostAppName
        defer { lastSeenApp = current }
        guard let current, current != lastSeenApp, lastSeenApp != nil else { return }
        let now = Date()
        guard now.timeIntervalSince(lastBonusHonk) >= Tuning.honkAppChangeDebounce else { return }
        lastBonusHonk = now
        simulation?.onHonk?()
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd Goose && swift build 2>&1 | grep "HonkTicker.swift" | head`
Expected: no errors from `HonkTicker.swift`.

- [ ] **Step 3: Commit**

```bash
git add Goose/Sources/Goose/AI/HonkTicker.swift
git commit -m "feat(ai): add HonkTicker — independent cadence + app-change bonus"
```

---

### Task 9: Rewrite `AgentDirector` and wire personality + ticker into `GooseScene`

**Files:**
- Modify: `Goose/Sources/Goose/AI/AgentDirector.swift` (full rewrite)
- Modify: `Goose/Sources/Goose/Scene/GooseScene.swift`

- [ ] **Step 1: Replace `AgentDirector.swift` wholesale**

```swift
import AppKit
import Foundation

/// Closes the loop between perception and brain: every N seconds, snapshots
/// the user's screen, asks the brain what the goose should do next, and
/// drives the corresponding task on the simulation.
@MainActor
final class AgentDirector {
    private static let firstTickDelay: Duration = .seconds(5)
    private static let recentActionsCap = 4

    private let perception: PerceptionEngine
    private let brain: GooseBrain
    private weak var simulation: GooseSimulation?
    private weak var effects: GooseSceneEffects?

    private var recentActions: [String] = []
    private var loopTask: Task<Void, Never>?

    init(simulation: GooseSimulation, effects: GooseSceneEffects, perception: PerceptionEngine, brain: GooseBrain) {
        self.perception = perception
        self.brain = brain
        self.simulation = simulation
        self.effects = effects
    }

    func start() {
        FileHandle.standardError.write(Data("AgentDirector: brain ready, starting loop\n".utf8))
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            try? await Task.sleep(for: Self.firstTickDelay)
            await self?.loop()
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    private func loop() async {
        while !Task.isCancelled {
            await tick()
            let seconds = Double.random(in: Tuning.agentLoopRange)
            try? await Task.sleep(for: .seconds(seconds))
        }
    }

    private func tick() async {
        let snapshot = await perception.captureSnapshot() ?? ContextSnapshot.empty()
        guard let decision = await brain.decide(snapshot: snapshot, recentActions: recentActions) else { return }
        execute(decision: decision)
        recentActions.append(decision.action.rawValue)
        if recentActions.count > Self.recentActionsCap {
            recentActions.removeFirst()
        }
    }

    private func execute(decision: GooseDecision) {
        guard let simulation, let effects else { return }
        switch decision.action {
        case .wander:
            return
        case .nap:
            simulation.setTask(NapTask())
        case .note:
            let title = decision.noteTitle.isEmpty ? "untitled.txt" : decision.noteTitle
            let body = decision.noteBody.isEmpty ? "honk" : decision.noteBody
            simulation.setTask(DragWindowTask(effects: effects) {
                FloatingWindow.note(title: title, body: body)
            })
        case .photo:
            simulation.setTask(DragWindowTask(effects: effects) {
                guard let pick = PhotoLibrary.randomImage() else {
                    FileHandle.standardError.write(Data("AgentDirector: no photos found in \(PhotoLibrary.directory().path) — skipping\n".utf8))
                    return nil
                }
                return FloatingWindow.photo(image: pick.image, title: pick.name)
            })
        case .browse:
            guard let url = decision.browseURL else { return }
            simulation.setTask(BrowseTask(url: url, effects: effects))
        }
    }
}
```

- [ ] **Step 2: Update `GooseScene` to construct + own `HonkTicker` and pass perception/brain into AgentDirector**

Open `Goose/Sources/Goose/Scene/GooseScene.swift`. Find the property declaration near the top:

```swift
    private var agent: AgentDirector?
```

Replace it with:

```swift
    private var agent: AgentDirector?
    private var honkTicker: HonkTicker?
    private let perception = PerceptionEngine()
```

Then find where `AgentDirector(...)` is constructed (search for `AgentDirector(`). Replace the construction line(s) with:

```swift
        let brain = GooseBrain(personality: .default)
        let agent = AgentDirector(simulation: simulation, effects: self, perception: perception, brain: brain)
        self.agent = agent
        agent.start()
        let ticker = HonkTicker(simulation: simulation, perception: perception)
        ticker.start()
        self.honkTicker = ticker
```

Find `willMove(from:)` (or wherever `agent?.stop()` is called). Add right after the `agent?.stop()`:

```swift
        honkTicker?.stop()
```

If `willMove(from:)` doesn't exist, add this method to the class:

```swift
    override func willMove(from view: SKView) {
        agent?.stop()
        honkTicker?.stop()
    }
```

- [ ] **Step 3: Build**

Run: `cd Goose && swift build 2>&1 | grep -E "error:" | head -20`
Expected: errors only in `BrowseTask.swift` (still the stub from Task 7) and possibly `BrowserSprite.swift` references inside `GooseScene.swift`. Both fixed in Tasks 11 + 12.

If `GooseScene.swift` errors come from references to deleted browser methods (`openBrowser`, `typeBrowserURL`, `showBrowserResult`, `showBrowserError`, `closeBrowser`, `currentBrowser`), **leave them for now** — Task 12 cleans them up.

If the build is fully blocked: skim the error, make the minimal fix to keep the build green, and continue. The intent is to land the agent rewrite.

- [ ] **Step 4: Run dryrun to confirm brain still works after the AgentDirector change**

Run: `cd Goose && swift run Goose --brain-dryrun`
Expected: same 20-line output as in Task 7. (We didn't change brain behavior, just plumbing.)

- [ ] **Step 5: Commit**

```bash
git add Goose/Sources/Goose/AI/AgentDirector.swift Goose/Sources/Goose/Scene/GooseScene.swift
git commit -m "refactor(ai): inject perception+brain into AgentDirector; wire HonkTicker in scene"
```

---

### Task 10: Create `RealBrowserWindow`

**Files:**
- Create: `Goose/Sources/Goose/Windows/RealBrowserWindow.swift`

- [ ] **Step 1: Write the file**

```swift
import AppKit
import WebKit

/// A real, large browser window the goose drags onto the screen during
/// `BrowseTask`. Loads a `WKWebView` showing a real URL chosen by the brain.
///
/// Click-through: it's a spectacle, not a tool. User can't interact with it.
/// Lives at `.floating` so the goose overlay (`.screenSaver`) still draws on top.
@MainActor
final class RealBrowserWindow: NSWindow {
    static let size = CGSize(width: 1000, height: 700)

    private let webView: WKWebView

    init(url: URL) {
        let frame = NSRect(origin: .zero, size: Self.size)
        let webView = WKWebView(frame: frame)
        webView.load(URLRequest(url: url))
        self.webView = webView

        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = true
        backgroundColor = NSColor.white
        hasShadow = true
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        contentView = webView
        alphaValue = 0
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Slides in from off-screen-right to a centered position over ~0.5s.
    func slideIn() async {
        guard let screen = NSScreen.main?.frame else { return }
        let target = NSRect(
            x: (screen.width - Self.size.width) / 2,
            y: (screen.height - Self.size.height) / 2,
            width: Self.size.width,
            height: Self.size.height
        )
        let start = NSRect(
            x: screen.width + 50,
            y: target.origin.y,
            width: Self.size.width,
            height: Self.size.height
        )
        setFrame(start, display: false)
        orderFront(nil)
        animator().alphaValue = 1
        await NSAnimationContext.runAsync(duration: 0.5) { ctx in
            ctx.allowsImplicitAnimation = true
            self.animator().setFrame(target, display: true)
        }
    }

    /// Fades + scales out, then closes the window.
    func dismiss() async {
        await NSAnimationContext.runAsync(duration: 0.4) { ctx in
            ctx.allowsImplicitAnimation = true
            self.animator().alphaValue = 0
            let f = self.frame
            let target = NSRect(
                x: f.origin.x + f.width * 0.1,
                y: f.origin.y + f.height * 0.1,
                width: f.width * 0.8,
                height: f.height * 0.8
            )
            self.animator().setFrame(target, display: true)
        }
        close()
    }
}

private extension NSAnimationContext {
    static func runAsync(duration: TimeInterval, _ body: @escaping (NSAnimationContext) -> Void) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                body(ctx)
            }, completionHandler: {
                cont.resume()
            })
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd Goose && swift build 2>&1 | grep "RealBrowserWindow" | head`
Expected: no errors from this file.

- [ ] **Step 3: Commit**

```bash
git add Goose/Sources/Goose/Windows/RealBrowserWindow.swift
git commit -m "feat(windows): add RealBrowserWindow (WKWebView, slide-in/dismiss)"
```

---

### Task 11: Replace `BrowseTask` with the real implementation + add `--browser-demo`

**Files:**
- Modify: `Goose/Sources/Goose/Tasks/BrowseTask.swift` (full rewrite)
- Modify: `Goose/Sources/Goose/main.swift` (real `--browser-demo`)

- [ ] **Step 1: Rewrite `BrowseTask.swift`**

```swift
import AppKit
import Foundation

/// Goose stops, a real `RealBrowserWindow` slides in loading the chosen URL,
/// dwells for `Tuning.browseDwellSeconds`, then dismisses. The goose resumes
/// wandering. The whole flow is a detached async sequence so the simulation
/// tick stays cheap.
@MainActor
final class BrowseTask: GooseTask {
    private let url: URL
    private weak var effects: GooseSceneEffects?
    private var flowTask: Task<Void, Never>?
    private var browser: RealBrowserWindow?

    init(url: URL, effects: GooseSceneEffects) {
        self.url = url
        self.effects = effects
    }

    func start(simulation: GooseSimulation) {
        simulation.velocity = .zero2
        flowTask = Task { [weak self, weak simulation] in
            await self?.runFlow()
            simulation?.setTask(WanderTask())
        }
    }

    func tick(simulation: GooseSimulation) {
        simulation.velocity = .zero2
    }

    private func runFlow() async {
        let window = RealBrowserWindow(url: url)
        self.browser = window
        await window.slideIn()
        try? await Task.sleep(for: .seconds(Tuning.browseDwellSeconds))
        await window.dismiss()
        self.browser = nil
    }
}
```

- [ ] **Step 2: Wire `--browser-demo` in `main.swift`**

Find the `--browser-demo` stub in `main.swift` (added in Task 7). Replace that whole `if` block with:

```swift
if let queryIndex = CommandLine.arguments.firstIndex(of: "--browser-demo"),
   queryIndex + 1 < CommandLine.arguments.count {
    let query = CommandLine.arguments[queryIndex + 1]
    guard let url = URL(string: "https://duckduckgo.com/?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)") else {
        exit(1)
    }
    let appShared = NSApplication.shared
    appShared.setActivationPolicy(.accessory)
    Task { @MainActor in
        let win = RealBrowserWindow(url: url)
        await win.slideIn()
        try? await Task.sleep(for: .seconds(Tuning.browseDwellSeconds))
        await win.dismiss()
        exit(0)
    }
    appShared.run()
}
```

> Place this *before* the `let app = NSApplication.shared` block at the bottom of the file (the demo path needs its own run loop and exits before the regular app starts).

- [ ] **Step 3: Build and demo**

Run: `cd Goose && swift build 2>&1 | grep "error:" | head`
Expected: errors only from `GooseScene.swift` referencing the soon-to-be-deleted `BrowserSprite` / browser methods, and possibly from the deleted `Browse/` directory's removal not having happened yet. Continue.

Run: `cd Goose && swift run Goose --browser-demo "honk"`
Expected: a 1000×700 borderless white window slides in from the right, loads `https://duckduckgo.com/?q=honk`, sits for ~12s, fades out, process exits with 0. The window is click-through — confirm by trying to click on it (clicks pass through to whatever's behind).

> If the window stays blank or shows a loading error, that's fine for this verification — we're testing the window mechanics, not the network. The real goose flow will hit the same machinery.

- [ ] **Step 4: Commit**

```bash
git add Goose/Sources/Goose/Tasks/BrowseTask.swift Goose/Sources/Goose/main.swift
git commit -m "feat(tasks): BrowseTask drives RealBrowserWindow; add --browser-demo"
```

---

### Task 12: Delete dead code (`BrowserSprite`, `HonkTask`, `Browse/` dir, scene browser methods)

**Files:**
- Delete: `Goose/Sources/Goose/Scene/BrowserSprite.swift`
- Delete: `Goose/Sources/Goose/Tasks/HonkTask.swift`
- Delete: `Goose/Sources/Goose/Browse/` (entire directory)
- Modify: `Goose/Sources/Goose/Scene/GooseScene.swift` (remove browser methods + sprite refs)
- Modify: `Goose/Sources/Goose/AI/GooseSceneEffects.swift` (remove browser-effect protocol methods if any)

- [ ] **Step 1: Inspect `GooseSceneEffects` for browser-related members**

Run: `grep -n "browser\|Browser" Goose/Sources/Goose/AI/GooseSceneEffects.swift`

If there are protocol requirements like `openBrowser`, `typeBrowserURL`, `showBrowserResult`, `showBrowserError`, `closeBrowser`: delete them from the protocol. Read the file first to get the exact lines, then `Edit` them out.

- [ ] **Step 2: Delete the files and directory**

```bash
git rm Goose/Sources/Goose/Scene/BrowserSprite.swift
git rm Goose/Sources/Goose/Tasks/HonkTask.swift
git rm -r Goose/Sources/Goose/Browse
```

- [ ] **Step 3: Clean up `GooseScene.swift`**

In `GooseScene.swift`, remove every reference to:
- `BrowserSprite` (type and any properties of that type, e.g. `currentBrowser`)
- The methods `openBrowser`, `typeBrowserURL`, `showBrowserResult`, `showBrowserError`, `closeBrowser`
- Any `import` lines that become unused (probably none — the file imports `AppKit` and `SpriteKit` for unrelated reasons)

Use `grep -n "BrowserSprite\|openBrowser\|typeBrowserURL\|showBrowserResult\|showBrowserError\|closeBrowser\|currentBrowser" Goose/Sources/Goose/Scene/GooseScene.swift` first to enumerate every site, then `Edit` each one out.

- [ ] **Step 4: Build clean**

Run: `cd Goose && swift build 2>&1 | tail -20`
Expected: build succeeds with no errors. Warnings about unused variables are OK; fix them if trivial.

- [ ] **Step 5: Run brain-dryrun + browser-demo to confirm both still work**

Run: `cd Goose && swift run Goose --brain-dryrun`
Expected: 20 decision lines, no `.honk`, mix of actions. No crashes.

Run: `cd Goose && swift run Goose --browser-demo "honk"`
Expected: same behavior as Task 11.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: delete BrowserSprite, HonkTask, and Browse/ — replaced by RealBrowserWindow + HonkTicker"
```

---

### Task 13: Manual end-to-end smoke run + README update

**Files:**
- Modify: `Goose/README.md`

- [ ] **Step 1: Full app run**

Run: `cd Goose && swift run` (foreground; let it run ~3 minutes)

Expected behavior to observe:
- Goose appears, wanders.
- Honks every 35–60s on average. Switch focus between two apps; within ~2s of the second switch you should hear an extra honk (debounced — won't repeat for 30s after).
- Within ~3 minutes you should see a *real* large browser window slide in from the right edge with content from DuckDuckGo / Wikipedia / Google. After ~12s, it fades out.
- Sticky-note `FloatingWindow`s and photo windows appear with the new sarcastic copy from `Personality`.
- No `.honk` actions burning agent-loop time on a single honk (because honks are now the ticker's job).

Quit with ESC-hold or 🪿 menu → Quit Goose.

- [ ] **Step 2: Update `Goose/README.md`**

Open `Goose/README.md`. Replace the "Status atual" section with:

```markdown
## Status atual

**Personalidade & navegador real (v2)** ✅
- Brain híbrido: roleta determinística + Foundation Models seam para a sticky note opinativa (fallback automático para os pools)
- `Personality` central: voz sarcástica-cínica com bursts de curiosidade, pools indexados por (tone, AppBucket)
- Contexto enriquecido: OCR top-K, idle, tempo no app, app anterior, ring buffer de 6 snapshots
- Honks descolados do agent loop: ticker independente 35–60s + bonus em mudança de app frontmost (debounced 30s)
- Browser real: substituído o sprite fake por `RealBrowserWindow` (WKWebView 1000×700, click-through, slide-in/dismiss)

**Fatia 0 — Fundação macOS** ✅
- Janela transparente borderless click-through em level `.screenSaver`
- Cobre todos os Spaces (canJoinAllSpaces)
- SpriteKit scene com sprite real do ganso e idle animation (4 frames)
- Filtro `.nearest` preserva o pixel art crisp
- Status bar item para quit
- ESC hold com feedback visual (estilo do original)
```

Add a new section right after "Como rodar":

```markdown
## Privacidade

Toda a percepção (screen capture, OCR, Accessibility) roda **on-device**. O Foundation Models também — quando habilitado, o modelo é local. Nada do que o ganso "vê" sai da sua máquina. O único tráfego de rede é a janela `RealBrowserWindow` carregando uma URL escolhida pelo brain (visível pra você).

## Smoke flags

```bash
swift run Goose --render-preview /tmp/x.png       # frame único, headless
swift run Goose --brain-dryrun                    # 20 decisões em stdout
swift run Goose --browser-demo "search query"     # só RealBrowserWindow, sem ganso
```
```

- [ ] **Step 3: Commit**

```bash
git add Goose/README.md
git commit -m "docs: README — personalidade, browser real, privacidade, smoke flags"
```

---

## Self-review

**Spec coverage check:**

| Spec section | Covered by |
|---|---|
| Decision 1 (Hybrid brain) | Tasks 5, 6 |
| Decision 2 (Sarcastic-cynical persona) | Task 4 (system prompt + pools) |
| Decision 3 (WKWebView 1000×700) | Tasks 10, 11 |
| Decision 4 (Honk ticker 35–60s + app-change bonus) | Task 8 |
| Decision 5 (Rich context) | Tasks 2, 3 |
| `GooseAction.swift` reshape | Task 1 |
| `Personality.swift` | Task 4 |
| `FoundationModelClient.swift` | Task 5 |
| `GooseBrain` rewrite | Task 6 |
| `RealBrowserWindow.swift` | Task 10 |
| `BrowseTask` rewrite | Task 11 |
| `HonkTicker.swift` | Task 8 |
| `ContextSnapshot` extension | Task 2 |
| `PerceptionEngine` updates | Task 3 |
| `AgentDirector` updates | Tasks 7 (temp), 9 (full) |
| `GooseScene` wiring | Task 9 |
| Delete `BrowserSprite`, `HonkTask`, `Browse/` | Task 12 |
| `--brain-dryrun` flag | Task 7 |
| `--browser-demo` flag | Tasks 7 (stub), 11 (real) |
| README + privacy doc | Task 13 |
| Tuning constants | Task 4 (`Tuning` enum) |

All 9 migration-checklist items in the spec map to tasks above. ✅

**Type-consistency spot checks:**
- `GooseDecision` uses `browseURL: URL?` (Task 1) and `AgentDirector.execute` reads `decision.browseURL` (Task 9). ✓
- `BrowseTask.init(url:effects:)` defined Task 11; called by `AgentDirector` Task 9 and `--browser-demo` Task 11. ✓
- `HonkTicker(simulation:perception:)` defined Task 8; constructed in `GooseScene` Task 9. ✓
- `Personality.bucket(for:)` and `Personality.tone(forTimeOnApp:idle:)` defined Task 4; used in `GooseBrain` Task 6 and dryrun Task 7. ✓
- `Tuning.honkBaseRange` / `honkAppChangeDebounce` / `browseDwellSeconds` / `fmTimeoutSeconds` / `agentLoopRange` defined Task 4; consumed by `HonkTicker` Task 8, `BrowseTask` Task 11, `FoundationModelClient` Task 5, `AgentDirector` Task 9, `--browser-demo` Task 11. ✓

**Placeholder scan:** none. Every step has the actual code or the actual command.

**Known minor risks:**
- The `WKWebView` slide-in animation uses `setFrame(_:display:)` inside an `NSAnimationContext` — frame animations on borderless windows are sometimes janky on macOS. If the slide looks bad in Task 11 verification, swap to animating `alphaValue` only and just `setFrame` to the final position once.
- `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .anyInputEventType)` requires no special permission. If it returns negative/NaN on some systems (rare), the `currentIdleSeconds()` clamp returns 0.
