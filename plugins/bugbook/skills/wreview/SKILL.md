---
name: wreview
description: Weekly OODA review that pre-fills a Bugbook page from all data sources (tickets, git, email, calendar, messages, reminders, insights, memory), then walks through personal sections interactively, then writes back tickets and memory updates. Use when the user says "wreview", "weekly review", "week review", "review my week", "how did my week go", "Sunday review", "Monday review", or wants to reflect on and plan around their week. Also trigger when it's been 7+ days since the last review page in Bugbook.
---

# Weekly Review (/wreview)

Two-phase OODA review. Phase 1: Claude pre-fills everything it can. Phase 2: interactive walk-through of personal sections. Phase 3: write-back.

Each review is a row in the **Weekly Reviews** database under Max Flow in Gateway 8.0. The row body contains the full OODA review.

---

## Workspace

The active Bugbook workspace is **Bugbook 2** in iCloud. All `bugbook` commands need the workspace flag:

```bash
WS="$HOME/Library/Mobile Documents/iCloud~com~bugbook~app/Documents/Bugbook 2"
bugbook query "Agent Tickets" --workspace "$WS"
```

Set `WS` once at the start of the session and use it everywhere. The symlink at `~/Documents/Bugbook/` points to a different (older) workspace — do not use the default.

---

## Before You Start

**Recommend running /inbox-zero first** so the inbox is clean before reviewing. The review reads email state but should not triage emails mid-review — it breaks the reflective flow.

Verify databases exist. If Max Tickets or Weekly Reviews is missing, read `references/databases.md` and create it.

```bash
bugbook db schema "Agent Tickets" --workspace "$WS" 2>/dev/null
bugbook db schema "Max Tickets" --workspace "$WS" 2>/dev/null
bugbook db schema "Weekly Reviews" --workspace "$WS" 2>/dev/null
```

Check for the previous week's review to compare against:
```bash
bugbook query "Weekly Reviews" --workspace "$WS" 2>/dev/null
```

---

## Phase 1: Pre-Fill (no interaction)

Claude gathers from all sources, creates the review page, and fills in everything it can. Do not ask Max anything during this phase.

### 1a. Gather

Read `references/gather.md` for the full list of data source queries. Run all source queries in parallel. Sources:

- Agent Tickets (done, review, in progress, to do)
- Max Tickets (done, in progress, to do)
- Git activity (commits, PRs across repos — last 7 days)
- Gmail (inbox, sent mail for commitments, starred items)
- Google Calendar (past 7 days + upcoming week)
- iMCP if available (Apple Calendar, Messages, Reminders)
- Claude Code insights (`~/.claude/usage-data/facets/`)
- Claude Code memory (`~/.claude/projects/-Users-maxforsey/memory/`)
- Alignment Zone (personal project progress)
- Previous weekly review (follow-through check)

### 1b. Create Review Row

Read `references/template.md` for the full OODA template. Create a row in the Weekly Reviews database:

```bash
echo '<filled template>' | bugbook create "Weekly Reviews" \
  --set "Name=Week of {Mon DD}" \
  --set 'Date={"start":"YYYY-MM-DD","end":"YYYY-MM-DD","date_format":"long","include_time":false}' \
  --body-file -
```

Pre-fill these sections from gathered data:
- **Observe > What happened this week** — tickets completed/stalled, git commits, email summary, calendar breakdown, commitments check, wins, blocked patterns
- **Observe > Work** — detailed work summary
- **Observe > Relationships** — people interacted with from email/calendar/messages
- **Orient > Project status** — pull from Bugbook project pages
- **Orient > Relationship pulse** — pending follow-ups
- **Decide > Action items review** — open tickets from both databases
- **Decide > Plan this week** — upcoming calendar events (but keep loose — the user will bring their own plan during the interactive phase)

Leave personal/reflective sections blank for Phase 2.

### 1c. Show Summary

Keep terminal output concise — the rich content is in Bugbook:

```
Weekly review created: "Week of Mar 29"

Pre-filled:
  Agent Tickets: X done, Y in review, Z open
  Max Tickets: X done, Y open
  Git: X commits across Y repos
  Email: X in inbox, Y pending follow-ups
  Calendar: X meetings, Y hours
  Commitments: Z unfulfilled
  Wins: {count}
  Blocked: {count}

Ready for walk-through. Starting with Observe...
```

---

## Phase 2: Interactive Walk-Through

One question at a time. Capture answers and update the review page section by section.

### 2a. Observe (Personal)

Ask each, wait for response, update the page:

1. "How did food go this week?"
2. "How did finances go?"
3. "How did exercise go this week, and what's the plan for next week?" — covers both retrospective and forward-looking in one question. Show the scheduled gym sessions from calendar for context. No need to ask about workouts again in Decide.
4. "How did spiritual progress go?"
5. "How are relationships and social life?" (show the pre-filled interaction list for context)
6. "Any significant observations or issues?"

### 2b. Decide (Planning)

1. "Any unique or upcoming events this week?" — forward-looking, not retrospective.
2. "What are you thinking for meals next week? Want me to generate a meal prep plan?" — if yes, ask for current ingredients, then generate plan (high-protein, high-calorie, 6-day lunch+dinner, easy reheating). Write the plan into the review page.
3. **Thought dump** — "Anything on your mind? I'll capture it all and turn it into tickets." Max talks freely. Claude listens, then proposes tickets. For each: suggest whether it's a Max Ticket or Agent Ticket based on the nature of the task. Create tickets in the appropriate database. Update the review page with the new tickets.
4. **Plan the week** — show upcoming calendar and ticket queue. Don't ask an open-ended question — present the data and let Max bring his own plan. He often has a structured day-by-day layout in mind. Claude's job is to help refine it, not prescribe it. New info may come in during the review (texts, real-time context) that changes the plan — stay flexible.

### 2c. Reflect

Offer: "Want to reflect on each day briefly?" If yes, go day by day — keep it light. If Max declines, skip entirely and move on. This section is optional.

### 2d. Iterate

"Want me to schedule next week's review in your calendar?" — if yes, create event via Google Calendar MCP.

### 2e. Insights

"Let's run /insights to see your Claude Code usage patterns this week." Run the insights report so patterns, friction, and suggestions are fresh. This data also feeds back into the review's Orient > Insights section.

### 2f. Compassion

"Take 5 minutes for meditation. I'll be here when you're back."

---

## Phase 3: Write-Back

### 3a. Verify Tickets
Confirm any tickets created during thought dump exist:
```bash
bugbook query "Max Tickets" --workspace "$WS" --filter "Status=To Do"
bugbook query "Agent Tickets" --workspace "$WS" --filter "Status=To Do"
```

### 3b. Update Claude Code Memory
Based on the full review:
- New patterns or feedback → save as memory files
- Stale memories → update or remove
- Insights-driven improvements → save as feedback memory

```bash
cat ~/.claude/projects/-Users-maxforsey/memory/MEMORY.md
```

### 3c. Update Alignment Zone
If personal projects made progress (Russian, Gather Bio, etc.), update relevant pages:
```bash
bugbook context "Alignment Zone" --workspace "$WS" --depth 1
```

### 3d. Finalize

```
Weekly review complete: "Week of Mar 29"

Created: X Max Tickets, Y Agent Tickets
Memory: {changes made}
Next review: {date if scheduled}

Open in Bugbook to see the full page.
```

---

## Notes

- Pre-fill aggressively. Max should see a mostly-complete review before interaction starts.
- Interactive phase is a conversation, not a form. One question at a time.
- Terminal output stays concise. Rich content goes to Bugbook.
- Meal prep is optional — skip if Max isn't interested that week.
- Thought dump is the most important interactive section — scattered ideas become tracked tickets.
- The gather infrastructure in `references/gather.md` will be shared by /dreview and /mreview later.
