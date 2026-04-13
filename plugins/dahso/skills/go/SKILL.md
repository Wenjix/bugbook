---
name: go
description: Autonomous long-running execution — works through open tickets while the user is away. Claude orchestrates, writes evals, manages queue/status, and verifies every change. Codex CLI is the default implementation worker; Claude worktree agents are the fallback for complex multi-file work. Runs sequentially by default, with safe two-ticket parallelism only when tickets touch completely different files. Use when the user says "go", "let's go", "night", "goodnight", "do everything", "work on this while I sleep", "run overnight", "keep working", "don't stop", or signals they want autonomous unattended execution.
---

# Go

Work through every open ticket until done or time's up. Claude orchestrates and verifies. Codex implements by default. Claude agents step in when Codex is the wrong tool.

---

## How It Works

```
1. Setup: clean stale worktrees, prep dev branch, load ticket queue
2. Loop:
   a. Pick the next ticket, or a safe pair
   b. Write the eval before any worker starts
   c. Choose worker: Codex first, Claude agent if needed
   d. Dispatch worker(s)
   e. Review results, merge to dev, verify the change
   f. Update ticket status to Review, log progress, continue
3. Report: write the morning summary with outcomes and blockers
```

Sequential is the default. Parallel is allowed only when two tickets have zero file overlap, no dependency relationship, and no shared glue files.

Claude owns verification. Codex never touches Dahso, MCP, or computer-use. Claude agents can use worktrees and skills.

---

## Project Filtering

Before querying tickets, detect the current project from the working directory:

- If cwd is inside `/Code/dahso` → **Dahso** project. Add `--filter "Project!=Canopy"` to all ticket queries.
- If cwd is inside `/Code/canopy-menu` or `/canopy` → **Canopy** project. Add `--filter "Project=Canopy"` to all ticket queries.
- Otherwise → no filter.

Apply this to every `dahso query` command in all phases below.

---

## Setup (run once at start)

### Preflight checks

Run these before anything else. Abort or warn if the environment is unhealthy.

```bash
# Disk space — warn if <10GB free
FREE_GB=$(df -h / | awk 'NR==2 {print $4}' | sed 's/Gi//')
if (( $(echo "$FREE_GB < 10" | bc -l) )); then
  echo "WARNING: Only ${FREE_GB}GB free on /. Consider freeing space before a long run."
fi

# Worktree count — warn if >5 exist
WT_COUNT=$(git worktree list | wc -l | tr -d ' ')
if [ "$WT_COUNT" -gt 5 ]; then
  echo "WARNING: $WT_COUNT git worktrees exist. Cleaning stale ones before proceeding."
fi
```

### Load the friction log

Past runs leave lessons. Before dispatching any worker, read `.go/friction-log.md` if it exists. The file contains short entries describing regressions, unauthorized actions, merge conflicts, and unwired-UI incidents from prior runs. Do not treat it as optional background — the worker prompts below embed recent entries so implementers don't repeat the same mistakes.

```bash
FRICTION_LOG=".go/friction-log.md"
if [ ! -f "$FRICTION_LOG" ]; then
  cat > "$FRICTION_LOG" <<'INIT'
# Friction Log

Append-only record of incidents from /go and /dispatch runs. Each entry: date, ticket, category, what happened, how to avoid.

Categories: regression | unauthorized-action | merge-conflict | unwired-ui | duplicated-logic | scope-creep | other
INIT
fi

# Grab the most recent 20 entries for worker prompts
RECENT_FRICTION=$(tail -200 "$FRICTION_LOG")
```

When an incident occurs later in the run, append to this file (see "Incident logging" in The Loop).

### Clean stale worktrees
```bash
rm -rf .claude/worktrees/agent-*
git worktree prune
```

### Prep dev branch
```bash
git stash push -m "go: auto-stash $(date '+%Y-%m-%d %H:%M')" 2>/dev/null
git checkout dev 2>/dev/null || git checkout -b dev main
git merge main --no-edit 2>/dev/null || true
```

Never commit directly to `main`. All implementation, fixes, and merges land on `dev`.

### Record start time
```bash
mkdir -p .go/screenshots .go/pids
echo "# Go Run — $(date '+%Y-%m-%d')" > .go/progress.md
echo "Started: $(date '+%I:%M %p')" >> .go/progress.md
echo "Time budget: <from user, default 8h>" >> .go/progress.md
```

### Request computer-use access if any UI ticket exists
```
mcp__computer-use__request_access(
  apps: ["Dahso", "Finder"],
  reason: "Verify ticket implementations through the app UI",
  clipboardRead: true, clipboardWrite: true, systemKeyCombos: true
)
```

### Query all tickets
```bash
dahso query "Agent Tickets" --filter "Status=To Do" --body
dahso query "Agent Tickets" --filter "Status=In Progress" --body
```

### Check for prep work

If `.go/queue.json` exists, follow it exactly.

If no queue file exists, do a fast inline prep:
1. Scan each ticket's `Files` field to build a file → ticket map.
2. Cluster tickets by shared files and dependencies.
3. Write short evals for each ticket.
4. Persist evals to ticket bodies.
5. Save execution order to `.go/queue.json`.

### Brief the user and go
Show ticket count, queue order, and whether the run looks sequential-only or has any safe parallel pairs.

---

## The Loop

For each iteration, run these steps:

### 1. Pick the next ticket or safe pair

If `.go/queue.json` exists, pop from that queue. It already encodes dependency order and file clustering.

If no queue file exists, fall back to: High > Medium > Low priority, with shared-file tickets kept adjacent.

**No skipping.** Every ticket gets at least one implementation attempt:
- Too big → split it into smaller tickets, then do the first slice.
- Different repo → dispatch the worker in that repo.
- No files listed → find the files first.
- Repeated failures → read all iteration context and try a different approach.
- Only valid skip: genuine external blocker.

**Parallel check:** only take two tickets at once if all are true:
1. Their listed files do not overlap.
2. Their likely touched files do not overlap.
3. Neither ticket likely touches shared glue such as `Package.swift`, `project.pbxproj`, app navigation registries, shared models, shared design tokens, or generated files.
4. Neither ticket depends on the other's result.

If any doubt remains, stay sequential.

### 2. Write the eval

Write the eval before starting a worker. Persist it to the ticket body.

**UI tickets**
```
Eval type: visual or interaction
Steps: Launch Dahso → navigate from the real entry point to X → do Y → capture screenshot
Pass: [exact visible behavior]
Fail: [missing UI, broken interaction, or screen unreachable from navigation]
```

For new UI, verification must prove the feature is wired into real navigation. A compile-only pass is not enough.

**Backend tickets**
```
Eval type: cli-only
Steps: swift build && swift test
Pass: build succeeds, relevant tests pass
Fail: build error, test failure, or regression
```

**CLI tickets**
```
Eval type: cli-only
Steps: swift build && dahso <command> ...
Pass: expected output
Fail: error or wrong output
```

Persist the eval:
```bash
dahso get "Agent Tickets" <row_id> --body | jq -r '.body // ""' > /tmp/ticket_body.md
cat >> /tmp/ticket_body.md << 'EVAL'

### Eval
<the eval you just wrote>
EVAL
cat /tmp/ticket_body.md | dahso update "Agent Tickets" <row_id> --body-file -
```

### 3. Select the worker

Default to Codex. Escalate to a Claude worktree agent only when Codex is likely to underperform.

**Use Codex when:**
- The ticket has clear files or a bounded search space.
- The change is localized or medium-sized.
- The work is straightforward implementation, refactor, test coverage, or CLI/build work.
- A self-contained prompt can fully describe the task.

**Use a Claude worktree agent when:**
- The ticket needs broad codebase exploration before editing.
- The change spans many files or multiple subsystems.
- The task likely touches shared glue files.
- The task needs deeper multi-file reasoning than a bounded Codex prompt can carry.
- A prior Codex attempt failed for strategy reasons, not just a small bug.

**If running in parallel:**
- Ticket A → Codex
- Ticket B → Claude worktree agent
- Never run two Codex workers at once here.
- Merge sequentially: Codex first, then Claude agent.

### 4. Dispatch the worker

#### Codex worker

Codex gets a fully self-contained prompt. It has no access to the conversation, Dahso, or MCP.

Create the prompt file:
```bash
TASK_ID=<row_id>
WORKING_DIR=<repo-root>
OUTPUT_FILE="/tmp/codex-output-$TASK_ID.md"
PROMPT_FILE="/tmp/codex-prompt-$TASK_ID.md"

cat > "$PROMPT_FILE" <<'PROMPT'
You are implementing a single ticket autonomously. Do not ask questions. Work only in this repository checkout.

## Constraints
- You do not have access to Dahso, MCP, or computer-use.
- Never commit to `main`.
- Keep changes scoped to this ticket.

## Ticket
Title: <ticket title>

Body:
<full ticket body>

Eval:
<full eval>

Iteration context:
<prior attempts, failures, and reviewer notes>

## Files to read first
- <exact file paths>

## Files you may modify
- <exact file paths>
- <new files if needed>

## Codebase expectations
- Read the relevant files before editing.
- Match surrounding patterns, naming, and structure.
- If you create a new `.swift` file, check whether `macos/Dahso.xcodeproj/project.pbxproj` must be updated. If you are unsure, say so explicitly.
- Build with `swift build 2>&1 | tail -20` and fix issues. Retry up to 3 times.
- Run any obvious targeted tests or CLI commands for touched code.
- Self-review before finishing: simplify the implementation, remove dead code, check edge cases, unused imports, regressions, and whether the code appears wired correctly.

## Output format
1. Summary
2. Files changed
3. Build/test result
4. Remaining risks
5. Eval prediction
PROMPT
```

Run Codex:
```bash
codex exec --full-auto -C "$WORKING_DIR" -o "$OUTPUT_FILE" "$(cat "$PROMPT_FILE")"
```

Codex runs in the main repo checkout on `dev`, not in a worktree.

Optional model override:
```bash
codex exec --full-auto -m o3 -C "$WORKING_DIR" -o "$OUTPUT_FILE" "$(cat "$PROMPT_FILE")"
```

For safe parallel execution, launch via Bash with `run_in_background: true`.

#### Claude worktree agent

Use a worktree agent for complex tickets or the secondary parallel slot.

```
Agent(
  description: "Implement: <ticket title>",
  isolation: "worktree",
  mode: "bypassPermissions",
  prompt: <see below>
)
```

**Claude worker prompt:**

```
You are implementing a single ticket autonomously. Do not ask questions.

## Ticket
<full ticket body including eval and iteration context>

## Files
<exact file paths; if missing, explore the codebase first>

## Instructions
1. Read all relevant files before writing code. Understand existing patterns.
2. Implement the change. Keep it scoped.
3. If creating new `.swift` files, update `macos/Dahso.xcodeproj/project.pbxproj` if needed.
4. Build with `swift build 2>&1 | tail -20` and fix issues, retrying up to 3 times.
5. Invoke the `simplify` skill via the Skill tool after code changes.
6. Invoke the `feature-dev:code-reviewer` agent via the Agent tool before returning to catch bugs, logic errors, and security issues.
7. Report: what you changed, assumptions, build status, and eval prediction.
```

For safe parallel execution, launch the agent in the background.

### 5. Process the result

When a worker completes, inspect the output before merging anything.

**For Codex:**
1. Read `/tmp/codex-output-<row_id>.md`.
2. Check the diff on the working tree.
3. Review the changed files yourself before merge.
4. Confirm any new `.swift` file is reflected in `project.pbxproj` if required.

**For Claude agents:**
1. Read the worker report.
2. Check the diff in the worktree.
3. Review the changed files yourself before merge.

**Check changes exist:**
```bash
git diff --stat
```
If empty, note `no changes produced`, append iteration context, and move on or redispatch.

**If running sequentially:**
- Codex ticket: commit directly on `dev` after review.
- Claude ticket: commit in the worktree branch, then merge that branch into `dev`.

**If running in parallel:**
- Wait for both workers.
- Review both results.
- Commit Codex changes on `dev` first.
- Rebase or reconcile the Claude worktree if needed.
- Merge the Claude agent second.

**Claude post-Codex review is mandatory:**
1. Read the Codex output file.
2. Inspect `git diff` for the exact changes.
3. Do a quick code review for correctness, style, and integration.
4. Run the build check.
5. Run the eval.
6. If issues are small, fix directly on `dev`.
7. If issues need another implementation pass, re-dispatch with explicit iteration context.

### 5a. Reviewer pass (mandatory before verification)

After the inline review and build pass, spawn an independent reviewer subagent. The reviewer has not seen the implementation conversation and reads only the diff + ticket + friction log. Its job is to catch the specific failure modes the inline review tends to miss.

```
Agent(
  description: "Review diff for ticket <row_id>",
  subagent_type: "feature-dev:code-reviewer",
  prompt: <reviewer prompt below>,
  mode: "default"
)
```

**Reviewer prompt:**

```
You are reviewing an autonomous ticket implementation. You have not seen the conversation that produced it — only the inputs below.

## Ticket
<full ticket body, including eval>

## Diff
<output of git diff dev..HEAD or git diff on the worktree>

## Recent friction patterns (do not repeat)
<paste the most recent 10 entries from .go/friction-log.md>

## Check for these specifically
1. Regression — does this break any existing behavior the diff doesn't mean to touch?
2. Duplicated logic — is there similar code elsewhere in the repo that this should have reused or replaced?
3. Unwired code paths — for UI work, is the new view actually reachable from real navigation (sidebar, toolbar, command palette, shortcut)?
4. Scope creep — does the diff change anything the ticket did not ask for? A UI polish beyond what was specified, a "while I'm here" refactor, an unrequested new feature — all count.
5. Unauthorized status transitions — does the diff include a ticket status change to "Done"? Only the user does that.
6. Hand-edits to generated files — project.pbxproj, generated resources, Package.resolved — these belong in their generating tool.

## Output
Return a review with exactly these sections, even if empty:
- REGRESSIONS: <list or "none">
- DUPLICATED LOGIC: <list or "none">
- UNWIRED UI: <list or "none, or N/A for backend">
- SCOPE CREEP: <list or "none">
- UNAUTHORIZED ACTIONS: <list or "none">
- OTHER CONCERNS: <list or "none">
- VERDICT: pass | fail | fix-inline
```

On `pass` → continue to Verification.
On `fix-inline` → apply the small fix directly, re-run the build, re-run the reviewer.
On `fail` → revert the change, append a friction-log entry with the reviewer's verdict, and either re-dispatch with the reviewer notes as iteration context or mark the ticket blocked.

**Codex commit on `dev`:**
```bash
git checkout dev
git add -A
git commit -m "<ticket title>"
```

**Claude worktree commit and merge to `dev`:**
```bash
git add -A
git commit -m "<ticket title>"
git checkout dev
git merge <worker-branch> --no-edit
```

All agent work merges to `dev`, never directly to `main`. If a worker accidentally commits to `main`, revert it immediately and cherry-pick onto `dev`.

**Self-healing build verification:**

After merging each ticket's changes, run `xcodebuild` to verify the build. If it fails, retry up to 3 times with the error context. If still failing after 3 attempts, revert all changes for that ticket, mark it as blocked, and move on.

```bash
BUILD_ATTEMPTS=0
BUILD_OK=false
while [ "$BUILD_ATTEMPTS" -lt 3 ] && [ "$BUILD_OK" = false ]; do
  BUILD_ATTEMPTS=$((BUILD_ATTEMPTS + 1))
  echo "Build attempt $BUILD_ATTEMPTS/3..."
  BUILD_OUTPUT=$(xcodebuild -quiet 2>&1 | tail -40)
  if [ $? -eq 0 ]; then
    BUILD_OK=true
  else
    echo "Build failed (attempt $BUILD_ATTEMPTS). Error:"
    echo "$BUILD_OUTPUT"
    # Diagnose and fix the error using the output as context before retrying
  fi
done

if [ "$BUILD_OK" = false ]; then
  echo "Build failed after 3 attempts. Reverting changes for this ticket."
  git revert HEAD --no-edit  # revert the merge/commit
  # Mark ticket as blocked with error details
  dahso update "Agent Tickets" <row_id> --set "Status=Review"
  dahso get "Agent Tickets" <row_id> --body | jq -r '.body // ""' > /tmp/ticket_body.md
  cat >> /tmp/ticket_body.md << BLOCKED

## Blocked — Build Failure (<date>)
Build failed after 3 attempts. Last error:
\`\`\`
$BUILD_OUTPUT
\`\`\`
BLOCKED
  cat /tmp/ticket_body.md | dahso update "Agent Tickets" <row_id> --body-file -
  # Move to next ticket
fi
```

If the build failure is small and obvious (e.g., missing import), fix it directly on `dev` during the retry loop rather than burning an attempt.

### 6. Verify the change (hard gate)

Verification is a gate, not a step. No ticket moves to `Status=Review` without a passing verification. If verification fails and cannot be fixed in ≤3 attempts, the ticket reverts and stays as `To Do` with an iteration-context note — it does not advance.

Verification depth must match the change.

**UI tickets**

Use computer-use. For any new screen, control, or flow, verify real navigation wiring from an existing entry point.

```
1. pkill -f "debug/Dahso" || true
2. swift build
3. .build/arm64-apple-macosx/debug/Dahso &
4. sleep 3
5. Navigate from the real entry point: sidebar, toolbar, menu, shortcut, or command palette
6. Execute the eval steps
7. Capture screenshot
8. Confirm the pass criteria exactly
```

Do not mark PASS if the view exists in code but cannot be reached in the app.

**Backend and CLI tickets**
```bash
swift build 2>&1 | tail -20
swift test 2>&1 | tail -20
# Or run the exact CLI commands from the eval
```

**Pass / fail**
- PASS → continue to step 7. Move ticket to `Review` status only. Never mark a ticket as Done without explicit user approval.
- FAIL → append iteration context and error details, log a friction entry (see below), then either fix directly or redispatch. Ticket stays `To Do`, not `Review`.
- Max 3 total attempts per ticket. After 3 failures, revert all changes for that ticket, mark it as blocked (set `Status=Review` with error details in the body), log the friction incident, and move to the next ticket.

**Incident logging (on any failure above):**

Any of these events gets appended to `.go/friction-log.md` immediately, before moving on:
- Build failure not fixable in 3 attempts
- Eval failure (UI or CLI)
- Reviewer verdict of `fail`
- Merge conflict (let /dispatch's merge protocol handle cleanup, but log it)
- Any unauthorized action the reviewer flagged

Format:
```bash
cat >> .go/friction-log.md <<ENTRY

## $(date '+%Y-%m-%d %H:%M') — <ticket title>
**Category:** <regression | unauthorized-action | merge-conflict | unwired-ui | duplicated-logic | scope-creep | other>
**What happened:** <one sentence>
**Root cause:** <one sentence>
**How to avoid:** <one actionable rule for future runs>
ENTRY
```

Keep entries terse. The log should stay readable at 200 entries — if it grows too big, the oldest entries stop fitting in worker prompts.

### 7. Update status and log

Never mark a ticket as Done without explicit user approval. Move completed tickets to Review status only.

```bash
dahso update "Agent Tickets" <row_id> --set "Status=Review"
```

Append notes to the ticket body:
```bash
dahso get "Agent Tickets" <row_id> --body | jq -r '.body // ""' > /tmp/ticket_body.md
cat >> /tmp/ticket_body.md << 'NOTES'

## Agent Notes (<date>)
**Worker:** <Codex or Claude agent>
**What changed:** <files and summary>
**Eval result:** PASS or FAIL (attempt N)
**Screenshot:** <path or "N/A — cli-only">
**Build:** PASSING or FAILING
**Follow-up:** <remaining risks or "none">
NOTES
cat /tmp/ticket_body.md | dahso update "Agent Tickets" <row_id> --body-file -
```

Append to `.go/progress.md` and clean up any Claude worktree:
```bash
git worktree remove <worktree-path> --force 2>/dev/null || true
git worktree prune
```

### 8. Continue or stop

Check whether work remains:
```bash
dahso query "Agent Tickets" --filter "Status=To Do" | jq '.total_count'
```

- More tickets remain → go back to step 1.
- No `To Do` tickets but time remains → retry `Blocked`, split large tickets, or inspect related repos.
- Time budget exhausted or genuinely nothing remains → go to Report.

---

## Report

Write `.go/progress.md` with:

```markdown
# Go Run — <date>

Started: <time>
Finished: <time>
Duration: <elapsed>
Time utilization: <elapsed>/<budget> (<percent>)

## Completed (<N> tickets, all verified)
- [x] <ticket> — <worker> — PASS (<screenshot path or "cli-only">)
- [x] <ticket> — <worker> — PASS (2 attempts, <screenshot>)

## Review Queue (<N> tickets)
- <ticket> — moved to Review after verification

## Blocked (<N> tickets, each attempted)
- <ticket> — 3 attempts failed. <what was tried, why it failed>

## Discoveries
- <anything learned about the codebase, navigation wiring, build quirks, or project file updates>

## How to Review
git checkout dev
swift build && .build/arm64-apple-macosx/debug/Dahso
```

Print a concise summary to the conversation showing completed/blocked/failed counts:
```
Completed: N | Blocked: N | Failed (reverted): N
```

---

## Rules

1. **Never stop to ask.** Make assumptions, record them, keep moving.
2. **Never touch `main`.** All work lands on `dev`.
3. **Clean stale worktrees first.** Start every run with the cleanup commands.
4. **Load the friction log before dispatching.** Past incidents go into worker prompts so they don't repeat.
5. **No eval, no worker.** Write the eval before dispatch.
6. **Codex first.** Use Claude agents only when the worker-selection rules say Codex is the wrong tool.
7. **Parallel is optional, not default.** Only run two tickets when file separation is truly clean. For wider parallelism, use `/dispatch`.
8. **Claude verifies everything.** Codex never self-verifies via MCP or Dahso.
9. **Independent reviewer before verify.** A fresh-context reviewer subagent must pass the diff before verification runs.
10. **Verification is a hard gate.** No `Status=Review` transition without a green build + passing eval.
11. **UI must be navigable.** New UI is not done until it is reachable from real app navigation.
12. **Never auto-close.** Never mark a ticket as Done without explicit user approval. Move completed tickets to Review status only.
13. **Every failure logs friction.** Append an entry to `.go/friction-log.md` before moving on.
14. **Try everything.** No skipping without a real external blocker.
15. **Keep going.** Re-query after each ticket until the queue or time budget is exhausted.

---

## CLI Quick Reference

```bash
# Dahso
dahso query "Agent Tickets" --filter "Status=To Do" --body
dahso query "Agent Tickets" --filter "Status=In Progress" --body
dahso get "Agent Tickets" <row_id> --body
dahso update "Agent Tickets" <row_id> --set "Status=Review"
echo "<body>" | dahso update "Agent Tickets" <row_id> --body-file -

# Codex
codex exec --full-auto -C "$WORKING_DIR" -o "/tmp/codex-output-$TASK_ID.md" "$(cat "$PROMPT_FILE")"
codex exec --full-auto -m o3 -C "$WORKING_DIR" -o "/tmp/codex-output-$TASK_ID.md" "$(cat "$PROMPT_FILE")"

# Git
git worktree prune
git checkout dev
git merge <branch> --no-edit
git diff --stat

# Build
swift build 2>&1 | tail -20
swift test 2>&1 | tail -20
xcodebuild -quiet 2>&1 | tail -40  # self-healing verification (retry up to 3x)
```
