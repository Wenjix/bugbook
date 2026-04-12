---
name: prep
description: Pre-/go handoff check. Audits all To Do tickets for agent-readiness and writes machine-verifiable evals for each ticket. Use when the user says "prep", "prepare for go", "get ready for tonight", "am I ready for go", "check my tickets", "end of day", "audit the queue", or signals they're about to step away and want to make sure tickets are solid before autonomous execution. This is the bridge between interactive work and overnight execution.
---

# Prep

Pre-/go handoff. Two jobs: (1) make sure every To Do ticket has a solid spec, and (2) write a machine-verifiable eval for each ticket so /go can verify changes through the actual UI. Run this while you're still at the keyboard so you can fix gaps before walking away.

This is NOT strategic planning. Use /ticket or /flow to create work. Use conversation for direction. Use /prep only when you're about to run /go and want to verify the queue is solid.

---

## Project Filtering

Before querying tickets, detect the current project from the working directory:

- If cwd is inside `/Code/dahso` → **Dahso** project. Exclude Canopy tickets from queries.
- If cwd is inside `/Code/canopy-menu` or `/canopy` → **Canopy** project. Only show Canopy tickets.
- Otherwise → show all tickets (no filter).

Apply the appropriate filter to ALL queries below. Never show tickets from a different project unless explicitly asked.

---

## Phase 1: Review the Queue

Query all To Do tickets for the current project:

```bash
# Dahso context:
dahso query "Agent Tickets" --filter "Status=To Do" --filter "Project!=Canopy" --body

# Canopy context:
dahso query "Agent Tickets" --filter "Status=To Do" --filter "Project=Canopy" --body

# Also check active projects:
dahso query "Agent Projects" --filter "Status=Active"
```

Present a quick summary:
```
Queue: 7 tickets across 2 projects

  UI Polish (4 tickets):
  1. [High] Fix resize line — BlockEditorView.swift
  2. [Medium] Add heading toggles — MarkdownBlockParser.swift, BlockViews.swift
  3. [Medium] Flashcard arrow — FlashcardReviewView.swift
  4. [Low] Update changelog — CHANGELOG.md

  Integrations (3 tickets):
  5. [High] Calendar sync — CalendarService.swift (new)
  6. [Medium] Transcript search — MeetingBlockView.swift
  7. [Low] Export to PDF — ExportManager.swift
```

---

## Phase 2: Audit Each Ticket

For each To Do ticket, check:

### Spec completeness

**Quick-tier tickets** (bug fix, typo, config) need at minimum:
- What (clear problem statement)
- Done When (concrete acceptance criteria)
- Files (verified paths that exist in the repo)

**Feature-tier tickets** (new behavior, meaningful change) need:
- Current State (what exists now)
- Desired State (what should exist after)
- Why (motivation — helps agents make judgment calls)
- Boundaries (what NOT to change)
- Approach (which patterns to follow)
- Done When
- Files

### Scope boundaries

Check that each ticket has clear scope boundaries — which files to modify and which to leave alone. Flag tickets that:
- Are too broad or vague about which files they touch
- Could cause file overlap with other To Do tickets (check the Files field across tickets)
- Touch too many unrelated files — suggest splitting into focused tickets so /go agents don't step on each other

### Blast radius

Classify risk based on files touched:
- **High:** Models/, Core/, shared state, data persistence, navigation
- **Medium:** Views/, ViewModels/, new features, logic changes
- **Low:** assets, styling, copy, config, documentation

### Iteration context

If this ticket was previously attempted and sent back, does it have structured failure context? Check for:
```
### Iteration Context
**Attempt:** N
**What was tried:** ...
**Why it failed:** ...
**Constraints for next attempt:** ...
```

If feedback exists in the ticket body but isn't formalized, formalize it now.

### Dependencies

- Are linked tickets resolved or ordered correctly?
- Does this ticket depend on work that hasn't been done yet?
- Are there external blockers (API keys, OAuth, hardware)?

### Write an eval for each ticket

Every ticket MUST have a concrete, machine-verifiable eval before /go executes it. The eval is what computer-use MCP will execute to verify the change through the actual app UI.

**Eval format:**

```markdown
### Eval
**Type:** visual | interaction | data | cli-only
**Steps:**
1. Open Dahso
2. Navigate to [specific view/page] via [Cmd+K / sidebar click / etc.]
3. Perform [specific action — click, type, scroll]
4. [Additional actions...]
**Pass criteria:**
- [Specific visual check — "X appears at Y position"]
- [Specific behavior — "clicking X does Y"]
- [Specific absence — "no Z is visible"]
**Fail indicators:**
- [What failure looks like — "blank area where X should be"]
- [Common failure modes from iteration context]
```

**Eval types:**

- **visual** — verify something renders correctly. Navigate, screenshot, check.
- **interaction** — verify clicking/typing does the right thing. Perform actions, check results.
- **data** — verify data persistence or transformation. Create data, reload, verify.
- **cli-only** — no UI component. Verify via build/test commands. Skip computer-use.

**Rules for good evals:**

1. Be specific about navigation: "Click 'Ask AI' in the sidebar" not "open the AI view"
2. Be specific about pass criteria: "Green animated bars visible in the pill" not "recording indicator works"
3. Include the negative case: what does failure look like?
4. Reference exact UI elements, not abstractions
5. For iteration tickets (attempt > 1), the eval MUST test the specific failure from the previous attempt
6. Keep evals short — 3-6 steps max. If an eval needs 10+ steps, the ticket might need splitting.

**Example — visual eval:**
```markdown
### Eval
**Type:** visual
**Steps:**
1. Open Dahso
2. Cmd+K → navigate to a page with 5+ bullet points
3. Screenshot the bullet list area
**Pass criteria:**
- Consecutive bullet items have visibly tighter spacing than paragraphs
- Gap between heading and first bullet is tight (items feel grouped)
**Fail indicators:**
- Bullet spacing identical to paragraph spacing
- Heading-to-bullet gap unchanged
```

**Example — interaction eval:**
```markdown
### Eval
**Type:** interaction
**Steps:**
1. Open Dahso, navigate to any page
2. Click into editor, type /callout, select from slash menu
3. Screenshot the inserted callout block
4. Type "Test callout" as the title
5. Click the icon to verify picker appears
**Pass criteria:**
- Callout appears with neutral gray background
- Generic icon visible, title editable
- Icon click shows picker
**Fail indicators:**
- No callout after slash command
- Hardcoded blue border (previous attempt failure)
```

If the ticket already has a Smoke Test section, convert it to eval format. Update the ticket body with the eval.

### Readiness verdict

Score each ticket:
- **Ready** — spec + eval complete, files verified, risk assessed
- **Needs input** — spec has gaps that need human judgment (flag for the user NOW)
- **Needs split** — too broad for one worker, split into 2-3 focused tickets
- **Blocked** — external dependency, skip for /go

---

## Phase 3: Fix Gaps (with the user)

Present findings:

```
Audit results:

Ready (5):
  1. [High] Fix resize line — ready, low risk, eval: visual
  2. [Medium] Flashcard arrow — ready, medium risk, eval: visual
  3. [Low] Update changelog — ready, low risk, eval: cli-only
  4. [Medium] Transcript search — ready, medium risk, eval: interaction
  5. [Low] Export to PDF — ready, medium risk, eval: interaction

Needs input (1):
  6. [High] Calendar sync — missing Approach + no eval yet
     Options: extend EventKit wrapper, or new CalendarService?

Needs split (1):
  7. [Medium] Add heading toggles — touches parser AND renderer AND shortcuts
     Suggest: parser → rendering → shortcuts (3 tickets, 3 evals)

Blocked (0)
```

For "needs input" tickets: invoke the `max:grill-me` skill in ticket mode on the specific ticket. Grill-me reads the ticket body, walks only the audit-flagged gaps (not the whole ticket), produces an ambiguity report (threshold 0.3 for ticket mode), and writes the resolved answers back to the body. After grill-me exits, write the eval.

**Fallback if `max` plugin is not installed:** walk the audit-flagged gaps yourself, asking the user one question at a time, and write the resolved answers back to the ticket body. Note in the terminal that installing `max` from the `max4c/dahso` marketplace would give active grilling with ambiguity scoring.

For "needs split" tickets: split them, write an eval for each sub-ticket.

For "blocked" tickets: note the blocker so /go skips them.

---

## Phase 4: Set Execution Order

/go executes tickets sequentially — the order matters. A good order prevents merge conflicts, builds momentum, and makes verification efficient. A bad order causes conflict cascades and wasted context windows.

### Build the order

Scan every Ready ticket's Files field. Build a file → ticket map:

```
MeetingBlockView.swift → [Wire Transcription, Summary Toggle, Floating Pill, Notes Padding, ...]
BlockCellView.swift → [Callout, Outline, Heading Toggles, Spacing, Wire Table]
TableView.swift → [Grip Dots, Calculations Footer, Table Grouping]
ContentView.swift → [Cmd+K Fix, Ask AI Full Chat]
```

Then apply these ordering rules:

**1. Cluster by shared files.** Tickets touching the same files go back-to-back. Never interleave unrelated tickets between them — each one merges to dev before the next starts, so the next worker sees the prior's changes cleanly. This is the single most important rule.

**2. Foundation before polish.** Within a file cluster, do structural/wiring tickets before visual/polish tickets. "Wire TranscriptionService" before "Reduce notes padding." The structural change establishes the code the polish ticket needs to modify.

**3. Well-spec'd first.** Start with tickets that have clear specs, files, and iteration context. Early tickets that succeed build confidence in the build pipeline and establish patterns for later tickets. Save the vague/exploratory ones for after the known work is done.

**4. Group by repo.** Do all Dahso tickets, then all Canopy tickets (or vice versa). Context switching between repos costs a worktree setup and mental model switch.

**5. Hard tickets after easy ones in the same cluster.** If MeetingBlockView has 5 tickets, put the easy ones (padding fix, 4 lines) before the hard ones (structured AI output, 100 lines). The easy ones merge cleanly and the hard one benefits from seeing all prior changes.

### Present the order

Show the execution queue as a numbered list. The user can reorder before confirming:

```
Execution order for /go (12 tickets):

  MeetingBlockView cluster (5 tickets):
   1. [High] Wire TranscriptionService — foundation
   2. [High] Summary/Notes toggle — structural
   3. [Medium] Notes padding — polish (4 lines)
   4. [Medium] Transcript modal centered — polish
   5. [Medium] Allow notes in finished meeting — polish

  BlockCellView cluster (4 tickets):
   6. [High] Callout block — new block type
   7. [High] Outline/TOC block — new block type
   8. [Medium] Heading toggles — wiring fix
   9. [Medium] Spacing — visual polish

  Independent (3 tickets):
  10. [High] Grip dots — TableView.swift only
  11. [Medium] Ask AI full chat — ContentView.swift
  12. [Low] Style thread picker — AI views only

  Different repo:
  13. [High] Canopy rename — /Users/maxforsey/canopy-menu

  Blocked (skip):
  14. Google OAuth — needs domain registration
```

Ask the user: "Does this order look right? Want to reorder anything?"

After confirmation, persist the order to `.go/queue.json`:

```bash
cat > .go/queue.json << 'EOF'
[
  {"position": 1, "row_id": "row_k02h50", "name": "Wire TranscriptionService", "files": ["MeetingBlockView.swift"]},
  {"position": 2, "row_id": "row_pi3io9", "name": "Summary/Notes toggle", "files": ["MeetingBlockView.swift"]},
  ...
]
EOF
```

/go reads this file and executes in order. No runtime planning needed.

---

## Phase 5: Confirm and Hand Off

After all gaps are filled, evals are written, and execution order is set:

```
Queue is ready. 12 tickets in order:

  Clusters: MeetingBlockView (5) → BlockCellView (4) → Independent (3)
  Evals: 12/12 written (5 visual, 4 interaction, 3 cli-only)
  Blocked: 1 (Google OAuth)

  Execution order saved to .go/queue.json
  /go will execute them in this exact order.

Ready for /go whenever you are.
```

Pull project context pages to verify they're current:

```bash
dahso context "<ProjectPage>" --depth 2
```

Update stale project context now — last chance before agents rely on it overnight.

---

## Key Principles

- This skill exists because auditing at /go time is too late for human input
- Every ticket needs an eval — /go will use computer-use to verify each change
- Don't create tickets here — that's /ticket and /flow
- Don't do strategic planning here — that's conversation
- Do fix specs, write evals, split oversized tickets, formalize iteration context
- Every minute spent here saves 10 minutes of agent iteration overnight
- A good eval is the difference between "build passes" and "feature actually works"

---

## CLI Quick Reference

```bash
dahso query "Agent Tickets" --filter "Status=To Do" --body
dahso query "Agent Projects" --filter "Status=Active"
dahso get "Agent Tickets" <row_id> --body
dahso update "Agent Tickets" <row_id> --body-file -
dahso context "<page>" --depth 2
```
