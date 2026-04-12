You manage a local dahso workspace via the `dahso` CLI.
All commands return JSON. Use jq to parse output when needed.

## Discovering what exists

dahso page list                  # -> [{path, relative_path, name, title, tags}]
dahso page get "Dahso Strategy"
dahso page embed-database "Dahso Strategy" "Dahso Strategy Board"
dahso board create "Dahso Strategy Board" --group-name "Phase" --column "Now" --column "Next" --column "Later" --view list --view calendar --embed-in "Dahso Strategy"
dahso board add-card "Dahso Strategy Board" "Search trust" --column "Now"
dahso board move-card "Dahso Strategy Board" row_abc123 "Next"
dahso db view list "Dahso Strategy Board"
dahso db view add "Dahso Strategy Board" --type calendar --name "Calendar" --date-property "Date"
dahso db view update "Dahso Strategy Board" "Calendar" --name "Timeline"
dahso db view set-default "Dahso Strategy Board" "Timeline"
dahso db view delete "Dahso Strategy Board" "Timeline"
dahso skill create "research-summarizer" --description "Summarize linked source pages into one note."
dahso skill list                 # -> [{path, relative_path, name, title, description}]
dahso skill get "research-summarizer"
dahso db list                    # -> [{id, name, path, row_count}]
dahso db schema <db_name>        # -> full schema with properties and options

Always check the schema before querying to get correct property IDs and option IDs.

## Working with notes

dahso page create "Notes/Research Summary" --title "Research Summary"
dahso page update "Notes/Research Summary" --append-file -    # pipe markdown via stdin
dahso page delete "Notes/Research Summary"
dahso backlinks "Dahso Strategy"                            # -> pages that link here
dahso page embed-database "Dahso Strategy" "Dahso Strategy Board"

Workspace skills live in `Skills/*.skill.md`. Use them as lightweight agent playbooks stored with the notes.
`dahso page update` accepts either `--content-file` for a full replacement or `--prepend-file` / `--append-file` for incremental edits.
Boards live in `databases/` by default. `dahso board create` returns the property/option IDs needed for custom card creation, supports extra `--view` values like `list` and `calendar`, accepts `--no-table` when you want a kanban-only board, and auto-adds a date property when calendar is enabled.
Use `dahso db view ...` to evolve an existing database without rewriting `_schema.json`.

## Querying

dahso query <db> [--filter "prop=val"] [--sort "prop:asc"] [--limit N]

Filter operators: = != > < ~ !~ =_empty =_not_empty
Multiple --filter flags are ANDed.

Common patterns:
  dahso query tasks --filter "status=opt_doing"
  dahso query tasks --filter "status!=opt_done" --sort "priority:asc"
  dahso query tasks --filter "project~row_proj_001"

## Reading a row

dahso get <db> <row_id> --body   # includes markdown body

## Creating

dahso create <db> --set "title=..." --set "status=opt_todo"

Use option IDs for select/multi_select (e.g. opt_todo not "Todo").

## Updating

dahso update <db> <row_id> --set "status=opt_done"
dahso update <db> <row_id> --body-file -    # pipe body via stdin

## Deleting

dahso delete <db> <row_id>

## Batch operations

Pipe JSON array to stdin:
echo '[{"op":"update","id":"row_x","set":{"status":"opt_done"}}]' | dahso batch <db>

## Conventions

- Always use property IDs (prop_status) not display names (Status)
- Always use option IDs (opt_todo) not display names (Todo)
- Relations store row IDs: --set "project=row_proj_001"
- Dates are YYYY-MM-DD: --set "due=2026-03-15"
- Multi-select values are comma-separated: --set "tags=opt_bug,opt_feature"

## Agent Workflow

Initialize agent tracking files:
  dahso agent init --write-agents-md

Task lifecycle:
  dahso agent task list
  dahso agent task create --title "Fix editor crash" --status todo --label bug --path Sources/Dahso
  dahso agent task update <task_id> --status in_progress
  dahso agent task update <task_id> --status done

Run lifecycle:
  dahso agent run start --task <task_id> --agent codex --cwd /path/to/repo --branch codex/fix-crash
  dahso agent event log --run <run_id> --level info --message "Added regression test"
  dahso agent run finish <run_id> --status succeeded --summary "Fixed crash" --commit abc1234

Status values:
  task statuses: backlog, todo, in_progress, blocked, done, cancelled
  run statuses: running, succeeded, failed, cancelled
  event levels: info, warning, error
