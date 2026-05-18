#!/bin/zsh
# Run the required Bugbook daily-driver meeting soak.
#
# This is a thin wrapper around profile-meeting-soak.sh. Environment variables
# set by the caller still win, but the defaults match the acceptance gate:
# a 60-minute recording inside a 65-minute Allocations trace, with privacy
# approval waiting, system-audio stimulus, live-transcription attach, required
# meeting markers, and enforced Instruments/RSS memory targets.
#
# Usage:
#   scripts/run-daily-driver-soak.sh
#   scripts/run-daily-driver-soak.sh preflight
#   scripts/run-daily-driver-soak.sh prompt
#   scripts/run-daily-driver-soak.sh status
#   scripts/run-daily-driver-soak.sh reset-tcc
#   scripts/run-daily-driver-soak.sh verify-latest
#
# Set BUGBOOK_DAILY_DRIVER_SOAK_DRY_RUN=1 to print the effective profiler
# environment and delegated command without building or launching Bugbook.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
MODE="${1:-soak}"
DRY_RUN="${BUGBOOK_DAILY_DRIVER_SOAK_DRY_RUN:-0}"

print_usage() {
  cat >&2 <<'EOF'
Usage: scripts/run-daily-driver-soak.sh [soak|preflight|prompt|status|reset-tcc|verify-latest]

Modes:
  soak       Run the required 60-minute meeting recording inside a 65-minute
             Allocations trace. Opens privacy panes, waits for approval, and
             enforces meeting markers plus Instruments/RSS memory targets.
  preflight  Build the signed Debug app and check bundle privacy/TCC state
             without launching Bugbook or opening System Settings.
  prompt     Open privacy panes and launch a one-minute recording attempt to
             create or refresh macOS Microphone and Screen/System Audio prompts.
  status     Print current Debug bundle and TCC authorization status without
             building, launching Bugbook, or opening System Settings.
  reset-tcc  Reset Microphone and Screen/System Audio TCC rows for the current
             Debug bundle. Use only when macOS has stale or denied rows.
  verify-latest
             Verify the newest Bugbook meeting soak evidence note under
             .codex/perf/.
EOF
}

case "$MODE" in
  -h|--help|help)
    print_usage
    exit 0
    ;;
esac

is_truthy() {
  case "${1:l}" in
    1|true|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

privacy_app_path() {
  local project_root
  project_root="${SCRIPT_DIR:h}"
  echo "${BUGBOOK_PROFILE_APP_PATH:-$project_root/.build/xcode-derived/Build/Products/$BUGBOOK_PROFILE_CONFIGURATION/Bugbook.app}"
}

privacy_bundle_id() {
  local app_path="$1"
  local bundle_id="${BUGBOOK_PROFILE_BUNDLE_ID:-}"
  if [[ -z "$bundle_id" && -f "$app_path/Contents/Info.plist" ]]; then
    bundle_id="$(plutil -extract CFBundleIdentifier raw "$app_path/Contents/Info.plist" 2>/dev/null || true)"
  fi
  if [[ -z "$bundle_id" ]]; then
    bundle_id="com.maxforsey.Bugbook.dev"
  fi
  echo "$bundle_id"
}

print_privacy_status() {
  local app_path bundle_id cdhash tcc_db rows microphone_status system_audio_status
  app_path="$(privacy_app_path)"
  bundle_id="$(privacy_bundle_id "$app_path")"

  cdhash=""
  if [[ -d "$app_path" ]]; then
    cdhash="$(codesign -dv --verbose=4 "$app_path" 2>&1 | awk -F= '/^CDHash=/ { value = $2 } END { print value }')"
  fi

  tcc_db="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
  rows=""
  if [[ -r "$tcc_db" ]]; then
    rows="$(sqlite3 "$tcc_db" "
      select service || char(9) || auth_value || char(9) || auth_reason || char(9) || last_modified
      from access
      where client = '$bundle_id'
        and service in ('kTCCServiceMicrophone', 'kTCCServiceAudioCapture', 'kTCCServiceScreenCapture')
      order by service;
    " 2>/dev/null || true)"
  fi

  if awk -F '\t' '$1 == "kTCCServiceMicrophone" && $2 == "2" { found = 1 } END { exit found ? 0 : 1 }' <<< "$rows"; then
    microphone_status="PASS"
  else
    microphone_status="FAIL"
  fi
  if awk -F '\t' '$1 == "kTCCServiceAudioCapture" && $2 == "2" { found = 1 } END { exit found ? 0 : 1 }' <<< "$rows" ||
     awk -F '\t' '$1 == "kTCCServiceScreenCapture" && $2 == "2" { found = 1 } END { exit found ? 0 : 1 }' <<< "$rows"; then
    system_audio_status="PASS"
  else
    system_audio_status="FAIL"
  fi

  echo "Bugbook privacy status"
  echo "- App: $app_path"
  echo "- Bundle ID: $bundle_id"
  echo "- CDHash: ${cdhash:-unavailable}"
  echo "- Microphone authorization: $microphone_status"
  echo "- Screen/System Audio authorization: $system_audio_status"
  echo "- TCC rows:"
  if [[ -n "$rows" ]]; then
    printf '%s\n' "$rows" | awk -F '\t' '{ printf "  - %s auth_value=%s auth_reason=%s last_modified=%s\n", $1, $2, $3, $4 }'
  else
    echo "  - none"
  fi

  if [[ "$microphone_status" == "PASS" && "$system_audio_status" == "PASS" ]]; then
    return 0
  fi
  echo "- Next: run scripts/run-daily-driver-soak.sh prompt and approve Bugbook in macOS Privacy & Security."
  echo "- If Bugbook is stale or denied there, run scripts/run-daily-driver-soak.sh reset-tcc first."
  return 1
}

reset_tcc_for_bundle() {
  local app_path bundle_id service
  app_path="$(privacy_app_path)"
  bundle_id="$(privacy_bundle_id "$app_path")"

  if is_truthy "$DRY_RUN"; then
    for service in Microphone AudioCapture ScreenCapture; do
      printf 'tccutil reset %q %q\n' "$service" "$bundle_id"
    done
    return
  fi

  echo "Resetting Bugbook TCC rows for $bundle_id..."
  for service in Microphone AudioCapture ScreenCapture; do
    if tccutil reset "$service" "$bundle_id" >/dev/null 2>&1; then
      echo "- $service: reset requested"
    else
      echo "- $service: no reset performed or service unavailable on this macOS version"
    fi
  done
  echo ""
  print_privacy_status || true
}

run_profiler() {
  local duration="$1"
  local template="$2"

  if is_truthy "$DRY_RUN"; then
    printf 'export BUGBOOK_PROFILE_CONFIGURATION=%q\n' "$BUGBOOK_PROFILE_CONFIGURATION"
    printf 'export BUGBOOK_PROFILE_CODE_SIGN_IDENTITY=%q\n' "$BUGBOOK_PROFILE_CODE_SIGN_IDENTITY"
    printf 'export BUGBOOK_PROFILE_DEVELOPMENT_TEAM=%q\n' "$BUGBOOK_PROFILE_DEVELOPMENT_TEAM"
    printf 'export BUGBOOK_PROFILE_AUTO_START_MEETING=%q\n' "$BUGBOOK_PROFILE_AUTO_START_MEETING"
    printf 'export BUGBOOK_PROFILE_ALLOW_PERMISSION_PROMPT=%q\n' "$BUGBOOK_PROFILE_ALLOW_PERMISSION_PROMPT"
    printf 'export BUGBOOK_PROFILE_OPEN_PRIVACY_SETTINGS=%q\n' "$BUGBOOK_PROFILE_OPEN_PRIVACY_SETTINGS"
    printf 'export BUGBOOK_PROFILE_WAIT_FOR_PRIVACY_APPROVAL=%q\n' "$BUGBOOK_PROFILE_WAIT_FOR_PRIVACY_APPROVAL"
    printf 'export BUGBOOK_PROFILE_WAIT_FOR_PRIVACY_APPROVAL_SECONDS=%q\n' "$BUGBOOK_PROFILE_WAIT_FOR_PRIVACY_APPROVAL_SECONDS"
    printf 'export BUGBOOK_PROFILE_ATTACH_AFTER_TIMEOUT_SECONDS=%q\n' "$BUGBOOK_PROFILE_ATTACH_AFTER_TIMEOUT_SECONDS"
    printf 'export BUGBOOK_PROFILE_MIC_PERMISSION_TIMEOUT_SECONDS=%q\n' "$BUGBOOK_PROFILE_MIC_PERMISSION_TIMEOUT_SECONDS"
    printf 'export BUGBOOK_PROFILE_SYSTEM_AUDIO_STIMULUS=%q\n' "$BUGBOOK_PROFILE_SYSTEM_AUDIO_STIMULUS"
    printf 'export BUGBOOK_PROFILE_SYSTEM_AUDIO_STIMULUS_SECONDS=%q\n' "$BUGBOOK_PROFILE_SYSTEM_AUDIO_STIMULUS_SECONDS"
    printf 'export BUGBOOK_PROFILE_AUTO_STOP_RECORDING_AFTER_SECONDS=%q\n' "$BUGBOOK_PROFILE_AUTO_STOP_RECORDING_AFTER_SECONDS"
    printf 'export BUGBOOK_PROFILE_AUTO_STOP_FINALIZATION_BUFFER_SECONDS=%q\n' "$BUGBOOK_PROFILE_AUTO_STOP_FINALIZATION_BUFFER_SECONDS"
    printf 'export BUGBOOK_PROFILE_ATTACH_AFTER_MARKER=%q\n' "$BUGBOOK_PROFILE_ATTACH_AFTER_MARKER"
    printf 'export BUGBOOK_REQUIRE_MEETING_SIGNPOSTS=%q\n' "$BUGBOOK_REQUIRE_MEETING_SIGNPOSTS"
    printf 'export BUGBOOK_REQUIRE_MEMORY_TARGETS=%q\n' "$BUGBOOK_REQUIRE_MEMORY_TARGETS"
    printf 'export BUGBOOK_PROFILE_PREFLIGHT_ONLY=%q\n' "${BUGBOOK_PROFILE_PREFLIGHT_ONLY:-0}"
    printf 'exec %q %q %q\n' "$SCRIPT_DIR/profile-meeting-soak.sh" "$duration" "$template"
    return
  fi

  exec "$SCRIPT_DIR/profile-meeting-soak.sh" "$duration" "$template"
}

OPEN_PRIVACY_SETTINGS_DEFAULT=1
WAIT_FOR_PRIVACY_APPROVAL_SECONDS_DEFAULT=600
ATTACH_AFTER_TIMEOUT_SECONDS_DEFAULT=900
MIC_PERMISSION_TIMEOUT_SECONDS_DEFAULT=900
SYSTEM_AUDIO_STIMULUS_SECONDS_DEFAULT=900
AUTO_STOP_RECORDING_AFTER_SECONDS_DEFAULT=3600
AUTO_STOP_FINALIZATION_BUFFER_SECONDS_DEFAULT=60
if [[ "$MODE" == "preflight" ]]; then
  OPEN_PRIVACY_SETTINGS_DEFAULT=0
fi
if [[ "$MODE" == "prompt" ]]; then
  WAIT_FOR_PRIVACY_APPROVAL_SECONDS_DEFAULT=600
  ATTACH_AFTER_TIMEOUT_SECONDS_DEFAULT=600
  MIC_PERMISSION_TIMEOUT_SECONDS_DEFAULT=600
  SYSTEM_AUDIO_STIMULUS_SECONDS_DEFAULT=600
  AUTO_STOP_RECORDING_AFTER_SECONDS_DEFAULT=30
  AUTO_STOP_FINALIZATION_BUFFER_SECONDS_DEFAULT=10
fi

export BUGBOOK_PROFILE_CONFIGURATION="${BUGBOOK_PROFILE_CONFIGURATION:-Debug}"
export BUGBOOK_PROFILE_CODE_SIGN_IDENTITY="${BUGBOOK_PROFILE_CODE_SIGN_IDENTITY:-Apple Development}"
export BUGBOOK_PROFILE_DEVELOPMENT_TEAM="${BUGBOOK_PROFILE_DEVELOPMENT_TEAM:-H9N9P29TX5}"
export BUGBOOK_PROFILE_AUTO_START_MEETING="${BUGBOOK_PROFILE_AUTO_START_MEETING:-1}"
export BUGBOOK_PROFILE_ALLOW_PERMISSION_PROMPT="${BUGBOOK_PROFILE_ALLOW_PERMISSION_PROMPT:-1}"
export BUGBOOK_PROFILE_OPEN_PRIVACY_SETTINGS="${BUGBOOK_PROFILE_OPEN_PRIVACY_SETTINGS:-$OPEN_PRIVACY_SETTINGS_DEFAULT}"
export BUGBOOK_PROFILE_WAIT_FOR_PRIVACY_APPROVAL="${BUGBOOK_PROFILE_WAIT_FOR_PRIVACY_APPROVAL:-1}"
export BUGBOOK_PROFILE_WAIT_FOR_PRIVACY_APPROVAL_SECONDS="${BUGBOOK_PROFILE_WAIT_FOR_PRIVACY_APPROVAL_SECONDS:-$WAIT_FOR_PRIVACY_APPROVAL_SECONDS_DEFAULT}"
export BUGBOOK_PROFILE_ATTACH_AFTER_TIMEOUT_SECONDS="${BUGBOOK_PROFILE_ATTACH_AFTER_TIMEOUT_SECONDS:-$ATTACH_AFTER_TIMEOUT_SECONDS_DEFAULT}"
export BUGBOOK_PROFILE_MIC_PERMISSION_TIMEOUT_SECONDS="${BUGBOOK_PROFILE_MIC_PERMISSION_TIMEOUT_SECONDS:-$MIC_PERMISSION_TIMEOUT_SECONDS_DEFAULT}"
export BUGBOOK_PROFILE_SYSTEM_AUDIO_STIMULUS="${BUGBOOK_PROFILE_SYSTEM_AUDIO_STIMULUS:-1}"
export BUGBOOK_PROFILE_SYSTEM_AUDIO_STIMULUS_SECONDS="${BUGBOOK_PROFILE_SYSTEM_AUDIO_STIMULUS_SECONDS:-$SYSTEM_AUDIO_STIMULUS_SECONDS_DEFAULT}"
export BUGBOOK_PROFILE_AUTO_STOP_RECORDING_AFTER_SECONDS="${BUGBOOK_PROFILE_AUTO_STOP_RECORDING_AFTER_SECONDS:-$AUTO_STOP_RECORDING_AFTER_SECONDS_DEFAULT}"
export BUGBOOK_PROFILE_AUTO_STOP_FINALIZATION_BUFFER_SECONDS="${BUGBOOK_PROFILE_AUTO_STOP_FINALIZATION_BUFFER_SECONDS:-$AUTO_STOP_FINALIZATION_BUFFER_SECONDS_DEFAULT}"
export BUGBOOK_PROFILE_ATTACH_AFTER_MARKER="${BUGBOOK_PROFILE_ATTACH_AFTER_MARKER:-liveTranscriptionChunk}"
export BUGBOOK_REQUIRE_MEETING_SIGNPOSTS="${BUGBOOK_REQUIRE_MEETING_SIGNPOSTS:-1}"
export BUGBOOK_REQUIRE_MEMORY_TARGETS="${BUGBOOK_REQUIRE_MEMORY_TARGETS:-1}"

case "$MODE" in
  soak)
    run_profiler 65m Allocations
    ;;
  preflight)
    export BUGBOOK_PROFILE_PREFLIGHT_ONLY=1
    run_profiler 10s Allocations
    ;;
  prompt)
    run_profiler 1m Allocations
    ;;
  status)
    print_privacy_status
    ;;
  reset-tcc)
    reset_tcc_for_bundle
    ;;
  verify-latest)
    exec "$SCRIPT_DIR/verify-daily-driver-soak-evidence.sh" latest
    ;;
  *)
    print_usage
    exit 2
    ;;
esac
