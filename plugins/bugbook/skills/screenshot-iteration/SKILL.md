---
name: screenshot-iteration
description: Close the vision loop on SwiftUI work. Given a natural-language spec or reference image, this skill implements the change, builds Bugbook, drives the app to the target state, captures a real screenshot, and uses vision to compare against the spec — iterating until the UI matches. Use when the user says "make it look like this", "iterate until it matches", "screenshot this and compare", "pixel-match this design", or describes UI behavior that previously needed multiple rounds of human review to get right (expand/collapse, toggles, padding, layout). Especially useful for AppKit/SwiftUI subtleties like LazyVStack caching, NSScrollView constraints, or animation timing where Claude cannot reliably reason without visual feedback.
---

# Screenshot Iteration

**Why this exists.** SwiftUI and AppKit hide behavior behind invisible contracts — LazyVStack caches offscreen rows, NSScrollView has its own layout pass, animations interrupt state. Claude cannot reason about any of this without seeing the result. Past sessions burned hours on meeting-block expand/collapse because the fix got "shipped" while the visible behavior stayed wrong. This skill forces a closed loop: implement → build → observe → compare → refine. The human is out of the inner loop; they re-enter only when the spec is met or the iteration budget is exhausted.

---

## Inputs

Accept one of:
- **Natural-language spec** — "collapsed meeting block shows title only; expanded shows transcript with 200ms fade-in"
- **Reference image path** — `/path/to/target.png`
- **Both** — image is the visual target, text clarifies behavior the image can't show

Also accept (optional):
- **Target view identifier** — the view name or accessibility id to drive to (skips discovery)
- **States** — distinct states to capture (e.g. `collapsed`, `expanded`, `hover`)
- **Iteration budget** — default 5 rounds; cap at 10

If the user gave only a one-line prompt, infer states from the spec. Expand/collapse implies two states. Hover implies three. Confirm only if ambiguous.

---

## The Loop

```
1. Read spec + reference image (if provided)
2. Locate the SwiftUI file to edit
3. Round N:
   a. Implement or refine the change
   b. Build Bugbook headless
   c. Launch app, drive to target state
   d. Capture screenshot
   e. Vision-compare screenshot vs spec/reference
   f. Pass? → commit and exit. Fail? → record gaps, loop back to (a)
4. If budget exhausted → halt, report gaps, do not commit
```

Sequential, not parallel. Each round's screenshot becomes input for the next round's implementation.

---

## Round 1: Establish Baseline

Before editing anything, capture the *current* state as a screenshot. This is your "before". If the current state already matches the spec, say so and exit — no change needed. This also prevents the common failure of claiming a fix worked when the behavior was already correct.

```bash
# Build and launch current code
pkill -f "debug/Bugbook" 2>/dev/null || true
swift build 2>&1 | tail -10
.build/arm64-apple-macosx/debug/Bugbook &
sleep 3
```

Drive to the target state (see "Driving the App" below). Capture:

```bash
mkdir -p .screenshot-iteration/round-0
screencapture -x -R"<x,y,w,h>" .screenshot-iteration/round-0/<state>.png
# Or full window:
screencapture -x -l$(osascript -e 'tell app "Bugbook" to id of window 1') .screenshot-iteration/round-0/<state>.png
```

Send the baseline screenshot and the spec/reference to vision:

```
Read tool: .screenshot-iteration/round-0/<state>.png
Read tool: <reference image if provided>
```

Then ask: does the current state already match? If yes, exit clean.

---

## Round N: Implement, Build, Observe

### a. Implement

Read the relevant SwiftUI file first. Match surrounding patterns — don't introduce a new style just because the task mentions a specific property. If this is round 2+, read round N-1's gap analysis and target only those gaps.

Common traps to avoid on UI work:
- **LazyVStack caching** — state changes in offscreen rows don't trigger layout. Use `VStack` for known-small lists, or mark the cached view with `.id(...)` tied to the state.
- **NSScrollView content sizing** — SwiftUI's `.frame(...)` does not always propagate to the scroll view's intrinsic content size. If content clips, inspect the wrapping view hierarchy.
- **Animation vs state** — an animation blocks the next state change from capturing cleanly. Add `sleep 0.5` after state transitions before screenshotting, or screenshot at both start and end.
- **Duplicate controls** — before adding a new toggle or button, grep the surrounding view for existing ones. Past rounds shipped two toggles side by side because the first wasn't obvious.

### b. Build

```bash
pkill -f "debug/Bugbook" 2>/dev/null || true
swift build 2>&1 | tail -20
```

If the build fails, fix and retry up to 3 times. After 3 build failures in one round, record it as a round failure and exit the loop with the error — don't silently move to the next round with broken code.

### c. Launch and drive

```bash
.build/arm64-apple-macosx/debug/Bugbook &
sleep 3
```

See "Driving the App" below for the state-driving playbook.

### d. Capture

```bash
mkdir -p .screenshot-iteration/round-$N
screencapture -x -l$(osascript -e 'tell app "Bugbook" to id of window 1') .screenshot-iteration/round-$N/<state>.png
```

Capture all required states before comparing. If the spec has two states (collapsed, expanded), capture both in the same round.

### e. Compare via vision

Load the captured screenshots and the reference/spec into context:

```
Read: .screenshot-iteration/round-$N/collapsed.png
Read: .screenshot-iteration/round-$N/expanded.png
Read: <reference image if provided>
```

Then reason explicitly, not vibes. Use this template:

```
## Round N Comparison

Spec: <restate the spec in one sentence>

Observed:
- collapsed.png: <describe what you see>
- expanded.png: <describe what you see>

Gaps:
1. <specific gap — e.g., "transcript is visible when collapsed; spec says title only">
2. <specific gap — e.g., "expanded fade-in appears instant, not 200ms">
3. <specific gap — e.g., "title font weight is regular; spec shows semibold">

Pass: <yes / no>
If no, next-round plan: <one sentence, what to change>
```

This template matters because unstructured "looks close" is how rounds stack without progress.

### f. Decision

- **Pass:** commit the change on the current branch with message `ui: <spec in one line>`. Clean up `.screenshot-iteration/` or leave it for the user to inspect. Report success and exit.
- **Fail and budget remaining:** loop back to (a) with the gap list as input.
- **Fail and budget exhausted:** halt. Do not commit. Report the final-round screenshot paths and gap analysis so the human can take over.

---

## Driving the App

Getting the app to the target state is the hardest part of this skill because Bugbook has no test harness yet. Three tiers, use the simplest that works:

### Tier 1 — Direct state injection (preferred)

If the view supports a debug/preview hook that can force a state (e.g. a `#if DEBUG` override on the meeting block's `isExpanded` binding), use it. Edit the hook, build, launch, screenshot. No UI automation needed.

If no hook exists and the spec is about state-driven UI, *add one* as part of the implementation. A small `#if DEBUG` hook that reads an env var or a URL scheme is worth the rounds it saves. Mark it clearly so it doesn't ship.

### Tier 2 — Scripted UI navigation via AppleScript / `osascript`

Use `osascript` to click sidebar items, open menus, or send keystrokes. Example:

```bash
osascript -e 'tell application "Bugbook" to activate'
osascript -e 'tell application "System Events" to keystroke "k" using command down'
osascript -e 'tell application "System Events" to keystroke "meeting"'
osascript -e 'tell application "System Events" to key code 36' # return
sleep 1  # let the page open
osascript -e 'tell application "System Events" to key code 49' # space to toggle (if applicable)
sleep 0.5  # let animation settle
```

Assume the Command Palette (`cmd+k`) works for most navigation. When it doesn't, fall back to tier 3.

### Tier 3 — Computer-use MCP

For anything that tier 2 can't reach (drag interactions, complex multi-click paths, hover states), request computer-use access once at skill startup and use it. Keep mouse paths short — computer-use rounds are expensive.

```
mcp__computer-use__request_access(
  apps: ["Bugbook"],
  reason: "Drive Bugbook to target UI state for visual iteration",
  clipboardRead: false, clipboardWrite: false, systemKeyCombos: true
)
```

---

## Outputs

On pass:
- Committed code on the current branch
- `.screenshot-iteration/round-0/*.png` (baseline) and `.screenshot-iteration/round-<N>/*.png` (final)
- A short summary in the skill's return — which file changed, which state(s) matched, how many rounds

On fail (budget exhausted):
- No commit
- Same screenshot artifacts as above
- Gap analysis from the final round
- Explicit statement: "iteration budget exhausted, human review needed"

---

## When NOT to use this skill

- **Copy/text changes** — a compile-check is enough; no visual verification needed
- **Backend or CLI changes** — no UI to observe
- **Design exploration** — use `max:design-interface` to pick the direction first, then come here to implement it
- **First-time feature scaffolding** — build the feature to where it launches without crashing, *then* use this to refine the look

---

## Rules

1. **No commit without a passing round.** If the final round doesn't match the spec, the change does not land.
2. **Baseline first.** Round 0 is always a capture-only round to confirm the starting state.
3. **One spec per invocation.** Don't combine unrelated UI changes — they confuse the gap analysis.
4. **Explicit gap analysis every round.** Don't accept vibes. The template above is not optional.
5. **Cap iteration at 10 rounds.** If ten rounds don't converge, the spec is underspecified or the approach is wrong — stop and get a human.
6. **Never mark tickets Done.** Move to Review only, same as `/go`.
7. **Clean up background Bugbook processes.** `pkill -f "debug/Bugbook"` before every launch so stale instances don't eat screenshots.
