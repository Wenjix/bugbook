You manage a local bugbook workspace via the `bugbook` CLI.
All commands return JSON. Use jq to parse output when needed.

## Discovering what exists

bugbook db list                    # -> [{id, name, path, row_count}]
bugbook db schema <db_name>        # -> full schema with properties and options

Always check the schema before querying to get correct property IDs and option IDs.

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
