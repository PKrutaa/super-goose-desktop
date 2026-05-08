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

1. **OpenAI (`gpt-5-mini` by default)** — opt-in, off by default. When configured, used first for note generation and chill-playlist selection.
2. **Apple Foundation Models** — on-device, used automatically if your Mac has Apple Intelligence enabled and the model assets are downloaded.
3. **Deterministic pools** — handcrafted notes, browse URLs, and music; always available as the last-resort fallback.

The router (`AI/LLMRouter.swift`) walks the list and uses the first ready provider; if a call fails or returns malformed output, it falls through to the next. This means the goose **always works** — even with no internet and no Apple Intelligence.

### Enabling OpenAI

Two ways. Pick one.

**Config file** (recommended for desktop apps launched from Finder):

```bash
mkdir -p ~/.config/goose
echo "sk-your-openai-key-here" > ~/.config/goose/openai-key
chmod 600 ~/.config/goose/openai-key
```

**Environment variable** (handy when launching via terminal):

```bash
export OPENAI_API_KEY=sk-your-key-here
swift run
```

The key is read once at process startup. Edit and re-launch to swap.

### Switching models

Default is `gpt-5-mini` (reasoning model). Cheaper and lower-latency choice: `gpt-4o-mini`. Edit `Goose/Sources/Goose/AI/OpenAIClient.swift`:

```swift
static let model = "gpt-5-mini"   // or "gpt-4o-mini", "gpt-5-nano", etc.
```

The client sets `reasoning_effort: "low"` and `max_completion_tokens: 1500`, which works for both 4o and 5-family models. Per-call cost is minimal — gpt-5-mini at low reasoning effort runs around fractions of a cent per note.

### Status checks at runtime

When you run `swift run`, the stderr log tells you which providers are live:

```
[Goose] OpenAIClient: ready (key=...A4f2)
[Goose] FoundationModelClient: unavailable (appleIntelligenceNotEnabled)
[Goose] LLMRouter: Router(OpenAI(gpt-5-mini)[ready] → AppleFoundationModels[unavailable])
```

If neither lights up, the deterministic pools take over silently — you'll see `[fallback]` markers in `ChillingTicker` decisions.

### What gets sent to OpenAI

Each LLM call carries a tiny context line:

> `user is in <app> (was in <prev_app> before, <N>s on this app, <N>s idle)`

That's it. **No OCR, no screenshot bytes, no window titles.** OCR was removed after it was found to leak verbatim into note bodies (and was a privacy risk). The model sees only app names + timing.

## Privacy

- **Screen capture, OCR, Accessibility** — always run **on-device**. Captured locally for the brain's deterministic pools and never sent over the network. (See "What gets sent to OpenAI" above.)
- **Apple Foundation Models** — **on-device** inference; no network involved.
- **OpenAI mode (opt-in)** — sends only the frontmost app name + timing summary to OpenAI servers. No OCR, no window titles, no screenshot data. Off by default.
- **`RealBrowserWindow`** — loads a URL the brain picked into a click-through `WKWebView`. Visible on-screen.
- **Spotify** — controlled via local AppleScript (`osascript`). Zero network from this app — Spotify itself does the streaming.
- **Honk audio** — local file playback only.

## Credits

- **Sam Chiet** ([@samnchiet](https://twitter.com/samnchiet)) — original [Desktop Goose](https://samperson.itch.io/desktop-goose) for Windows; this project takes the concept and reimagines it on macOS.
- **Jesús A. Álvarez** — prior Mac port (v0.22) of Sam's project, which inspired some of the macOS wiring choices.
- **[romainflcht/py-goose](https://github.com/romainflcht/py-goose)** — sprite source used at runtime (not versioned in this repo; pulled at setup time).
- **Honks** sampled from *Untitled Goose Game*.

## License

MIT — see [`LICENSE`](LICENSE). Audio samples (honks, etc.) belong to their respective owners and are not redistributed by this repository — they're loaded at runtime from the user's local resources.

This is a personal hobby project, not affiliated with samperson, Jesús A. Álvarez, or the *Untitled Goose Game* team.
