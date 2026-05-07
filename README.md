# super-goose-desktop

A desktop goose for macOS, written in Swift, that observes what you're doing and opines on it.

This is a Swift 6.2 / SpriteKit reimagining of [Sam Chiet's Desktop Goose](https://samperson.itch.io/desktop-goose), evolved into an agent: it watches your screen via Vision OCR + Accessibility, and decides — sarcastically — what to do next. It can leave snide sticky notes about what you're working on, drag a real WKWebView browser onto your screen with a search it picked, fall asleep, and wake up angrily chasing your cursor if you get too close.

> **Status:** personal project, work in progress. Builds and runs. The Foundation Models brain has a deterministic fallback so it works even before the on-device LLM call is wired up.

## Requirements

- macOS 26.1+
- Swift 6.2+ toolchain (or Xcode 26.1+)
- Apple Silicon (tested on M-series)

## Quick start

```bash
cd Goose

# One-time: pull sprites (not versioned, see Goose/ASSETS.md)
git clone --depth 1 https://github.com/romainflcht/py-goose /tmp/py-goose
mkdir -p Sources/Goose/Resources/Sprites/Goose
cp -R /tmp/py-goose/sprite/* Sources/Goose/Resources/Sprites/Goose/

# Run
swift run
```

The goose appears in a transparent click-through overlay covering the whole screen. To quit: hold **ESC** for ~1.5s, click the 🪿 menu-bar item, or `pkill -f Goose`.

### Smoke flags (no goose, for development)

```bash
swift run Goose --render-preview /tmp/x.png       # single-frame headless render
swift run Goose --brain-dryrun                    # 20 brain decisions, stdout
swift run Goose --browser-demo "honk"             # only RealBrowserWindow
```

## What's in the box

- **Hybrid brain** (`AI/GooseBrain.swift`) — deterministic roulette over actions, with an Apple Foundation Models seam for the opinionated sticky note (with deterministic fallback so it works without the on-device LLM).
- **Personality module** (`AI/Personality.swift`) — sarcastic-cynical voice, content pools indexed by `(tone, AppBucket)`, URL routing for browse actions.
- **Independent honk ticker** — honks every 35–60s, plus a debounced bonus honk when the foreground app changes.
- **Real browser** — `Windows/RealBrowserWindow.swift` is a borderless `WKWebView` (1000×700, click-through) the goose drags onto your screen during `BrowseTask`.
- **Perception layer** — `PerceptionEngine` runs Vision OCR + Accessibility frontmost-app probe; brain consumes app, time-on-app, idle seconds, and OCR top-K snippets. **All on-device.**
- **Mouse antagonism** — fall asleep too long, get the cursor too close, and the goose wakes up and chases it (`DeepSleepTask` → `NabMouseTask`).

## Architecture

See [`CLAUDE.md`](CLAUDE.md) for the high-level layering. Short version:

- `Engine/` — pure simulation (position, velocity, foot IK). Ported from samperson's C#.
- `Tasks/` — behaviors implementing the `GooseTask` protocol; one runs at a time.
- `AI/` — perception → brain → action loop, plus the honk ticker.
- `Scene/` + `Windows/` — SpriteKit rendering and real `NSWindow`s the goose drags around.

Design history lives under `docs/superpowers/specs/` and `docs/superpowers/plans/`.

## Brain backends

The goose has three layered decision paths, tried in order:

1. **OpenAI (gpt-4o-mini)** — opt-in, off by default. If a key is configured, this is used first.
2. **Apple Foundation Models** — on-device, on if your Mac has Apple Intelligence enabled.
3. **Deterministic pools** — handcrafted notes, browse URLs, and music; runs when neither LLM is reachable.

To enable OpenAI:

```bash
mkdir -p ~/.config/goose
echo "sk-your-openai-key-here" > ~/.config/goose/openai-key
```

Or set `OPENAI_API_KEY` in the environment before launching. The key is read once at startup; restart `swift run` to pick up changes.

## Privacy

- **Screen capture, OCR, Accessibility** — always run **on-device**. Nothing the goose "sees" through these channels ever leaves your machine.
- **Apple Foundation Models** — **on-device** inference; no network involved.
- **OpenAI mode (opt-in)** — when configured, sends snapshot context (frontmost app name, OCR top-K snippets, idle time) to OpenAI servers. Don't enable this if your screen contents are sensitive.
- **`RealBrowserWindow`** — loads a URL the brain picked. Visible network traffic, on screen, that's the whole point.
- **Spotify** — controlled via local AppleScript only, no API calls.

## Credits

- **Sam Chiet** ([@samnchiet](https://twitter.com/samnchiet)) — original [Desktop Goose](https://samperson.itch.io/desktop-goose) for Windows; this project takes the concept and reimagines it on macOS.
- **Jesús A. Álvarez** — prior Mac port (v0.22) of Sam's project, which inspired some of the macOS wiring choices.
- **[romainflcht/py-goose](https://github.com/romainflcht/py-goose)** — sprite source used at runtime (not versioned in this repo; pulled at setup time).
- **Honks** sampled from *Untitled Goose Game*.

## License

MIT — see [`LICENSE`](LICENSE). Audio samples (honks, etc.) belong to their respective owners and are not redistributed by this repository — they're loaded at runtime from the user's local resources.

This is a personal hobby project, not affiliated with samperson, Jesús A. Álvarez, or the *Untitled Goose Game* team.
