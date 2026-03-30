# Long Run — 2026-03-29

Started: 9:45 PM
Status: Working (batch 4)

## Completed

- [x] Outline (TOC) block type [High] (row_u9mndd) — merged to dev
- [x] Database table calculations footer [High] (row_kegyb1) — merged to dev
- [x] Add Agents sidebar section [Medium] (row_woy99m) — merged to dev
- [x] Add MCP Servers listing [Low] (row_qfrvll) — merged to dev
- [x] Callout block type [High] (row_fnmxx9) — merged to dev
- [x] Change select option color [Medium] (row_bu993v) — merged to dev

## In Progress

- [ ] Meeting notes markdown shortcuts [High] (row_34on11) — worker running

## Remaining

- [ ] AND/OR filter groups [Medium] (row_1i5rmc) — very large
- [ ] Inline mentions [Medium] (row_xxvee0) — very large
- [ ] Formula/rollup/lookup [Medium] (row_cygwau) — very large

## Blocked / Skipped

- Build native Gateway interface — too vague
- Google OAuth — external deps
- Restructure Gateway 8.0 — content/data work
- Live knowledge retrieval — too vague
- Skills viewer tab — superseded by Agents sidebar
- Canopy tickets — different repo

## Discoveries

- AggregationEngine existed in BugbookCore from prior session
- ~/.claude/skills/ has symlinks to ~/.agents/skills/
- MCP servers stored in ~/.claude.json (not ~/.claude/settings.json as spec said)
- Select option color infrastructure existed but was undiscoverable (context menu only on inline pills, not dropdown items)

## Build Status

Dev branch: PASSING (swift build clean)
All 6 completed features build and compile together.
