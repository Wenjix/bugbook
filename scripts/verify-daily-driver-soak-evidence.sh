#!/bin/zsh
# Verify a completed Bugbook daily-driver soak evidence note.
#
# Usage:
#   scripts/verify-daily-driver-soak-evidence.sh .codex/perf/bugbook-meeting-soak-allocations-<timestamp>.md
#   scripts/verify-daily-driver-soak-evidence.sh latest

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
EVIDENCE_PATH="${1:-}"
if [[ "$EVIDENCE_PATH" == "-h" || "$EVIDENCE_PATH" == "--help" ]]; then
  echo "Usage: scripts/verify-daily-driver-soak-evidence.sh <evidence.md|latest>" >&2
  exit 0
fi
if [[ -z "$EVIDENCE_PATH" ]]; then
  echo "Usage: scripts/verify-daily-driver-soak-evidence.sh <evidence.md|latest>" >&2
  exit 2
fi

if [[ "$EVIDENCE_PATH" == "latest" || "$EVIDENCE_PATH" == "--latest" ]]; then
  latest_evidence=("$PROJECT_ROOT"/.codex/perf/bugbook-meeting-soak-allocations-*.md(N.om))
  if (( ${#latest_evidence[@]} == 0 )); then
    echo "No Bugbook meeting soak evidence notes found under .codex/perf/." >&2
    exit 2
  fi
  EVIDENCE_PATH="$latest_evidence[1]"
fi

if [[ ! -f "$EVIDENCE_PATH" ]]; then
  echo "Missing evidence file: $EVIDENCE_PATH" >&2
  exit 2
fi

echo "Verifying daily-driver soak evidence: $EVIDENCE_PATH"

missing=0
require_pattern() {
  local pattern="$1"
  local label="$2"
  if grep -Eq -- "$pattern" "$EVIDENCE_PATH"; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s\n' "$label" >&2
    missing=1
  fi
}

reject_pattern() {
  local pattern="$1"
  local label="$2"
  if grep -Eq -- "$pattern" "$EVIDENCE_PATH"; then
    printf 'FAIL %s\n' "$label" >&2
    missing=1
  else
    printf 'PASS %s\n' "$label"
  fi
}

require_pattern '^- xctrace exit: success$' 'xctrace completed successfully'
require_pattern '^- Duration: 65m$' '65-minute trace duration configured'
require_pattern '^- Template: Allocations$' 'Allocations template used'
require_pattern '^- Legacy panes: off \(BUGBOOK_LEGACY_PANES=0\)$' 'legacy panes disabled'
require_pattern '^- Attach-after marker: liveTranscriptionChunk$' 'attached after live transcription'
require_pattern '^- Auto-start meeting: 1$' 'auto-start meeting enabled'
require_pattern '^- Auto-stop recording after: 3600$' '60-minute recording auto-stop configured'
require_pattern '^- Auto-stop finalization buffer: 60$' 'finalization buffer configured'
require_pattern '^- App process alive after trace: PASS$' 'app survived trace'
require_pattern '^- meetingRecordingStart: [1-9][0-9]* \(PASS\)$' 'meeting started'
require_pattern '^- meetingMicAudioCapture: [1-9][0-9]* \(PASS\)$' 'mic audio captured'
require_pattern '^- meetingSystemAudioCapture: [1-9][0-9]* \(PASS\)$' 'system audio captured'
require_pattern '^- liveTranscriptionChunk: [1-9][0-9]* \(PASS\)$' 'live transcription chunk observed'
require_pattern '^- meetingRecordingStopFinalize: [1-9][0-9]* \(PASS\)$' 'recording finalized'
require_pattern '^- meetingTranscriptPersist: [1-9][0-9]* \(PASS\)$' 'transcript persisted'
require_pattern '^- meetingNotePersist: [1-9][0-9]* \(PASS\)$' 'meeting note persisted'
require_pattern '^- Meeting signpost validation: PASS$' 'meeting signpost gate passed'
require_pattern '^- [0-9]+(\.[0-9]+)? MiB peak RSS target: PASS$' 'peak RSS target passed'
require_pattern '^- [0-9]+(\.[0-9]+)? MiB RSS growth target: PASS$' 'RSS growth target passed'
require_pattern '^- RSS memory target enforcement: 1$' 'RSS target enforcement enabled'
require_pattern '^- Instruments memory target enforcement: 1$' 'Instruments memory target enforcement enabled'
require_pattern '^- [0-9]+(\.[0-9]+)? MiB persistent memory target: PASS$' 'Instruments persistent memory target passed'
reject_pattern '\bFAIL\b|\bMISSING\b|xctrace exit: failure' 'no failure markers remain'

if (( missing != 0 )); then
  echo "Daily-driver soak evidence verification failed: $EVIDENCE_PATH" >&2
  exit 1
fi

echo "Daily-driver soak evidence verification passed: $EVIDENCE_PATH"
