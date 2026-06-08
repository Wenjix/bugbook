---
name: wreview
description: Weekly review built around a free-form brain dump from Max and Zhanel, with a coverage-check pass that nudges about any standard life areas they didn't mention. Saves both dumps and the follow-up answers to a Weekly Reviews page in Bugbook. Use when the user says "wreview", "weekly review", "week review", "review my week", "how did our week go", "Sunday review", "Monday review", or wants to reflect on the week. Also trigger when it's been 7+ days since the last review page in Bugbook.
---

# Weekly Review (/wreview)

A light review built around two brain dumps — one from Max, one from Zhanel — followed by a coverage check that catches anything they skipped. Save it all to a Bugbook page. No pre-fill, no gather, no ticket creation, no memory write-back.

Each review is a row in the **Weekly Reviews** database under Max Flow in Gateway 8.0. The row body holds both brain dumps and the coverage follow-ups.

---

## Workspace

The active Bugbook workspace is **Bugbook** in iCloud. All `bugbook` commands need the workspace flag:

```bash
WS="$HOME/Library/Mobile Documents/iCloud~com~bugbook~app/Documents/Bugbook"
```

Set `WS` once at the start of the session and use it everywhere. Don't use old duplicate workspaces.

Verify the database exists before writing:

```bash
bugbook db schema "Weekly Reviews" --workspace "$WS" 2>/dev/null
```

If the database doesn't exist, tell Max rather than guessing at a schema — the dumps are worth capturing somewhere even if it's just the conversation.

---

## Phase 1: Brain Dump

No pre-fill. Open with the dump, one person at a time.

1. **Max** — "Brain dump — anything on your mind about this week? How it went, what's coming up, whatever's there. Talk freely, I'll just capture it."
2. **Zhanel** — "Your turn — same thing. Anything on your mind about the week?"

Listen and capture verbatim-ish. Don't interrupt to ask follow-ups during the dump — let each person finish.

---

## Phase 2: Coverage Check

After both dumps, scan what was said against the standard life areas below. For each area that wasn't meaningfully touched, nudge once: "You didn't mention {area} — anything there?" Keep it conversational, ask one at a time, and skip any area they clearly already covered. Don't force an answer — "nothing this week" is a fine response.

Standard areas:

- **Food / eating** — how it went, plans for next week
- **Finances** — anything notable
- **Exercise / health** — workouts, sleep, how the body feels; plan for next week
- **Spiritual** — progress, church, scripture
- **Relationships / social** — friends, family, people to follow up with
- **Work** — Max's Runpod work and side projects; Zhanel's work
- **Upcoming week** — events, travel, anything unusual on the calendar
- **Anything significant** — issues, decisions, things weighing on either of you

This is a catch-net, not an interview. If both dumps were thorough, you might only nudge on one or two areas.

---

## Phase 3: Save

Write both brain dumps and the coverage follow-ups into a new Weekly Reviews row. Don't create tickets, don't touch memory.

Write the body to a temp file first — brain dumps contain apostrophes and other characters that break shell quoting if piped via `echo`. Use the Write tool to create `/tmp/wreview-body.md`, then:

```bash
bugbook create "Weekly Reviews" \
  --set "Name=Week of {Mon DD}" \
  --set 'Date={"start":"YYYY-MM-DD","end":"YYYY-MM-DD","date_format":"long","include_time":false}' \
  --workspace "$WS" \
  --body-file /tmp/wreview-body.md
```

Use the current week's Monday–Sunday for the name and date range. Suggested body structure:

```md
# Week of {Mon DD}

## Brain Dump — Max
{Max's dump, lightly cleaned up}

## Brain Dump — Zhanel
{Zhanel's dump, lightly cleaned up}

## Coverage Follow-Ups
- **{Area}**: {what they said when nudged}
- ...
```

Then confirm concisely:

```
Weekly review saved: "Week of {Mon DD}"
Open in Bugbook to see the full page.
```

---

## Notes

- The brain dump is the heart of this. The coverage check exists only to catch what slips through — don't turn it back into a section-by-section questionnaire.
- One person dumps fully before the other starts.
- Terminal output stays concise. The content lives in Bugbook.
