# Chilling Frequency + LLM Wire-Up — Amendment

**Date:** 2026-05-07
**Branch:** `feat/spotify-chilling`
**Amends:** `2026-05-07-spotify-chilling-design.md`

## Problem

After landing the initial chilling feature on `feat/spotify-chilling`, real-world usage showed:

1. **Too rare.** Chill at 5% of agent loop ticks (every 30–75s) means expected time to first chill ≈ 10 minutes. User reports listening to music for "a long time" and the goose never interrupted.
2. **Not contextual.** Mood is hardcoded `AppBucket → Mood`. Doesn't use OCR, time-on-app, or recent activity.
3. **FM stub.** `FoundationModelClient` always returns `nil`. The seam exists; it was never lit.

User has confirmed Apple Intelligence is enabled on this Mac. Path: wire FM for real, decouple chilling from the agent loop, increase frequency.

## Decisions (locked)

| # | Decision | Choice |
|---|---|---|
| 1 | FM integration | Wire `LanguageModelSession` from `FoundationModels` for real, gated by `#if canImport(FoundationModels)`. **No `@Generable` macros** (build-hang risk per existing comment in `GooseAction.swift`). Use plain `respond(to:)` returning `String`; instruct the model to emit strict JSON; parse with `JSONDecoder`. |
| 2 | Chilling cadence | New `ChillingTicker` parallel to `HonkTicker`. Tick every 90–180s + bonus tick on frontmost-app change (debounced 60s). Expected time to first chill drops from ~10min to ~90s. |
| 3 | Brain `.chill` rate | Keep `.chill` in roulette as belt-and-suspenders; bump 5% → 15%. If both ticker and brain fire chill near each other, `simulation.setTask` overrides cleanly — no race damage. |
| 4 | LLM call structure | One call per ChillingTicker tick: `decideChill(snapshot, candidatePlaylists)` → returns `{shouldChill, playlistURI, reason}`. Caller checks `shouldChill`, dispatches `ChillingTask` if true. |
| 5 | Fallback when FM unavailable | Ticker uses deterministic logic: 60% chill probability per tick, mood from bucket. Maintains the higher cadence even without LLM. |
| 6 | LLM budget | Model is on-device → no $$ concern. Each call is cheap. We make one call every 90–180s plus app-change bonus → ~30 calls/hour worst case. Acceptable. |

## Architecture

```
Goose/Sources/Goose/
├── AI/
│   ├── FoundationModelClient.swift   ← REWRITE: real LanguageModelSession + JSON parse
│   ├── ChillingTicker.swift          ← NEW
│   ├── GooseBrain.swift              ← MODIFY: chill 5% → 15% (small redistribution)
│   └── (unchanged: AgentDirector, Personality, GooseAction)
└── Scene/
    └── GooseScene.swift              ← MODIFY: instantiate ChillingTicker
```

## `FoundationModelClient` rewrite

### Status detection

```swift
#if canImport(FoundationModels)
import FoundationModels

private func computeStatus() -> Status {
    let model = SystemLanguageModel.default
    switch model.availability {
    case .available: return .ready
    case .unavailable(let reason): return .unavailable(String(describing: reason))
    @unknown default: return .unavailable("unknown availability state")
    }
}
#else
private func computeStatus() -> Status {
    .unavailable("FoundationModels SDK not available")
}
#endif
```

> If a method/property name above doesn't match the actual SDK at compile time, fix the names to match — the *shape* of the integration stands.

### Note generation (existing API kept compatible)

```swift
func generateNote(systemPrompt: String, snapshot: ContextSnapshot) async -> GeneratedNote? {
    guard case .ready = status else { return nil }
    let prompt = Self.notePrompt(snapshot: snapshot)
    let raw = await runWithTimeout(seconds: Tuning.fmTimeoutSeconds) {
        await self.callJSON(systemPrompt: systemPrompt, prompt: prompt)
    }
    guard let raw,
          let data = raw.data(using: .utf8),
          let decoded = try? JSONDecoder().decode(GeneratedNote.self, from: data) else {
        return nil
    }
    return decoded
}
```

`GeneratedNote` becomes `Codable` (already a struct; add conformance).

### New: `decideChill`

```swift
struct ChillDecision: Codable, Sendable {
    let shouldChill: Bool
    let playlistURI: String
    let reason: String
}

func decideChill(systemPrompt: String, snapshot: ContextSnapshot, candidates: [String]) async -> ChillDecision? {
    guard case .ready = status else { return nil }
    let prompt = Self.chillPrompt(snapshot: snapshot, candidates: candidates)
    let raw = await runWithTimeout(seconds: Tuning.fmTimeoutSeconds) {
        await self.callJSON(systemPrompt: systemPrompt, prompt: prompt)
    }
    guard let raw,
          let data = raw.data(using: .utf8),
          let decoded = try? JSONDecoder().decode(ChillDecision.self, from: data) else {
        return nil
    }
    return decoded
}
```

### Prompt template — chill

System prompt: existing `Personality.systemPrompt`, plus appended directive:
> "When asked to make a decision, respond with strict JSON only. No prose, no markdown fences."

Per-call user prompt:
```
context: app=<app> | timeOnApp=<n>s | prev=<prev> | idle=<n>s | ocr=[<top1>; <top2>; <top3>]
candidate playlists (Spotify URIs):
- spotify:playlist:... (mood: chill, name: Lo-Fi Beats)
- spotify:playlist:... (mood: focus, name: Deep Focus)
- ...

Decide whether the goose should put on headphones and play music for the user RIGHT NOW.
Be liberal — the goose is sociable and enjoys soundtracking the user's work. Default to yes
unless the context strongly implies it would be obnoxious (e.g. user is on a video call,
recording, or in deep focus on a tight task).

Respond with strict JSON only:
{"shouldChill": <bool>, "playlistURI": "<one of the candidates>", "reason": "<one short phrase>"}
```

### Internal `callJSON`

```swift
private func callJSON(systemPrompt: String, prompt: String) async -> String? {
    #if canImport(FoundationModels)
    do {
        let session = LanguageModelSession(instructions: systemPrompt + " Respond with strict JSON only.")
        let response = try await session.respond(to: prompt)
        return response.content
    } catch {
        FileHandle.standardError.write(Data("[Goose] FM call failed: \(error)\n".utf8))
        return nil
    }
    #else
    return nil
    #endif
}
```

(`response.content` may be the literal property name; if the SDK uses something else, adjust.)

## `ChillingTicker`

```swift
@MainActor
final class ChillingTicker {
    init(simulation: GooseSimulation,
         perception: PerceptionEngine,
         personality: Personality,
         fmClient: FoundationModelClient,
         effects: GooseSceneEffects)

    func start()
    func stop()
}
```

- Two parallel `Task`s like `HonkTicker`:
  - **Base**: `sleep(random(90...180))` → `tickOnce()`
  - **Watcher**: every 3s, polls `perception.lastFrontmostAppName`. On change + ≥60s since last bonus → `tickOnce()`.
- `tickOnce()`:
  1. Fetch latest snapshot via `perception.captureSnapshot()` (or `mostRecent()` if available — captures are not free).
  2. Build candidate list from `Personality.chillPlaylists` across all 3 moods (with name labels).
  3. Try `fmClient.decideChill(...)`. If ready and result is `shouldChill: true`, fire `ChillingTask(spotifyURI: result.playlistURI, effects:)`.
  4. If FM unavailable: deterministic fallback — 60% chance, mood by `Personality.mood(for:)`, random URI from that mood's list.
  5. Skip if simulation already on a long-running task (DeepSleepTask / ChillingTask / DragWindowTask) — check `simulation.currentTask`. (`currentTask` is `private(set)` already on the simulation.)

## `GooseBrain` change

Distribution becomes: `wander 22%, note 32%, nap 5%, deepSleep 10%, chill 15%, photo 8%, browse 8%`. Photo drops 14→8 to make room. (Photo is the lowest-impact decrease — losing a few photo events doesn't hurt the experience.)

## `GooseScene` wiring

- Construct `ChillingTicker(simulation:perception:personality:fmClient:effects:)` after `HonkTicker` setup. Hold a strong ref. `start()` it. `stop()` in `willMove(from:)`.
- The brain and ticker share the **same** `Personality.default` and a **single** `FoundationModelClient` instance — pass them in.

## Concurrency

All FM calls are `@MainActor` per `FoundationModelClient`'s annotation. The 3s timeout uses the existing `withTimeout` helper. No background queues for FM work — the model is on-device but fast enough that staying on main is fine (and avoids Sendable headaches).

## Privacy

Unchanged from the original chilling spec. FM is on-device. Snapshot context is built locally, never leaves the process. The only network is Spotify itself.

## Migration checklist

1. Rewrite `FoundationModelClient.swift`:
   - Add `#if canImport(FoundationModels)` import.
   - Real status check via `SystemLanguageModel`.
   - Keep `generateNote` API; route through `callJSON`.
   - Add `decideChill` API + `ChillDecision` Codable struct.
2. Make `GeneratedNote: Codable`.
3. Create `Goose/Sources/Goose/AI/ChillingTicker.swift`.
4. Bump `.chill` to 15% (and `.photo` to 8%) in `GooseBrain.rollOnce`.
5. Wire `ChillingTicker` into `GooseScene` lifecycle (mirroring `HonkTicker`).
6. Build + dryrun + push.

## Risks / Mitigations

| Risk | Mitigation |
|---|---|
| `LanguageModelSession` API names differ from the placeholder above | If the build fails on naming, adjust to whatever the SDK exposes. The deterministic fallback ensures the feature still works while debugging. |
| Model returns malformed JSON | `try?` decoder → nil → fallback. We don't crash. |
| Both brain and ticker fire `.chill` near-simultaneously | `simulation.setTask` is last-writer-wins; harmless. |
| Bonus tick fires while goose is already chilling | Skip-if-busy guard inside `tickOnce` (check `simulation.currentTask is ChillingTask` etc). |
| User is on a call and goose interrupts | The system prompt instructs the LLM to skip when the user is in deep focus / call-like context. Imperfect; an OS-level "do not disturb" check is out of scope. |
