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
- Agent data: `.bugbook/agents/tasks.json`, `.bugbook/agents/runs.jsonl`, `.bugbook/agents/events.jsonl`

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
4. Make note, board, or database changes through the `bugbook` CLI.
5. Log meaningful events while you work.
6. Finish the run with a summary and update the task status.

## Notes And Pages
```bash
bugbook page list
bugbook page get "Bugbook Strategy"
bugbook page get "Bugbook Strategy" --raw
bugbook page get "Bugbook Strategy" --raw --include-internal-comments
bugbook page get "Bugbook Strategy" --blocks
bugbook page get "Bugbook Strategy" --block-id path:3 --raw
bugbook page headings "Bugbook Strategy"
bugbook page format "Bugbook Strategy" --style commonmark --dry-run --output summary
bugbook page compact "Bugbook Strategy" --output summary
bugbook page ensure-block-ids "Bugbook Strategy" --blocks
bugbook page strip-block-ids "Bugbook Strategy"
bugbook page get "Bugbook Strategy" --section-line 110
bugbook page create "Notes/Research Summary" --title "Research Summary"
cat replacement.md | bugbook page update "Bugbook Strategy" --content-file -
cat replacement.md | bugbook page update "Bugbook Strategy" --content-file - --output summary
cat roadmap.md | bugbook page update "Bugbook Strategy" --section "Roadmap" --content-file -
cat roadmap.md | bugbook page update "Bugbook Strategy" --section "Roadmap" --create-section --section-level 2 --content-file -
cat roadmap.md | bugbook page update "Bugbook Strategy" --section "Roadmap" --create-section --section-level 2 --content-file - --dry-run
cat block.md | bugbook page update "Bugbook Strategy" --block-id path:3 --content-file -
cat text.txt | bugbook page update "Bugbook Strategy" --block-id path:3 --text-file -
cat sibling.md | bugbook page update "Bugbook Strategy" --block-id path:3 --append-file - --dry-run
bugbook block list "Bugbook Strategy"
bugbook block get "Bugbook Strategy" path:3 --raw
cat block.md | bugbook block replace "Bugbook Strategy" path:3 --content-file -
cat text.txt | bugbook block update-text "Bugbook Strategy" path:3 --text-file -
cat sibling.md | bugbook block insert "Bugbook Strategy" path:3 --after --content-file - --dry-run
bugbook block move "Bugbook Strategy" path:3 path:7 --before --dry-run
bugbook block delete "Bugbook Strategy" path:3 --dry-run
cat snippet.md | bugbook page update "Bugbook Strategy" --append-file -
bugbook get "Bugbook Strategy Board" row_1234abcd --fields "Title,Phase" --raw-properties
bugbook backlinks "Bugbook Strategy"
bugbook search "local-first agent notes"
```

`bugbook page get --raw` prints clean markdown by default; add `--include-internal-comments` for the literal stored file. `bugbook page get --blocks` returns parsed markdown blocks plus document metadata. `bugbook page get --block-id` narrows reads to one block by stable UUID or `path:` selector. `bugbook page headings` lists headings with levels and line numbers. `bugbook page format --style bugbook|commonmark` rewrites a page using either Bugbook's dense block format or a CommonMark-style layout with structural blank lines. `bugbook page format --style commonmark` strips persisted block IDs and converts Bugbook-only block syntax into portable approximations: toggles become `<details>`, columns are flattened sequentially with thematic breaks, database embeds become labeled text, and page-link blocks become relative markdown links when they resolve uniquely in the workspace or plain text when they do not. `bugbook page compact` is the shortcut for `bugbook page format --style bugbook` and removes empty paragraph gaps. `bugbook page ensure-block-ids` persists unique stable block IDs and repairs duplicate persisted IDs, while `bugbook page strip-block-ids` removes those internal comments again. `bugbook page get --section` or `--section-line` narrows reads to a single heading section. `bugbook page update` supports either a full replacement or prepend/append edits per command, `--section` or `--section-line` scopes those edits to a heading body, `--block-id` scopes them to one block without polluting a clean note, `--text-file` preserves the selected block's markdown type, `--create-section` appends a missing section safely, `--dry-run` previews the resulting page plus structured line changes before writing, and `--output summary` returns a compact mutation payload. `bugbook block list`, `block get`, `block replace`, `block update-text`, `block insert`, `block move`, and `block delete` provide a dedicated block-level surface. `bugbook get` and `bugbook query --fields` return friendly property names and display values by default; add `--raw-properties` when you also need schema IDs and stored option IDs.

## Boards And Databases
```bash
bugbook board create "Bugbook Strategy Board" --group-name "Phase" --column "Now" --column "Next" --column "Later" --view list --view calendar --embed-in "Bugbook Strategy"
bugbook board create "Sprint Board" --column "Todo" --column "Doing" --column "Done" --no-table
bugbook board add-card "Bugbook Strategy Board" "Search trust" --column "Now" --date 2026-03-07
bugbook board move-card "Bugbook Strategy Board" row_1234abcd "Next"
bugbook page embed-database "Bugbook Strategy" "Bugbook Strategy Board"
bugbook db schema "Bugbook Strategy Board"
bugbook db view list "Bugbook Strategy Board"
bugbook db view add "Bugbook Strategy Board" --type calendar --name "Calendar" --date-property "Date"
bugbook db view set-default "Bugbook Strategy Board" "Calendar"
```

You can write rows using either schema IDs or friendly property/option names, but inspect the schema first when you need exact field coverage.

## Skills
```bash
bugbook skill list
bugbook skill get "research-summarizer"
bugbook skill create "research-summarizer" --description "Summarize linked source pages into one note."
```

## Agent Tracking
```bash
bugbook agent init --write-agents-md
bugbook agent task create --title "Implement feature X" --status todo --label ios --path Sources/Bugbook
bugbook agent run start --task task_1234abcd --agent codex --cwd /path/to/repo --branch codex/feature-x
bugbook agent event log --run run_1234abcd --level info --message "Opened architecture docs"
bugbook agent run finish run_1234abcd --status succeeded --summary "Added feature X" --commit abc1234
bugbook agent task update task_1234abcd --status done
```

## Status Values
- Task: `backlog`, `todo`, `in_progress`, `blocked`, `done`, `cancelled`
- Run: `running`, `succeeded`, `failed`, `cancelled`
- Event: `info`, `warning`, `error`
"""
    }
}
