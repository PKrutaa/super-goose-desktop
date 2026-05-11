# Contributing

Thanks for your interest in this very serious project.

## Ground rules

- **One change per PR.** Keep the diff focused. A new task + a refactor + a doc update belong in three PRs, not one.
- **Match the voice.** The goose is sarcastic-cynical, antagonistic-friendly, and disruptive. Notes / songs / browse picks should be in character. Quiet productivity features are usually a bad fit.
- **No new runtime dependencies without discussion.** The project deliberately uses only Apple frameworks (AppKit, SpriteKit, WebKit, Vision, FoundationModels, AVAudioEngine) plus the OpenAI HTTP API. Anything else needs a good story.
- **Privacy posture is load-bearing.** Capture / OCR / Accessibility are on-device. Anything sending data off-device must be opt-in and documented. See `README.md` "Privacy".
- **Don't bump deployment targets.** macOS 26.1+ and Swift 6.2+ are required and intentional.

## Running locally

```bash
cd Goose

# One-time: sprite setup (not versioned)
git clone --depth 1 https://github.com/romainflcht/py-goose /tmp/py-goose
mkdir -p Sources/Goose/Resources/Sprites/Goose
cp -R /tmp/py-goose/sprite/* Sources/Goose/Resources/Sprites/Goose/

swift build -c release
swift run
```

There is no test target — that's deliberate. Verification happens through:

```bash
swift run Goose --brain-dryrun        # headless brain check, 20 decisions to stdout
swift run Goose --browser-demo "honk" # WKWebView slide-in / dismiss
swift run Goose --render-preview /tmp/x.png   # single frame headless render
```

CI runs `--brain-dryrun` and asserts shape (20 decisions, no `→ honk`, ≥ 3 distinct action types).

## Architecture pointers

Read `CLAUDE.md` first — it's a one-pager covering the layers (Engine / Tasks / Scene / AI / Perception). Then `docs/superpowers/specs/` for the design history of each major feature.

The protocol you'll most often work with is `GooseTask`:

```swift
@MainActor
protocol GooseTask: AnyObject {
    func start(simulation: GooseSimulation)
    func tick(simulation: GooseSimulation)
    func stop(simulation: GooseSimulation)   // default no-op; override to release visuals on preemption
}
```

If your task paints anything on screen (headphones, particles, dragged windows), it MUST clean up in `stop(simulation:)` — that hook fires on natural completion *and* on any external `setTask(...)` preemption. See `ChillingTask` for the canonical example.

## Code style

SwiftLint runs in CI (`.swiftlint.yml` at the repo root). Lines can be long when they're prose. Force-unwraps are fine for hardcoded URLs / sprite resources. Force-casts for `SKAction` building are tolerated.

Conventions:
- `@MainActor` on everything that touches AppKit, SpriteKit, or simulation state.
- Async work (perception, LLM calls, AppleScript) uses `Task` / `await` and snaps back to main before mutating sim state.
- Diagnostic logging goes to `stderr` via `FileHandle.standardError.write(...)`. Don't use `os_log` — terminal users won't see it.
- Pixel art uses `.nearest` filtering. Don't add smoothed transforms / antialiasing to sprite-aligned nodes.

## Commit messages

Conventional-commits style preferred:

```
feat(chill): all-metal playlists, head-banger dance bob
fix(openai): bump timeout 8s→30s, add reasoning_effort=low for gpt-5
chore: drop C# reference and v0.22 readme — Swift only
```

If a commit needs more than two paragraphs of body, it's probably two commits.

## Filing issues

- Bugs: use the bug template; include macOS version, hardware, brain mode (from the `LLMRouter:` stderr line at startup), and stderr output.
- Features: keep them goose-flavored. Quiet utility features will likely get closed.

## Questions?

Open a Discussion (link in the issue template config) before a feature issue if you're unsure about scope.
