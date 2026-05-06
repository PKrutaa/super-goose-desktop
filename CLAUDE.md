# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

This repo holds **two separate codebases for the same app**:

- `Goose/` — **the active project**: a Swift 6.2 / SPM port targeting macOS 26+. All new work happens here.
- `Source/GooseDesktop/` — the original C# (WinForms/MonoGame) code from samperson, kept as **read-only reference** when porting behaviors. Do not modify.
- `Desktop Goose v0.22/` and `Desktop Goose v0.22.zip` — Jesús A. Álvarez's prior Mac port, also reference-only.

The Swift port is more than a 1:1 rewrite — it's evolving the goose into an agent that observes the screen (Vision OCR + Accessibility) and decides actions via Apple Foundation Models. See `Goose/README.md` for the slice roadmap.

## Build / run / develop

All commands run from `Goose/`:

```bash
swift build             # debug build
swift run               # build + launch the overlay
swift run Goose --render-preview /tmp/goose.png   # headless single-frame render (used for visual diffs)
swift build -c release
```

There is no test target yet — `swift test` will report no tests. Do not invent one unless asked.

### First-time setup gotcha

Goose sprites are **not versioned**. Before the first `swift run`, populate `Goose/Sources/Goose/Resources/Sprites/Goose/` from `https://github.com/romainflcht/py-goose` (see `Goose/README.md` for the exact `cp` recipe). A build will succeed without sprites, but the scene will be empty.

### Quitting a running instance

The overlay is borderless, click-through, and on `.screenSaver` level — there is no window to close. To kill it: hold **ESC ~1.5s**, click the 🪿 status item, or `pkill -f Goose` from another terminal.

## Architecture

Entry: `main.swift` → `AppDelegate` → `OverlayWindow` (transparent, click-through, joins all Spaces) → `GooseScene` (SpriteKit). The scene drives a per-frame `update`, ticking the simulation and rendering.

Three layers, deliberately decoupled:

1. **Engine / simulation** (`Engine/`, `Scene/`)
   `GooseSimulation` is the single source of truth for goose state (position, velocity, feet IK, current task). It exposes mutable fields that tasks read/write directly each tick — there's no event bus. `GooseRig` derives a renderable pose; `GooseArt` (in `Scene/`) draws it. Math helpers ported from the C# original live in `SamMath.swift`, `Vec2Math.swift`, `Easings.swift`.

2. **Tasks** (`Tasks/`)
   Behaviors implement the `GooseTask` protocol (`start` + per-frame `tick`). One task is active at a time via `simulation.setTask(...)`. Tasks own their timing/state and mutate the simulation directly. When adding behavior, prefer a new task over wedging logic into the simulation.

3. **AI / agent loop** (`AI/`, `Perception/`)
   `AgentDirector` runs a 30–75s loop: `PerceptionEngine.captureSnapshot()` (screen capture + Vision OCR + Accessibility frontmost-app probe) → `GooseBrain.decide(...)` returns a `GooseDecision` → director maps it to a task. `GooseBrain` is currently a **deterministic stub** with weighted probabilities; the seam for swapping in `LanguageModelSession.respond(to:generating:)` is documented at the top of `GooseBrain.swift`. `GooseDecision` / `GooseAction` are the contract — keep them shaped to be `@Generable`-friendly.

Supporting modules:
- `Browse/` — fetchers for Reddit/Wikipedia/DuckDuckGo, used by `BrowseTask` to populate the in-app fake browser sprite.
- `Windows/FloatingWindow.swift` — real `NSWindow`s the goose drags around (sticky notes, photos). Click-through is intentionally disabled on these so the user can interact.
- `Photos/PhotoLibrary.swift` — pulls random images from `~/Pictures`.
- `Audio/AudioPlayer.swift` — honk/bite via AVAudioEngine.
- `Input/EscQuitMonitor.swift` — global ESC-hold polling (the overlay can't be key window).
- `Tools/PreviewRenderer.swift` — renders one frame to PNG for the `--render-preview` flag.

### Concurrency

Almost everything is `@MainActor`. SpriteKit, AppKit, and the simulation all live on the main thread. Async work (perception, network fetchers, brain) uses `Task` and `await`s back to main before mutating simulation state. Don't introduce background queues for engine state — keep the main-actor invariant.

## Conventions worth following

- **Logging**: warnings/errors go to **stderr** via `FileHandle.standardError.write(...)` (see `PerceptionLog`). This is intentional — running from a terminal surfaces permission/setup issues without opening Console.app. Prefer this pattern over `print` or `os_log` for diagnostics.
- **Pixel art**: the SKView uses `.nearest` filtering. Don't add bilinear scaling or smoothed transforms to sprites.
- **No XCConfig / Xcode project files**: this is pure SPM. The `.gitignore` explicitly excludes `*.xcodeproj` — do not commit one.
- **Reference C# when porting**: when implementing a new task or engine behavior, check `Source/GooseDesktop/` for the original (e.g. `TheGoose.cs`, `MainGame.cs`, `FootMark.cs`). The Swift names mirror the C# ones intentionally.
- The Swift target requires `macOS(.v26)` and `swift-tools-version: 6.2` — don't lower these to broaden compatibility unless asked.
