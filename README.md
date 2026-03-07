# Bugbook

**Local-first notes for agents and humans.**

Bugbook is a local-first notes + database workspace where humans and coding agents collaborate in the same files.

## What This Repo Contains

- `BugbookCore`: shared models + storage engine.
- `BugbookCLI`: automation and agent-friendly CLI.
- `Bugbook` (app target): desktop macOS app for humans.
- `BugbookMobile` (SwiftPM executable): shared mobile code and local validation target.
- `ios/BugbookMobile.xcodeproj`: real iOS app target for Simulator/device.

## How Humans and Agents Work Together

Both interfaces read/write the same workspace data.

Human interface (desktop/mobile):
- Edit notes and databases.
- Open **Agent Hub** to see active tasks, recent runs, and recent events.
- Update task statuses visually.

Agent interface (CLI):
- List/read/create/update/delete markdown pages.
- Embed databases into notes.
- Discover workspace skills.
- Create kanban boards without hand-writing schema JSON.
- Add and move cards by column name from the CLI.
- Add, update, delete, and set default database views from the CLI.
- Query databases and rows.
- Traverse backlinks.
- Create/update tasks.
- Start/finish runs.
- Log structured events.
- Output dashboard JSON for automation.

Shared source of truth (inside your workspace):
- `.bugbook/agents/tasks.json`
- `.bugbook/agents/runs.jsonl`
- `.bugbook/agents/events.jsonl`
- `AGENTS.md` (optional workspace instructions)

## Download and Setup

### 1. Clone

```bash
git clone https://github.com/max4c/bugbook.git
cd bugbook
```

### 2. Build

```bash
swift build
```

### 3. Confirm CLI

```bash
swift run BugbookCLI agent --help
```

## Usage

### CLI (agent workflow)

Read and update notes:

```bash
swift run BugbookCLI page list --workspace "~/Library/Application Support/Bugbook"
swift run BugbookCLI page get "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook"
cat updated-note.md | swift run BugbookCLI page update "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook" --content-file -
cat snippet.md | swift run BugbookCLI page update "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook" --append-file -
swift run BugbookCLI backlinks "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook"
swift run BugbookCLI page embed-database "Bugbook Strategy" "Bugbook Strategy Board" --workspace "~/Library/Application Support/Bugbook"
swift run BugbookCLI board create "Bugbook Strategy Board" --workspace "~/Library/Application Support/Bugbook" --group-name "Phase" --column "Now" --column "Next" --column "Later" --view list --view calendar --embed-in "Bugbook Strategy"
swift run BugbookCLI board create "Sprint Board" --workspace "~/Library/Application Support/Bugbook" --column "Todo" --column "Doing" --column "Done" --no-table
swift run BugbookCLI board add-card "Bugbook Strategy Board" "Search trust" --workspace "~/Library/Application Support/Bugbook" --column "Now" --date 2026-03-07
swift run BugbookCLI board move-card "Bugbook Strategy Board" row_abc123 "Next" --workspace "~/Library/Application Support/Bugbook"
swift run BugbookCLI db view list "Bugbook Strategy Board" --workspace "~/Library/Application Support/Bugbook"
swift run BugbookCLI db view add "Bugbook Strategy Board" --workspace "~/Library/Application Support/Bugbook" --type calendar --name "Calendar" --date-property "Date"
swift run BugbookCLI db view set-default "Bugbook Strategy Board" "Calendar" --workspace "~/Library/Application Support/Bugbook"
swift run BugbookCLI skill create "research-summarizer" --workspace "~/Library/Application Support/Bugbook" --description "Summarize linked source pages into one note."
swift run BugbookCLI skill list --workspace "~/Library/Application Support/Bugbook"
swift run BugbookCLI skill get "research-summarizer" --workspace "~/Library/Application Support/Bugbook"
```

Initialize workspace files:

```bash
swift run BugbookCLI agent init --workspace "~/Library/Application Support/Bugbook" --write-agents-md
```

Create task and track a run:

```bash
swift run BugbookCLI agent task create --workspace "~/Library/Application Support/Bugbook" --title "Fix editor bug" --status todo
swift run BugbookCLI agent run start --workspace "~/Library/Application Support/Bugbook" --task <task_id> --agent codex --branch codex/fix-editor
swift run BugbookCLI agent event log --workspace "~/Library/Application Support/Bugbook" --run-id <run_id> --level info --message "Added regression test"
swift run BugbookCLI agent run finish <run_id> --workspace "~/Library/Application Support/Bugbook" --status succeeded --summary "Shipped fix"
swift run BugbookCLI agent task update <task_id> --workspace "~/Library/Application Support/Bugbook" --status done
```

Open dashboard JSON:

```bash
swift run BugbookCLI agent dashboard --workspace "~/Library/Application Support/Bugbook"
```

### macOS app

```bash
swift run Bugbook
```

Then open **Agent Hub** from the sidebar (or `Cmd+Shift+J`).

### iPhone simulator / device

Open the iOS project in Xcode:

```bash
open ios/BugbookMobile.xcodeproj
```

The iOS project is generated from `ios/project.yml` (XcodeGen). Regenerate if needed:

```bash
cd ios && xcodegen generate
```

Then:

1. Select scheme **`BugbookMobileApp`**.
2. Select an iOS simulator/device.
3. Run.

Important:
- **Do not** run `Bugbook` on iOS. `Bugbook` is macOS-only and uses `AppKit`.
- If you see `No such module 'AppKit'`, you launched the wrong scheme.
- If you see `BUNDLE_IDENTIFIER_FOR_CURRENT_PROCESS_IS_NIL`, you are launching the SwiftPM executable instead of the iOS app bundle.

## Smoke Testing

Run the one-command smoke test:

```bash
./scripts/smoke-cli.sh
```

This verifies:
- workspace init
- task create/update
- run start/finish
- event logging
- dashboard output
- on-disk agent files

## Troubleshooting

### iPhone simulator fails

- Verify scheme is `BugbookMobileApp` in `ios/BugbookMobile.xcodeproj`.
- In Xcode: Product -> Clean Build Folder.
- Rebuild and run again.

You can also verify simulator build from terminal:

```bash
xcodebuild -project ios/BugbookMobile.xcodeproj -scheme BugbookMobileApp -destination 'platform=iOS Simulator,name=iPhone 17' build
```

### "How do I inspect details?"

Use either:

```bash
swift run BugbookCLI agent task list --workspace "~/Library/Application Support/Bugbook"
swift run BugbookCLI agent run list --workspace "~/Library/Application Support/Bugbook" --limit 50
swift run BugbookCLI agent event list --workspace "~/Library/Application Support/Bugbook" --limit 100
```

Or inspect raw files directly:
- `"~/Library/Application Support/Bugbook"/.bugbook/agents/tasks.json`
- `"~/Library/Application Support/Bugbook"/.bugbook/agents/runs.jsonl`
- `"~/Library/Application Support/Bugbook"/.bugbook/agents/events.jsonl`

## MCP Status (Xcode Model Context Protocol)

This repo currently does **not** contain MCP-specific integration/config.

If you want MCP-enabled workflows here, we can add:
- an MCP capability document in `AGENTS.md`
- task templates for Xcode actions
- explicit agent instructions for MCP tools
