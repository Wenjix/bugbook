---
name: dispatch
description: Smart parallel ticket dispatcher — analyzes file overlap across tickets, builds a dependency graph, groups tickets into conflict-free parallel lanes, and executes each lane in its own git worktree. The analysis and routing layer on top of /go. Use when the user says "dispatch tickets", "smart parallel", "parallelize these tickets", "run tickets without conflicts", "dispatch", "parallel dispatch", "multi-lane", or wants to execute multiple tickets simultaneously without merge conflicts.
---

# Dispatch

Analyze ticket file overlap, build parallel lanes with no conflicts, execute each lane in its own worktree, merge results sequentially. This is the smart front-end to /go — it handles analysis and routing, /go handles the actual ticket execution logic.

---

## Project Filtering

Before querying tickets, detect the current project from the working directory:
- `/Code/dahso` → add `--filter "Project!=Canopy"` to all queries
- `/Code/canopy-menu` or `/canopy` → add `--filter "Project=Canopy"` to all queries

---

## Input

Accept one of:
1. Explicit ticket IDs: `dispatch row_abc row_def row_ghi`
2. No IDs: query all To Do tickets from the Agent Tickets database (filtered by project)

```bash
# Dahso context:
dahso query "Agent Tickets" --filter "Status=To Do" --filter "Project!=Canopy" --body
# Canopy context:
dahso query "Agent Tickets" --filter "Status=To Do" --filter "Project=Canopy" --body
```

If no tickets are To Do, stop and say so.

---

## Phase 1: File Analysis

For each ticket, identify which source files it will touch.

### Primary source: Files field
```bash
dahso get "Agent Tickets" <row_id> --body
```

Read the `Files` property. This is the authoritative source — /ticket and /prep verify these paths exist.

### Secondary source: ticket body scan

If the Files field is empty or sparse, scan the ticket body for clues:
- Explicit file paths (anything ending in `.swift`, `.ts`, `.json`, etc.)
- View names — grep the codebase: `grep -rl "struct <ViewName>" --include="*.swift"`
- Model names — grep for type declarations
- Component names mentioned in the spec

Record a file list per ticket:
```
ticket_a: [SidebarView.swift, SidebarViewModel.swift]
ticket_b: [EditorView.swift, BlockCellView.swift]
ticket_c: [SidebarView.swift, NavigationStore.swift]
ticket_d: [TableView.swift, TableViewModel.swift]
```

### Glue file detection

Flag these as shared glue — any ticket touching them cannot safely parallelize with other tickets touching them:
- `Package.swift`, `project.pbxproj`
- App entry points (`App.swift`, `ContentView.swift`)
- Navigation registries, route definitions
- Shared models, design tokens, generated files

If a ticket's Files field includes a glue file, note it. Glue files increase the blast radius and reduce parallelism.

---

## Phase 2: Dependency Graph

Build a file-to-ticket map:

```
SidebarView.swift      -> [ticket_a, ticket_c]
SidebarViewModel.swift -> [ticket_a]
EditorView.swift       -> [ticket_b]
BlockCellView.swift    -> [ticket_b]
NavigationStore.swift  -> [ticket_c]
TableView.swift        -> [ticket_d]
TableViewModel.swift   -> [ticket_d]
```

Invert to get the conflict graph — tickets that share at least one file must be sequenced:
```
ticket_a <-> ticket_c  (share SidebarView.swift)
ticket_b              (no overlap)
ticket_d              (no overlap)
```

Also check the Linked field on each ticket — /flow and /ticket populate this with cross-ticket dependencies. Linked tickets must be sequenced regardless of file overlap.

---

## Phase 3: Parallel Lanes

Group tickets into lanes where no two lanes share a file. Within each lane, tickets run sequentially in priority order (High > Medium > Low), with foundation-before-polish ordering for same-priority tickets.

Algorithm:
1. Build connected components from the conflict graph.
2. Each connected component becomes one lane.
3. Unconnected tickets are each their own lane (maximum parallelism).
4. Merge single-ticket lanes that have no overlap into a combined lane to reduce worktree count — but only if they're truly independent.

Cap at 4 parallel lanes. If more lanes are possible, combine the smallest ones. Each worktree has overhead (disk, build cache, context window), so more than 4 rarely helps.

Example output:
```
Lane 1: ticket_a -> ticket_c  (share SidebarView.swift, must sequence)
Lane 2: ticket_b              (independent)
Lane 3: ticket_d              (independent)
```

---

## Phase 4: Confirmation

Print the execution plan and wait for user approval.

```
Dispatch Plan
=============

Tickets: 4
Lanes: 3 (max parallelism: 3)
Estimated time: faster than sequential by ~2x

Lane 1 (sequential — shared files):
  1. [High] Fix sidebar drag — SidebarView.swift, SidebarViewModel.swift
  2. [Medium] Add nav shortcut — SidebarView.swift, NavigationStore.swift
  Shared: SidebarView.swift

Lane 2:
  3. [High] Callout block — EditorView.swift, BlockCellView.swift

Lane 3:
  4. [Medium] Grip dots — TableView.swift, TableViewModel.swift

Glue files touched: none
Overlap between lanes: none (safe to parallelize)

Proceed? (y/n)
```

If the user wants to adjust (move a ticket between lanes, force sequential, remove a ticket), update the plan and re-confirm.

---

## Phase 5: Execution

### Setup

```bash
# Clean stale worktrees
rm -rf .claude/worktrees/dispatch-*
git worktree prune

# Ensure dev branch is current
git stash push -m "dispatch: auto-stash $(date '+%Y-%m-%d %H:%M')" 2>/dev/null
git checkout dev 2>/dev/null || git checkout -b dev main
git merge main --no-edit 2>/dev/null || true
```

### Create worktrees

One worktree per lane, branching from dev:

```bash
for LANE_NUM in 1 2 3; do
  BRANCH="dispatch-lane-${LANE_NUM}-$(date '+%m%d')"
  git worktree add ".claude/worktrees/dispatch-lane-${LANE_NUM}" -b "$BRANCH" dev
done
```

### Dispatch agents

For each lane, spawn a sub-agent working in that lane's worktree. Each agent processes its ticket queue sequentially using /go execution logic.

**Agent prompt per lane:**

```
You are executing a queue of tickets in this worktree. Work through them sequentially.

## Worktree
<absolute path to this lane's worktree>

## Queue
<for each ticket in this lane: title, body, files, eval>

## Instructions
1. For each ticket:
   a. Read all files listed before writing code.
   b. Implement the change. Stay scoped.
   c. Run `xcodebuild -quiet 2>&1 | tail -40` (or appropriate build command) and fix issues, up to 3 retries.
   d. Commit on this lane's branch with message: "<ticket title>"
   e. Update ticket status to Review via dahso.
   f. Append Agent Notes to the ticket body.
   g. Never mark tickets as Done — Review only.
   h. Never add unrequested features.
2. If a ticket fails after 3 build attempts, revert its changes, note the failure in the ticket body, and move to the next ticket.
3. Report results for all tickets when done.
```

Launch lanes in parallel:

```
# Lane 1 — Agent (worktree)
Agent(
  description: "Dispatch lane 1: <ticket names>",
  isolation: "worktree:<path>",
  mode: "bypassPermissions",
  prompt: <lane 1 prompt>
)

# Lane 2 — Agent (worktree)
Agent(
  description: "Dispatch lane 2: <ticket names>",
  isolation: "worktree:<path>",
  mode: "bypassPermissions",
  prompt: <lane 2 prompt>
)

# Lane 3 — can also use Codex for simple tickets
codex exec --full-auto -C "<lane 3 worktree path>" -o "/tmp/dispatch-lane-3.md" "$(cat "$PROMPT_FILE")"
```

**Model selection per lane:**
- Single-ticket lanes with straightforward work (bug fix, small UI change): use model "haiku" or Codex
- Multi-ticket lanes or complex architectural work: use model "sonnet"
- Reserve opus only if the lane involves cross-cutting design decisions

**Agent prompt efficiency:** Keep lane prompts tight. Include only: ticket title, body, files, and the 8 rules from the Instructions block above. Don't paste the full dispatch skill into each sub-agent.

Wait for all lanes to complete.

---

## Phase 6: Merge Protocol

Merge each lane's branch into dev one at a time. Order lanes by size (fewest commits first) to surface conflicts early when they're easiest to resolve.

```bash
git checkout dev

for LANE_NUM in 1 2 3; do
  BRANCH="dispatch-lane-${LANE_NUM}-$(date '+%m%d')"

  echo "Merging lane ${LANE_NUM}..."
  git merge "$BRANCH" --no-edit

  # If merge conflict — should not happen if analysis was correct
  if [ $? -ne 0 ]; then
    echo "CONFLICT in lane ${LANE_NUM}. Resolving..."
    # Inspect conflicts, resolve, then:
    git add -A
    git commit --no-edit
  fi

  # Build verification after each merge
  BUILD_OK=false
  for ATTEMPT in 1 2 3; do
    echo "Post-merge build check (lane ${LANE_NUM}, attempt ${ATTEMPT}/3)..."
    if xcodebuild -quiet 2>&1 | tail -20 | grep -q "BUILD SUCCEEDED"; then
      BUILD_OK=true
      break
    fi
    # Read error output, diagnose, fix before retry
  done

  if [ "$BUILD_OK" = false ]; then
    echo "Build failed after merging lane ${LANE_NUM}. Reverting merge."
    git revert HEAD --no-edit
    # Flag affected tickets as blocked
  fi
done
```

If a merge conflict occurs (the analysis missed an overlap), resolve it manually. This is the safety net — the analysis in Phase 2 should prevent this, but the merge protocol catches it.

---

## Phase 7: Cleanup

```bash
# Remove all dispatch worktrees
for LANE_NUM in 1 2 3; do
  git worktree remove ".claude/worktrees/dispatch-lane-${LANE_NUM}" --force 2>/dev/null || true
done
git worktree prune

# Delete lane branches (merged into dev)
for LANE_NUM in 1 2 3; do
  BRANCH="dispatch-lane-${LANE_NUM}-$(date '+%m%d')"
  git branch -d "$BRANCH" 2>/dev/null || true
done
```

---

## Phase 8: Report

```
Dispatch Complete
=================

Lanes: 3
Tickets completed: 4/4
Merge conflicts: 0
Build status: PASSING

Lane 1 (2 tickets):
  - [Review] Fix sidebar drag — PASS
  - [Review] Add nav shortcut — PASS

Lane 2 (1 ticket):
  - [Review] Callout block — PASS

Lane 3 (1 ticket):
  - [Review] Grip dots — PASS

All changes on dev branch. Ready for review.
```

---

## Rules

1. Never merge to main. All work lands on dev.
2. Never mark tickets Done. Move to Review only.
3. Never add unrequested features.
4. If file analysis is uncertain, be conservative — put uncertain tickets in the same lane.
5. Cap at 4 lanes. More worktrees means more overhead.
6. Build after every merge. A green lane can break dev if it conflicts with another lane's changes.
7. If a merge conflict occurs, stop and resolve before continuing. Don't merge the next lane on top of a conflict.
8. Confirm the plan with the user before creating any worktrees.
9. Glue files (pbxproj, Package.swift, app entry points) force tickets into the same lane.
10. The analysis is the value — /go handles execution. Don't reinvent ticket execution logic here.

---

## CLI Quick Reference

```bash
# Dahso
dahso query "Agent Tickets" --filter "Status=To Do" --body
dahso get "Agent Tickets" <row_id> --body
dahso update "Agent Tickets" <row_id> --set "Status=Review"

# Git worktrees
git worktree add <path> -b <branch> dev
git worktree remove <path> --force
git worktree list
git worktree prune

# Merge
git checkout dev
git merge <branch> --no-edit

# Build
xcodebuild -quiet 2>&1 | tail -40
swift build 2>&1 | tail -20
```
