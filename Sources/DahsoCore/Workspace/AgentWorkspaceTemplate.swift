import Foundation

public enum AgentWorkspaceTemplate {
    public static func agentsMarkdown(workspace: String) -> String {
        """
# AGENTS.md

## Workspace
- Root: \(workspace)
- Pages: `*.md`
- Skills: `Skills/*.skill.md`
- Databases: folders with `_schema.json` and `_index.json`
- Agent data: `.dahso/agents/tasks.json`, `.dahso/agents/runs.jsonl`, `.dahso/agents/events.jsonl`

## What Agents Can Do
- Read, create, update, and delete markdown pages in the workspace.
- Search notes, inspect backlinks, and embed databases into pages.
- Create boards, add cards, move cards, and manage database views.
- Discover workspace skills and use them as reusable instructions.
- Track work with agent tasks, runs, and events.

## Recommended Workflow
1. Read the relevant pages and workspace skills before making changes.
2. Create a task before starting significant work.
3. Start a run when execution begins.
4. Make note, board, or database changes through the `dahso` CLI.
5. Log meaningful events while you work.
6. Finish the run with a summary and update the task status.

## Notes And Pages
```bash
dahso page list
dahso page get "Dahso Strategy"
dahso page get "Dahso Strategy" --raw
dahso page get "Dahso Strategy" --raw --include-internal-comments
dahso page get "Dahso Strategy" --blocks
dahso page get "Dahso Strategy" --block-id path:3 --raw
dahso page headings "Dahso Strategy"
dahso page format "Dahso Strategy" --style commonmark --dry-run --output summary --report
dahso page format "Dahso Strategy" --style commonmark --dry-run --fail-on-warnings
dahso page compact "Dahso Strategy" --output summary
dahso page ensure-block-ids "Dahso Strategy" --blocks
dahso page strip-block-ids "Dahso Strategy"
dahso page get "Dahso Strategy" --section-line 110
dahso page create "Notes/Research Summary" --title "Research Summary"
cat replacement.md | dahso page update "Dahso Strategy" --content-file -
cat replacement.md | dahso page update "Dahso Strategy" --content-file - --output summary
cat roadmap.md | dahso page update "Dahso Strategy" --section "Roadmap" --content-file -
cat roadmap.md | dahso page update "Dahso Strategy" --section "Roadmap" --create-section --section-level 2 --content-file -
cat roadmap.md | dahso page update "Dahso Strategy" --section "Roadmap" --create-section --section-level 2 --content-file - --dry-run
cat block.md | dahso page update "Dahso Strategy" --block-id path:3 --content-file -
cat text.txt | dahso page update "Dahso Strategy" --block-id path:3 --text-file -
cat sibling.md | dahso page update "Dahso Strategy" --block-id path:3 --append-file - --dry-run
dahso block list "Dahso Strategy"
dahso block get "Dahso Strategy" path:3 --raw
cat block.md | dahso block replace "Dahso Strategy" path:3 --content-file -
cat text.txt | dahso block update-text "Dahso Strategy" path:3 --text-file -
cat sibling.md | dahso block insert "Dahso Strategy" path:3 --after --content-file - --dry-run
dahso block move "Dahso Strategy" path:3 path:7 --before --dry-run
dahso block delete "Dahso Strategy" path:3 --dry-run
cat snippet.md | dahso page update "Dahso Strategy" --append-file -
dahso get "Dahso Strategy Board" row_1234abcd --fields "Title,Phase" --raw-properties
dahso backlinks "Dahso Strategy"
dahso search "local-first agent notes"
```

`dahso page get --raw` prints clean markdown by default; add \
`--include-internal-comments` for the literal stored file. \
`dahso page get --blocks` returns parsed markdown blocks plus document metadata. \
`dahso page get --block-id` narrows reads to one block by stable UUID or `path:` selector. \
`dahso page headings` lists headings with levels and line numbers. \
`dahso page format --style dahso|commonmark` rewrites a page using either Dahso's dense \
block format or a CommonMark-style layout with structural blank lines. \
`dahso page format --style commonmark` strips persisted block IDs and converts Dahso-only \
block syntax into portable approximations: toggles become `<details>`, columns are flattened \
sequentially with thematic breaks, database embeds become labeled text, and page-link blocks \
become relative markdown links when they resolve uniquely in the workspace or plain text when \
they do not. `dahso page format --report` adds `warning_count` plus structured `warnings` \
so agents can see which page links were downgraded during commonmark export. \
`dahso page format --fail-on-warnings` turns those portability warnings into a non-zero exit \
and skips the write, which is useful for agent and CI gating. \
`dahso page compact` is the shortcut for `dahso page format --style dahso`, removes \
empty paragraph gaps, and both commands report `empty_paragraphs_removed` in their mutation \
payloads. `dahso page ensure-block-ids` persists unique stable block IDs and repairs \
duplicate persisted IDs, while `dahso page strip-block-ids` removes those internal comments \
again. `dahso page get --section` or `--section-line` narrows reads to a single heading \
section. `dahso page update` supports either a full replacement or prepend/append edits per \
command, `--section` or `--section-line` scopes those edits to a heading body, `--block-id` \
scopes them to one block without polluting a clean note, `--text-file` preserves the selected \
block's markdown type, `--create-section` appends a missing section safely, `--dry-run` \
previews the resulting page plus structured line changes before writing, and \
`--output summary` returns a compact mutation payload. `dahso block list`, `block get`, \
`block replace`, `block update-text`, `block insert`, `block move`, and `block delete` \
provide a dedicated block-level surface. `dahso get` and `dahso query --fields` return \
friendly property names and display values by default; add `--raw-properties` when you also \
need schema IDs and stored option IDs.

## Boards And Databases
```bash
dahso board create "Dahso Strategy Board" --group-name "Phase" --column "Now" --column "Next" --column "Later" --view list --view calendar --embed-in "Dahso Strategy"
dahso board create "Sprint Board" --column "Todo" --column "Doing" --column "Done" --no-table
dahso board add-card "Dahso Strategy Board" "Search trust" --column "Now" --date 2026-03-07
dahso board move-card "Dahso Strategy Board" row_1234abcd "Next"
dahso db list
dahso db move "Agent Tickets" --page "Agent Tickets" --dry-run
dahso db move "Agent Tickets" --page "Agent Tickets"
dahso page embed-database "Dahso Strategy" "Dahso Strategy Board"
dahso db schema "Dahso Strategy Board"
dahso db view list "Dahso Strategy Board"
dahso db view add "Dahso Strategy Board" --type calendar --name "Calendar" --date-property "Date"
dahso db view set-default "Dahso Strategy Board" "Calendar"
```

`dahso db list` includes `relative_path` and, when applicable, `parent_page` metadata so \
agents can see where a database actually lives. `dahso db move --page` reparents a database \
into a page companion folder, retargets stale embed markers, and supports `--dry-run` so \
agents can preview the change before writing. You can write rows using either schema IDs or \
friendly property/option names, but inspect the schema first when you need exact field coverage.

## Skills
```bash
dahso skill list
dahso skill get "research-summarizer"
dahso skill create "research-summarizer" --description "Summarize linked source pages into one note."
```

## Agent Tracking
```bash
dahso agent init --write-agents-md
dahso agent task create --title "Implement feature X" --status todo --label ios --path Sources/Dahso
dahso agent run start --task task_1234abcd --agent codex --cwd /path/to/repo --branch codex/feature-x
dahso agent event log --run run_1234abcd --level info --message "Opened architecture docs"
dahso agent run finish run_1234abcd --status succeeded --summary "Added feature X" --commit abc1234
dahso agent task update task_1234abcd --status done
```

## Status Values
- Task: `backlog`, `todo`, `in_progress`, `blocked`, `done`, `cancelled`
- Run: `running`, `succeeded`, `failed`, `cancelled`
- Event: `info`, `warning`, `error`
"""
    }
}
