# Bugbook Daily Driver Evidence

Date: 2026-05-18

This file records the current implementation evidence for the Notes + Meetings
daily-driver plan. It is intentionally separate from `.codex/perf/` because that
directory is ignored and stores local trace artifacts.

## Current Status

Not complete. The code paths and automated checks below are green, but the live
60-minute meeting soak is blocked until macOS privacy permissions are approved
for the current app bundle. The foundation implementation is committed in
`4994142`, with doc/metadata/evidence follow-up commits on top; the remaining
commit work is the final live-soak evidence after TCC approval.

Current debug bundle ID:

```text
com.maxforsey.Dahso.dev
```

Current TCC query for `com.maxforsey.Dahso.dev` returns no rows after resetting
the stale Debug-bundle grants. The reset removed older `auth_value=2` rows that
were cdhash-scoped to a previous signed build and did not apply to the current
Debug app. The latest short prompt diagnostic rebuilt the app with CDHash
`A308CBA1F45E01DA9EF2FEF7029344C807838580`; TCC still has no current
microphone, screen, or system-audio rows for that bundle.

## Completion Audit Snapshot

Objective: ship Bugbook as a local-first Notes + Meetings daily driver, with
legacy panes feature-flagged off by default, production-grade notes editing,
rock-solid meeting capture, shared plain `.md` storage, and measured performance.

Audit result: not achieved yet. Automated implementation checks pass, but the
definition of done requires a real 60-minute meeting capture run with live audio
and transcription. That run is blocked by macOS privacy approval for the current
Debug bundle. The execution-note requirement to land small commits with
before/after performance numbers is partially satisfied by the foundation commit,
but the final live-soak numbers are not available yet.

Remaining required gate:

1. Approve Bugbook for Microphone and Screen/System Audio Recording in macOS
   Privacy & Security.
2. Run the enforced 65-minute Allocations soak command in "Blocked Live Soak".
3. Confirm the trace includes `meetingRecordingStart`, `meetingMicAudioCapture`,
   `meetingSystemAudioCapture`, `liveTranscriptionChunk`,
   `meetingRecordingStopFinalize`, `meetingTranscriptPersist`, and
   `meetingNotePersist`.
4. Run `scripts/verify-daily-driver-soak-evidence.sh` against the generated
   evidence note.
5. Confirm RSS peak/growth stays under 200 MiB and the app process remains
   alive after the trace.
6. Commit the final live-soak evidence with before/after performance details.

Approval path:

1. Open System Settings > Privacy & Security > Microphone and enable Bugbook.
2. Open System Settings > Privacy & Security > Screen & System Audio Recording
   and enable Bugbook.
3. If Bugbook does not appear or macOS keeps stale debug-signing rows, reset the
   current Debug bundle and rerun the short preflight/prompt command:

   ```sh
   scripts/run-daily-driver-soak.sh reset-tcc
   ```

4. To open the relevant privacy panes and trigger fresh macOS prompts while you
   are at the Mac, run:

   ```sh
   scripts/run-daily-driver-soak.sh prompt
   ```

5. To check whether macOS has recorded the approvals without building or
   launching Bugbook, run:

   ```sh
   scripts/run-daily-driver-soak.sh status
   ```

## Prompt-to-Artifact Audit

| Objective clause | Concrete artifact or command | Current result |
| --- | --- | --- |
| Feature-flag Home, Search, Calendar, Terminal, Browser, and Mail off by default without deleting code | `BugbookFeatureGate`, `ContentView` lazy `LegacyPaneServices`, `BugbookFeatureGateTests` | Verified |
| Hidden panes must not load, initialize, or consume runtime resources by default | `shouldInitializeLegacyServices`, `shouldScanLegacyWorkspaces`, `shouldRegisterSearchIndexAtLaunch`, AppState legacy refresh no-op tests | Verified |
| Sidebar shows only Meeting and Notes | `ShellNavigationItems.visible`, `BugbookFeatureGate.allowsSidebarItem`, `BugbookFeatureGateTests` | Verified |
| Notes pane uses the block editor and saves local `.md` files on every edit | `BlockEditorView`, `ContentView.scheduleSave`, `EditorSaveWorker`, `EditorSaveWorkerTests` | Verified |
| Premium markdown coverage: headings, lists, tables, code, callouts, wikilinks, embedded images, footnotes | `MarkdownBlockParser`, `CodeSyntaxHighlighter`, `AsyncLocalImageView`, `FootnoteBlockView`, `BlockDocumentTests`, `CodeSyntaxHighlighterTests` | Verified by unit tests |
| Notes file tree supports fast switching and fuzzy filename filtering | `FileTreeFilter`, `ShellNavigationViews`, `FileTreeFilterTests`, `PerformanceTests` | Verified |
| Notes and Meetings share the configurable notes folder root | `AppSettings.resolvedNotesFolderPath`, `ContentView.initializeWorkspace`, `AppSettingsTests` | Verified |
| Daily note can be first screen and daily notes live in a first-party database | `openDailyNote`, `ensureDailyNotesHub`, `FirstPartyFileSystemServiceTests` | Verified |
| Meeting capture records system audio and mic via ScreenCaptureKit where available | `SystemAudioCapture`, `TranscriptionService.startScreenCaptureKitAudioCapture`, enforced `meetingMicAudioCapture` and `meetingSystemAudioCapture` markers in `scripts/profile-meeting-soak.sh`, `TranscriptionServiceTests` configuration/source-mapping coverage | Verified by unit tests; live capture blocked by TCC |
| Live transcription is visible during meeting and copyable afterward | `MeetingTranscriptWidget`, `MeetingTranscriptFormatter`, `MeetingTranscriptStoreTests` | Verified |
| Stop writes structured frontmatter and transcript body into notes folder | `MeetingRecordingDocumentFinalizer`, `MeetingFrontmatterTests` | Verified |
| Stop persists the completed meeting `.md` before reporting success | `ContentView.completeBackgroundSave` emits `meetingNotePersist` only after the markdown save finishes and the saved document frontmatter is `type: meeting` | Verified |
| Completed meeting opens in Notes pane for editing | `MeetingNavigationCoordinator`, `MeetingsView.createNewMeeting`, floating pill stop routing, `MeetingPageView.onMeetingFinalized`, `MeetingRecordingNoticeTests` | Verified |
| Meeting summary generation retained while AI side panel/settings/agent hub are hidden by default | `MeetingSummaryService`, `MeetingSummaryServiceTests`, `MeetingPageView`, inline `MeetingBlockView` summary path routed through the shared service, `shouldExposeAgentSurfaces`, settings and command catalog tests | Verified |
| Performance targets are measured, not assumed | `Tests/BugbookTests/perf_baseline.tsv`, `swift test`, xctrace launch baseline, blocked soak script with enforced signpost and RSS gates | Verified except live RSS soak |
| 60-minute meeting must not drop audio, stall transcription, crash, or grow above 200 MB | `scripts/run-daily-driver-soak.sh`, which delegates to `scripts/profile-meeting-soak.sh 65m Allocations` with a 60-minute auto-stop and finalization buffer after privacy approval | Blocked |

## Requirement Checklist

| Requirement | Evidence | Status |
| --- | --- | --- |
| Default sidebar shows only Meeting and Notes | `BugbookFeatureGate.allowsSidebarItem`, `paneLauncherBuiltInPanes`, `BugbookFeatureGateTests` | Verified |
| Home, Search, Calendar, Terminal, Browser, Mail remain behind flag and do not initialize by default | `shouldInitializeLegacyServices`, `shouldScanLegacyWorkspaces`, `shouldRegisterSearchIndexAtLaunch`, lazy `LegacyPaneServices`, notification and shortcut catalog guards, `BugbookFeatureGateTests` | Verified |
| Search pane is hidden while qmd/search infrastructure remains available for note finding | `ShellNavigationItems.visible`, `CommandPaletteCreateKind.availableCases`, `SearchSettingsView`, `shouldRegisterSearchIndexAtLaunch` | Verified |
| Search settings remain available without legacy Search pane startup work | `SearchSettingsView` keeps qmd configuration available on demand; default mode keeps `shouldRegisterSearchIndexAtLaunch` false and no force-unwrapped qmd repository URL remains | Verified |
| Daily note is first screen in default mode | `ContentView.finalizeResolvedWorkspaceStartup` calls `openDailyNote()` and returns when `shouldAutoOpenOnboardingAtLaunch` is false; `BugbookFeatureGateTests` | Verified |
| Launch onboarding cannot override the default daily note screen | `BugbookFeatureGate.shouldAutoOpenOnboardingAtLaunch` is false by default and true only with legacy panes enabled | Verified |
| Daily Notes hub/database exists from start | `FirstPartyDatabaseFiles.ensureDailyNotesHub`, `FirstPartyFileSystemServiceTests` | Verified |
| Meetings hub/database exists from start | `FirstPartyDatabaseFiles.ensureMeetingsHub`, `MeetingNoteServiceTests`, `FirstPartyFileSystemServiceTests` | Verified |
| Inline meeting database embeds use the canonical Meetings hub/database | `ContentView.ensureMeetingsDatabase`, `FirstPartyDatabaseFiles.ensureMeetingsHub`, `FirstPartyFileSystemServiceTests`, `MeetingNoteServiceTests` | Verified |
| Notes and meetings use one configurable notes root | `AppSettings.resolvedNotesFolderPath`, `ContentView.initializeWorkspace`, `AppSettingsTests` | Verified |
| Notes save automatically to disk | `ContentView.scheduleSave`, `saveDocumentInBackground`, `EditorSaveWorkerTests` | Verified |
| Page title and filename stay synchronized with readable sanitized names | `synchronizePlainMarkdownFilename`, `synchronizeMeetingRowFilename`, first-party row filename and YAML escaping tests | Verified |
| Markdown/editor support covers headings, lists, tables, code, callouts, wikilinks, images, footnotes | `MarkdownBlockParser`, editor views, `BlockDocumentTests`, `CodeSyntaxHighlighterTests`, `EditorTypographyTests` | Verified by tests |
| File tree supports fast switching and fuzzy filtering | `FileTreeFilter`, `ShellNavigationViews`, `FileTreeFilterTests`, performance baselines | Verified |
| Meeting capture uses ScreenCaptureKit for system audio | `SystemAudioCapture` imports ScreenCaptureKit and uses `SCStream`; `meetingSystemAudioCapture` is emitted on the first raw system buffer and required by the soak script; `TranscriptionServiceTests` covers SCK output-source mapping and audio-only stream defaults | Verified by unit tests; live capture blocked by TCC |
| Meeting capture includes mic audio | `TranscriptionService.startRecording`, ScreenCaptureKit microphone path on macOS 15+, AVAudioEngine fallback; `meetingMicAudioCapture` is emitted on the first raw mic buffer and required by the soak script; `TranscriptionServiceTests` covers the macOS 15 microphone configuration gate | Verified by unit tests; live capture blocked by TCC |
| Live transcript is visible and copyable during meeting | `MeetingTranscriptWidget`, `MeetingTranscriptFormatter`, `MeetingTranscriptStoreTests` | Verified |
| Recording privacy notices route to the right macOS settings panes | `MeetingRecordingNoticePrivacySettings`, `MeetingRecordingNoticeTests` | Verified |
| Stop writes structured meeting markdown with transcript body | `MeetingRecordingDocumentFinalizer`, `MeetingFrontmatterTests` | Verified |
| Meeting transcript persistence marker means persistence completed | `MeetingPageView.finalizeStoppedRecording` awaits `MeetingTranscriptStore.saveAsync` before ending the `meetingTranscriptPersist` signpost and emitting the `meetingTranscriptPersist` profile marker | Verified |
| Meeting note persistence marker means the `.md` save completed | `ContentView.completeBackgroundSave` emits `meetingNotePersist` only after the markdown file save future completes for a `type: meeting` document | Verified |
| Completed meeting note opens in Notes pane | `MeetingNavigationCoordinator` sets editor mode, hides settings, arms auto-record for newly created meeting notes, and routes floating-pill stop back to the active meeting page before posting stop; covered by `MeetingRecordingNoticeTests` | Verified |
| Meeting summary generation is retained | `MeetingSummaryService`, `MeetingSummaryServiceTests` | Verified |
| AI side panel, ASCII commands, AI settings, agent hub hidden by default | `shouldExposeAgentSurfaces`, settings normalization, command and shortcut catalog guards, `BugbookFeatureGateTests`, direct `AppState` AI surface calls clear transient state in default mode | Verified |
| Inline meeting block does not keep a separate hard-coded AI command path | `MeetingBlockView` uses `MeetingSummaryService`; no `runClaude`, `Process`, or `DispatchQueue` summary runner remains in that view | Verified |
| Floating recording pill can stop the active meeting | `FloatingRecordingPill` renders a `stop.fill` icon button wired to `onStop`; `ContentView.handleRecordingChange` navigates to the meeting page and posts `.stopMeetingRecording` | Verified |
| Meeting capture/finalization touched files are lint-clean | `MeetingBlockView` split into private extensions; targeted lint across meeting capture, frontmatter, transcript, summary, and meeting UI files exits 0 with 0 violations | Verified |
| File watcher events are debounced | `WorkspaceWatcher` uses FSEvents plus a 2-second debounce; `WorkspaceWatcherTests` covers rapid event coalescing and stop-time cancellation | Verified |
| No main-thread file I/O on hot editor saves | `EditorSaveWorker`, background save paths, append-on-block-move worker tests | Verified for touched hot paths |
| Legacy workspace document restore avoids synchronous page-content reads on the UI path | `ContentView.restoreWorkspaceDocumentsIfNeeded` now restores via `EditorSaveWorker.loadPageContent`; targeted async restore tests and lint pass | Verified |
| Default meeting database creation/open fallback avoids workspace-root schema scans on the UI path | `ContentView.ensureMeetingsDatabase`, `openDatabase(at:)`, `FirstPartyDatabaseFiles.ensureMeetingsHub`, database/first-party regression tests | Verified |
| Hot-path force unwrap cleanup | `rg "try!|as!|[A-Za-z0-9_\\)\\]]!([\\)\\]\\.,:]|$)"` across markdown/editor/file-tree/sidebar/save/meeting-capture paths; `MarkdownBlockParser` `first!` sites replaced with guarded unwraps; `TrashView` path abbreviation no longer force-unwraps; database view `state.schema!`, `editingTemplate!`, `self.row!`, lookup/rollup, and row-id force unwraps replaced with safe fallbacks; database settings and option row helpers extracted to keep touched database files lint-clean | Verified |
| Runtime Bugbook branding cleanup in touched daily-driver paths | Legacy workspace user-facing titles now say Bugbook while Dahso enum cases/path candidates remain only for migration compatibility; `FileSystemServiceTests/testDetectLegacyWorkspacesFindsKnownLegacyRootsWithContent` covers the titles | Verified |
| Default visible settings code health | Force-unwrap and TODO/FIXME/HACK scans are clean across `GeneralSettingsView`, `AppearanceSettingsView`, `MeetingsSettingsView`, `SearchSettingsView`, and `ShortcutsSettingsView` | Verified |
| TODO/FIXME hack cleanup in affected paths | `rg -ni "todo|fixme|hack|xxx"` over current Bugbook notes/meetings/database source paths returns no code-comment hacks in the affected implementation paths | Verified |
| 60-minute live meeting must not drop audio, stall transcription, crash, or grow above 200 MB | Requires `scripts/run-daily-driver-soak.sh` after TCC approval, including raw mic/system audio capture markers plus transcript/persist markers, enforced Instruments/RSS targets, and an app-process-alive check after the trace | Blocked |
| Small-commit execution evidence and before/after perf data | `Tests/BugbookTests/perf_baseline.tsv`, Xcode build, lint, `BUGBOOK_DAILY_DRIVER_EVIDENCE.md`, foundation commit `4994142`, follow-up doc/metadata/evidence commits, final live-soak commit | Partial: foundation perf evidence is committed, but final live-soak before/after numbers are still blocked |

## Performance Baseline

Latest baseline source in the current worktree:
`Tests/BugbookTests/perf_baseline.tsv`

| Target | Current measurement | Status |
| --- | ---: | --- |
| Cold launch under 500 ms | 459.090 ms (`xctrace_default_launch_initial_frame`) | Pass |
| Note switching under 50 ms on 1,000 `.md` files | 0.378 ms (`note_switch_1000_folder`) | Pass |
| Block editor input latency under 16 ms | 0.164 ms (`block_input_model_update_1000`) | Pass |
| File tree filter on 1,000 files | 3.505 ms (`file_tree_filter_1000`) | Pass |
| File tree build on 1,000 files | 48.445 ms (`filesystem_tree_1000`) | Measured |
| 60-minute transcript finalization model | 2.327 ms (`transcript_finalize_60min_segments`) | Pass |
| Live 60-minute meeting RSS peak/growth under 200 MB | Not yet measured | Blocked |

Latest `swift test` refreshed `Tests/BugbookTests/perf_baseline.tsv` at
2026-05-18T13:03Z. It exited successfully with 502 tests and 0 failures. The
hard targets above pass. The performance comparison reported a relative
`transcript_finalize_60min_segments` regression from about 1.9 ms to 2.3 ms,
which is still tiny in absolute terms and far below the 60-minute meeting
finalization requirement; live RSS stability remains blocked on TCC approval.

## Latest Permission Preflight

Dry bundle/TCC preflight:

```sh
scripts/run-daily-driver-soak.sh preflight
```

Result: failed before launching Bugbook or Instruments because the only current
Debug-bundle TCC rows are stale cdhash-scoped rows from an older signed build.
Diagnostic evidence:
`.codex/perf/bugbook-meeting-soak-allocations-20260518T133510Z.md`.

Latest diagnostics:

- Current CDHash:
  `511467b3f88c1a0b4ad5a214fc465e5cfed95c6a`
- Permission marker rows: none
- TCC rows for microphone/screen/system audio:
  `kTCCServiceAudioCapture` and `kTCCServiceMicrophone` are present with
  `auth_value=2`, but their `csreq` contains old cdhash
  `A44BCC76C91B28DB97187AEB566A68D7A6C03743`
- `scripts/run-daily-driver-soak.sh status` marks those rows as `stale-cdhash`
- System audio stimulus default path recorded in preflight:
  `/System/Library/Sounds/Glass.aiff`

Preflight gate:

- Bundle privacy declarations: PASS
- Microphone authorization: FAIL
- Screen/System Audio authorization: FAIL
- Overall preflight: FAIL

The latest dry preflight rebuilt the Debug app through the one-command required
soak wrapper, with privacy-pane opening disabled for the audit, and failed
before launch, as intended, because existing Debug TCC rows do not apply to the
current signed app. The Debug build keeps the legacy
`com.maxforsey.Dahso.dev` bundle ID for local continuity, but repeated debug
signing can still leave cdhash-scoped rows stale.

After that diagnostic, the wait helper was corrected to skip pre-launch waiting
when the current Debug bundle has no TCC rows yet. In that first-time state the
script launches Bugbook so macOS can create the permission prompt/list entry;
once rows exist, the same helper waits for the required approvals before the
soak starts. A shortened validation run confirmed the no-row path now launches
Bugbook and reaches `meetingMicPermissionPrompt` instead of waiting forever;
that run wrote
`.codex/perf/bugbook-meeting-soak-allocations-20260518T112644Z.md`.

Recommended short permission-prompt refresh:

```sh
scripts/run-daily-driver-soak.sh prompt
```

Latest prompt refresh ran after `scripts/run-daily-driver-soak.sh reset-tcc`,
with shortened 90-second prompt/attach windows for diagnostics. It timed out
waiting for `liveTranscriptionChunk` after Bugbook emitted both
`meetingMicPermissionPrompt` and `meetingMicPermissionRequestSubmitted`, which
confirms the app submitted the AVFoundation microphone permission request. No
grant/deny callback marker arrived before timeout, and macOS still did not
create any TCC rows. Diagnostic evidence:
`.codex/perf/bugbook-meeting-soak-allocations-20260518T135225Z.md`.

Observed markers:

- `appInitialLifecycleStart`
- `workspaceStartupFinalized`
- `profileMeetingRequested`
- `appInitialLifecycleComplete`
- `profileMeetingCreated`
- `meetingMicPermissionPrompt`
- `meetingMicPermissionRequestSubmitted`
- `meetingNotePersist`

The diagnostic TCC query still returned no microphone/screen/system-audio rows.
The short non-live run sampled RSS from 96.3 MiB down to 83.9 MiB, with a
108.9 MiB peak, but it does not cover the 60-minute live capture requirement.
The harness
now defaults `BUGBOOK_PROFILE_ALLOW_PERMISSION_PROMPT=1` runs to a 180-second
macOS prompt window and 240-second first-marker wait when no explicit attach
timeout is supplied. The wrapper's `prompt` mode extends those windows to 600
seconds, records for 30 seconds inside a one-minute trace after approval, and
leaves a 10-second finalization buffer so manual approval does not race the
short prompt attempt. `BUGBOOK_PROFILE_OPEN_PRIVACY_SETTINGS=1` opens the
Microphone and Screen/System Audio settings panes before the prompt run so the
manual approval controls are visible. `BUGBOOK_PROFILE_WAIT_FOR_PRIVACY_APPROVAL=1`
waits for the required TCC rows before launching Bugbook, so a prompt/soak run
can pause until manual approval is complete instead of burning the app-side
recording timeout. `BUGBOOK_PROFILE_SYSTEM_AUDIO_STIMULUS=1` plays a short
external macOS sound loop after launch so ScreenCaptureKit has non-Bugbook
system audio to capture for the `meetingSystemAudioCapture` marker. Enforced
auto-stop runs now require a finalization buffer before the trace ends, so the
stop/finalize/save markers are not racing the 65-minute trace timeout.

Short unattended preflight:

```sh
BUGBOOK_PROFILE_CONFIGURATION=Debug \
BUGBOOK_PROFILE_CODE_SIGN_IDENTITY="Apple Development" \
BUGBOOK_PROFILE_DEVELOPMENT_TEAM=H9N9P29TX5 \
BUGBOOK_PROFILE_AUTO_START_MEETING=1 \
BUGBOOK_PROFILE_AUTO_STOP_RECORDING_AFTER_SECONDS=5 \
BUGBOOK_PROFILE_ATTACH_AFTER_TIMEOUT_SECONDS=30 \
BUGBOOK_REQUIRE_MEETING_SIGNPOSTS=1 \
BUGBOOK_PROFILE_ALLOW_PERMISSION_PROMPT=0 \
scripts/profile-meeting-soak.sh 10s Allocations
```

Result: failed before attaching Instruments, as intended, because
`liveTranscriptionChunk` was never observed. Diagnostic evidence:
`.codex/perf/bugbook-meeting-soak-allocations-20260518T084440Z.md`.

Observed markers:

- `profileMeetingRequested`
- `profileMeetingCreated`
- `meetingMicPermissionUnavailable`

The diagnostic TCC query again returned no rows for microphone/screen/system
audio. This proves the remaining blocker is macOS privacy approval, not the
profile harness silently skipping the meeting flow.

## Bundle Privacy Preflight

Current Debug bundle checks:

- Bundle ID: `com.maxforsey.Dahso.dev`
- `NSMicrophoneUsageDescription`: present
- `NSAudioCaptureUsageDescription`: present
- Signed entitlement `com.apple.security.device.audio-input`: present

The app bundle has the required microphone/system-audio declarations. The
remaining capture blocker is the empty post-reset TCC authorization state above.
The previous stale Debug grants were reset with
`scripts/run-daily-driver-soak.sh reset-tcc`; macOS still needs to record fresh
Microphone and Screen/System Audio approvals for the current signed app. The
foundation commit `4994142` includes the Bugbook rename/default-mode
implementation, soak scripts, README updates, and automated performance
evidence in one buildable slice. Follow-up doc/metadata/evidence commits are
separate from runtime behavior. The remaining commit-sequencing work is to
commit the completed 65-minute live-soak evidence after privacy approval.

## Green Verification Commands

Latest observed results:

- `swift test`: 502 tests passed, 0 failures; refreshed `Tests/BugbookTests/perf_baseline.tsv` at 2026-05-18T13:03Z. The hard daily-driver benchmarks passed; the comparison flagged only the relative `transcript_finalize_60min_segments` change from about 1.9 ms to 2.3 ms, still far below any user-visible meeting finalization risk.
- Targeted local-file daily-driver regression: `swift test --filter 'FirstPartyFileSystemServiceTests|MeetingNoteServiceTests|MeetingFrontmatterTests|MeetingTranscriptMarkdownTests|MeetingTranscriptStoreTests|EditorSaveWorkerTests|FileTreeFilterTests|CodeSyntaxHighlighterTests'` passed, 34 tests, 0 failures after re-checking first-party Daily Notes/Meetings hubs, friendly markdown files, title-to-filename synchronization, meeting frontmatter/finalization, transcript copy/sidecar storage, off-main editor saves, fuzzy file filtering, and code highlighting
- Targeted meeting-capture logic regression: `swift test --filter 'TranscriptionServiceTests|MeetingRecordingNoticeTests|MeetingsViewModelTests|MeetingSummaryServiceTests'` passed, 28 tests, 0 failures after re-checking ScreenCaptureKit source mapping/configuration, raw mic/system audio marker emission, bounded live-transcription dispatch, long-session stop/finalize transcript assembly, privacy notice routing, floating-pill meeting navigation, symlinked meeting-root scanning, and retained meeting-summary generation/timeouts
- Targeted parser/editor/meeting-summary regression: `swift test --filter 'MeetingSummaryServiceTests|MeetingTranscriptMarkdownTests|BlockDocumentTests|BugbookFeatureGateTests'` passed, 62 tests, 0 failures
- Targeted meeting editor/summary regression after `MeetingBlockView` split: `swift test --filter 'MeetingSummaryServiceTests|MeetingTranscriptMarkdownTests|BlockDocumentTests'` passed, 46 tests, 0 failures
- Targeted first-party database regression: `swift test --filter 'FirstPartyFileSystemServiceTests|MeetingNoteServiceTests|DatabaseServiceLoadTests|BugbookFeatureGateTests|BlockDocumentTests'` passed, 69 tests, 0 failures
- Targeted database-view safety regression: `swift test --filter 'DatabaseServiceLoadTests|FirstPartyFileSystemServiceTests|MeetingNoteServiceTests'` passed, 12 tests, 0 failures after database binding/force-unwrap cleanup
- Targeted legacy-workspace branding regression: `swift test --filter FileSystemServiceTests/testDetectLegacyWorkspacesFindsKnownLegacyRootsWithContent` passed, 1 test, 0 failures after updating user-facing legacy workspace titles to Bugbook
- Targeted Search settings/default-mode regression: `swift test --filter BugbookFeatureGateTests/testDefaultModeKeepsOnlyDailyDriverSettingsVisible` passed, 1 test, 0 failures after removing the qmd link force unwrap
- Targeted default-startup/feature-gate regression: `swift test --filter BugbookFeatureGateTests` passed, 17 tests, 0 failures after a fresh audit of default-mode runtime gates, hidden-pane sanitization, launcher/sidebar/settings visibility, shortcut hiding, and legacy-flag restore behavior
- Targeted async restore regression: `swift test --filter 'EditorSaveWorkerTests|BugbookFeatureGateTests/testDefaultModeDisablesLegacyRuntimeWork|BugbookFeatureGateTests/testLegacyFlagRestoresHiddenPaneAccess'` passed, 9 tests, 0 failures after moving legacy workspace document restore onto `EditorSaveWorker.loadPageContent`
- Targeted workspace watcher debounce regression: `swift test --filter WorkspaceWatcherTests` passed, 2 tests, 0 failures after making the observed-change debounce path directly testable
- Targeted floating recording pill regression: `swift test --filter 'MeetingRecordingNoticeTests|BugbookFeatureGateTests/testDefaultModeDisablesLegacyRuntimeWork'` passed, 5 tests, 0 failures after wiring the pill stop button
- Targeted meeting navigation regression: `swift test --filter MeetingRecordingNoticeTests` passed, 6 tests, 0 failures after extracting `MeetingNavigationCoordinator` to cover newly created meeting-note navigation and floating-pill stop routing
- Targeted meeting persist-marker regression: `swift test --filter 'MeetingFrontmatterTests|MeetingTranscriptStoreTests|TranscriptionServiceTests/testStopRecordingAndWaitBuildsFullTextFromConfirmedSegments|BugbookFeatureGateTests/testDefaultModeDisablesLegacyRuntimeWork'` passed, 13 tests, 0 failures after moving `meetingTranscriptPersist` marker emission after the awaited sidecar save
- Targeted meeting note persist-marker regression: `swift test --filter 'MeetingFrontmatterTests|MeetingTranscriptStoreTests|EditorSaveWorkerTests|BugbookFeatureGateTests/testDefaultModeDisablesLegacyRuntimeWork'` passed, 19 tests, 0 failures after adding the `meetingNotePersist` marker after the markdown save completes
- Targeted raw audio capture and ScreenCaptureKit helper regression: `swift test --filter TranscriptionServiceTests` passed, 17 tests, 0 failures after adding one-shot `meetingMicAudioCapture` and `meetingSystemAudioCapture` markers, requiring them in the soak script, and covering SCK output-source/configuration helpers
- Xcode Debug build: passed as part of the latest wrapper preflight at 2026-05-18T13:35Z, with only known multiple-destination, GhosttyKit umbrella-header, and CEF copy-script warnings
- Default-mode launch smoke: LaunchServices `open -n` of the rebuilt Debug app reached `appInitialLifecycleComplete` in `.codex/perf/bugbook-default-open-launch-20260518T115137Z.markers`; marker deltas were 4.3 ms to `workspaceStartupFinalized` and 5.6 ms to `appInitialLifecycleComplete`
- `swiftlint lint --config .swiftlint.yml`: exit 0, 324 warning-only existing violations, 0 serious after the ScreenCaptureKit helper and evidence refresh
- Targeted editor/parser lint: `swiftlint lint --config .swiftlint.yml Sources/Bugbook/Views/Editor/BlockViews.swift Sources/Bugbook/Views/Editor/AsyncLocalImageView.swift Sources/Bugbook/Lib/MarkdownBlockParser.swift` exit 0, 3 warning-only structural parser-size violations, 0 serious
- Targeted meeting-summary lint: `swiftlint lint --config .swiftlint.yml Sources/Bugbook/Views/Editor/MeetingBlockView.swift Sources/Bugbook/Views/ContentView.swift Sources/Bugbook/Services/MeetingSummaryService.swift` exit 0, 1 warning-only legacy view-size violation, 0 serious
- Targeted meeting capture/finalization lint: `swiftlint lint --config .swiftlint.yml Sources/Bugbook/Services/SystemAudioCapture.swift Sources/Bugbook/Services/TranscriptionService.swift Sources/Bugbook/Services/MeetingFrontmatter.swift Sources/Bugbook/Services/MeetingNoteService.swift Sources/Bugbook/Services/MeetingSummaryService.swift Sources/Bugbook/Services/MeetingTranscriptStore.swift Sources/Bugbook/Views/Meetings/MeetingPageView.swift Sources/Bugbook/Views/Meetings/MeetingsView.swift Sources/Bugbook/Views/Meetings/MeetingTranscriptWidget.swift Sources/Bugbook/Views/Editor/MeetingBlockView.swift` exit 0, 0 violations
- Targeted meeting persist-marker lint: `swiftlint lint --config .swiftlint.yml Sources/Bugbook/Views/Meetings/MeetingPageView.swift Sources/Bugbook/Services/MeetingTranscriptStore.swift` exit 0, 0 violations
- Targeted meeting note persist-marker lint: `swiftlint lint --config .swiftlint.yml Sources/Bugbook/Views/ContentView.swift Sources/Bugbook/Views/Meetings/MeetingPageView.swift Sources/Bugbook/Services/MeetingTranscriptStore.swift` exit 0, 0 violations
- Targeted raw audio capture and ScreenCaptureKit helper lint: `swiftlint lint --config .swiftlint.yml Sources/Bugbook/Services/SystemAudioCapture.swift Tests/BugbookTests/TranscriptionServiceTests.swift` exit 0, 0 violations
- Targeted microphone-permission marker lint: `swiftlint lint --config .swiftlint.yml Sources/Bugbook/Services/TranscriptionService.swift` exit 0, 0 violations
- Targeted microphone/transcription regression: `swift test --filter TranscriptionServiceTests` passed, 17 tests, 0 failures after adding request-submitted and grant/deny profile markers around `AVCaptureDevice.requestAccess`
- Targeted first-party database lint: `swiftlint lint --config .swiftlint.yml Sources/Bugbook/Views/ContentView.swift Sources/Bugbook/Services/FirstPartyDatabaseIndexWorker.swift` exit 0, 0 violations
- Targeted database-view lint: `swiftlint lint --config .swiftlint.yml Sources/Bugbook/Views/Database/DatabaseFullPageView.swift Sources/Bugbook/Views/Database/DatabaseInlineEmbedView.swift Sources/Bugbook/Views/Database/DatabaseSettingsPopover.swift Sources/Bugbook/Views/Database/DatabaseRowViewModel.swift Sources/Bugbook/Views/Database/KanbanView.swift Sources/Bugbook/Views/Database/PropertyEditorView.swift Sources/Bugbook/Views/Database/PropertyOptionRows.swift` exit 0, 0 violations
- Targeted file-system branding lint: `swiftlint lint --config .swiftlint.yml Sources/Bugbook/Services/FileSystemService.swift Tests/BugbookTests/FileSystemServiceTests.swift` exit 0, 3 warning-only pre-existing file/type-size violations, 0 serious
- Targeted Search settings lint: `swiftlint lint --config .swiftlint.yml Sources/Bugbook/Views/Settings/SearchSettingsView.swift` exit 0, 0 violations
- Targeted AppState/feature-gate lint: `swiftlint lint --config .swiftlint.yml Sources/Bugbook/App/AppState.swift Tests/BugbookTests/BugbookFeatureGateTests.swift` exit 0, 0 violations
- Targeted startup/feature-gate lint: `swiftlint lint --config .swiftlint.yml Sources/Bugbook/App/BugbookFeatureGate.swift Sources/Bugbook/Views/ContentView.swift Tests/BugbookTests/BugbookFeatureGateTests.swift` exit 0, 0 violations
- Targeted async restore lint: `swiftlint lint --config .swiftlint.yml Sources/Bugbook/Views/ContentView.swift Sources/Bugbook/Services/EditorSaveWorker.swift` exit 0, 0 violations
- Targeted sidebar lint: `swiftlint lint --config .swiftlint.yml Sources/Bugbook/Views/Sidebar/TrashView.swift` exit 0, 0 violations after replacing the remaining sidebar force unwrap
- Targeted workspace watcher lint: `swiftlint lint --config .swiftlint.yml Sources/Bugbook/Services/WorkspaceWatcher.swift Tests/BugbookTests/WorkspaceWatcherTests.swift` exit 0, 0 violations
- Targeted floating recording pill lint: `swiftlint lint --config .swiftlint.yml Sources/Bugbook/Views/Components/FloatingRecordingPill.swift` exit 0, 0 violations after adding the stop button and cleaning an existing one-letter duration variable
- Targeted meeting navigation lint: `swiftlint lint --config .swiftlint.yml Sources/Bugbook/Views/Meetings/MeetingsView.swift Sources/Bugbook/Views/ContentView.swift Tests/BugbookTests/MeetingRecordingNoticeTests.swift` exit 0, 0 violations
- Affected-path force-unwrap/TODO scan: `rg -n "TODO|FIXME|HACK|XXX|fatalError|try!|as!|[A-Za-z0-9_\\)\\]]!([\\)\\]\\.,:]|$)"` over App, ContentView, Meetings, MeetingBlockView, Meetings settings, meeting services, editor save, first-party database index, workspace watcher, Sidebar, floating recording pill, file-tree filter, markdown parser, image/footnote/code renderer paths returned no matches
- `git diff --check`: passed
- Stale evidence and touched-file trailing-whitespace scans: passed
- `zsh -n scripts/profile-meeting-soak.sh` and `zsh -n scripts/run-daily-driver-soak.sh`: passed after tightening the interactive permission-prompt timeout defaults, adding the explicit privacy-pane opener flag, adding the optional TCC approval wait mode, adding the opt-in system-audio stimulus loop, enforcing a finalization buffer before trace end, making enforced runs fail on missing or over-target Instruments/RSS samples, adding the one-command required soak wrapper with `preflight` and `prompt` modes, and rejecting stale cdhash-scoped TCC rows for older Debug builds
- Wrapper preflight check: `scripts/run-daily-driver-soak.sh preflight` builds with the wrapper defaults, keeps `Open privacy settings: 0`, writes the latest preflight evidence, and fails on missing, denied, or stale TCC rows
- Direct TCC recheck without rebuild: queried `~/Library/Application Support/com.apple.TCC/TCC.db`; `com.maxforsey.Dahso.dev` has old Microphone and AudioCapture rows with `auth_value=2`, but the wrapper marks both as stale because their cdhash-scoped `csreq` does not match the current Debug app CDHash `511467B3F88C1A0B4AD5A214FC465E5CFED95C6A`
- Wrapper help/usage check: `scripts/run-daily-driver-soak.sh --help` exits 0 and documents `soak`, `preflight`, `prompt`, `status`, `reset-tcc`, and `verify-latest`; invalid modes exit 2 with the same usage text
- Wrapper privacy status check: `scripts/run-daily-driver-soak.sh status` does not build, launch Bugbook, or open System Settings; it reports the current Debug bundle path, bundle ID `com.maxforsey.Dahso.dev`, CDHash `511467B3F88C1A0B4AD5A214FC465E5CFED95C6A`, current TCC rows, and whether cdhash-scoped rows are current or stale; it exits nonzero while Microphone or Screen/System Audio authorization is missing, denied, or stale
- Wrapper TCC reset command: `scripts/run-daily-driver-soak.sh reset-tcc` resolves the current Debug bundle ID and runs the bundle-specific `tccutil reset` calls for Microphone, AudioCapture, and ScreenCapture, then prints the same status output without building or launching Bugbook; with `BUGBOOK_DAILY_DRIVER_SOAK_DRY_RUN=1`, it prints the reset commands without executing them; latest real reset cleared the stale `com.maxforsey.Dahso.dev` rows and status now reports no rows
- Wrapper dry-run support: `BUGBOOK_DAILY_DRIVER_SOAK_DRY_RUN=1 scripts/run-daily-driver-soak.sh [mode]` prints shell-quoted `export` lines plus the delegated command without building, launching Bugbook, or opening System Settings; dry-run verified `soak` delegates to `65m Allocations` with `AUTO_STOP_RECORDING_AFTER_SECONDS=3600` and privacy panes enabled, `preflight` delegates to `10s Allocations` with `PREFLIGHT_ONLY=1` and privacy panes disabled, and `prompt` delegates to `1m Allocations` with a 30-second auto-stop and 10-second finalization buffer
- Completed-soak evidence verifier: `scripts/verify-daily-driver-soak-evidence.sh` prints the selected evidence path, then checks the generated evidence note for the required 65-minute Allocations run shape, 60-minute auto-stop, live-transcription attach, required meeting markers, signpost validation, xctrace success, app-process survival after trace, enforced Instruments/RSS targets, and absence of failure markers; it accepts `latest`/`--latest` to pick the newest `.codex/perf/bugbook-meeting-soak-allocations-*.md` note, and `scripts/run-daily-driver-soak.sh verify-latest` delegates to that path; it passes a synthetic complete 65-minute evidence note including `App process alive after trace: PASS` and exits nonzero on the current short blocked prompt artifact, as expected
- Wrapper mode validation: `BUGBOOK_PROFILE_MEMORY_TARGET_RSS_KIB=0 scripts/run-daily-driver-soak.sh`, `BUGBOOK_PROFILE_MEMORY_TARGET_RSS_KIB=0 scripts/run-daily-driver-soak.sh preflight`, and `BUGBOOK_PROFILE_MEMORY_TARGET_RSS_KIB=0 scripts/run-daily-driver-soak.sh prompt` all fail fast before build with the memory-target validation error
- Harness RSS target guard check: `BUGBOOK_PROFILE_MEMORY_TARGET_RSS_KIB=0 BUGBOOK_PROFILE_PREFLIGHT_ONLY=1 scripts/profile-meeting-soak.sh 1s Allocations` fails fast before build with `BUGBOOK_PROFILE_MEMORY_TARGET_RSS_KIB must be a positive integer KiB value.`
- Harness finalization-buffer guard check: `BUGBOOK_PROFILE_AUTO_STOP_RECORDING_AFTER_SECONDS=3900 scripts/run-daily-driver-soak.sh` fails fast before build because the auto-stop is too close to trace end; the wrapper's default `65m` trace + `3600s` auto-stop + `60s` buffer is the accepted live-soak shape

```sh
swift test
xcodebuild -project macos/Bugbook.xcodeproj -scheme BugbookApp -configuration Debug -derivedDataPath .build/xcode-derived -quiet DEVELOPMENT_TEAM=H9N9P29TX5 CODE_SIGN_IDENTITY='Apple Development' build
swiftlint lint --config .swiftlint.yml
git diff --check
zsh -n scripts/profile-meeting-soak.sh
zsh -n scripts/run-daily-driver-soak.sh
zsh -n scripts/verify-daily-driver-soak-evidence.sh
```

## Blocked Live Soak

After approving Bugbook in macOS Privacy & Security for Microphone and Screen &
System Audio Recording, rerun. The command records a 60-minute meeting inside a
65-minute Allocations trace, leaving five minutes for stop/finalize/save
markers. It fails if required meeting markers are missing, Bugbook exits during
the trace, the Instruments Allocations/Leaks summary is unavailable or over
target, RSS samples are missing, or RSS peak/growth exceeds the 200 MiB target.
It also opens the relevant privacy panes first so missing approval is visible
before the live soak starts.
The wrapper sets the required Debug signing, privacy wait, system-audio
stimulus, live-transcription attach, auto-stop, signpost, and memory-target
defaults while still allowing explicit environment overrides:

```sh
scripts/run-daily-driver-soak.sh
scripts/run-daily-driver-soak.sh verify-latest
```

The goal should not be marked complete until that run includes the required
meeting signposts and passes the RSS targets.
