# dahso plugin

Claude Code workflow skills for [Dahso](https://github.com/max4c/dahso) — the macOS personal knowledge management app.

This plugin turns your Dahso workspace into a project management system that Claude Code can drive. You get ticket tracking, autonomous overnight execution, project context pages, review gates, and a knowledge loop that grows your spec library as you ship work.

## Skills

| Skill | What it does |
|---|---|
| `flow` | End-to-end project orchestration — transcript in, spec written, tickets created, work executed through review gates. Composes with `max:write-prd` for the spec phase. |
| `ticket` | Create and optionally execute a single bug/feature ticket. The atomic unit of work. |
| `go` | Autonomous overnight execution of the ticket queue. Codex as primary worker, Claude worktree agents as fallback for complex multi-file work. |
| `prep` | Pre-`/go` audit. Walks every To Do ticket, checks spec completeness, writes machine-verifiable evals for each. |
| `catchup` | Start-of-session orientation. Reviews overnight results, writes a Session Brief page to your Dahso workspace. |
| `book` | Direct Dahso CLI access — search, query, create, update databases and pages from the conversation. |
| `wreview` | Weekly OODA review. Pre-fills a Dahso page from tickets, git, email, calendar, and memory. |
| `compile` | Compile a Dahso workspace into an agent-navigable wiki. |
| `dispatch` | Parallel ticket dispatcher. Groups tickets into conflict-free lanes and executes them in worktrees. |
| `import-obsidian` | One-shot migration from an Obsidian vault into a Dahso workspace. |

## Installation

```
/plugin marketplace add max4c/dahso
/plugin install dahso@max4c-dahso
/plugin install max@max4c-dahso
```

The install syntax is `plugin-name@marketplace-name` — both plugins ship from the `max4c-dahso` marketplace bundled in this repo. The `max` plugin source itself lives in `max4c/skills`; the marketplace just points at it.

The `max` plugin is a companion general skills library that provides `grill-me`, `write-prd`, `tdd`, and more. The dahso plugin's `flow`, `prep`, and `ticket` skills invoke `max:grill-me` and `max:write-prd` for active spec grilling and ambiguity scoring. Without `max` installed, those skills fall back to passive review gates.

## Requirements

- **Dahso macOS app** with the `dahso` CLI on your `$PATH`. This plugin's skills invoke `dahso query`, `dahso page`, `dahso create`, `dahso update`, etc.
- **Claude Code** with the plugin system enabled.
- **Optional:** [Codex CLI](https://github.com/openai/codex) for `/go`'s autonomous execution.
- **Optional:** `gh` CLI for some git operations.

## Core workflow loop

```
/flow       — take a project description, turn it into a spec and tickets
/prep       — audit the ticket queue before walking away
/go         — autonomous overnight execution (or while you're AFK)
/catchup    — start-of-session orientation, see what happened overnight
```

Plus `/ticket` for one-off work items and `/grill-me` (from the `max` plugin) as the interrogation engine throughout.

## Dahso app

The Dahso macOS app is at [max4c/dahso](https://github.com/max4c/dahso). It's a local-first PKM tool with notes, databases, meetings, calendar, and a CLI. This plugin assumes you're running Dahso and have the CLI wired up.

## License

MIT. See repository root LICENSE.
