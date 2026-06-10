# Handoff: run the WKWebView sandbox GATE on a Mac

**Written:** 2026-06-10, by the Linux agent fleet (3 agents, beads workflow)
**Blocking bead:** `bb-epic-sandbox-lis.6` — *GATE: live WKWebView sandbox verification (hostile probes blocked)*

## Why you're reading this

The HTML-artifacts epic is 24/41 beads done. All code for the sandbox gate is
**written, committed, and spec-verbatim** — but the gate itself is an *empirical*
check (design doc §6 risk a): real WKWebViews must load a hostile artifact and
prove every escape probe is blocked. WKWebView does not exist on Linux and the
only tailnet Mac (`maximus-book`) has been offline for ~17 days, so the fleet
stopped here. Everything still open (pane UI → wiki-link nav → final
verification) is intentionally gated behind this run.

The spec explicitly says: **do not start any pane work with a failing probe.**

## Step 0 — Get the code onto the MacBook

All 21 session commits exist only on the Linux box
(`ubuntu`, tailscale `100.116.231.106`, repo `/home/ubuntu/ntm_Dev/bugbook-html/bugbook`,
branch `main`, HEAD `e85014a`, clean tree). `origin/main`
(https://github.com/Wenjix/bugbook) is still at the old base `221254c`.

```bash
# On the Linux box (or ask an agent to do it):
cd /home/ubuntu/ntm_Dev/bugbook-html/bugbook && git push origin main

# On the MacBook:
cd ~/Code/bugbook   # or wherever your clone lives
git pull origin main
git log --oneline -3   # expect e85014a "Add live WKWebView sandbox tests..." at top
```

## Step 1 — Run the gate (spec Step 4.6)

Run from a **local terminal in a logged-in GUI session** (WKWebView needs
WindowServer; a headless SSH session will hang or fail for the wrong reason).
Do **NOT** set `BUGBOOK_SKIP_WEBKIT_TESTS` — that env var skips exactly the
tests you're here to run.

```bash
swift build \
  && swift test --filter ArtifactSchemeHandlerTests \
  && swift test --filter ArtifactSandboxLiveTests
```

Notes:
- First run compiles the whole package (Sparkle/Sentry/FluidAudio/GhosttyKit) — slow once.
- The shared content-rule-list compile adds ~1s to the first live test; timeouts in the tests are already generous.

## Step 2 — Read the results

**PASS looks like:** all 4 live tests green —

| Test | Proves |
|---|---|
| `testNetworkBlockRuleListCompiles` | rule list compiles at all |
| `testBenignArtifactRenders` | fail-closed control: sandbox doesn't break a legit inline-everything artifact; in-page `#anchor` click still navigates |
| `testHostileFixtureAllProbesBlocked` | ≥13 probes reported, every one `blocked`, except `control-img-data` = `allowed` (proves the harness can observe a load) |
| `testNoPersistenceAcrossSessions` | two separately-built sessions share no localStorage/cookies |

**FAIL — apply the spec fallbacks** (html-implementation-spec.md:1518–1521), in order:

1. *CSP response header ignored on the custom scheme* → change the scheme
   handler to also inject `<meta http-equiv="Content-Security-Policy" content="…">`
   right after `<head>` when serving (keep the response header too). Re-run.
2. *Content rule list not applied to custom-scheme pages* → acceptable
   degradation: CSP + navigation delegate + no-window-open still cover threat
   T1. Document the reduced redundancy in `ArtifactSandbox.swift` comments. Re-run.

If `__probesComplete` never appears, a **navigation** probe escaped
(meta-refresh / form-action / location-assign) — that's a real sandbox hole,
fix before anything else. Do not proceed to pane work with any failing probe.

## Step 3 — Record the result so the fleet can continue

The beads DB lives on the **Linux box** at `/home/ubuntu/ntm_Dev/bugbook-html/.beads`
(workspace root, *not* inside the git repo). From that box:

```bash
cd /home/ubuntu/ntm_Dev/bugbook-html
CI=1 br close bb-epic-sandbox-lis.6 --reason "GATE PASSED on <mac>, <date>: swift build + ArtifactSchemeHandlerTests + ArtifactSandboxLiveTests all green; hostile fixture all probes blocked, control allowed. <paste test summary line>"
CI=1 br close bb-epic-sandbox-lis --reason "Epic complete: all 6 children closed, gate verified live."
```

(If you changed code for a fallback, commit it on the Mac per spec Step 4.7
and push before closing.)

Closing `lis.6` unblocks `qr3.1` + `qr3.2` and the rest of the pane chain —
restart the agent fleet and it will pick them up from triage.

## Step 4 (optional, same Mac session) — the remaining macOS-only gates

These come later in the dependency chain but also need this MacBook, so you
may want them in the same sitting once the pane epic is done:

- `bb-epic-verification-1u0.1`: `swift build && swift test && bash scripts/smoke-cli.sh`
- `bb-epic-verification-1u0.2`: `cd macos && xcodegen generate && xcodebuild -project Bugbook.xcodeproj -scheme BugbookApp -configuration Debug build`
- `bb-epic-verification-1u0.3`: end-to-end demo run (design doc §7.4)

Prereqs: Xcode + command-line tools, `jq` (smoke script auto-installs via brew), `xcodegen`.

## Known quirks / context

- **`BugbookCLITests.testContextRepoCommandsListCreateValidateExportAndReadPack`**
  fails on Linux (3 assertions) — proven pre-existing at the old HEAD, believed
  Linux-platform-specific. It should pass on macOS; if it *also* fails there,
  that's new signal worth a bead.
- Everything the fleet implemented was verified on Linux in a Docker
  `swift:6.0` harness (BugbookCore/BugbookCLI targets + full smoke script);
  macOS app-target code (`ContentView`, `AiService`, sandbox, live tests) is
  syntax-checked and spec-verbatim but has **never been compiled** — expect
  `swift build` in Step 1 to be the first real compile. Trivial fixups (a
  missed import, etc.) are fair game; anything structural deserves a bead.
- Session commit range: `221254c..e85014a` (21 commits, all on `main`).
