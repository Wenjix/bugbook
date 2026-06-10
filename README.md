# Bugbook

A local-first Notes + Meetings workspace for daily notes, meeting capture, and agent-readable markdown.

Bugbook keeps plain `.md` files on disk as the source of truth. The desktop app is optimized for human writing and meeting capture, while the CLI and future agent layers can read and write the same notes folder without a private sync layer.

## What's in the workspace

**Notes and pages.** Rich markdown editor with blocks, toggles, columns, tables, code blocks, callouts, wikilinks, embedded images, footnotes, and inline database embeds.

**Daily notes.** A first-party Daily Notes database/hub is created in the notes folder and the daily note is the default first screen.

**Meetings.** Meeting capture records mic plus system audio, shows live transcription, writes structured markdown with frontmatter, and opens the completed meeting note for editing.

**Databases.** Schema-based local databases back the Daily Notes and Meetings hubs. Database rows are still plain markdown files.

**Search.** The Search pane is hidden in daily-driver mode, but filename filtering and qmd-backed search infrastructure remain available for notes workflows.

## Pane system

The default desktop workspace keeps Notes available through the left file tree and exposes Meeting as the only fixed sidebar destination. Panes can be split, dragged, swapped, and closed; tabs let you save and switch between layouts.

A launcher (Cmd+K or the chrome bar split button) searches pages, databases, and the enabled built-in panes, then lets you open them in place, split right, split down, or in a new tab.

## Targets

- **Bugbook** — macOS desktop app (SwiftUI + AppKit, macOS 14+)
- **BugbookCLI** — command-line interface for agent and automation workflows
- **BugbookCore** — shared models, storage engine, query/mutation engines
- **BugbookMobile** — iOS app target (iOS 17+)

## CLI

The CLI is designed for coding agents (Claude, Codex, etc.) to read and write the same workspace data the desktop app uses. The SwiftPM product is `BugbookCLI`; the installed shell command is `bugbook`.

```
bugbook page list / get / create / update / delete
bugbook db list / query / row create / row update
bugbook board create / add-card / move-card
bugbook agent task create / update / list
bugbook agent run start / finish
bugbook agent event log
bugbook agent dashboard
bugbook skill list / get / create
bugbook backlinks <page>
```

Install locally:

```bash
swift build -c release --product BugbookCLI
swift run -c release BugbookCLI install --force --copy
bugbook --help
```

## Build and run

```bash
# macOS app (SwiftPM)
swift run Bugbook

# macOS app bundle (Xcode)
cd macos && xcodegen generate
xcodebuild -project macos/Bugbook.xcodeproj -scheme BugbookApp -configuration Debug build

# CLI
swift run BugbookCLI --help
bugbook --help

# iOS (open in Xcode, select BugbookMobileApp scheme)
open ios/BugbookMobile.xcodeproj
```

## Performance checks

```bash
# Compare Swift performance baselines.
scripts/perf-compare.sh

# Capture a manual meeting-recording soak trace.
# While it records, create/open a meeting, start recording, run the meeting, stop, and let finalization finish.
# Writes the trace, stdout, and parsed Allocations/Leaks evidence under .codex/perf/.
scripts/profile-meeting-soak.sh 65m Allocations

# Check bundle privacy declarations and TCC authorization without launching Bugbook.
scripts/run-daily-driver-soak.sh preflight

# Open privacy panes and launch a one-minute recording attempt to create/refresh macOS permission prompts.
scripts/run-daily-driver-soak.sh prompt

# Print the effective wrapper defaults without building or launching Bugbook.
BUGBOOK_DAILY_DRIVER_SOAK_DRY_RUN=1 scripts/run-daily-driver-soak.sh prompt

# Check the current Debug bundle's macOS privacy authorization without building
# or launching Bugbook. Exits nonzero until Microphone and Screen/System Audio
# are approved.
scripts/run-daily-driver-soak.sh status

# Reset stale or denied TCC rows for the current Debug bundle, then rerun prompt.
scripts/run-daily-driver-soak.sh reset-tcc

# Enforced automated soak. Waits for live transcription before attaching Instruments.
# Records for 60 minutes inside a 65-minute trace, leaving time for stop/finalize/save markers.
# Fails if required meeting markers, Instruments summaries, or RSS targets fail.
scripts/run-daily-driver-soak.sh

# Verify a completed soak evidence note before treating the run as accepted.
scripts/verify-daily-driver-soak-evidence.sh .codex/perf/bugbook-meeting-soak-allocations-<timestamp>.md

# Or verify the newest generated evidence note directly.
scripts/run-daily-driver-soak.sh verify-latest
```

## Dependencies

Sparkle (auto-update), Sentry (error tracking), FluidAudio (transcription), Yams (YAML/frontmatter), swift-argument-parser (CLI), and qmd (search).
