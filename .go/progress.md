# Long Run — 2026-03-20

Started: ~11:00 PM
Finished: ~1:00 AM
Status: Complete

## Summary
Completed: 9/10 tickets across 4 projects
Skipped: 1 (Google OAuth — requires external services)
All merged to `review` branch. Build passing.

## Review Guide

All 9 branches merged to `review` branch. To test:

```
git checkout review
open macos/Bugbook.xcodeproj   # Cmd+R to build and run
```

### 1. Remove canvas feature (HIGH)
Files: CommandPaletteView, ContentView, FileTreeItemView, SidebarView
Smoke test:
- Type "/" in editor — "Canvas" should NOT appear
- Right-click sidebar — "New Canvas" gone
- Cmd+K — "New Canvas" gone
- Existing canvas tabs show "Canvas (coming soon)" placeholder

### 2. Floating recording indicator pill (HIGH)
Files: FloatingRecordingPill.swift (NEW), AppState, ContentView
Smoke test:
- Set appState.isRecording = true
- Switch to another app — dark pill with green audio bars appears
- Drag pill around, click to refocus, set isRecording=false to dismiss

### 3. Notes-first meeting recording UI (HIGH)
Files: MeetingBlockView.swift (NEW), Block, MarkdownBlockParser, BlockDocument, BlockCellView, PageBlockHelpers
Smoke test:
- Type /meeting to insert block
- Click Record — pulsing red dot, waveform, notes area
- Type notes, press Enter — timestamp auto-inserted
- "Show transcript" toggle reveals transcript

### 4. Search content index refresh (MED)
Files: CommandPaletteView
Smoke test:
- Edit page content, add unique word
- Cmd+K — search finds the word immediately

### 5. Editor→sidebar drag fix (MED)
Files: WikiLinkView, BlockViews, Info.plist, BlockCellView
Smoke test:
- Drag [[Page]] link from editor to sidebar — creates reference
- Drag database embed handle to sidebar — same

### 6. Delete marquee-selected blocks (MED)
Files: BlockEditorView
Smoke test:
- Marquee-select 3+ blocks, press Delete — all removed
- Cmd+Z restores them

### 7. Sidebar drag moves page (MED)
Files: BlockDocument, BlockEditorView, ContentView
Smoke test:
- Drag page from sidebar into editor — link created, page removed from sidebar
- Page nested under target in companion folder

### 8. Ask anything AI bar (MED)
Files: MeetingBlockView (integrated)
Smoke test:
- In meeting block, type question in "Ask anything" bar
- Answer generated via claude CLI (Haiku)

### 9. Post-meeting structured output (MED)
Files: MeetingBlockView (integrated), TranscriptionService (NEW)
Smoke test:
- After stopping recording, AI processing cleans transcript
- Structured sections appear (topics, action items)
- "View Transcript" shows chat-style bubbles

## Blocked / Skipped
- Google OAuth verification (row_rv254w) — requires domain registration, Google Cloud Console, OAuth credentials. Code change is just swapping placeholder client ID in CalendarService.swift.

## Build Status
Review branch: PASSING (swift build clean)
Worktrees: cleaned up (9 removed)

## To merge accepted work:
```
git checkout main && git merge review
```

## To iterate on any ticket:
Open /flow and reference the ticket.
