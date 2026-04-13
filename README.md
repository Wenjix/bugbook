# Dahso

A local-first personal workspace for notes, databases, terminal, mail, calendar, and AI — in one window.

Dahso replaces the tab sprawl of separate apps with a single pane-based workspace where everything lives together. Notes link to database rows, calendar events spawn meeting notes, terminal output sits next to the doc you're working on, and AI agents operate on the same data you do.

## What's in the workspace

**Notes and pages.** Rich markdown editor with blocks, toggles, columns, inline database embeds, backlinks, and a knowledge graph view.

**Databases.** Schema-based databases with table, kanban, calendar, list, and gallery views. Properties include selects, dates, numbers, checkboxes, relations, formulas, and rollups.

**Terminal.** GPU-accelerated terminal (Ghostty Metal backend) running as a native pane — no separate app needed.

**Mail.** Gmail integration with thread view, search, compose, filters, and categories.

**Calendar.** Google Calendar sync with day, week, and month views plus event creation.

**Meetings.** Meeting notes linked to calendar events with audio transcription support.

**AI.** Claude and Codex CLI detection, in-page chat sidebar, and writing assistance with workspace context.

**Agent Hub.** Task and run tracking for coding agents — tasks, runs, events, and a dashboard view so you can see what your agents are doing.

**Home.** A time-of-day adaptive dashboard with pinned databases, recent items, and quick access to tasks.

## Pane system

The workspace is built on a multi-pane layout. Any combination of notes, terminal, mail, calendar, meetings, graph, or home can be arranged side by side with horizontal/vertical splits. Panes can be dragged to swap, split, or closed. Tabs let you save and switch between layouts.

A launcher (Cmd+K or the chrome bar split button) searches pages, databases, and built-in panes, then lets you open them in place, split right, split down, or in a new tab.

## Targets

- **Dahso** — macOS desktop app (SwiftUI + AppKit, macOS 14+)
- **DahsoCLI** — command-line interface for agent and automation workflows
- **DahsoCore** — shared models, storage engine, query/mutation engines
- **DahsoMobile** — iOS app target (iOS 17+)

## CLI

The CLI is designed for coding agents (Claude, Codex, etc.) to read and write the same workspace data the desktop app uses. Core commands:

```
dahso page list / get / create / update / delete
dahso db list / query / row create / row update
dahso board create / add-card / move-card
dahso agent task create / update / list
dahso agent run start / finish
dahso agent event log
dahso agent dashboard
dahso skill list / get / create
dahso backlinks <page>
```

Install locally:

```bash
swift build
swift run DahsoCLI install --force
```

## Build and run

```bash
# macOS app (SwiftPM/WebKit fallback path)
swift run Dahso

# macOS app bundle (Xcode/Chromium path)
bash scripts/fetch-cef.sh
cd macos && xcodegen generate
xcodebuild -project /Users/maxforsey/Code/dahso/macos/Dahso.xcodeproj -scheme DahsoApp -configuration Debug build

# CLI
swift build && swift run DahsoCLI --help

# iOS (open in Xcode, select DahsoMobileApp scheme)
open ios/DahsoMobile.xcodeproj
```

## Dependencies

Ghostty (terminal), Sparkle (auto-update), Sentry (error tracking), FluidAudio (transcription), Yams (YAML/frontmatter), Google OAuth (mail + calendar).
