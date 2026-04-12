---
name: flow
description: Structured agent workflow that takes a Granola transcript or written description, creates tracked projects and tickets in Dahso, executes them sequentially with status updates, and loops on human review until clean. Use this skill whenever the user wants to start a development workflow, process a meeting transcript into tasks, break work into tickets, or says "flow", "start a flow", "process this transcript", "break this into tickets", "here's what we discussed", or pastes meeting notes. Also use when the user pastes a Granola transcript, describes a batch of work to be done, or wants to turn a planning conversation into tracked action items.
---

# Flow

Structured agent workflow: input in, spec written, tickets out, work done, repeat until clean.

Use the `book` skill for Dahso CLI patterns and the `swiftui-pro` skill for SwiftUI conventions when working in Swift code.

---

## Entry Modes

Detect automatically from context:

1. **Fresh start** — user provides a Granola transcript, meeting notes, or description of new work -> create project + spec + tickets -> run full flow
2. **Continue with additions** — user describes new work on an existing project -> query active project + existing To Do tickets, create new tickets, then run flow
3. **Just continue** — user says "keep going", "continue", "pick up where we left off", or similar -> query existing To Do tickets and jump straight to execution

If ambiguous, ask. For modes 2 and 3, query the active project:

```bash
dahso query "Agent Projects" --filter "Status=Active"
```

If multiple active projects, ask which one. If there are none, ask whether to start a fresh flow instead.

---

## Project Filtering

Before querying or creating tickets, detect the current project from the working directory:

- If cwd is inside `/Code/dahso` → **Dahso** project. Exclude Canopy tickets from queries. When creating, don't set Project (Dahso is the default/home project).
- If cwd is inside `/Code/canopy-menu` or `/canopy` → **Canopy** project. Only show Canopy tickets. When creating, set `--set "Project=Canopy"`.
- Otherwise → show all tickets (no filter).

**Query patterns:**
```bash
# Dahso context — exclude Canopy
dahso query "Agent Tickets" --filter "Status=To Do" --filter "Project!=Canopy" --body

# Canopy context — only Canopy
dahso query "Agent Tickets" --filter "Status=To Do" --filter "Project=Canopy" --body
```

Apply this filter to ALL ticket queries in every phase below. When presenting tickets to the user, never show tickets from a different project unless explicitly asked.

---

## Setup: Database Cache

On first run, discover and cache both database IDs. On subsequent runs, read from cache. Re-lookup if a cached ID fails.

**Cache file:** `~/.dahso/flow-cache.json`

```bash
dahso db list
```

**Cache format:**
```json
{
  "agent_projects": "<db_id>",
  "agent_tickets": "<db_id>"
}
```

**Logic:**
1. Check if `~/.dahso/flow-cache.json` exists. If yes, read it.
2. If missing or a CLI call fails, run `dahso db list`, find "Agent Projects" and "Agent Tickets", then `mkdir -p ~/.dahso` and write the cache.

---

## Database Schemas

### Agent Projects
| Property | Type   | Values                    |
|----------|--------|---------------------------|
| Name     | title  | Project title             |
| Status   | select | Backlog, Active, Complete |
| Body     | —      | Project description       |

### Agent Tickets
| Property | Type     | Values                                            |
|----------|----------|---------------------------------------------------|
| Name     | title    | Ticket title                                      |
| Status   | select   | To Do, In Progress, Review, Done                  |
| Project  | relation | Row ID of the parent Agent Projects entry         |
| Priority | select   | High, Medium, Low                                 |
| Files    | text     | Comma-separated file paths                        |
| Linked   | text     | Comma-separated row IDs of tickets sharing files  |
| Source   | text     | How the ticket was created (user, mid-flow)       |
| Body     | —        | Spec, agent notes, and review feedback            |

---

## Phase 1: Intake

Understand the input and detect entry mode.

For a fresh start: identify the project scope and individual work items from the transcript, meeting notes, or written description. If the input is ambiguous about what constitutes a separate ticket or which files are involved, ask before proceeding.

For continue modes: query existing To Do tickets and present a brief summary of what's pending before proceeding.

---

## Phase 2: Spec Phase

*(Fresh start and continue-with-additions only — skip for just-continue)*

Before creating any tickets, write a proper spec. The spec lives as a Dahso project context page that all tickets reference and agents consult during execution. It's a living document — updated as implementation reveals new information.

This phase delegates the heavy lifting (codebase exploration, Socratic interview, spec drafting, ambiguity gate) to the `max:write-prd` skill from the companion general skills plugin. /flow handles the Dahso-specific parts around it: pulling prior context before invocation, and persisting the result to a Dahso project context page after.

### 2a. Pull existing Dahso context

Check if there's already relevant context in Dahso:
```bash
dahso search "<project area or feature name>"
```

If a context page exists, read it:
```bash
dahso context "<ProjectPage>" --depth 2
```

Look for prior decisions, discoveries from previous cycles, and constraints that should carry forward. Inject what you find into the conversation so `max:write-prd` sees it when invoked.

### 2b. Invoke max:write-prd

Invoke the `max:write-prd` skill. It will handle:
- Codebase exploration (read the files the spec will touch, find existing patterns)
- Socratic interview (one question at a time, with your recommended answers)
- PRD drafting (Goals / Requirements / Non-Goals / Constraints / Approach / Open Questions)
- Grill gate via `max:grill-me` in spec mode (per-dimension ambiguity scoring, threshold 0.2)

`max:write-prd` will output a PRD as conversation content. Capture it for the next step.

**Fallback if `max` plugin is not installed:** fall back to the old inline spec-writing. Do the codebase exploration yourself, draft the spec using the same format (Goals / Requirements / Non-Goals / Constraints / Approach / Open Questions / Discoveries), and invoke `grill-me` if it exists locally. Note in the terminal that installing `max` from `max4c/dahso` marketplace would give active grilling and ambiguity scoring.

### 2c. Persist to Dahso project context page

Take the PRD content from `max:write-prd` and create (or update) a Dahso page with it:

```bash
cat <<'PAGE' | dahso page create "<Project Name>" --content-file -
<PRD content from max:write-prd>

## Discoveries

<Initially empty. Populated by agents during execution as they find unexpected things. This section is the knowledge loop — each entry includes date, ticket name, what was found, and implications.>
PAGE
```

The `## Discoveries` section is Dahso-specific — it's the knowledge loop that feeds discoveries back from execution to future planning. `max:write-prd` doesn't know about this; /flow adds it on persistence.

If `max:write-prd` already appended an `## Ambiguity Report` section (spec-mode grill does this), preserve it in the Dahso page.

### 2d. Proceed to Phase 3

The spec is ready. Proceed to ticket creation.

(There's no separate "review gate" step anymore — `max:write-prd`'s internal grill gate replaces the old passive review gate. If the grill exit produced an ambiguity report above threshold and the user overrode, that's already captured.)

---

## Phase 3: Ticket Creation

Derive tickets from the spec. Each ticket is a single, independently completable unit of work.

### Classify each ticket

Use the /ticket tier system:
- **Quick** (bug fix, typo, config): lightweight spec — What + Done When
- **Feature** (new behavior, meaningful change): full spec — Current State, Desired State, Why, Boundaries, Approach, Done When

Most tickets in a fresh flow will be feature-tier since they're part of a larger initiative. Quick-tier is for small fixes discovered along the way.

### Create tickets

For each ticket, use the appropriate spec template from the /ticket skill:

```bash
cat <<'SPEC' | dahso create "Agent Tickets" \
  --set "Name=<Ticket Title>" \
  --set "Status=To Do" \
  --set "Project=<project_row_id>" \
  --set "Priority=<High|Medium|Low>" \
  --set "Files=<comma-separated paths>" \
  --set "Source=user" \
  --body-file -
<Feature-tier or quick-tier body from /ticket Phase 3>
SPEC
```

Each `dahso create` returns `{"created": true, "id": "row_xxx"}`. Save every row ID.

**Ticket guidelines:**
- Each ticket is a single, independently completable unit of work
- Order by dependency (blockers first), then priority
- Be specific about files — check the codebase before listing them
- Blockers and core functionality = High, supporting work = Medium, nice-to-haves = Low
- Reference the project context page in each ticket's Context section so agents can consult it

### Detect file overlaps and set Linked field

After creating all tickets, scan their Files fields. For each pair of tickets that share at least one file, populate both tickets' Linked fields with each other's row ID:

```bash
# Tickets A and B share files
dahso update "Agent Tickets" <row_a> --set "Linked=<row_b>"
dahso update "Agent Tickets" <row_b> --set "Linked=<row_a>"

# If ticket A shares files with both B and C
dahso update "Agent Tickets" <row_a> --set "Linked=<row_b>,<row_c>"
```

Linked tickets must be committed together — they touch the same files and a partial commit would leave things in an inconsistent state.

---

## Phase 4: Review Gate (Plan Approval)

**STOP.** Present all tickets with linkages clearly shown:

```
Project: <name>
Spec: <Dahso page name>

Tickets:
1. [High] Fix sidebar drag — SidebarView.swift, SidebarViewModel.swift  <-> linked to #2
2. [Medium] Add search filter — SidebarView.swift, SidebarViewModel.swift  <-> linked to #1
3. [Low] Update changelog — CHANGELOG.md
```

Wait for the user to approve. They may edit, add, remove, or reprioritize tickets in the Dahso app. When they give the go-ahead, proceed.

The plan review exists to catch misunderstandings before any code gets written — it's worth a full stop.

### Agent Assignment

After the user approves the plan, ask: **"Want to assign any of these to Codex, or all Claude?"**

Splitting work across agents lets the user spend tokens on both platforms in parallel and play to each model's strengths. It's not about one being better — it's about throughput and budget. If all tickets are straightforward, defaulting to all-Claude is fine. Only surface the question; don't push one way or the other.

The user will respond conversationally (e.g., "Use Codex for 1 and 3, Claude for the rest"). Record the assignment per ticket — default is Claude.

**Overlap check:** After assignments are set, compare the Files fields between Claude-assigned and Codex-assigned tickets. If any files are shared across agents, flag it:

```
Heads up — tickets #1 (Codex) and #2 (Claude) both touch SidebarView.swift and SidebarViewModel.swift.
Running them on different agents in parallel could cause conflicts. Recommend keeping them on the same agent.

Options:
  1. Move #1 to Claude (both run sequentially on Claude)
  2. Move #2 to Codex (both run sequentially on Codex)
  3. Keep split — I'll run them sequentially, not in parallel
```

Wait for the user to resolve any conflicts before proceeding. Tickets that share files across agents must either be consolidated to one agent or run sequentially (never in parallel).

---

## Phase 5: Execution

Re-query To Do tickets from Dahso — the user may have changed things during the review:

```bash
dahso query "Agent Tickets" --filter "Project=<project_row_id>" --filter "Status=To Do" --body
```

**Before starting: propose a batch.** Look at all the To Do tickets and propose how many to tackle this cycle. Consider:
- Complexity (a single targeted fix vs. a multi-file refactor each warrant different batch sizes)
- Natural stopping points (e.g., all High priority tickets, or a file-clustered group)
- Dependencies (work that unblocks other work goes first)

Example: "I see 5 tickets. I'd suggest starting with the 2 High priority ones — they share files and should be worked together. Want me to start with those, or adjust the batch?"

Get user approval on the batch before starting.

**Work order within the batch:** High priority first, then Medium, then Low. When two tickets share files (check the Linked field), work them back-to-back to minimize context switching and avoid touching the same file twice in separate passes.

**For each ticket:**

### 1. Set In Progress
```bash
dahso update "Agent Tickets" <row_id> --set "Status=In Progress"
```

### 2. Read the spec and project context
```bash
dahso get "Agent Tickets" <row_id> --body | jq -r '.body // ""'
```

Read the full body: spec sections, and — if this is a retry — all previous `## Agent Notes` sections and any user feedback written after the last note. The feedback has no label; it's plain text below the last notes section.

Also read the project context page for current discoveries and constraints:
```bash
dahso context "<ProjectPage>" --depth 2
```

### 3. Do the work

**If assigned to Claude (default):**
- Read all files listed in the ticket's Files field
- For feature-tier: follow the Approach from the spec and the project context page
- For Swift code: follow `swiftui-pro` conventions and patterns
- Implement according to spec and acceptance criteria
- Match existing codebase patterns
- Stay within Boundaries — don't touch what the spec says not to touch
- **CRITICAL — Xcode project membership for new .swift files:** The app is built from Xcode (`macos/Dahso.xcodeproj`), not SPM. `swift build` passes without pbxproj entries but Xcode won't compile — the user gets "Cannot find X in scope" errors. For each new .swift file: (1) read `macos/Dahso.xcodeproj/project.pbxproj`, (2) add PBXBuildFile + PBXFileReference + PBXGroup child entries matching adjacent files in the same directory, (3) verify with `grep "YourFileName" macos/Dahso.xcodeproj/project.pbxproj`, (4) validate with `plutil -lint macos/Dahso.xcodeproj/project.pbxproj`. Use `git add -f` if the pbxproj is gitignored.

**If assigned to Codex:**

Codex runs as a separate process with no shared context — it doesn't see the conversation, the project history, or other tickets. The prompt you send it needs to be entirely self-contained.

Build the prompt by combining:
- The ticket's spec sections (verbatim)
- The file paths from the Files field
- Any prior Agent Notes and user feedback (so Codex knows what was already tried on retries)
- Relevant project context (constraints, discoveries, approach from the project context page)
- Relevant codebase conventions if the ticket touches a domain with specific patterns

Keep it factual and direct — Codex doesn't need preamble or motivation, just the task and the constraints.

```bash
codex exec --full-auto -C "<project_root>" -o "/tmp/codex-ticket-<row_id>.md" "<prompt>"
```

Use `run_in_background: true` when there are Claude-assigned tickets to work on in parallel. When the Codex task finishes, read the output file and verify the changes with `git diff`.

**Parallel dispatch:** If the batch contains both Claude and Codex tickets with no file overlaps between them, launch all Codex tickets via background Bash commands first, then work through Claude tickets sequentially. As Codex tasks complete, check their output before moving on. If a Codex ticket fails, note the error in its Agent Notes and offer to retry on Claude.

**Agent Notes for Codex tickets:** After a Codex task completes, still append Agent Notes (step 4) as usual — but note that Codex performed the work, and include a summary of its output. This keeps the ticket history honest for the review gate.

### 4. Build verification

Before presenting work to the user, verify it compiles. Don't waste the user's smoke-testing time on code that won't build.

```bash
swift build 2>&1 | tail -20
```

If the build fails, fix the errors and retry (up to 3 attempts). If it still fails after 3 attempts, note the build failure in Agent Notes and set the ticket to Review anyway — but flag it clearly so the user knows it needs attention rather than discovering it themselves.

Adapt the build command to the project type (e.g., `npm run build`, `cargo build`). Check the project structure if unsure.

### 5. Append Agent Notes and Knowledge Loop

Read the current body, append the new notes section, write it back:

```bash
# Get current body
dahso get "Agent Tickets" <row_id> --body | jq -r '.body // ""' > /tmp/ticket_body.md

# Append notes (N = next sequential number, count existing ## Agent Notes headers)
cat >> /tmp/ticket_body.md << EOF

## Agent Notes $N ($(date "+%Y-%m-%d %H:%M"))

**Root cause:** <One sentence: what was actually wrong or what was missing>

**What changed:**
- <file:line — what was added/modified and why>
- <file:line — ...>

**How to verify:** <Restate the smoke test steps with any adjustments based on what was actually built. If the implementation differs from the spec, explain why.>

**Discoveries:** <Anything unexpected found during implementation that future agents should know. "None" if nothing surprising.>

**Build:** PASSING / FAILING
**Branch:** <branch name if worktree>
EOF

# Write back
cat /tmp/ticket_body.md | dahso update "Agent Tickets" <row_id> --body-file -
```

**Knowledge Loop:** If Discoveries has anything meaningful (not "None"), append it to the project context page:

```bash
dahso page update "<ProjectPage>" --section "Discoveries" --create-section --content-file - << EOF

**$(date "+%Y-%m-%d") — <ticket title>:** <what was found> — <implication for future work>
EOF
```

### 6. Set to Review
```bash
dahso update "Agent Tickets" <row_id> --set "Status=Review"
```

### 7. Print status
```
[3/5] "Fix sidebar drag" -> Review
```

---

## Phase 6: Review Gate (Work Verification)

**STOP.** Present the batch summary:

```
Ready for review:
- [Review] Fix sidebar drag  <-> linked to: Add search filter
- [Review] Add search filter  <-> linked to: Fix sidebar drag
- [Review] Update changelog

Skipped: none
```

**Before asking the user to review, take screenshots of UI/UX changes.** For each ticket that modified views or layout:

```bash
# Build the app (skip if already built this session)
xcodebuild -project macos/Dahso.xcodeproj -scheme DahsoApp -configuration Debug build 2>&1 | tail -3

# Launch if not running
open /Users/maxforsey/Library/Developer/Xcode/DerivedData/Dahso-dgmanoqdbbqekudyzmycpiaxegkk/Build/Products/Debug/Dahso.app
sleep 3

# Navigate to the relevant page/view
osascript -e '
tell application "Dahso" to activate
delay 0.3
tell application "System Events"
    keystroke "k" using command down
    delay 0.5
    keystroke "<page name from smoke test>"
    delay 0.8
    keystroke return
end tell
'
sleep 1.5

# Capture screenshot
WID=$(swift -e 'import Cocoa; let o: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]; guard let wl = CGWindowListCopyWindowInfo(o, kCGNullWindowID) as? [[String: Any]] else { exit(1) }; for w in wl { if (w["kCGWindowOwnerName"] as? String ?? "").contains("Dahso") && (w["kCGWindowLayer"] as? Int ?? -1) == 0 { print(w["kCGWindowNumber"] as? Int ?? 0); break } }')
screencapture -l "$WID" -x /tmp/screenshot-<ticket-id>.png

# View the screenshot inline with the Read tool to verify
```

Present each ticket with its screenshot to the user:
```
### 1. Fix sidebar drag
Screenshot: [viewed inline]
Smoke test: Drag items in sidebar → verify no ghost entries
Status: ✓ Looks correct / ✗ Visual issue found
```

Skip screenshots for CLI-only, model/service, or parser changes.

Wait for the user to verify. They will:
- Move tickets to **Done** (accepted)
- Write feedback directly in the ticket body, then move back to **To Do** (rejected)
- Optionally add new To Do tickets during this time

When they confirm they're done reviewing, proceed to Phase 7.

---

## Phase 7: Revision Loop

Query To Do tickets — this includes rejected tickets and any new ones added during review:

```bash
dahso query "Agent Tickets" --filter "Project=<project_row_id>" --filter "Status=To Do" --body
```

### Structured failure context for retries

For tickets that were previously in Review and sent back, formalize the feedback before re-executing. This prevents agents from repeating the same mistakes.

Read the previous Agent Notes and the user's feedback. Prepend to the Context section:

```
### Iteration Context
**Attempt:** N
**What was tried:** <extracted from previous Agent Notes>
**Why it failed:** <the reviewer's feedback>
**Constraints for next attempt:** <specific, actionable things that must be different>
```

Constraints must be concrete — not "do it better" but "the animation duration must match the existing spring in ContentView:L45."

### Mid-flow ticket quality check

For new tickets created during this flow (not retries), classify them:
- **Quick-tier** (bug fix, small tweak): create with lightweight spec, add to execution queue
- **Feature-tier** (new behavior): draft a spec (Current State, Desired State, Why, Boundaries, Approach) and present for approval before adding to the queue. Don't silently add underspecified feature tickets — this is what causes iteration loops.

Tag mid-flow tickets with `Source=mid-flow`.

Work through all tickets using the same execution flow as Phase 5. When done, loop back to Phase 6.

Repeat until all tickets are Done, or the user says to stop.

---

## Phase 8: Commit

**All merges target `dev`, never `main`.** When creating branches, committing, or merging completed work, the target branch is always `dev`. The `main` branch is protected — only the user promotes `dev` to `main`.

Query Done tickets:

```bash
dahso query "Agent Tickets" --filter "Project=<project_row_id>" --filter "Status=Done"
```

For each Done ticket, check its Linked field. If any linked ticket is **not** Done, flag it:

```
Ticket "Fix sidebar drag" (Done) is linked to "Add search filter" (currently Review).
They share files. Options:
  1. Commit both — I'll mark "Add search filter" Done and include it
  2. Hold both — I'll move "Fix sidebar drag" back to Review
  3. Commit anyway — commit "Fix sidebar drag" independently
```

Wait for the user's decision on each flagged pair before proceeding.

For clean commits: present a summary of all changes, commit, and ask: "There are N To Do tickets remaining. Want to continue, or wrap up?"

---

## Ticket Body Lifecycle

Shows how agent notes and user feedback accumulate over iterations:

```
## Current State
Sidebar items are stored in a flat array...

## Desired State
Items persist throughout drag operations...

## Why
Users are losing sidebar organization when dragging...

## Boundaries
Don't modify the data model. Only touch SidebarView and SidebarViewModel.

## Approach
Add a shadow copy during drag. Use the existing onDrop pattern from DatabaseView.

## Done When
Items persist throughout drag operations

## Smoke Test
1. Drag an item — verify no ghost entries
2. Drop outside sidebar — verify item returns to original position

## Context
Project context: Sidebar Improvements

## Agent Notes 1 (2026-03-10 11:30)
**Root cause:** Drag handler was removing items before drop confirmed.
**What changed:**
- SidebarView.swift:142 — added shadow copy during drag
- SidebarViewModel.swift:88 — added guard against double-fire
**How to verify:** Drag items in sidebar, verify no ghost entries.
**Discoveries:** The onDrop delegate fires twice on macOS 15 — guard needed.
**Build:** PASSING

Doesn't dismiss on Escape. Try checking the event handler.

### Iteration Context
**Attempt:** 2
**What was tried:** Shadow copy + double-fire guard
**Why it failed:** Escape key doesn't dismiss the drag overlay
**Constraints for next attempt:** Check the keyDown event handler in SidebarView for .escape handling

## Agent Notes 2 (2026-03-10 12:15)
**Root cause:** Missing .escape case in keyDown handler.
**What changed:**
- SidebarView.swift:156 — added .escape case to cancel drag
**How to verify:** Drag an item, press Escape, verify overlay dismisses.
**Discoveries:** None.
**Build:** PASSING
```

Agent writes timestamped notes. User just writes their feedback directly below — no label or timestamp needed. The agent's next note creates the chronology.

---

## Key Principles

- **Never mark a ticket Done without explicit user approval.** Move completed tickets to Review status. Only the user moves tickets from Review to Done.
- **Never add unrequested features.** If you notice something worth fixing during execution, create a new ticket for it instead of bundling it into the current work.
- **All merges target `dev`** — never merge to `main`. The user promotes `dev` to `main`.
- **Spec before tickets** — understand what you're building before breaking it into pieces
- **Living context page** — the project spec is a document that grows with discoveries, not a static plan
- **Knowledge loop** — discoveries flow from agents back to the project context page, available to all future agents
- **Structured failure context** — retries include what was tried, why it failed, and what must change
- **Mid-flow quality gate** — new feature tickets created during execution get spec review, not silent execution
- Three human gates: spec grill (2d), plan approval (4), smoke test (6) — each catches a different class of error before it becomes rework
- File linking prevents messy partial commits
- Agent proposes batch size based on complexity rather than using a fixed number
- The flow is a loop, not a straight line — new tickets can arrive at any review gate
- Cache database IDs to avoid repeated lookups
- Project is a relation property, not plain text

---

## CLI Quick Reference

```bash
# List databases
dahso db list

# Get schema
dahso db schema "<db_name_or_id>"

# Create row
echo "<body>" | dahso create "<db>" --set "Key=Value" --body-file -

# Update row properties
dahso update "<db>" <row_id> --set "Key=Value"

# Update row body
echo "<new body>" | dahso update "<db>" <row_id> --body-file -

# Get row with body
dahso get "<db>" <row_id> --body

# Query with filters
dahso query "<db>" --filter "Status=To Do" --filter "Project=<row_id>" --body

# Delete row
dahso delete "<db>" <row_id>

# Page operations
dahso page create "<name>" --content-file -
dahso page update "<name>" --section "X" --create-section --content-file -
dahso page get "<name>" --raw
dahso context "<name>" --depth 2
dahso search "<query>"
```
