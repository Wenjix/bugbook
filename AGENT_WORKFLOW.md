# Agent Workflow

This repo now supports a shared task/run/event workflow for coding agents and humans.

## Files

Workspace files (inside your selected Bugbook workspace):

- `.bugbook/agents/tasks.json`
- `.bugbook/agents/runs.jsonl`
- `.bugbook/agents/events.jsonl`
- `AGENTS.md` (optional instructions for agents)

## CLI

Initialize:

```bash
bugbook agent init --workspace ~/Documents/Bugbook --write-agents-md
```

Create and move tasks:

```bash
bugbook agent task create --workspace ~/Documents/Bugbook --title "Implement agent dashboard" --status todo
bugbook agent task list --workspace ~/Documents/Bugbook
bugbook agent task update task_xxxxxxxx --workspace ~/Documents/Bugbook --status in_progress
bugbook agent task update task_xxxxxxxx --workspace ~/Documents/Bugbook --status done
```

Track runs:

```bash
bugbook agent run start --workspace ~/Documents/Bugbook --task task_xxxxxxxx --agent codex --branch codex/agent-dashboard
bugbook agent event log --workspace ~/Documents/Bugbook --run run_xxxxxxxx --level info --message "Implemented status cards"
bugbook agent run finish run_xxxxxxxx --workspace ~/Documents/Bugbook --status succeeded --summary "Agent dashboard shipped" --commit abc1234
```

Dashboard JSON:

```bash
bugbook agent dashboard --workspace ~/Documents/Bugbook
```

## Desktop App

- Default daily-driver mode hides Agent Hub from the sidebar; use the CLI for agent task/run/event workflows.
- For development, enable legacy panes with `BUGBOOK_LEGACY_PANES=1` to restore the desktop Agent Hub surface.
- In legacy mode, Agent Hub shows active tasks, recent runs, recent events, quick-create tasks, and task status controls.

## iPhone App

- Open `ios/BugbookMobile.xcodeproj`.
- Run scheme `BugbookMobileApp`.
- `Notes` tab: create/open markdown notes.
- `Agent Hub` tab: view task/run/event activity and update task statuses.
