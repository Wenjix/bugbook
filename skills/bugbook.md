You manage a local bugbook workspace via the `bugbook` CLI.
All commands return JSON. Use jq to parse output when needed.

## Discovering what exists

bugbook page list                  # -> [{path, relative_path, name, title, tags}]
bugbook page get "Bugbook Strategy"
bugbook page embed-database "Bugbook Strategy" "Bugbook Strategy Board"
bugbook board create "Bugbook Strategy Board" --group-name "Phase" --column "Now" --column "Next" --column "Later" --view list --view calendar --embed-in "Bugbook Strategy"
bugbook board add-card "Bugbook Strategy Board" "Search trust" --column "Now"
bugbook board move-card "Bugbook Strategy Board" row_abc123 "Next"
bugbook db view list "Bugbook Strategy Board"
bugbook db view add "Bugbook Strategy Board" --type calendar --name "Calendar" --date-property "Date"
bugbook db view update "Bugbook Strategy Board" "Calendar" --name "Timeline"
bugbook db view set-default "Bugbook Strategy Board" "Timeline"
bugbook db view delete "Bugbook Strategy Board" "Timeline"
bugbook skill create "research-summarizer" --description "Summarize linked source pages into one note."
bugbook skill list                 # -> [{path, relative_path, name, title, description}]
bugbook skill get "research-summarizer"
bugbook db list                    # -> [{id, name, path, row_count}]
bugbook db schema <db_name>        # -> full schema with properties and options

Always check the schema before querying to get correct property IDs and option IDs.

## Working with notes

bugbook page create "Notes/Research Summary" --title "Research Summary"
bugbook page update "Notes/Research Summary" --append-file -    # pipe markdown via stdin
bugbook page delete "Notes/Research Summary"
bugbook backlinks "Bugbook Strategy"                            # -> pages that link here
bugbook page embed-database "Bugbook Strategy" "Bugbook Strategy Board"

Workspace skills live in `Skills/*.skill.md`. Use them as lightweight agent playbooks stored with the notes.
`bugbook page update` accepts either `--content-file` for a full replacement or `--prepend-file` / `--append-file` for incremental edits.
Boards live in `databases/` by default. `bugbook board create` returns the property/option IDs needed for custom card creation, supports extra `--view` values like `list` and `calendar`, accepts `--no-table` when you want a kanban-only board, and auto-adds a date property when calendar is enabled.
Use `bugbook db view ...` to evolve an existing database without rewriting `_schema.json`.

## Querying

bugbook query <db> [--filter "prop=val"] [--sort "prop:asc"] [--limit N]

Filter operators: = != > < ~ !~ =_empty =_not_empty
Multiple --filter flags are ANDed.

Common patterns:
  bugbook query tasks --filter "status=opt_doing"
  bugbook query tasks --filter "status!=opt_done" --sort "priority:asc"
  bugbook query tasks --filter "project~row_proj_001"

## Reading a row

bugbook get <db> <row_id> --body   # includes markdown body

## Creating

bugbook create <db> --set "title=..." --set "status=opt_todo"

Use option IDs for select/multi_select (e.g. opt_todo not "Todo").

## Updating

bugbook update <db> <row_id> --set "status=opt_done"
bugbook update <db> <row_id> --body-file -    # pipe body via stdin

## Deleting

bugbook delete <db> <row_id>

## Batch operations

Pipe JSON array to stdin:
echo '[{"op":"update","id":"row_x","set":{"status":"opt_done"}}]' | bugbook batch <db>

## Conventions

- Always use property IDs (prop_status) not display names (Status)
- Always use option IDs (opt_todo) not display names (Todo)
- Relations store row IDs: --set "project=row_proj_001"
- Dates are YYYY-MM-DD: --set "due=2026-03-15"
- Multi-select values are comma-separated: --set "tags=opt_bug,opt_feature"

## Agent Workflow

Initialize agent tracking files:
  bugbook agent init --write-agents-md

Task lifecycle:
  bugbook agent task list
  bugbook agent task create --title "Fix editor crash" --status todo --label bug --path Sources/Bugbook
  bugbook agent task update <task_id> --status in_progress
  bugbook agent task update <task_id> --status done

Run lifecycle:
  bugbook agent run start --task <task_id> --agent codex --cwd /path/to/repo --branch codex/fix-crash
  bugbook agent event log --run <run_id> --level info --message "Added regression test"
  bugbook agent run finish <run_id> --status succeeded --summary "Fixed crash" --commit abc1234

Status values:
  task statuses: backlog, todo, in_progress, blocked, done, cancelled
  run statuses: running, succeeded, failed, cancelled
  event levels: info, warning, error
