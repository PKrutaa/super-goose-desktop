# Deep Sleep + Angry Wake-Up — Design

**Date:** 2026-05-07
**Scope:** Goose Swift (`Goose/`).

## Goal

Add long sleep moments where the goose can be "woken up" by getting too close or clicking near it, triggering an angry chase via the existing `NabMouseTask`.

## Decisions (locked)

| # | Decision | Choice |
|---|---|---|
| 1 | Sleep mechanism | New `DeepSleepTask` distinct from existing short `NapTask` (4–9s). Duration 30–90s. |
| 2 | Visual cue | None for v1 (no Z particles). Long stillness + angry honk on wake is enough. |
| 3 | Wake trigger | Cursor within 80px of goose **OR** left-click inside that radius. |
| 4 | Wake reaction | Single angry honk → transition to `NabMouseTask` (existing chase + drag behavior). |
| 5 | Brain distribution | New `.deepSleep` case at 10%. Existing `.nap` drops from 15% → 5%. Other actions unchanged. |

## Non-goals

- Visual sleep indicator ("Z" particles, eye sprites).
- Multiple anger levels.
- Configurable wake radius / probability.
- Sleeping in safer spots (corners, etc.).

## Architecture

One new task, three small modifications. The wake-up logic lives entirely inside `DeepSleepTask` — it polls mouse position and click state on each tick, the same way `GooseScene.pollMouseInteraction` already does.

### File-level changes

```
Goose/Sources/Goose/
├── AI/
│   ├── GooseAction.swift           ← add `case deepSleep` to GooseDecisionType
│   ├── GooseBrain.swift            ← add deepSleep arm to roulette (10%); reduce nap to 5%
│   └── AgentDirector.swift         ← add .deepSleep case → setTask(DeepSleepTask())
└── Tasks/
    └── DeepSleepTask.swift         ← NEW
```

## Components

### `DeepSleepTask`

```swift
@MainActor
final class DeepSleepTask: GooseTask {
    private static let minDuration: CGFloat = 30
    private static let maxDuration: CGFloat = 90
    private static let wakeRadius: CGFloat = 80

    private var endTime: CGFloat = 0
    private var lastLeftMouseDown = false

    func start(simulation: GooseSimulation)
    func tick(simulation: GooseSimulation)
}
```

**Behavior:**
- `start`: zero velocity; `endTime = GameTime.time + random(30, 90)`; capture initial mouse-button state to avoid spurious wake on stale clicks.
- `tick` each frame:
  - Hold velocity at zero (goose is asleep, no drift).
  - Read `NSEvent.mouseLocation` and compute distance to `simulation.position`.
  - Read `NSEvent.pressedMouseButtons & 1` for left-click rising edge.
  - **Wake conditions** (any one):
    - distance ≤ 80px AND mouse moved this tick (cursor came near)
    - rising-edge click AND distance ≤ 80px (poke)
  - On wake: fire `simulation.onHonk?()` and `simulation.setTask(NabMouseTask())` and return.
  - On natural timeout (no wake): `simulation.setTask(WanderTask())`.

> Note: "mouse moved" detection is needed so a sleeping goose that *spawns* near the cursor doesn't immediately wake up. We compare current cursor pos to the cursor pos snapshot from `start`.

### `GooseAction.swift`

Add `case deepSleep` to `GooseDecisionType`. No new fields on `GooseDecision`.

### `GooseBrain.swift`

Update `rollOnce` distribution: `wander 28%`, `note 35%`, `nap 5%`, `deepSleep 10%`, `photo 14%`, `browse 8%`. Add `summary(of:)` arm for `.deepSleep`.

### `AgentDirector.swift`

Add to `execute(decision:)`:
```swift
case .deepSleep:
    simulation.setTask(DeepSleepTask())
```

## Data flow

```
AgentDirector.tick
  └── brain.decide → GooseDecision(.deepSleep)
        └── simulation.setTask(DeepSleepTask())
              ├── timeout (30–90s) → WanderTask
              └── wake-up trigger → onHonk + NabMouseTask
                                         └── chase → drag cursor → WanderTask
```

## Error handling

| Failure | Behavior |
|---|---|
| `NSScreen.main` returns nil while sleeping | `mouseLocation` still works (it's screen-relative); no special handling. |
| `NabMouseTask` itself terminates early (its own timeout) | It already transitions to `WanderTask`. No coupling needed. |
| Goose moves into a corner just before sleeping | Cursor proximity check still uses absolute distance — no edge-case concern. |

## Testing

Same constraint as before — no test target. Verification:
- `swift build` clean.
- `swift run Goose --brain-dryrun` — over 20 decisions, expect ~2 `.deepSleep`, ~1 `.nap`. (Stochastic; check a couple of runs.)
- Visual smoke: `swift run Goose`, wait until goose enters a long stillness, move cursor near it. Expect honk + chase. Wait again, let it timeout: should resume wander.

## Migration checklist

1. Create `Goose/Sources/Goose/Tasks/DeepSleepTask.swift`.
2. Add `.deepSleep` to `GooseDecisionType` in `GooseAction.swift`.
3. Update `GooseBrain.rollOnce` distribution + `summary(of:)`.
4. Add `.deepSleep` arm in `AgentDirector.execute`.
5. Run dryrun + manual smoke.
