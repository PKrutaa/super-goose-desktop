# Security policy

This is a personal hobby project. There's no formal security program. That said:

## Reporting a vulnerability

If you find something genuinely sensitive (e.g. a way the goose could leak data from your screen to a third party without you knowing), **don't open a public issue.** Email the maintainer at the address in `git log` instead, or open a private security advisory via the GitHub UI:

`Repository → Security tab → Advisories → New draft security advisory`

For everything else — privacy hygiene, dependency hardening, supply-chain notes — a regular issue is fine.

## What's in scope

- The OpenAI integration (`Goose/Sources/Goose/AI/OpenAIClient.swift`)
- AppleScript invocation (`Goose/Sources/Goose/Audio/SpotifyController.swift`)
- Screen capture / OCR / Accessibility (`Goose/Sources/Goose/Perception/`)
- API key handling (env var + `~/.config/goose/openai-key` file)

## What's not

- Apple framework bugs (file with Apple)
- Spotify's AppleScript surface (file with Spotify)
- The goose being annoying. That is the project.

## Known privacy boundaries

Documented in `README.md` under "Privacy". The short version:

- All perception runs locally.
- Apple Foundation Models is on-device.
- **OpenAI mode (opt-in) sends only the frontmost app name + timing summary.** No OCR, no window titles, no screenshot data.
- WKWebView (`RealBrowserWindow`) loads URLs visibly on-screen — the user can always see the network activity.
