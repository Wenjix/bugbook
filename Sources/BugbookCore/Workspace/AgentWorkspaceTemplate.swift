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
bugbook page create "Notes/Research Summary" --title "Research Summary"
cat replacement.md | bugbook page update "Bugbook Strategy" --content-file -
cat snippet.md | bugbook page update "Bugbook Strategy" --append-file -
bugbook backlinks "Bugbook Strategy"
bugbook search "local-first agent notes"
```

`bugbook page update` supports either a full replacement or prepend/append edits per command.

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

Inspect the schema before writing rows directly so you use the real property IDs and option IDs.

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
