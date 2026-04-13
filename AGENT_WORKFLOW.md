# Agent Workflow

This repo now supports a shared task/run/event workflow for coding agents and humans.

## Files

Workspace files (inside your selected Dahso workspace):

- `.dahso/agents/tasks.json`
- `.dahso/agents/runs.jsonl`
- `.dahso/agents/events.jsonl`
- `AGENTS.md` (optional instructions for agents)

## CLI

Initialize:

```bash
dahso agent init --workspace ~/Documents/Dahso --write-agents-md
```

Create and move tasks:

```bash
dahso agent task create --workspace ~/Documents/Dahso --title "Implement agent dashboard" --status todo
dahso agent task list --workspace ~/Documents/Dahso
dahso agent task update task_xxxxxxxx --workspace ~/Documents/Dahso --status in_progress
dahso agent task update task_xxxxxxxx --workspace ~/Documents/Dahso --status done
```

Track runs:

```bash
dahso agent run start --workspace ~/Documents/Dahso --task task_xxxxxxxx --agent codex --branch codex/agent-dashboard
dahso agent event log --workspace ~/Documents/Dahso --run run_xxxxxxxx --level info --message "Implemented status cards"
dahso agent run finish run_xxxxxxxx --workspace ~/Documents/Dahso --status succeeded --summary "Agent dashboard shipped" --commit abc1234
```

Dashboard JSON:

```bash
dahso agent dashboard --workspace ~/Documents/Dahso
```

## Desktop App

- Open **Agent Hub** from the sidebar (or `Cmd+Shift+J`).
- See active tasks, recent runs, recent events, and quick-create tasks.
- Update task status directly from the task list.

## iPhone App

- Open `ios/DahsoMobile.xcodeproj`.
- Run scheme `DahsoMobileApp`.
- `Notes` tab: create/open markdown notes.
- `Agent Hub` tab: view task/run/event activity and update task statuses.
