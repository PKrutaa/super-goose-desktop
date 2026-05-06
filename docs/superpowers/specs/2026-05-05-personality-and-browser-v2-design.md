# Goose Personality & Browser v2 — Design

**Date:** 2026-05-05
**Scope:** Goose Swift (`Goose/`). C# reference (`Source/`) untouched.

## Goals

1. Give the goose a coherent **personality** that drives every line of text it writes/says.
2. Replace the cartoony 280×200 `BrowserSprite` with a **real WKWebView window** the goose drags onto the screen.
3. Make the goose **opine more** about the user's current activity, using OCR + Accessibility context that already gets captured but is currently ignored.
4. **Honk more often** and tie honks to context changes.

## Non-goals

- AppleScript scripting parity with the original C# port.
- A settings UI. Defaults are tuned in code; `defaults`-style override is out of scope for this spec.
- Test target / unit tests (project has none today; we add headless smoke entry-points instead).
- Network-based content fetching beyond what WKWebView does itself.

## Decisions (locked)

| # | Decision | Choice |
|---|---|---|
| 1 | Brain mechanism | **Hybrid** — deterministic for honk/short text/queries; Apple Foundation Models for the opinionated sticky note, with deterministic fallback on failure or unavailability. |
| 2 | Personality voice | **Sarcastic-cynical with curious bursts.** Dry, direct, lightly cruel but not mean; occasionally distracted by random curiosity. Lower-case, no emojis. |
| 3 | "Big browser" rendering | **WKWebView in a borderless NSWindow** at 1000×700, click-through, dragged in by the goose. |
| 4 | Honk cadence | **Independent ticker**, 35–60s base interval, plus a debounced (30s) bonus honk on frontmost-app change. Decoupled from the agent loop. |
| 5 | Context inputs | **Rich:** frontmost app + time on app + previous app + idle seconds + OCR top-K snippets + access to last 6 snapshots. All on-device. |

## Architecture

Three independent subsystems coordinate through `GooseSimulation` and a shared `Personality` value:

1. **Personality** — the voice. Owns the system prompt for FM, the tone tags, and the deterministic content pools indexed by `(tone, AppBucket)`. Stateless.
2. **GooseBrain (hybrid)** — `decide(snapshot, recentActions, personality) → GooseDecision`. Roulette over actions; `.note` calls `FoundationModelClient` (with deterministic fallback); `.browse` picks a URL via `Personality`. Honk no longer goes through here.
3. **HonkTicker** — runs in parallel with `AgentDirector`. Sleeps 35–60s, fires `simulation.onHonk?()`. Observes frontmost-app changes via `PerceptionEngine` and adds a debounced bonus honk.

### File-level changes

```
Goose/Sources/Goose/
├── AI/
│   ├── Personality.swift              ← NEW
│   ├── FoundationModelClient.swift    ← NEW
│   ├── HonkTicker.swift               ← NEW
│   ├── GooseBrain.swift               ← rewritten as hybrid
│   ├── AgentDirector.swift            ← removes honk handling
│   └── GooseAction.swift              ← .honk case removed; GooseDecision.browseQuery+browseSource → browseURL: URL?
├── Perception/
│   ├── ContextSnapshot.swift          ← +timeOnFrontmostApp, prevFrontmostAppName, idleSeconds, ocrTopK
│   └── PerceptionEngine.swift         ← populates new fields, exposes recentSnapshots, lastFrontmostAppName
├── Tasks/
│   └── BrowseTask.swift               ← rewritten to drive RealBrowserWindow
├── Windows/
│   ├── FloatingWindow.swift           ← unchanged (notes/photos)
│   └── RealBrowserWindow.swift        ← NEW (NSWindow + WKWebView)
├── Scene/
│   └── BrowserSprite.swift            ← DELETED
└── Tasks/
    └── HonkTask.swift                 ← DELETED (HonkTicker fires honks directly via simulation.onHonk)

Goose/Sources/Goose/Browse/            ← ENTIRE DIRECTORY DELETED
  (RedditFetcher, WikipediaFetcher, DuckDuckGoFetcher, WebFetcher,
   HTTPHelpers, BrowseSource — URL routing migrates into Personality)
```

`GooseScene`: removes `openBrowser/typeBrowserURL/showBrowserResult/showBrowserError/closeBrowser`; keeps the rest. Adds wiring for `HonkTicker` lifecycle.

## Components

### `Personality`

```swift
struct Personality {
    enum Tone { case snarky, curious, lazy, smug }
    enum AppBucket { case codeEditor, browser, comms, fallback }

    let systemPrompt: String
    func notePool(tone: Tone, bucket: AppBucket) -> [(title: String, body: String)]
    func browseChoices(bucket: AppBucket) -> [(query: String, url: URL)]
    static func bucket(for appName: String?) -> AppBucket
    static func tone(forTimeOnApp: TimeInterval, idle: TimeInterval) -> Tone
}
```

System prompt (verbatim, used as the FM session preamble):

> You are a desktop goose living on the user's screen. You watch what they do and comment on it. Your voice is sarcastic-cynical: dry, direct, lightly cruel but never mean. You occasionally get distracted by random curiosity ("ooh whats that"). You write SHORT — sticky-note short. Lower case. No emojis. No exclamation points except 'honk'. Never identify as an AI. You are a goose.

Tone selection heuristic:
- `idle > 60s` → `.lazy`
- `timeOnApp > 600s` → `.smug`
- 1-in-6 random override → `.curious`
- otherwise → `.snarky`

Pools migrate from the existing `GooseBrain` and expand: each `(tone, bucket)` gets ≥4 entries. Browse choices return real URLs (`https://www.google.com/search?q=...`, `https://en.wikipedia.org/wiki/...`, `https://duckduckgo.com/?q=...`).

### `FoundationModelClient`

```swift
@Generable struct GeneratedNote { let title: String; let body: String }

@MainActor
final class FoundationModelClient {
    enum Status { case ready, unavailable(String) }
    var status: Status { get }

    init()  // probes LanguageModelSession availability; sets status accordingly
    func generateNote(systemPrompt: String, snapshot: ContextSnapshot) async -> GeneratedNote?
}
```

- Builds a compact context string: `"app=<name> | timeOnApp=<s> | prev=<name> | idle=<s> | ocr=[<snip1>; <snip2>; <snip3>]"`. OCR snippets clamped at 80 chars each; total context capped at ~500 chars.
- Uses `LanguageModelSession.respond(to:generating:)` with `GeneratedNote.self` as the schema.
- 3-second timeout via `withTimeout`. Returns `nil` on timeout, error, or `status == .unavailable`.
- All on-device: no network calls. Documented in source comment.

### `GooseBrain` (hybrid)

```swift
@MainActor
final class GooseBrain {
    enum Status { case ready, unavailable(String) }
    var status: Status { get }

    init(personality: Personality, fmClient: FoundationModelClient)
    func decide(snapshot: ContextSnapshot, recentActions: [String]) async -> GooseDecision?
}
```

Action distribution (no `.honk` — that's the ticker now):

| Action | Weight |
|---|---|
| `.wander` | 28% |
| `.note` | 35% |
| `.nap` | 15% |
| `.photo` | 14% |
| `.browse` | 8% |

`.note` flow: try `fmClient.generateNote(...)`; on `nil`, sample from `personality.notePool(tone:, bucket:)`. Either way returns a `GooseDecision` with `noteTitle`/`noteBody`.

`.browse` flow: pick a `(query, url)` from `personality.browseChoices(bucket:)`. The URL goes into `GooseDecision.browseURL` (new field; replaces `browseQuery` + `browseSource`).

`recentActions` filter (avoid back-to-back duplicates) — keep current behavior.

### `RealBrowserWindow`

```swift
@MainActor
final class RealBrowserWindow: NSWindow {
    static let size = CGSize(width: 1000, height: 700)

    init(url: URL)                  // borderless, .floating, hasShadow=true,
                                    // ignoresMouseEvents=true, isOpaque=true
    func slideIn(from edge: NSRectEdge) async   // animates onto screen
    func dismiss() async                         // fade + scale-down, then close
}
```

- Content view = `WKWebView`. Loads URL in `init`.
- Click-through (`ignoresMouseEvents = true`) — it's a spectacle, not a tool.
- Level `.floating`: above normal app windows, below the goose overlay (`.screenSaver`), so the goose still walks on top of it.
- `slideIn` animates over ~0.5s; `dismiss` over ~0.4s.

### `BrowseTask` (rewritten)

1. Stop the goose; spawn `RealBrowserWindow(url:)` off-screen at the right edge.
2. Reuse `DragWindowTask` semantics: goose walks to a grab point, "grabs" the window's leading edge, drags it to a stable on-screen position (centered horizontally, ~30% from top).
3. Window calls `webView.load(...)` immediately on init — page is loading while being dragged.
4. Dwell: 12s (configurable constant).
5. Goose returns, "bites" the window's edge, calls `dismiss()`. Window animates out, closes.
6. Resume `WanderTask`.

### `HonkTicker`

```swift
@MainActor
final class HonkTicker {
    init(simulation: GooseSimulation, perception: PerceptionEngine)
    func start()
    func stop()
}
```

- Two concurrent `Task`s:
  - **Base ticker:** `try? await Task.sleep(for: .seconds(.random(in: 35...60)))` → `simulation.onHonk?()` → loop.
  - **App-change watcher:** polls `perception.lastFrontmostAppName` every 2s; when it changes and ≥30s since the last bonus honk, fires `simulation.onHonk?()` and updates the bonus timestamp.
- Honk audio path remains `simulation.onHonk → AudioPlayer.playHonk()`.

### `PerceptionEngine` / `ContextSnapshot` changes

```swift
struct ContextSnapshot {
    // existing fields...
    let timeOnFrontmostApp: TimeInterval
    let prevFrontmostAppName: String?
    let idleSeconds: TimeInterval
    let ocrTopK: [String]            // up to 3, each ≤80 chars
}
```

`PerceptionEngine`:
- `timeOnFrontmostApp` already tracked internally (`elapsedOnCurrentApp`) — surface it.
- `prevFrontmostAppName`: hold the previous value across snapshot calls.
- `idleSeconds`: `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .anyEventType)`.
- `ocrTopK`: take the existing recognized text, split into lines, drop blanks/noise, take the 3 longest meaningful substrings, clamp to 80 chars.
- Expose `recentSnapshots: [ContextSnapshot]` (the existing 6-deep ring buffer) for the brain.
- Expose `lastFrontmostAppName: String?` for `HonkTicker`.

### `AgentDirector`

- Drop the `.honk` case from `execute(decision:)`.
- Inject `Personality` and `FoundationModelClient` into the `GooseBrain`.
- Otherwise unchanged. Loop interval stays 30–75s.

### `GooseScene`

- Remove `currentBrowser`, `BrowserSprite` references, and the five `openBrowser*` methods.
- On scene setup: instantiate `HonkTicker(simulation:, perception:)` and `start()` it; `stop()` on teardown.
- Wire `simulation.onHonk = { [weak audio] in audio?.playHonk() }` (already does this — keeps).

## Data flow

```
PerceptionEngine.captureSnapshot()
  └── ContextSnapshot { app, timeOnApp, prevApp, idle, ocrTopK, recent[] }
        ↓
AgentDirector.tick()
  └── GooseBrain.decide(snapshot, recentActions)
        ├── deterministic roulette → action
        ├── if .note → FoundationModelClient.generateNote(...) ?? Personality.notePool(...)
        └── if .browse → Personality.browseChoices(...)
              ↓
        GooseDecision
              ↓
AgentDirector.execute(decision)
  └── simulation.setTask(BrowseTask | NapTask | DragWindowTask{note|photo})

HonkTicker (parallel)
  ├── 35–60s timer → simulation.onHonk?()
  └── frontmost-app change (debounced 30s) → simulation.onHonk?()
```

## Error handling

| Failure | Behavior |
|---|---|
| Foundation Models unavailable (no model, unsupported macOS, init throws) | `FoundationModelClient.status = .unavailable`. `.note` always uses `Personality.notePool`. Logged to stderr once at startup. |
| FM `generateNote` throws or times out (>3s) | Returns `nil`. Brain falls back to deterministic pool. No retry within the same decision. |
| WKWebView fails to load (no network, bad URL) | Window still appears with the white WebKit error page. After dwell, dismissed normally. No special handling. |
| Accessibility permission missing for app probe | `lastFrontmostAppName` stays `nil`. App-change bonus honks simply don't fire. (Existing behavior — `AccessibilityProbe` already handles this.) |
| Screen Recording permission missing for OCR | `ocrTopK = []`. FM still gets app + idle context. (Existing behavior in `ScreenCapturer`.) |

## Privacy

All perception runs **on-device**. Foundation Models is on-device by design (Apple Intelligence). OCR runs locally via Vision. No snapshot data, OCR text, or context strings ever leave the machine. The only network traffic is the user-visible WKWebView loading a URL the goose chose — clearly observable. This will be documented in `Goose/README.md`.

## Headless smoke entry-points (in lieu of a test target)

Existing: `swift run Goose --render-preview <path>`. Add two more in `main.swift`:

- `swift run Goose --brain-dryrun` — instantiates `Personality` + `GooseBrain` + a stub `ContextSnapshot`, runs 20 `decide()` calls, prints each decision and (if used) FM vs fallback to stderr. Exits.
- `swift run Goose --browser-demo "<query>"` — opens just `RealBrowserWindow` with the URL `Personality` would pick, dwells 12s, exits. No goose, no overlay.

Both are exit-on-completion; they share `main.swift`'s flag-parsing pattern.

## Tuning constants (single source of truth)

Put in `Personality.swift` so a future settings UI can override:

```swift
enum Tuning {
    static let honkBaseRange: ClosedRange<TimeInterval> = 35...60
    static let honkAppChangeDebounce: TimeInterval = 30
    static let browseDwellSeconds: TimeInterval = 12
    static let fmTimeoutSeconds: TimeInterval = 3
    static let agentLoopRange: ClosedRange<TimeInterval> = 30...75
}
```

## Out of scope (explicitly)

- Persisting recent actions across launches.
- Multiple personalities / user-selectable persona.
- Localization. All copy stays English.
- Settings UI / `defaults`-based overrides.
- A test target.

## Migration checklist

1. Add `Personality.swift`, `FoundationModelClient.swift`, `HonkTicker.swift`, `RealBrowserWindow.swift`.
2. Update `GooseAction.swift`: remove `.honk` case from `GooseAction`; replace `GooseDecision.browseQuery`/`browseSource` with `browseURL: URL?`.
3. Extend `ContextSnapshot` and `PerceptionEngine`.
4. Rewrite `GooseBrain` (hybrid) and `BrowseTask` (drives `RealBrowserWindow`).
5. Update `AgentDirector` (drop honk, inject Personality + FM client).
6. Wire `HonkTicker` into `GooseScene` lifecycle.
7. Delete `Scene/BrowserSprite.swift`, `Tasks/HonkTask.swift`, and the entire `Browse/` directory; remove `GooseScene` browser methods.
8. Add `--brain-dryrun` and `--browser-demo` flags to `main.swift`.
9. Update `Goose/README.md`: privacy paragraph, status section reflecting personality + real browser.
