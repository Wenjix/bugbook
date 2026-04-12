---
name: ticket
description: Create and execute single bug/feature tickets in Dahso. Use when the user describes a bug, reports an issue, requests a feature, or says "ticket", "create a ticket", "log this", "file a bug". Also use when someone pastes an error, describes unexpected behavior, or asks to fix something specific. This is for single items — use /flow for batch workflows with multiple tickets.
---

# Ticket

Single-ticket creation and optional immediate execution. The atomic unit of work — /flow orchestrates these in batches, /ticket handles one at a time.

For Swift/SwiftUI code changes, use the `swiftui-pro` skill for conventions.

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

On first run, read database IDs from cache. If missing, discover and cache them.

**Cache file:** `~/.dahso/flow-cache.json`

```bash
cat ~/.dahso/flow-cache.json
```

If missing or a call fails:
```bash
dahso db list
```

Find "Agent Tickets", then `mkdir -p ~/.dahso` and write the cache:
```json
{
  "agent_projects": "<db_id>",
  "agent_tickets": "<db_id>"
}
```

---

## Database Schema: Agent Tickets

| Property | Type     | Values                                            |
|----------|----------|---------------------------------------------------|
| Name     | title    | Ticket title                                      |
| Status   | select   | To Do, In Progress, Review, Done                  |
| Project  | relation | Row ID of parent Agent Projects entry (optional)  |
| Priority | select   | High, Medium, Low                                 |
| Files    | text     | Comma-separated file paths                        |
| Linked   | text     | Comma-separated row IDs of tickets sharing files  |
| Source   | text     | How the ticket was created (see Phase 1)          |
| Body     | —        | Spec with sections based on tier                  |

---

## Phase 1: Assess

From the user's description, determine two things: the **ticket content** and the **complexity tier**.

### Extract ticket content:

- **Title** — short, specific (e.g., "Fix sidebar drag losing items", not "Bug fix")
- **Priority** — High (crashes, data loss, blockers), Medium (broken functionality), Low (cosmetic, nice-to-have)
- **Files** — check the codebase to identify affected files. Don't guess. Verify every file path exists in the current repo (`ls` or `glob` it). If the user describes work that requires files from an external project or another repo, don't create the ticket as-is — either scope it to only the current-repo side of the work, or defer it with a note about the external dependency. /go agents can only work within this repo, so tickets referencing outside files will just get skipped.
- **Source** — how this ticket originated: `user` (typed directly), `mid-flow` (created during /flow execution), `mid-go` (created during /go execution), `catchup` (surfaced during /catchup)

### Determine complexity tier:

**Quick** — bug fixes, typos, config changes, single-file tweaks. Signals: "fix", "broken", "wrong", "update", "typo", "rename", touches 1-2 files, the problem and solution are both obvious.

**Feature** — new behavior, meaningful changes, anything where the approach isn't immediately clear. Signals: "add", "build", "create", "redesign", "implement", touches 3+ files, or the user describes desired behavior without specifying how.

**Project** — multi-ticket initiative, large feature, system-level change. Signals: the description implies multiple independent pieces of work, or the user says "project", "epic", "initiative". Escalate to /flow — don't try to cram a project into a single ticket.

The user can override the tier: "just quick-fix this" or "I want to spec this out properly" always wins. If the description is vague, ask one round of clarifying questions before creating. Don't block on perfection — a reasonable assumption with a note is fine.

---

## Phase 2: Spec (Feature tier only)

Quick-tier tickets skip to Phase 3. Project-tier escalates to /flow.

For feature-tier tickets, build a proper spec before creating:

### 2a. Pull context

Check if there's a relevant Dahso project context page:
```bash
dahso search "<relevant project or feature area>"
```

If a project context page exists, read it for prior decisions, discoveries, and constraints:
```bash
dahso context "<ProjectPage>" --depth 2
```

### 2b. Explore the code

Read the files that will be affected. Understand existing patterns, not just file locations. Look for:
- How similar features are implemented in this area
- What conventions the surrounding code follows
- Any constraints or gotchas that aren't obvious from the file list

This exploration takes 30 seconds but prevents the most common failure mode: agents making locally reasonable decisions that conflict with existing patterns.

### 2c. Draft the spec

Write a spec with these sections:

- **Current State** — what exists now, how it behaves. Be specific. An agent reading this with zero prior context should understand the starting point.
- **Desired State** — what should exist after. Describe the behavior, not the implementation.
- **Why** — motivation. This is what lets an agent make judgment calls when the spec doesn't cover every edge case. "We need this because users are losing data when X" leads to different decisions than "we want this for polish."
- **Boundaries** — what NOT to change. Scope creep is the #1 failure mode for agent execution. Be explicit: "Don't modify the data model", "Don't change the navigation structure", "Only touch files in Views/Editor/".
- **Approach** — high-level implementation direction. Not pseudocode, but enough that an agent knows which pattern to follow. "Extend the existing BlockType enum and add a new case to BlockCellView" is the right level.

### 2d. Present for approval

Show the spec to the user. This is the one review gate. For non-trivial feature-tier specs, **invoke the `max:grill-me` skill in freeform mode** against the spec to stress-test scope, assumptions, and boundaries before asking for approval. Skip the grill only when the spec is small and uncontroversial (e.g., a single-file addition with obvious behavior).

**Fallback if `max` plugin is not installed:** do a passive review — show the spec and ask "does this capture what you want?". Note in the terminal that installing `max` from the `max4c/dahso` marketplace would give active grilling with ambiguity scoring.

When grill-me exits (or if skipped), ask for approval. If the user has corrections, update the spec. This gate exists because it's cheaper to fix a spec than to fix code.

---

## Phase 3: Create

### Quick-tier body:

```bash
cat <<'SPEC' | dahso create "Agent Tickets" \
  --set "Name=<Title>" \
  --set "Status=To Do" \
  --set "Priority=<High|Medium|Low>" \
  --set "Files=<comma-separated paths>" \
  --body-file -
## What

<What's wrong or what's needed. For bugs: what's happening vs what should happen.>

## Done When

<Concrete acceptance criteria as a checklist>

## Smoke Test

<Numbered steps the reviewer should follow to verify the fix in the running app.
Be specific — name the exact view, action, and expected result.
Example:
1. Open a database with 3+ view tabs
2. Drag the second tab to the left of the first
3. Verify the tab order updates and a 2px accent indicator shows during drag
4. Close and reopen the database — tab order should persist>

## Context

<One paragraph: why this matters, what area of the app it touches, and anything
the reviewer should keep in mind while testing. If this is a retry, mention what
was tried before and why it didn't work.>
SPEC
```

### Feature-tier body:

```bash
cat <<'SPEC' | dahso create "Agent Tickets" \
  --set "Name=<Title>" \
  --set "Status=To Do" \
  --set "Priority=<High|Medium|Low>" \
  --set "Files=<comma-separated paths>" \
  --body-file -
## Current State

<What exists now — behavior and relevant code patterns, not just file paths.>

## Desired State

<What should exist after — describe the behavior, not the implementation.>

## Why

<Motivation. What problem does this solve? What happens if we don't do this?>

## Boundaries

<What NOT to change. Be explicit about scope limits.>

## Approach

<High-level implementation direction. Which patterns to follow, which files to modify and how.>

## Done When

<Concrete acceptance criteria as a checklist>

## Smoke Test

<Numbered steps to verify in the running app.>

## Context

<Prior decisions, discoveries, or constraints from the project context page.
If this is a retry, include the iteration context (see below).>
SPEC
```

Save the returned row ID.

If there's an active project context, set the Project relation:
```bash
dahso update "Agent Tickets" <row_id> --set "Project=<project_row_id>"
```

Present the created ticket and ask: **fix now or queue for later?**

---

## Phase 4a: Queue (if "later")

Done. The ticket stays as To Do. Report the ticket ID and move on.

---

## Phase 4b: Fix (if "now")

### 1. Set In Progress
```bash
dahso update "Agent Tickets" <row_id> --set "Status=In Progress"
```

### 2. Do the work
- Read all files listed in the ticket's Files field
- For feature-tier: follow the Approach from the spec
- For Swift code: follow `swiftui-pro` conventions
- Implement according to spec and acceptance criteria
- Match existing codebase patterns
- Stay within Boundaries — don't touch what the spec says not to touch
- **Only modify files directly related to this ticket.** If you notice something unrelated that needs fixing, create a new ticket for it — don't scope-creep.
- **Do NOT add features not described in the ticket.** If something would be "nice to have," create a separate ticket instead of building it now.

### 3. Verify
- Run a clean build appropriate to the project (e.g., `xcodebuild` for Swift)
- If the build fails, fix and retry
- If tests exist, run them

### 4. Append Agent Notes
```bash
dahso get "Agent Tickets" <row_id> --body | jq -r '.body // ""' > /tmp/ticket_body.md

cat >> /tmp/ticket_body.md << EOF

## Agent Notes N ($(date "+%Y-%m-%d %H:%M"))

**Root cause:** <One sentence: what was actually wrong or what was missing>

**What changed:**
- <file:line — what was added/modified and why>
- <file:line — ...>

**How to verify:** <Restate the smoke test steps with any adjustments based on what was actually built. If the implementation differs from the spec, explain why.>

**Discoveries:** <Anything unexpected found during implementation that future agents should know. If nothing surprising, write "None." If something was discovered, this also gets written to the Dahso project context page — see Knowledge Loop below.>

**Build:** PASSING / FAILING
**Branch:** <branch name if worktree>
EOF

cat /tmp/ticket_body.md | dahso update "Agent Tickets" <row_id> --body-file -
```

### 5. Knowledge Loop

If the Discoveries field has anything meaningful (not "None"), AND there's a linked project context page in Dahso, append the discovery:

```bash
dahso page update "<ProjectPage>" --section "Discoveries" --create-section --content-file - << EOF

**$(date "+%Y-%m-%d") — <ticket title>:** <what was found> — <implication for future work>
EOF
```

This closes the loop. What this agent learned is now available to every future agent working on this project.

### 6. Set to Review
```bash
dahso update "Agent Tickets" <row_id> --set "Status=Review"
```

**Never mark a ticket as Done.** Only move to Review. The user decides when a ticket is Done after smoke testing.

### 6.5. Post-implementation: Xcode project membership

For Dahso: if you added new `.swift` files, add them to `macos/Dahso.xcodeproj/project.pbxproj` before the build step. The app builds from Xcode, not SPM — `swift build` passes without pbxproj entries but Xcode won't compile ("Cannot find X in scope"). For each new file: add PBXBuildFile + PBXFileReference + PBXGroup child entries matching adjacent files in the same directory. Verify with `grep "YourFileName" macos/Dahso.xcodeproj/project.pbxproj` and validate with `plutil -lint macos/Dahso.xcodeproj/project.pbxproj`. Use `git add -f` if the pbxproj is gitignored.

### 7. Report
Present a summary of changes and verification results. The user can then:
- Mark Done (accepted)
- Write feedback in the ticket body and set back to To Do (rejected — re-run Phase 4b)

---

## Structured Failure Context (for retries)

When a ticket is sent back from Review with feedback, the feedback must be formalized before re-execution. This is what prevents agents from making the same mistake twice.

Before re-running Phase 4b on a previously-attempted ticket, prepend this to the Context section:

```
### Iteration Context
**Attempt:** N
**What was tried:** <extracted from previous Agent Notes>
**Why it failed:** <the reviewer's feedback>
**Constraints for next attempt:** <specific things that must be different>
```

Read the previous Agent Notes to understand what was tried. Read the reviewer's feedback to understand why it failed. Synthesize constraints that are actionable — not "do it better" but "the animation duration must match the existing spring in ContentView:L45."

---

## CLI Quick Reference

```bash
dahso db list                                    # List databases
dahso create "<db>" --set "K=V" --body-file -    # Create row
dahso update "<db>" <id> --set "K=V"             # Update properties
dahso update "<db>" <id> --body-file -           # Update body
dahso get "<db>" <id> --body                     # Get row with body
dahso query "<db>" --filter "K=V" --body         # Query with filters
dahso page update "<page>" --section "X" --create-section --content-file -  # Update page section
dahso context "<page>" --depth 2                 # Read page with linked context
dahso search "<query>"                           # Search across Dahso
```
