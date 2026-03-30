# Long Run — 2026-03-29

Started: 9:45 PM
Status: Working (batch 2-3 parallel)

## Plan

22 tickets across 9 projects. 10 executable in this repo.

### Batches
- Batch 1 (parallel): A1 + B1 + C1 — DONE
- Batch 2 (after A1): A2 Callout — RUNNING
- Batch 3 (parallel with B2): C2 MCP Servers + D1 Select Color — RUNNING
- Batch 4+: Large features

## Completed

- [x] A1: Outline (TOC) block type [High] — merged to dev
- [x] B1: Database table calculations footer [High] — merged to dev
- [x] C1: Add Agents sidebar section [Medium] — merged to dev

## In Progress

- [ ] A2: Callout block type — worker running
- [ ] C2: Add MCP Servers listing — worker running
- [ ] D1: Change select option color — worker running

## Remaining

- [ ] A3: Meeting notes markdown shortcuts
- [ ] E1: AND/OR filter groups
- [ ] E2: Inline mentions
- [ ] E3: Formula/rollup/lookup

## Blocked / Skipped

- Build native Gateway interface — too vague
- Google OAuth — external deps
- Restructure Gateway 8.0 — content/data work
- Live knowledge retrieval — too vague
- Skills viewer tab — superseded by Agents sidebar
- Canopy tickets — different repo

## Discoveries

- BugbookCore/Engine/AggregationEngine.swift already existed from prior session with full string-based API
- Worker's duplicate AggregationFunction enum in DatabaseViewHelpers cleaned up during merge
- ~/.claude/skills/ contains both regular folders and symlinks to ~/.agents/skills/

## Build Status

Dev branch: PASSING (swift build clean)
