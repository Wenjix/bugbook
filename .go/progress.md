# Long Run — 2026-03-23 (night)

Started: 11:10 PM
Finished: 12:30 AM (blocked on disk)
Status: BLOCKED — disk full from accumulated worktrees

## Summary
Workers completed: 5/7 tickets
Not started: 2 (disk full before batch 2)
Skipped: 1 (Google OAuth)
Builds: UNVERIFIED (disk full prevented swift build)

## Action needed
```bash
# Free disk space by removing OLD worktrees (from prior /go run)
rm -rf ~/Code/bugbook/.claude/worktrees/agent-a42c45ab \
  ~/Code/bugbook/.claude/worktrees/agent-a688e61b \
  ~/Code/bugbook/.claude/worktrees/agent-a6919ad7 \
  ~/Code/bugbook/.claude/worktrees/agent-a3c362c4 \
  ~/Code/bugbook/.claude/worktrees/agent-a023882d \
  ~/Code/bugbook/.claude/worktrees/agent-a876125b \
  ~/Code/bugbook/.claude/worktrees/agent-adbe6daa \
  ~/Code/bugbook/.claude/worktrees/agent-a7e60d8f \
  ~/Code/bugbook/.claude/worktrees/agent-a690675a \
  ~/Code/bugbook/.claude/worktrees/agent-a2388abe \
  ~/Code/bugbook/.claude/worktrees/agent-af890d65 \
  ~/Code/bugbook/.claude/worktrees/agent-a9737ffc \
  ~/Code/bugbook/.claude/worktrees/agent-a64e714e \
  ~/Code/bugbook/.claude/worktrees/agent-a1459f47 \
  ~/Code/bugbook/.claude/worktrees/agent-a923313b \
  ~/Code/bugbook/.claude/worktrees/agent-a3422373 \
  ~/Code/bugbook/.claude/worktrees/agent-acb1dc64 \
  ~/Code/bugbook/.claude/worktrees/agent-afd3bf65
cd ~/Code/bugbook && git worktree prune
```

Then /catchup → /flow to merge the 5 completed branches to dev.

## Completed branches (ready to merge to dev)

### 1. Table vertical lines alignment
Branch: worktree-agent-a34add35
Fix: Moved columnDividers overlay in phantomRow to match dataRow coordinate space
Smoke: Create table with 1-2 rows, verify separators align header/data/phantom

### 2. AskAI progress + change summaries + edit quality
Branch: worktree-agent-a441fa9c
Fix: Phased status ("Reading..." → "Generating..." → "Applying..."), change summary in Done bubble, sanitizeResponse strips empty blocks, system instruction prohibits blank blocks
Smoke: Ask AI to rewrite page → verify phased status → verify summary → no empty blocks

### 3. Sidebar drag move (not link)
Branch: worktree-agent-a1eb267f
Root cause: Cross-directory .above drops silently ignored; moves inserted unwanted wiki links
Fix: Cross-directory drop support + insertLink:false for sidebar drags
Smoke: Drag page between folders in sidebar → moves (not links) → old location gone

### 4. Drag embed to sidebar
Branch: worktree-agent-a9fa58bb
Root cause: Custom UTType not registered; .draggable conflicted with interactive views
Fix: Switched to .json UTType + .onDrag instead of .draggable
Smoke: Drag [[page link]] from editor toward sidebar → drop accepted
Note: Info.plist may have trailing XML — run `git checkout -- macos/App/Info.plist`

### 5. Search index refresh (7th attempt — finally found real root cause!)
Branch: worktree-agent-a7a6aa10
Root cause: 3 issues — (1) 1-second save debounce means disk file stale when Cmd+K opens, (2) qmd external index has its own stale cache, (3) in-memory tab content not synced before indexing
Fix: Flush dirty tab content before Cmd+K, build index from memory for unsaved files, skip qmd when tabs dirty
Smoke: Edit a page → add unique word → Cmd+K → search for it → should appear
Note: SourceKit reports extraneous brace at line 861 — fix after merge

## Not started
- Database breadcrumb (row_kz9860) — blocked on disk
- Database row templates (row_ti2v4r) — blocked on disk

## Skipped
- Google OAuth — external deps

## Lesson learned
Worktree cleanup (Phase 3.9) must run BEFORE launching new workers, not after. 18 worktrees from the prior /go run were never cleaned, filling the disk.
