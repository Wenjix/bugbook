# Long Run — 2026-03-27

Started: 12:15 AM
Status: Working (batch 1/3, 0/10 tickets)

## Plan

**Batch 1 (parallel — 7 workers, no file overlaps):**
1. [HIGH] Meeting block header pinned (row_2owqcb)
2. [HIGH] FluidAudio transcription fix (row_6if5fq)
3. [HIGH] Ghost databases from drag ops (row_oafne9)
4. [MED] AI chat thread history (row_y0n3u0)
5. [MED] Meetings workspace scan + recency (row_sj7iye)
6. [MED] List item spacing (row_q9rs8t)
7. [MED] Table view grouping (row_m3tz6s)

**Batch 2 (sequential chains, after batch 1 predecessors complete):**
8. [HIGH] Sidebar sort fix (row_bf99mr) — after #3 (share FileSystemService)
9. [MED] Heading toggle wiring (row_b7h2vl) — after #6 (share BlockCellView)
10. [LOW] Hide database title (row_pr65jt) — after #7 (share Database views)

**Skipped (4):**
- Google OAuth verification (row_rv254w) — requires domain registration, Google Console, external setup
- Char design review (row_q1mmj4) — research task, needs user to review external app
- Meeting notes markdown (row_34on11) — ticket recommends discussing architecture direction first
- Live knowledge retrieval (row_25nsk1) — too ambiguous, no files specified

## Completed

## In Progress

## Blocked / Skipped

## Stash
Auto-stashed dirty .go/progress.md: `git stash pop` to restore

## Build Status
