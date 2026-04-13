---
name: catchup
description: Start-of-session orientation and review. Gets you up to speed on the project — reviews /go run results if there are any, shows what's in flight, what's blocked, and what happened since you last looked. Surfaces overnight discoveries from the knowledge loop. Writes a visual Session Brief page to Dahso so you can review in the app. Use when the user says "catchup", "catch up", "what happened", "where are we", "what's the status", "bring me up to speed", "what did I miss", "morning review", "show me what you did", "what happened overnight", or starts a new session and wants to get oriented. Works with or without a prior /go run — it's the universal "start of session" skill.
---

# Catchup

Start-of-session orientation. Bring the user up to speed by writing a **Session Brief** page in Dahso. The user reads the brief in the app — visual, structured, with embedded database views they can click into.

The terminal gets a short summary. Dahso gets the real content.

---

## Project Filtering

Before querying tickets, detect the current project from the working directory:
- `/Code/dahso` → add `--filter "Project!=Canopy"` to all ticket queries
- `/Code/canopy-menu` or `/canopy` → add `--filter "Project=Canopy"` to all ticket queries
- Otherwise → no filter

Apply this to every `dahso query` command below.

---

## Output: Session Brief Page

Every /catchup creates or updates a page called **"Session Brief"** in the Dahso workspace. Use section-level updates so each run refreshes the content without losing structure.

```bash
# Create the page if it doesn't exist, or update if it does
dahso page create "Session Brief" --title "Session Brief" --content-file - <<< ""
# (If it already exists, this is a no-op — just proceed to section updates)
```

The page has these sections, each updated independently:

```markdown
<!-- icon:sf:sunrise -->
# Session Brief

## Local Changes
<uncommitted files, staged changes, stashes>

## Overnight Results
<only if /go ran — summary + link to worktree branches>

## Discoveries
<knowledge loop — what agents learned overnight>

## Project Snapshot
<ticket counts by status, recent commits, active projects>

## Tickets in Review
<embedded database view — Agent Tickets filtered to Review>

## What Needs Attention
<stale tickets, blockers, thin backlog>

## Suggested Next Steps
<what to focus on — links to /flow, /ticket, /go>
```

---

## Phase 1: Gather State

Collect everything in parallel before writing:

### Local changes
```bash
git status --short
git diff --stat
git stash list
```

### /go results
```bash
cat .go/progress.md 2>/dev/null
git worktree list
```

### Regression check
If /go ran, review git diffs for each completed ticket branch against main. Look for:
- Files modified that aren't in the ticket's Files field (scope creep)
- Unintended deletions or changes to unrelated code
- Any tickets that were moved to Done without user approval (they should only be in Review)

```bash
# For each worktree branch:
git diff --stat main...<branch-name>
# Compare against the ticket's Files field — flag mismatches
```

### Ticket counts
```bash
dahso query "Agent Tickets" --filter "Status=Review"
dahso query "Agent Tickets" --filter "Status=In Progress"
dahso query "Agent Tickets" --filter "Status=To Do"
dahso query "Agent Tickets" --filter "Status=Done"
```

### Recent activity
```bash
git log --oneline -10
```

### Active projects
```bash
dahso query "Agent Projects" --filter "Status=Active"
```

### Knowledge loop — overnight discoveries
```bash
# Check each active project's context page for recent discoveries
# Read the Discoveries section of each project context page
```

For each active project, read its Dahso context page and look for discoveries dated since the last session:

```bash
dahso context "<ProjectPage>" --depth 2
```

Extract any entries in the Discoveries section that are new since the last /catchup run. These are things agents learned during overnight execution that the user hasn't seen yet.

---

## Phase 2: Write the Session Brief

Build the page content and write it to Dahso. Use `--section` with `--create-section` to update each section independently.

### Local Changes section

```bash
cat <<'CONTENT' | dahso page update "Session Brief" --section "Local Changes" --create-section --content-file -
<based on git status output>

If uncommitted changes exist:
  **3 files modified** (uncommitted):
  - `Sources/Dahso/Views/Editor/BlockTextView.swift` (+42, -8)
  - `Sources/Dahso/Lib/AttributedStringConverter.swift` (+31, -2)
  - `Sources/Dahso/Views/Editor/FlashcardReviewView.swift` (+18, -3)

  Looks like flashcard arrow + reverse card work from last session.

If clean:
  Working tree is clean. No uncommitted changes.
CONTENT
```

### Overnight Results section (only if /go ran)

```bash
cat <<'CONTENT' | dahso page update "Session Brief" --section "Overnight Results" --create-section --content-file -
/go completed — **9/12 tickets done**, 2 blocked, 1 skipped.

Each completed ticket is on its own worktree branch:

| Ticket | Branch | Risk | Status |
|--------|--------|------|--------|
| Fix loading spinner | `worktree/fix-spinner` | Low | Ready for review |
| Inline flashcard polish | `worktree/flashcard-polish` | Medium | Ready for review |
| Heading toggles | `worktree/heading-toggles` | High (full review) | Ready for review |
| ... | ... | ... | ... |

**Blocked:**
- Google Calendar sync — needs OAuth2 credentials
- Sidebar drag — layout regression after 3 attempts

Review each ticket below, or walk through them in the terminal with accept/iterate/reject.
CONTENT
```

If no /go ran, write:
```
No /go run to review. Starting fresh.
```

### Discoveries section (knowledge loop)

This is what agents learned overnight. Surface it prominently — these insights affect today's work.

```bash
cat <<'CONTENT' | dahso page update "Session Brief" --section "Discoveries" --create-section --content-file -
**3 discoveries** from overnight execution:

- **Heading toggles:** onDrop delegate fires twice on macOS 15 — guard needed in all drag handlers. *Implication: any ticket touching drag behavior needs this guard.*
- **Calendar sync:** NSCalendar API requires explicit permission prompt on first access. *Implication: need to add permission request flow before Calendar features work.*
- **Flashcard polish:** existing animation springs use 0.35s response — new animations should match. *Implication: use 0.35s as the standard spring response time across the app.*

These have been written to each project's context page in Dahso. Future agents will see them automatically.
CONTENT
```

If no discoveries, write:
```
No new discoveries from overnight execution.
```

If no /go ran:
```
No overnight run — no new discoveries. Check project context pages for historical discoveries.
```

### Project Snapshot section

```bash
cat <<'CONTENT' | dahso page update "Session Brief" --section "Project Snapshot" --create-section --content-file -
| Status | Count |
|--------|-------|
| Done (this week) | 8 |
| In Review | 6 |
| In Progress | 1 |
| To Do | 2 |
| Blocked | 1 |

**Active projects:** UI Polish, Integrations, Editor

**Last commit:** `<short hash>` — "<message>" (<time ago>)

**Momentum:** Editor work moving fast (8 tickets this week). Integrations stalled (Calendar blocked 3 days).
CONTENT
```

### Tickets in Review section

This is the most important section — it's the user's review checklist. They need to know what to test, how to test it, and whether the code is already on dev or still on branches.

First, check if branches have been merged to dev (Phase 4.5 of /go does this):
```bash
git worktree list | grep "\.claude/worktrees" | wc -l
git log --oneline -20  # look for merge commits from worktree branches
```

Then query each Review ticket with `--body` to extract the smoke test steps from Agent Notes.

Write the section as an actionable numbered checklist with inline smoke tests:

```bash
cat <<'CONTENT' | dahso page update "Session Brief" --section "Tickets in Review" --create-section --content-file -
**8 tickets** ready for smoke testing.

**Status:** All branches merged to dev (or: "Branches NOT merged — run /catchup merge to consolidate")

**To test:** `git checkout dev` → Open Xcode → `macos/Dahso.xcodeproj` → Cmd+R to build and run.
Then work through this checklist:

### 1. [High] Fix resize line stuck after column resize
**Test:** Open a database table → resize a column by dragging the border → release → the accent line should disappear immediately. Try multiple resizes.

### 2. [High] Multi-node canvas drag
**Test:** Open a canvas → shift-click 3 shapes to select them → drag one → all 3 should move together maintaining relative positions. Single drag should still work normally.

### 3. [Medium] Kanban sub-grouping
**Test:** Open Agent Tickets in Kanban → look for "Sub-group by" dropdown next to "Group by" → select Project → cards should cluster under collapsible project headers with count badges → collapse/expand → drag between sub-groups.

...etc for each ticket, pulling smoke test steps from the ticket body's Agent Notes.

Mark each ticket Done in Dahso after testing, or write feedback and set back to To Do.
CONTENT
```

If branches are NOT on the `dev` branch yet, offer to consolidate:
```
Branches aren't consolidated yet — you need them on the `dev` branch to test from Xcode.
Want me to merge all Review branches to `dev` so you can build and test?
```

If the user says yes, merge worktree branches into dev:
```bash
git checkout dev
git merge main --no-edit  # pick up any new main commits
for branch in $(git worktree list | grep "\.claude/worktrees" | awk '{print $3}' | tr -d '[]'); do
  git merge "$branch" --no-edit
done
swift build 2>&1 | tail -5
swift test 2>&1 | tail -20
git checkout main
```

Embed the Agent Tickets database so the user can also browse in Dahso:

```bash
dahso page embed-database "Session Brief" "Agent Tickets"
```

Note: Only embed once — if the database is already embedded, skip this step.

### What Needs Attention section

Check for and flag these issues:
- Tickets moved to Done without user approval (should only be Review after /go)
- Stale worktrees that need cleanup (branches already merged or tickets rejected)
- Regressions found in the diff review (files changed outside ticket scope)

```bash
# Check for tickets incorrectly set to Done
dahso query "Agent Tickets" --filter "Status=Done"
# Cross-reference with user's last accepted set — flag any new Done tickets

# Check for stale worktrees
git worktree list | grep "\.claude/worktrees"
# Flag worktrees whose tickets are already Done or rejected
```

```bash
cat <<'CONTENT' | dahso page update "Session Brief" --section "What Needs Attention" --create-section --content-file -
- **6 tickets in Review** — need acceptance or feedback
- **Google Calendar** has been blocked for 3 days — unblock or deprioritize?
- **To Do queue is thin** (2 tickets) — might need to plan next work
- **1 stale In Progress ticket** — flashcard block, leftover from 2 sessions ago
- **Discovery action needed** — onDrop double-fire guard should be applied to all drag handlers (see Discoveries above)
- **Stale worktrees:** <list any that need cleanup>
- **Unauthorized Done tickets:** <list any moved to Done without approval>
- **Scope drift:** <list any tickets where diffs touched files outside the ticket's Files field>
CONTENT
```

### Suggested Next Steps section

```bash
cat <<'CONTENT' | dahso page update "Session Brief" --section "Suggested Next Steps" --create-section --content-file -
Based on current state:

- **Review overnight work** — 6 tickets in Review need acceptance or feedback
- **Act on discoveries** — check if onDrop guard needs to be applied to other views
- **Start /flow** — pick up iteration tickets or work on new features
- **Create tickets with /ticket** — backlog is thin, add work for the next /go run
- **Run /go tonight** — once tickets are queued and specs are solid
CONTENT
```

---

## Phase 3: Terminal Summary

After writing the page, print a brief summary to the terminal. This should be actionable — tell the user exactly what to do next:

```
Session Brief updated in Dahso.

Quick status:
  Overnight: 8/10 tickets done, 2 skipped
  Discoveries: 3 new (written to project context pages)
  Review queue: 8 tickets ready to smoke test
  Merged to dev: ✓ (all branches consolidated)
  To Do: 3 tickets remaining

To test: git checkout dev → Open Xcode → Cmd+R
Smoke test checklist is in the Session Brief page in Dahso.

Walk through reviews here, or test from Xcode and mark tickets Done in Dahso?
```

If branches are NOT on the dev branch yet:
```
Worktree branches aren't consolidated yet.
Want me to merge them to the `dev` branch so you can build from Xcode?
  git checkout dev → open Xcode → Cmd+R
```

If the user says yes, merge into dev, run tests, and verify the build.

After the user finishes testing and accepts:
```
To land accepted work on main:
  git checkout main && git merge dev
```

---

## Phase 4: Interactive Review (if /go results exist)

If the user wants to review branches in the terminal (rather than just in Dahso), walk through each one:

**1. Show context:**
```
[1/9] Fix loading spinner
Priority: High | Risk: Low | Branch: worktree/fix-spinner
```

**2. Show the diff:**
```bash
git diff --stat main...<branch-name>
```

**3. Show the smoke test** from the ticket body.

**4. Wait for decision:**

- **Accept** — Merge to dev, clean up worktree, set Done
  ```bash
  git checkout dev && git merge <branch-name> --no-edit && git checkout main
  git worktree remove <worktree-path>
  dahso update "Agent Tickets" <row_id> --set "Status=Done"
  ```

- **Iterate** — Keep branch, formalize feedback as structured failure context
  ```bash
  dahso get "Agent Tickets" <row_id> --body | jq -r '.body // ""' > /tmp/ticket_body.md
  cat >> /tmp/ticket_body.md << EOF

  ### Iteration Context
  **Attempt:** N
  **What was tried:** <extracted from Agent Notes>
  **Why it failed:** <user's feedback>
  **Constraints for next attempt:** <specific, actionable>
  EOF
  cat /tmp/ticket_body.md | dahso update "Agent Tickets" <row_id> --body-file -
  dahso update "Agent Tickets" <row_id> --set "Status=To Do"
  ```

- **Reject** — Discard branch, set ticket back to To Do
  ```bash
  git worktree remove --force <worktree-path>
  git branch -D <branch-name>
  dahso update "Agent Tickets" <row_id> --set "Status=To Do"
  ```

After each decision, update the Session Brief's "Overnight Results" section with the outcome.

**5. Next ticket.** Repeat until done.

### Integration Check

After merging accepted tickets to dev:
```bash
git checkout dev
swift build 2>&1 | tail -20
git checkout main
```

---

## Phase 5: Knowledge Capture

At the end of the catchup session, scan the conversation for any decisions, corrections, or new context that should be persisted:

- Did the user make a decision about priorities or direction? Update the relevant project context page.
- Did the user correct an assumption from overnight work? Update the project context page's Constraints section.
- Did reviewing the work reveal something about how the codebase should work? Add to the project context page's Discoveries section.

This ensures that what the user communicated during review is available to the next agent session, not trapped in this conversation's context.

```bash
dahso page update "<ProjectPage>" --section "Discoveries" --create-section --content-file - << EOF

**$(date "+%Y-%m-%d") — catchup review:** <what was learned during review>
EOF
```

---

## Navigation Commands

During terminal walkthrough:
- **"next"** / **"skip"** — move to next ticket
- **"list"** — show all tickets with review status
- **"accept all"** — merge all remaining to dev
- **"show diff"** — full diff for current ticket
- **"show ticket"** — full Dahso ticket body
- **"build"** — build check in current worktree

---

## Workspace Note

All dahso commands need the workspace flag for Dahso 2:
```bash
WS="$HOME/Library/Mobile Documents/iCloud~com~dahso~app/Documents/Dahso 2"
dahso --workspace "$WS" <command>
```

---

## CLI Quick Reference

```bash
# Dahso pages
dahso page create "Session Brief" --content-file -
dahso page update "Session Brief" --section "<heading>" --create-section --content-file -
dahso page get "Session Brief" --raw
dahso page embed-database "Session Brief" "Agent Tickets"
dahso context "<page>" --depth 2

# Git
git status --short
git diff --stat
git worktree list
git log --oneline -10

# Ticket operations
dahso query "Agent Tickets" --filter "Status=Review"
dahso update "Agent Tickets" <row_id> --set "Status=Done"
```
