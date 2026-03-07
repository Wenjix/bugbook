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

### 4. Install `bugbook` For Local Development

```bash
swift run BugbookCLI install --force
```

Or use the helper script:

```bash
./scripts/install-bugbook-cli.sh
```

By default this installs a symlink at `~/.local/bin/bugbook`. If that directory is not on your `PATH`, the command prints the shell snippet needed to add it.

## Usage

### CLI (agent workflow)

Read and update notes:

```bash
swift run BugbookCLI page list --workspace "~/Library/Application Support/Bugbook"
swift run BugbookCLI page get "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook"
swift run BugbookCLI page get "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook" --raw
swift run BugbookCLI page get "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook" --raw --include-internal-comments
swift run BugbookCLI page get "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook" --blocks
swift run BugbookCLI page get "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook" --block-id path:3 --raw
swift run BugbookCLI page headings "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook"
swift run BugbookCLI page format "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook" --style commonmark --dry-run --output summary
swift run BugbookCLI page compact "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook" --output summary
swift run BugbookCLI page ensure-block-ids "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook" --blocks
swift run BugbookCLI page strip-block-ids "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook"
swift run BugbookCLI page get "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook" --section-line 110
cat updated-note.md | swift run BugbookCLI page update "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook" --content-file -
cat updated-note.md | swift run BugbookCLI page update "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook" --content-file - --output summary
cat roadmap.md | swift run BugbookCLI page update "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook" --section "Roadmap" --content-file -
cat roadmap.md | swift run BugbookCLI page update "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook" --section "Roadmap" --create-section --section-level 2 --content-file -
cat roadmap.md | swift run BugbookCLI page update "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook" --section "Roadmap" --create-section --section-level 2 --content-file - --dry-run
cat block.md | swift run BugbookCLI page update "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook" --block-id path:3 --content-file -
cat text.txt | swift run BugbookCLI page update "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook" --block-id path:3 --text-file -
cat sibling.md | swift run BugbookCLI page update "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook" --block-id path:3 --append-file - --dry-run
cat snippet.md | swift run BugbookCLI page update "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook" --append-file -
swift run BugbookCLI block list "Bugbook Strategy" --workspace "~/Library/Application Support/Bugbook"
swift run BugbookCLI block get "Bugbook Strategy" path:3 --workspace "~/Library/Application Support/Bugbook" --raw
cat block.md | swift run BugbookCLI block replace "Bugbook Strategy" path:3 --workspace "~/Library/Application Support/Bugbook" --content-file -
cat text.txt | swift run BugbookCLI block update-text "Bugbook Strategy" path:3 --workspace "~/Library/Application Support/Bugbook" --text-file -
cat sibling.md | swift run BugbookCLI block insert "Bugbook Strategy" path:3 --workspace "~/Library/Application Support/Bugbook" --after --content-file - --dry-run
swift run BugbookCLI block move "Bugbook Strategy" path:3 path:7 --workspace "~/Library/Application Support/Bugbook" --before --dry-run
swift run BugbookCLI block delete "Bugbook Strategy" path:3 --workspace "~/Library/Application Support/Bugbook" --dry-run
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

Notes:
- `page get --raw` prints clean markdown by default; add `--include-internal-comments` for the literal stored file.
- `page get --blocks` returns parsed markdown blocks plus document metadata.
- `page get --block-id <selector>` narrows reads to one markdown block by stable UUID or `path:0/1`.
- `page headings` returns heading titles, levels, and line numbers for section targeting.
- `page format --style bugbook|commonmark` rewrites a page using either Bugbook's dense block format or a CommonMark-style layout with structural blank lines.
- `page format --style commonmark` now strips persisted block IDs and converts Bugbook-only block syntax into portable approximations: toggles become `<details>`, columns are flattened sequentially with thematic breaks, database embeds become labeled text, and page-link blocks become relative markdown links when they resolve uniquely in the workspace or plain text when they do not.
- `page compact` rewrites a page through Bugbook's block serializer and removes empty paragraph gaps, which is useful when a note has accumulated extra blank lines.
- `page compact` is the shortcut for `page format --style bugbook`.
- `page ensure-block-ids` persists unique stable block IDs and repairs duplicate persisted IDs when needed; add `--blocks` if you want the parsed block list in the response.
- `page strip-block-ids` removes persisted block ID comments from a page and restores clean markdown storage.
- `page get --section "<Heading>"` or `--section-line N` narrows reads to one heading section and fails if the selector does not match.
- `page update --section "<Heading>"` or `--section-line N` scopes replace/prepend/append operations to a heading body.
- `page update --block-id <selector>` scopes replace/prepend/append operations to one block without polluting a clean note with persisted block IDs.
- `page update --block-id <selector> --text-file` updates only the selected block's text and preserves its markdown type.
- `page update --section "<Heading>" --create-section` appends the section if it is missing.
- `page update --dry-run` previews the post-edit page plus structured line changes without writing anything.
- `page create` and `page update` accept `--output summary` when you want a compact write result instead of the full page payload.
- `block list`, `block get`, `block replace`, `block update-text`, `block insert`, `block move`, and `block delete` provide a dedicated block-level command surface on top of the same selectors used by `page get --block-id`.
- Row `get` now matches `query` by returning friendly property names and display values by default; add `--fields` to narrow the payload and `--raw-properties` to include schema IDs and stored option IDs.
- `query --fields` returns friendly property names and display values by default; add `--raw-properties` when you also need schema IDs and stored option IDs.
- Row `create`, `update`, `query --filter`, `query --sort`, and `query --fields` accept friendly property names in addition to schema IDs.

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
