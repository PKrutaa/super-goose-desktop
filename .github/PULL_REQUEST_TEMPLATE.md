<!--
Thanks for contributing! Keep PRs focused — one feature or fix per PR is
much easier to review and revert than a grab-bag. If you're working on
something larger, consider opening a tracking issue first.
-->

## Summary

<!-- One or two sentences. What does this change and why? -->

## Motivation

<!--
Link a related issue if any (`Closes #N`). If this is a behavior change,
explain the user-visible difference. If it's an internal refactor,
explain what it enables or simplifies.
-->

## Changes

<!-- Bulleted list of the meaningful changes. Skip mechanical churn. -->

- 
- 

## Screenshots / recordings

<!--
For UI changes (the goose, the headphones, the dragged windows, the
browser): drop a short screen recording or before/after screenshots
here. The visual is half the point of this project.
-->

## Test plan

<!-- How you verified this works. Tick what applies. -->

- [ ] `cd Goose && swift build -c release` succeeds without warnings
- [ ] `swift run Goose --brain-dryrun` produces 20 decisions, no `→ honk` lines, mix of action types
- [ ] `swift run Goose --browser-demo "honk"` opens the real browser window and dismisses cleanly
- [ ] `swift run Goose` — full overlay runs without crashes for at least 5 minutes
- [ ] If you touched `ChillingTask` / `ChillingTicker`: chill triggers, runs 3-5 min, music actually finishes a song
- [ ] If you touched perception/brain: no leftover OCR / context bleed in generated notes
- [ ] If you touched a `GooseTask`: preempting it via `simulation.setTask(...)` doesn't leak visuals

## Checklist

- [ ] One logical change per PR (ideally < ~500 LOC changed)
- [ ] Commits are atomic with clear messages (conventional-commits style preferred — `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`)
- [ ] No bumps to Swift / macOS deployment targets without explicit need
- [ ] No new dependencies without discussion
- [ ] Privacy notes in `README.md` / `Goose/README.md` updated if data flow changed (especially for LLM / OpenAI mode)
- [ ] If this adds a long-running task type, it implements `stop(simulation:)` to release any visual state

## Notes for the reviewer

<!-- Anything you want them to focus on, or things you're unsure about. -->
