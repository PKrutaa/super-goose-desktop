# Spotify + Chilling Pose — Design

**Date:** 2026-05-07
**Branch:** `feat/spotify-chilling`
**Scope:** Goose Swift (`Goose/`).

## Goal

Goose occasionally puts on headphones, sits down, and plays music on the user's Spotify. In character: it picks the song, the user gets it whether they wanted it or not.

## Decisions (locked)

| # | Decision | Choice |
|---|---|---|
| 1 | Spotify integration | AppleScript via `osascript` Process. No auth, no API keys. Controls user's Spotify.app directly. |
| 2 | Music source | Hardcoded curated **playlist** URIs by mood (chill / focus / hype). Playlists are more stable than tracks and survive regional unavailability. |
| 3 | Mood selection | App-bucket-driven — Slack/Mail/Messages → chill; code editor → focus; everything else → random. |
| 4 | Interruption policy | **Always interrupt.** If Spotify is running, takes over. If not running, AppleScript launches it. |
| 5 | Fallback when Spotify is unavailable | Chill anyway: headphones go on, goose sits, no audio. The meme is the visual; missing audio is a soft failure. |
| 6 | Headphones visual | `SKShapeNode` pixel-style: black arc band + two oval cups. Tracks `rig.neckHeadPoint` each frame. `.nearest` filtering for consistency with goose pixel art. |
| 7 | Chill duration | 45–90s, then headphones come off, goose resumes wander. No active "stop Spotify" — playlist keeps playing. |
| 8 | Brain distribution | New `.chill` action at 5%, taking from `.wander` (28% → 23%). |

## Non-goals

- OAuth / Web API integration.
- Per-user playlist preferences or settings UI.
- Restoring user's previous music when chill ends.
- Beat-synced animation. Head bob is fake (sine wave).
- Apple Music / YouTube Music integration.
- Resume-where-it-left-off across runs.

## Architecture

Three new files, four small modifications. Spotify control is fire-and-forget; the goose doesn't track playback state.

### File-level changes

```
Goose/Sources/Goose/
├── Audio/
│   └── SpotifyController.swift          ← NEW
├── Scene/
│   ├── HeadphonesNode.swift             ← NEW
│   └── GooseScene.swift                 ← MODIFY (instantiate node, wire effect)
├── Tasks/
│   └── ChillingTask.swift               ← NEW
└── AI/
    ├── Personality.swift                ← MODIFY (add chillPlaylists by mood)
    ├── GooseAction.swift                ← MODIFY (add .chill + spotifyURI field)
    ├── GooseBrain.swift                 ← MODIFY (roulette + mood→playlist)
    ├── AgentDirector.swift              ← MODIFY (handle .chill)
    └── GooseSceneEffects.swift          ← MODIFY (add setHeadphones API)
```

## Components

### `SpotifyController`

```swift
@MainActor
enum SpotifyController {
    /// Best-effort: tells Spotify.app to play the URI. Returns true on success.
    /// On failure (Spotify not installed, AppleScript permission denied, etc.),
    /// returns false. Never throws — caller proceeds with the visual chill anyway.
    static func play(uri: String) async -> Bool
}
```

- Uses `Process` + `/usr/bin/osascript`. Command:
  `tell application "Spotify" to play track "<uri>"`
- Process timeout 3s.
- Exit code 0 → true; anything else → log to stderr, return false.
- Runs off-main inside a detached `Task` to avoid blocking the simulation tick during AppleScript negotiation.

### `Personality.swift` extension

```swift
extension Personality {
    enum Mood: Sendable { case chill, focus, hype }

    static func mood(for bucket: AppBucket) -> Mood {
        switch bucket {
        case .comms: return .chill
        case .codeEditor: return .focus
        case .browser, .fallback: return Bool.random() ? .chill : .hype
        }
    }

    func chillPlaylists(mood: Mood) -> [String] {
        switch mood {
        case .chill: return [
            "spotify:playlist:37i9dQZF1DWWQRwui0ExPn",   // Lo-Fi Beats (Spotify)
            "spotify:playlist:37i9dQZF1DX4WYpdgoIcn6",   // Chill Hits
            "spotify:playlist:37i9dQZF1DX0SM0LYsmbMT",   // Jazz in the Background
        ]
        case .focus: return [
            "spotify:playlist:37i9dQZF1DWZeKCadgRdKQ",   // Deep Focus
            "spotify:playlist:37i9dQZF1DX9sIqqvKsjG8",   // Coding Mode
            "spotify:playlist:37i9dQZF1DX8NTLI2TtZa6",   // Lo-Fi Cafe
        ]
        case .hype: return [
            "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M",   // Today's Top Hits
            "spotify:playlist:37i9dQZF1DWXRqgorJj26U",   // Rock Classics
            "spotify:playlist:37i9dQZF1DX1lVhptIYRda",   // Hot Country
        ]
        }
    }
}
```

> URIs above are Spotify's editorial playlist URIs — long-lived but technically subject to Spotify changing them. Wrong URIs fail gracefully (Spotify just plays nothing or errors); the chill animation still runs. User can edit this list freely.

### `GooseAction.swift` change

Add to `GooseDecisionType`: `case chill`. Add to `GooseDecision`: `let spotifyURI: String?` (default nil).

### `GooseBrain.swift` change

Add roulette arm:
```swift
// distribution: wander 23%, note 35%, nap 5%, deepSleep 10%, chill 5%, photo 14%, browse 8%
```

New `pickChill(bucket:)` method picks a random URI from `personality.chillPlaylists(mood: .mood(for: bucket))`.

### `AgentDirector.swift` change

Add to `execute(decision:)`:
```swift
case .chill:
    simulation.setTask(ChillingTask(spotifyURI: decision.spotifyURI, effects: effects))
```

### `ChillingTask`

```swift
@MainActor
final class ChillingTask: GooseTask {
    private static let minDuration: CGFloat = 45
    private static let maxDuration: CGFloat = 90

    private let spotifyURI: String?
    private weak var effects: GooseSceneEffects?
    private var endTime: CGFloat = 0

    init(spotifyURI: String?, effects: GooseSceneEffects)
    func start(simulation:)   // velocity zero, headphones on, fire spotify play
    func tick(simulation:)    // hold velocity at zero; on timeout → headphones off, WanderTask
}
```

- On `start`: `effects.setHeadphones(visible: true)` and detached `Task { await SpotifyController.play(uri:) }`. Duration randomized.
- On `tick`: keep velocity at zero. When `GameTime.time >= endTime`, `effects.setHeadphones(visible: false)` and transition to `WanderTask`.

### `HeadphonesNode`

```swift
@MainActor
final class HeadphonesNode: SKNode {
    init()                      // builds band + 2 cups as SKShape, hidden by default
    func show()                 // fade-in (0.25s)
    func hide()                 // fade-out (0.25s)
    func update(rig: GooseRig)  // tracks rig.neckHeadPoint each frame
}
```

- Band: small black arc (SKShapeNode with stroked path).
- Cups: two black `SKShapeNode(circleOfRadius: 3)` offset on the rig's `perpendicular` axis.
- Position = `rig.neckHeadPoint`. Z above the goose body but below the FloatingWindow / RealBrowserWindow z.
- All shapes use `lineWidth = 2`, `antialiased = false` to keep the pixel-art style.

### `GooseSceneEffects.swift` change

Add to protocol:
```swift
func setHeadphones(visible: Bool)
```

### `GooseScene.swift` change

- Instantiate `HeadphonesNode` once in `didMove(to:)`, add to `gooseContainer`.
- In `update(_:)`, after `goose.update(simulation:)`, call `headphones.update(rig: ...)`. The rig is already computed by `GooseArt`; expose its current rig via a `currentRig` property on `GooseArt` (small addition) or recompute cheaply here using `simulation.position / direction / neckLerpPercent`.
- Implement `setHeadphones(visible:)` — calls `headphones.show()` / `hide()`.

## Data flow

```
AgentDirector.tick
  └── brain.decide → GooseDecision(.chill, spotifyURI: "spotify:playlist:...")
        └── simulation.setTask(ChillingTask)
              ├── effects.setHeadphones(visible: true)
              ├── Task { SpotifyController.play(uri:) }   // fire-and-forget
              └── (45–90s timeout)
                    └── effects.setHeadphones(visible: false)
                          → WanderTask
```

## Error handling

| Failure | Behavior |
|---|---|
| Spotify.app not installed | `osascript` exits with error → `SpotifyController.play` returns false → stderr log. Goose still chills with no audio. |
| AppleScript permission denied (first run) | Same as above — false return, log. macOS prompts the user to grant permission on the first attempt; second run will work. |
| Bad/expired playlist URI | Spotify silently fails or plays nothing. Goose chills regardless. No retry. |
| `osascript` itself missing (impossible on macOS) | Same fail-soft path. |

## Privacy

`SpotifyController` runs entirely locally — `osascript` never reaches the network on its own. Spotify's playback obviously does (it's a streaming app), but that's user-visible and expected. No song picks, app names, or user data leave this process.

## Testing

Same constraint — no test target. Verification:
- `swift build` clean.
- `swift run Goose --brain-dryrun` — over 20 decisions, expect ~1 `.chill`.
- New smoke flag: `swift run Goose --chill-demo` — runs `SpotifyController.play(uri:)` against the first focus-mood playlist + opens a tiny preview window with a static `HeadphonesNode`. Exits after 5s. Skipped if not testing audio.
- Visual smoke: `swift run Goose`, wait for `.chill` decision, observe headphones + Spotify play.

## Migration checklist

1. Create `Audio/SpotifyController.swift`.
2. Create `Scene/HeadphonesNode.swift`.
3. Create `Tasks/ChillingTask.swift`.
4. Extend `Personality.swift` with `Mood`, `mood(for:)`, `chillPlaylists(mood:)`.
5. Modify `GooseAction.swift` (`.chill` case + `spotifyURI` field).
6. Modify `GooseBrain.swift` (roulette + `pickChill`).
7. Modify `AgentDirector.swift` (handle `.chill`).
8. Modify `GooseSceneEffects.swift` (`setHeadphones(visible:)`).
9. Modify `GooseScene.swift` (instantiate + per-frame `update` + protocol impl).
10. Add `--chill-demo` smoke flag to `main.swift`.
11. Build + dryrun + visual smoke.
12. Commit + push branch.
