# Performance /go Run — 2026-03-24

Started: 7:00 PM
Status: Working (batch 1/4)
Focus: Performance improvements across the app

## Plan
- Batch 1 (parallel): buildFileTree async, graph simulation, content index, table props
- Batch 2 (after batch 1): sidebar expanded-state
- Batch 3 (after batch 2): async image loading
- Batch 4 (parallel): backlink reverse index + FSEvents queue

## Completed
(none yet)

## In Progress
- [ ] Move buildFileTree off main thread + truncate icon reads
- [ ] Move graph force simulation off main thread
- [ ] Single-pass content index + O(1) globalIndex
- [ ] Cache table computed properties per render

## Remaining
- [ ] Hoist sidebar expanded-state
- [ ] Async image loading + downsampling
- [ ] BacklinkService reverse index + FSEvents background queue

## Build Status
Pending first batch.
