#!/bin/zsh
# Capture an Instruments trace for a manual Bugbook meeting-recording soak.
#
# Usage:
#   scripts/profile-meeting-soak.sh [duration] [template]
#
# Examples:
#   scripts/profile-meeting-soak.sh 65m Allocations
#   scripts/profile-meeting-soak.sh 10m "Time Profiler"
#   scripts/profile-meeting-soak.sh 10m Leaks
#
# For a real validation run, set BUGBOOK_REQUIRE_MEETING_SIGNPOSTS=1. That makes
# the script fail if the trace does not include the meeting start/stop/persist
# signposts emitted by the live meeting flow.
#
# Profiling runs use an isolated notes workspace by default:
#   .codex/perf/profile-workspaces/<timestamp>
# Override with BUGBOOK_PROFILE_WORKSPACE_PATH when profiling against a specific
# notes root.
#
# Heavy templates can interfere with FluidAudio/CoreML model loading when they
# attach before recording starts. Enforced automated runs wait for the first
# liveTranscriptionChunk marker by default before attaching Instruments. To set
# a different marker or disable the wait:
#
#   BUGBOOK_PROFILE_ATTACH_AFTER_MARKER=meetingRecordingActive \
#     scripts/profile-meeting-soak.sh 65m Allocations
#
#   BUGBOOK_PROFILE_ATTACH_AFTER_MARKER=none \
#     scripts/profile-meeting-soak.sh 65m Allocations
#
# To check bundle privacy declarations and current TCC authorization without
# launching Bugbook or Instruments:
#
#   BUGBOOK_PROFILE_PREFLIGHT_ONLY=1 scripts/profile-meeting-soak.sh
#
# When using BUGBOOK_PROFILE_ALLOW_PERMISSION_PROMPT=1, the harness gives the
# macOS permission prompt a longer default window before failing the run. Override
# with BUGBOOK_PROFILE_MIC_PERMISSION_TIMEOUT_SECONDS when needed.
#
# Set BUGBOOK_PROFILE_OPEN_PRIVACY_SETTINGS=1 to open the relevant macOS Privacy
# panes before launching Bugbook. This does not grant access; it only brings the
# user to the controls needed for the manual approval gate.
#
# Set BUGBOOK_PROFILE_WAIT_FOR_PRIVACY_APPROVAL=1 to poll TCC until Microphone
# is approved before launching Bugbook. Screen/System Audio is still reported
# from TCC when macOS exposes a row, but the enforced soak validates it through
# the runtime meetingSystemAudioCapture marker because macOS may not expose a
# readable user TCC row for ScreenCaptureKit audio grants.
#
# Set BUGBOOK_PROFILE_SYSTEM_AUDIO_STIMULUS=1 to play a short external system
# sound loop after launch. This gives ScreenCaptureKit a concrete non-Bugbook
# audio source to capture for the meetingSystemAudioCapture marker.
#
# For enforced automated runs, BUGBOOK_PROFILE_AUTO_STOP_RECORDING_AFTER_SECONDS
# must leave a finalization buffer before the trace ends. Override the default
# 60-second buffer with BUGBOOK_PROFILE_AUTO_STOP_FINALIZATION_BUFFER_SECONDS.
#
# Enforced automated runs also fail if Instruments/RSS samples are missing or
# if memory exceeds the default 200 MiB target. Override the target with
# BUGBOOK_PROFILE_MEMORY_TARGET_RSS_KIB, or set BUGBOOK_REQUIRE_MEMORY_TARGETS=0
# for exploratory local traces.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
DURATION="${1:-65m}"
REQUESTED_TEMPLATE="${2:-Allocations}"
REQUESTED_TEMPLATE_KEY="${REQUESTED_TEMPLATE:l}"
REQUESTED_TEMPLATE_KEY="${REQUESTED_TEMPLATE_KEY// /-}"
case "$REQUESTED_TEMPLATE_KEY" in
  allocations)
    TEMPLATE="Allocations"
    ;;
  leaks)
    TEMPLATE="Leaks"
    ;;
  time-profiler)
    TEMPLATE="Time Profiler"
    ;;
  *)
    TEMPLATE="$REQUESTED_TEMPLATE"
    ;;
esac
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
SAFE_TEMPLATE="${TEMPLATE:l}"
SAFE_TEMPLATE="${SAFE_TEMPLATE// /-}"
DERIVED_DATA="$PROJECT_ROOT/.build/xcode-derived"
PROFILE_CONFIGURATION="${BUGBOOK_PROFILE_CONFIGURATION:-Debug}"
APP_PATH="$DERIVED_DATA/Build/Products/$PROFILE_CONFIGURATION/Bugbook.app"
EXECUTABLE="$APP_PATH/Contents/MacOS/Bugbook"
OUTPUT_DIR="$PROJECT_ROOT/.codex/perf"
TRACE_PATH="$OUTPUT_DIR/bugbook-meeting-soak-${SAFE_TEMPLATE}-${STAMP}.trace"
STDOUT_PATH="$OUTPUT_DIR/bugbook-meeting-soak-${SAFE_TEMPLATE}-${STAMP}.stdout"
EVIDENCE_PATH="$OUTPUT_DIR/bugbook-meeting-soak-${SAFE_TEMPLATE}-${STAMP}.md"
MEMORY_SAMPLES_PATH="$OUTPUT_DIR/bugbook-meeting-soak-${SAFE_TEMPLATE}-${STAMP}.memory.tsv"
MARKER_PATH="$OUTPUT_DIR/bugbook-meeting-soak-${SAFE_TEMPLATE}-${STAMP}.markers"
REQUIRE_MEETING_SIGNPOSTS="${BUGBOOK_REQUIRE_MEETING_SIGNPOSTS:-0}"
ATTACH_AFTER_MARKER_RAW="${BUGBOOK_PROFILE_ATTACH_AFTER_MARKER:-}"
ATTACH_AFTER_MARKER="$ATTACH_AFTER_MARKER_RAW"
ATTACH_AFTER_TIMEOUT_SECONDS="${BUGBOOK_PROFILE_ATTACH_AFTER_TIMEOUT_SECONDS:-120}"
AUTO_STOP_RECORDING_AFTER_SECONDS="${BUGBOOK_PROFILE_AUTO_STOP_RECORDING_AFTER_SECONDS:-}"
AUTO_STOP_FINALIZATION_BUFFER_SECONDS="${BUGBOOK_PROFILE_AUTO_STOP_FINALIZATION_BUFFER_SECONDS:-60}"
AUTO_START_MEETING="${BUGBOOK_PROFILE_AUTO_START_MEETING:-0}"
ALLOW_PERMISSION_PROMPT="${BUGBOOK_PROFILE_ALLOW_PERMISSION_PROMPT:-0}"
MIC_PERMISSION_TIMEOUT_SECONDS="${BUGBOOK_PROFILE_MIC_PERMISSION_TIMEOUT_SECONDS:-}"
OPEN_PRIVACY_SETTINGS="${BUGBOOK_PROFILE_OPEN_PRIVACY_SETTINGS:-0}"
WAIT_FOR_PRIVACY_APPROVAL="${BUGBOOK_PROFILE_WAIT_FOR_PRIVACY_APPROVAL:-0}"
WAIT_FOR_PRIVACY_APPROVAL_SECONDS="${BUGBOOK_PROFILE_WAIT_FOR_PRIVACY_APPROVAL_SECONDS:-300}"
SYSTEM_AUDIO_STIMULUS="${BUGBOOK_PROFILE_SYSTEM_AUDIO_STIMULUS:-0}"
SYSTEM_AUDIO_STIMULUS_SECONDS="${BUGBOOK_PROFILE_SYSTEM_AUDIO_STIMULUS_SECONDS:-60}"
SYSTEM_AUDIO_STIMULUS_INTERVAL_SECONDS="${BUGBOOK_PROFILE_SYSTEM_AUDIO_STIMULUS_INTERVAL_SECONDS:-5}"
SYSTEM_AUDIO_STIMULUS_PATH="${BUGBOOK_PROFILE_SYSTEM_AUDIO_STIMULUS_PATH:-/System/Library/Sounds/Glass.aiff}"
MEMORY_SAMPLE_INTERVAL_SECONDS="${BUGBOOK_PROFILE_MEMORY_SAMPLE_INTERVAL_SECONDS:-5}"
MEMORY_TARGET_RSS_KIB="${BUGBOOK_PROFILE_MEMORY_TARGET_RSS_KIB:-204800}"
REQUIRE_MEMORY_TARGETS="${BUGBOOK_REQUIRE_MEMORY_TARGETS:-$REQUIRE_MEETING_SIGNPOSTS}"
LAUNCH_WITH_OPEN="${BUGBOOK_PROFILE_LAUNCH_WITH_OPEN:-1}"
PREFLIGHT_ONLY="${BUGBOOK_PROFILE_PREFLIGHT_ONLY:-0}"
PROFILE_CODE_SIGN_IDENTITY="${BUGBOOK_PROFILE_CODE_SIGN_IDENTITY:-}"
PROFILE_DEVELOPMENT_TEAM="${BUGBOOK_PROFILE_DEVELOPMENT_TEAM:-}"
PROFILE_ARCHS="${BUGBOOK_PROFILE_ARCHS:-}"
PROFILE_ONLY_ACTIVE_ARCH="${BUGBOOK_PROFILE_ONLY_ACTIVE_ARCH:-}"
PROFILE_WORKSPACE_PATH="${BUGBOOK_PROFILE_WORKSPACE_PATH:-$OUTPUT_DIR/profile-workspaces/$STAMP}"
if [[ "$PROFILE_WORKSPACE_PATH" != /* ]]; then
  PROFILE_WORKSPACE_PATH="$PROJECT_ROOT/$PROFILE_WORKSPACE_PATH"
fi
case "${ALLOW_PERMISSION_PROMPT:l}" in
  1|true|yes|on)
    if [[ -z "$MIC_PERMISSION_TIMEOUT_SECONDS" ]]; then
      MIC_PERMISSION_TIMEOUT_SECONDS="180"
    fi
    if [[ -z "${BUGBOOK_PROFILE_ATTACH_AFTER_TIMEOUT_SECONDS:-}" ]]; then
      ATTACH_AFTER_TIMEOUT_SECONDS="240"
    fi
    ;;
esac
PROFILE_ENV_SET=0
APP_PID=""
MEMORY_SAMPLER_PID=""
SYSTEM_AUDIO_STIMULUS_PID=""
MEETING_SIGNPOSTS=(
  meetingRecordingStart
  meetingMicAudioCapture
  meetingSystemAudioCapture
  liveTranscriptionChunk
  meetingRecordingStopFinalize
  meetingTranscriptPersist
  meetingNotePersist
)

case "${ATTACH_AFTER_MARKER:l}" in
  none|off|false|0)
    ATTACH_AFTER_MARKER=""
    ;;
  "")
    if [[ "$REQUIRE_MEETING_SIGNPOSTS" == "1" && "$AUTO_START_MEETING" == "1" ]]; then
      ATTACH_AFTER_MARKER="liveTranscriptionChunk"
    fi
    ;;
esac

xml_value() {
  local xml="$1"
  local tag="$2"
  perl -ne "if (/<$tag>([^<]*)<\\/$tag>/) { print \$1; exit }" <<< "$xml"
}

regex_count() {
  local text="$1"
  local pattern="$2"
  perl -0ne "\$count = () = /$pattern/g; print \$count || 0" <<< "$text"
}

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

duration_to_seconds() {
  local value="$1"
  perl -e '
    my $value = shift // "";
    if ($value =~ /\A([0-9]+(?:\.[0-9]+)?)([smh]?)\z/i) {
      my ($amount, $unit) = ($1, lc($2 || "s"));
      my %scale = (s => 1, m => 60, h => 3600);
      print int(($amount * $scale{$unit}) + 0.5);
    }
  ' "$value"
}

validate_soak_timing() {
  if [[ "$REQUIRE_MEETING_SIGNPOSTS" != "1" || -z "$AUTO_STOP_RECORDING_AFTER_SECONDS" ]]; then
    return
  fi

  local duration_seconds auto_stop_seconds buffer_seconds latest_auto_stop
  duration_seconds="$(duration_to_seconds "$DURATION")"
  auto_stop_seconds="$(duration_to_seconds "$AUTO_STOP_RECORDING_AFTER_SECONDS")"
  buffer_seconds="$(duration_to_seconds "$AUTO_STOP_FINALIZATION_BUFFER_SECONDS")"

  if [[ -z "$duration_seconds" || -z "$auto_stop_seconds" || -z "$buffer_seconds" ]]; then
    echo "Unable to validate enforced soak timing. Use numeric durations with optional s/m/h suffixes." >&2
    return 1
  fi
  if (( buffer_seconds < 0 )); then
    echo "BUGBOOK_PROFILE_AUTO_STOP_FINALIZATION_BUFFER_SECONDS must be non-negative." >&2
    return 1
  fi

  latest_auto_stop=$(( duration_seconds - buffer_seconds ))
  if (( latest_auto_stop < 1 )); then
    echo "The requested duration '$DURATION' is too short for a ${buffer_seconds}s finalization buffer." >&2
    return 1
  fi
  if (( auto_stop_seconds > latest_auto_stop )); then
    echo "Enforced soak auto-stop is too close to trace end." >&2
    echo "Duration: ${duration_seconds}s; auto-stop: ${auto_stop_seconds}s; required finalization buffer: ${buffer_seconds}s." >&2
    echo "Lower BUGBOOK_PROFILE_AUTO_STOP_RECORDING_AFTER_SECONDS to ${latest_auto_stop}s or increase the trace duration." >&2
    return 1
  fi
}

validate_memory_target() {
  if [[ "$MEMORY_TARGET_RSS_KIB" != <-> ]]; then
    echo "BUGBOOK_PROFILE_MEMORY_TARGET_RSS_KIB must be a positive integer KiB value." >&2
    return 1
  fi
  if (( MEMORY_TARGET_RSS_KIB <= 0 )); then
    echo "BUGBOOK_PROFILE_MEMORY_TARGET_RSS_KIB must be a positive integer KiB value." >&2
    return 1
  fi
}

append_run_summary() {
  local toc
  toc="$(xcrun xctrace export --input "$TRACE_PATH" --toc 2>/dev/null || true)"
  if [[ -z "$toc" ]]; then
    echo "- Trace table of contents: unavailable from xctrace export" >> "$EVIDENCE_PATH"
    return
  fi

  local start_date end_date actual_duration end_reason template_name time_limit process_status process_reason
  start_date="$(xml_value "$toc" "start-date")"
  end_date="$(xml_value "$toc" "end-date")"
  actual_duration="$(xml_value "$toc" "duration")"
  end_reason="$(xml_value "$toc" "end-reason")"
  template_name="$(xml_value "$toc" "template-name")"
  time_limit="$(xml_value "$toc" "time-limit")"
  process_status="$(perl -ne 'if (/return-exit-status="([^"]*)"/) { print $1; exit }' <<< "$toc")"
  process_reason="$(perl -ne 'if (/termination-reason="([^"]*)"/) { print $1; exit }' <<< "$toc")"

  {
    echo ""
    echo "## Trace Run Summary"
    echo ""
    echo "- xctrace template: ${template_name:-unknown}"
    echo "- Requested time limit: ${time_limit:-unknown}"
    echo "- Actual trace duration: ${actual_duration:-unknown} seconds"
    echo "- Start date: ${start_date:-unknown}"
    echo "- End date: ${end_date:-unknown}"
    echo "- End reason: ${end_reason:-unknown}"
    echo "- Profiled process exit status: ${process_status:-unknown}"
    echo "- Profiled process termination reason: ${process_reason:-unknown}"
  } >> "$EVIDENCE_PATH"
}

append_meeting_signpost_summary() {
  local signpost_rows signpost_interval_rows roi_rows stdout_markers marker_file_markers combined
  signpost_rows="$(xcrun xctrace export \
    --input "$TRACE_PATH" \
    --xpath '//table[@schema="os-signpost"]/row' \
    2>/dev/null || true)"
  signpost_interval_rows="$(xcrun xctrace export \
    --input "$TRACE_PATH" \
    --xpath '//table[@schema="os-signpost-interval"]/row' \
    2>/dev/null || true)"
  roi_rows="$(xcrun xctrace export \
    --input "$TRACE_PATH" \
    --xpath '//table[@schema="region-of-interest"]/row' \
    2>/dev/null || true)"
  stdout_markers="$(grep 'BUGBOOK_PROFILE_MARKER' "$STDOUT_PATH" 2>/dev/null || true)"
  marker_file_markers="$(grep 'BUGBOOK_PROFILE_MARKER' "$MARKER_PATH" 2>/dev/null || true)"
  combined="${signpost_rows}${signpost_interval_rows}${roi_rows}${stdout_markers}${marker_file_markers}"

  local missing_required=0
  {
    echo ""
    echo "## Meeting Flow Signposts"
    echo ""
    echo "- Required signpost gate: ${REQUIRE_MEETING_SIGNPOSTS}"
    echo "- Marker sources: xctrace os-signpost/os-signpost-interval/ROI plus BUGBOOK_PROFILE_MARKER stdout/marker-file fallback"
  } >> "$EVIDENCE_PATH"

  local signpost signpost_count signpost_status
  for signpost in "${MEETING_SIGNPOSTS[@]}"; do
    signpost_count="$(regex_count "$combined" "$signpost")"
    if (( signpost_count > 0 )); then
      signpost_status="PASS"
    else
      signpost_status="MISSING"
      if [[ "$REQUIRE_MEETING_SIGNPOSTS" == "1" ]]; then
        missing_required=1
      fi
    fi
    echo "- ${signpost}: ${signpost_count} (${signpost_status})" >> "$EVIDENCE_PATH"
  done

  if [[ "$REQUIRE_MEETING_SIGNPOSTS" == "1" ]]; then
    if (( missing_required == 0 )); then
      echo "- Meeting signpost validation: PASS" >> "$EVIDENCE_PATH"
    else
      echo "- Meeting signpost validation: FAIL" >> "$EVIDENCE_PATH"
      return 1
    fi
  else
    echo "- Meeting signpost validation: not enforced for this run" >> "$EVIDENCE_PATH"
  fi
}

marker_timestamp() {
  local marker="$1"
  grep "BUGBOOK_PROFILE_MARKER ${marker} " "$MARKER_PATH" 2>/dev/null \
    | tail -n 1 \
    | awk '{ print $3 }'
}

append_startup_marker_summary() {
  local lifecycle_start workspace_finalized lifecycle_complete
  lifecycle_start="$(marker_timestamp appInitialLifecycleStart)"
  workspace_finalized="$(marker_timestamp workspaceStartupFinalized)"
  lifecycle_complete="$(marker_timestamp appInitialLifecycleComplete)"

  {
    echo ""
    echo "## Startup Marker Summary"
    echo ""
    echo "- Marker source: $MARKER_PATH"
    echo "- appInitialLifecycleStart: ${lifecycle_start:-missing}"
    echo "- workspaceStartupFinalized: ${workspace_finalized:-missing}"
    echo "- appInitialLifecycleComplete: ${lifecycle_complete:-missing}"
  } >> "$EVIDENCE_PATH"

  if [[ -n "$lifecycle_start" && -n "$workspace_finalized" ]]; then
    local workspace_ms workspace_status
    workspace_ms="$(awk "BEGIN { printf \"%.1f\", ($workspace_finalized - $lifecycle_start) * 1000 }")"
    if awk "BEGIN { exit !($workspace_ms <= 500) }"; then
      workspace_status="PASS"
    else
      workspace_status="FAIL"
    fi
    echo "- Lifecycle start to workspace finalized: ${workspace_ms} ms (${workspace_status} for 500 ms target)" \
      >> "$EVIDENCE_PATH"
  else
    echo "- Lifecycle start to workspace finalized: unavailable" >> "$EVIDENCE_PATH"
  fi

  if [[ -n "$lifecycle_start" && -n "$lifecycle_complete" ]]; then
    local lifecycle_ms lifecycle_status
    lifecycle_ms="$(awk "BEGIN { printf \"%.1f\", ($lifecycle_complete - $lifecycle_start) * 1000 }")"
    if awk "BEGIN { exit !($lifecycle_ms <= 500) }"; then
      lifecycle_status="PASS"
    else
      lifecycle_status="FAIL"
    fi
    echo "- Lifecycle start to lifecycle complete: ${lifecycle_ms} ms (${lifecycle_status} for 500 ms target)" \
      >> "$EVIDENCE_PATH"
  else
    echo "- Lifecycle start to lifecycle complete: unavailable" >> "$EVIDENCE_PATH"
  fi

  echo "- Note: these markers measure app lifecycle work after process start; use Instruments launch profiling for full cold-launch timing." \
    >> "$EVIDENCE_PATH"
}

append_trace_summary() {
  local summary_template="${TEMPLATE:l}"
  case "$summary_template" in
    allocations)
      local xml
      xml="$(xcrun xctrace export \
        --input "$TRACE_PATH" \
        --xpath '/trace-toc/run[@number="1"]/tracks/track[@name="Allocations"]/details/detail[@name="Statistics"]' \
        2>/dev/null || true)"
      local parsed
      parsed="$(perl -ne '
        if (/category="All Heap &amp; Anonymous VM"[^>]*persistent-bytes="([0-9]+)"[^>]*total-bytes="([0-9]+)"[^>]*transient-bytes="([0-9]+)"[^>]*count-total="([0-9]+)"/) {
          print "$1\t$2\t$3\t$4\n";
          exit;
        }
      ' <<< "$xml")"
      if [[ -n "$parsed" ]]; then
        local persistent total transient count
        IFS=$'\t' read -r persistent total transient count <<< "$parsed"
        local persistent_mib total_mib transient_mib target_mib target_bytes
        persistent_mib="$(awk "BEGIN { printf \"%.3f\", $persistent / 1048576 }")"
        total_mib="$(awk "BEGIN { printf \"%.3f\", $total / 1048576 }")"
        transient_mib="$(awk "BEGIN { printf \"%.3f\", $transient / 1048576 }")"
        target_mib="$(awk "BEGIN { printf \"%.1f\", $MEMORY_TARGET_RSS_KIB / 1024 }")"
        target_bytes=$(( MEMORY_TARGET_RSS_KIB * 1024 ))
        local memory_target_status
        if (( persistent <= target_bytes )); then
          memory_target_status="PASS"
        else
          memory_target_status="FAIL"
        fi
        {
          echo ""
          echo "## Allocation Summary"
          echo ""
          echo "- All Heap & Anonymous VM persistent: ${persistent_mib} MiB (${persistent} bytes)"
          echo "- All Heap & Anonymous VM total: ${total_mib} MiB (${total} bytes)"
          echo "- All Heap & Anonymous VM transient: ${transient_mib} MiB (${transient} bytes)"
          echo "- Allocation rows counted by Instruments: ${count}"
          echo "- ${target_mib} MiB persistent memory target: ${memory_target_status}"
          echo "- Instruments memory target enforcement: ${REQUIRE_MEMORY_TARGETS}"
        } >> "$EVIDENCE_PATH"
        if is_truthy "$REQUIRE_MEMORY_TARGETS" && [[ "$memory_target_status" != "PASS" ]]; then
          return 1
        fi
      else
        echo "- Allocation summary: unavailable from xctrace export" >> "$EVIDENCE_PATH"
        if is_truthy "$REQUIRE_MEMORY_TARGETS"; then
          return 1
        fi
      fi
      ;;
    leaks)
      local xml
      xml="$(xcrun xctrace export \
        --input "$TRACE_PATH" \
        --xpath '/trace-toc/run[@number="1"]/tracks/track[@name="Leaks"]/details/detail[@name="Leaks"]' \
        2>/dev/null || true)"
      local leak_count
      leak_count="$(perl -ne '$count += () = /<row\b/g; END { print $count || 0 }' <<< "$xml")"
      local leak_target_status
      if (( leak_count == 0 )); then
        leak_target_status="PASS"
      else
        leak_target_status="FAIL"
      fi
      {
        echo ""
        echo "## Leaks Summary"
        echo ""
        echo "- Leak rows counted by Instruments: ${leak_count}"
        echo "- Zero leak target: ${leak_target_status}"
        echo "- Instruments leak target enforcement: ${REQUIRE_MEMORY_TARGETS}"
      } >> "$EVIDENCE_PATH"
      if is_truthy "$REQUIRE_MEMORY_TARGETS" && [[ "$leak_target_status" != "PASS" ]]; then
        return 1
      fi
      ;;
    *)
      echo "- Automatic summary: not available for template '$TEMPLATE'" >> "$EVIDENCE_PATH"
      ;;
  esac
}

append_memory_summary() {
  if [[ ! -s "$MEMORY_SAMPLES_PATH" ]]; then
    echo "- RSS memory summary: unavailable; no samples written" >> "$EVIDENCE_PATH"
    if is_truthy "$REQUIRE_MEMORY_TARGETS"; then
      return 1
    fi
    return
  fi

  local parsed
  parsed="$(awk -F '\t' '
    NR == 2 {
      first = $2
      last = $2
      max = $2
      count = 1
      next
    }
    NR > 2 {
      last = $2
      if ($2 > max) { max = $2 }
      count++
    }
    END {
      if (count > 0) {
        printf "%d\t%d\t%d\t%d\n", first, last, max, count
      }
    }
  ' "$MEMORY_SAMPLES_PATH")"

  if [[ -z "$parsed" ]]; then
    echo "- RSS memory summary: unavailable; no numeric samples found" >> "$EVIDENCE_PATH"
    if is_truthy "$REQUIRE_MEMORY_TARGETS"; then
      return 1
    fi
    return
  fi

  local first_rss last_rss max_rss sample_count
  IFS=$'\t' read -r first_rss last_rss max_rss sample_count <<< "$parsed"
  local first_mib last_mib max_mib delta_mib target_mib peak_status growth_status
  first_mib="$(awk "BEGIN { printf \"%.1f\", $first_rss / 1024 }")"
  last_mib="$(awk "BEGIN { printf \"%.1f\", $last_rss / 1024 }")"
  max_mib="$(awk "BEGIN { printf \"%.1f\", $max_rss / 1024 }")"
  delta_mib="$(awk "BEGIN { printf \"%.1f\", ($last_rss - $first_rss) / 1024 }")"
  target_mib="$(awk "BEGIN { printf \"%.1f\", $MEMORY_TARGET_RSS_KIB / 1024 }")"
  if (( max_rss <= MEMORY_TARGET_RSS_KIB )); then
    peak_status="PASS"
  else
    peak_status="FAIL"
  fi
  if (( last_rss - first_rss <= MEMORY_TARGET_RSS_KIB )); then
    growth_status="PASS"
  else
    growth_status="FAIL"
  fi

  {
    echo ""
    echo "## RSS Memory Samples"
    echo ""
    echo "- Samples: ${sample_count}"
    echo "- Sample interval: ${MEMORY_SAMPLE_INTERVAL_SECONDS}s"
    echo "- Samples path: ${MEMORY_SAMPLES_PATH}"
    echo "- First RSS: ${first_mib} MiB"
    echo "- Last RSS: ${last_mib} MiB"
    echo "- Peak RSS: ${max_mib} MiB"
    echo "- RSS delta: ${delta_mib} MiB"
    echo "- ${target_mib} MiB peak RSS target: ${peak_status}"
    echo "- ${target_mib} MiB RSS growth target: ${growth_status}"
    echo "- RSS memory target enforcement: ${REQUIRE_MEMORY_TARGETS}"
  } >> "$EVIDENCE_PATH"

  if is_truthy "$REQUIRE_MEMORY_TARGETS" && [[ "$peak_status" != "PASS" || "$growth_status" != "PASS" ]]; then
    return 1
  fi
}

append_permission_diagnostics() {
  local reason="$1"
  local bundle_id cdhash designated_requirement tcc_db tcc_rows related_tcc_rows marker_rows
  bundle_id="$(plutil -extract CFBundleIdentifier raw "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
  cdhash="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 | awk -F= '/^CDHash=/ { value = $2 } END { print value }')"
  designated_requirement="$(codesign -dr - "$APP_PATH" 2>&1 | sed -n 's/^designated => //p')"
  tcc_db="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
  marker_rows="$(grep 'BUGBOOK_PROFILE_MARKER' "$MARKER_PATH" 2>/dev/null || true)"

  {
    echo ""
    echo "## Permission Diagnostics"
    echo ""
    echo "- Reason: ${reason}"
    echo "- App bundle ID: ${bundle_id:-unknown}"
    echo "- Current CDHash: ${cdhash:-unknown}"
    echo "- Current designated requirement: ${designated_requirement:-unknown}"
    echo "- Permission marker rows:"
    if [[ -n "$marker_rows" ]]; then
      sed 's/^/  - /' <<< "$marker_rows"
    else
      echo "  - none"
    fi
  } >> "$EVIDENCE_PATH"

  if [[ -n "$bundle_id" && -r "$tcc_db" ]]; then
    tcc_rows="$(sqlite3 "$tcc_db" "
      select service || char(9) || auth_value || char(9) || auth_reason || char(9) || last_modified || char(9) || hex(csreq)
      from access
      where client = '$bundle_id'
        and service in ('kTCCServiceMicrophone', 'kTCCServiceAudioCapture', 'kTCCServiceScreenCapture')
      order by service;
    " 2>/dev/null || true)"
    {
      echo "- TCC rows for microphone/screen/system audio:"
      if [[ -n "$tcc_rows" ]]; then
        echo "  - Columns: service, auth_value, auth_reason, last_modified, csreq_hex"
        while IFS=$'\t' read -r service auth_value auth_reason last_modified csreq_hex; do
          [[ -z "$service" ]] && continue
          echo "  - ${service}: auth_value=${auth_value:-unknown}, auth_reason=${auth_reason:-unknown}, last_modified=${last_modified:-unknown}, csreq_hex=${csreq_hex:-unknown}"
        done <<< "$tcc_rows"
      else
        echo "  - none"
      fi
    } >> "$EVIDENCE_PATH"
  else
    echo "- TCC rows for microphone/screen/system audio: unavailable" >> "$EVIDENCE_PATH"
  fi

  if [[ -r "$tcc_db" ]]; then
    related_tcc_rows="$(sqlite3 "$tcc_db" "
      select client || char(9) || service || char(9) || auth_value || char(9) || auth_reason || char(9) || last_modified || char(9) || hex(csreq)
      from access
      where client in ('com.maxforsey.Bugbook', 'com.maxforsey.Bugbook.dev', 'com.maxforsey.Dahso.dev')
        and service in ('kTCCServiceMicrophone', 'kTCCServiceAudioCapture', 'kTCCServiceScreenCapture')
      order by client, service;
    " 2>/dev/null || true)"
    {
      echo "- Related Bugbook TCC rows:"
      if [[ -n "$related_tcc_rows" ]]; then
        echo "  - Columns: client, service, auth_value, auth_reason, last_modified, csreq_hex"
        while IFS=$'\t' read -r client service auth_value auth_reason last_modified csreq_hex; do
          [[ -z "$client" ]] && continue
          echo "  - ${client} ${service}: auth_value=${auth_value:-unknown}, auth_reason=${auth_reason:-unknown}, last_modified=${last_modified:-unknown}, csreq_hex=${csreq_hex:-unknown}"
        done <<< "$related_tcc_rows"
      else
        echo "  - none"
      fi
    } >> "$EVIDENCE_PATH"
  fi

  {
    echo "- If the marker list includes meetingMicPermissionUnavailable, grant Microphone permission to ${bundle_id:-Bugbook} and rerun with BUGBOOK_PROFILE_ALLOW_PERMISSION_PROMPT=1 if macOS needs to refresh the prompt."
    echo "- If the marker list includes meetingMicPermissionTimedOut, the prompt was not answered before the app-side timeout; approve Bugbook in System Settings > Privacy & Security > Microphone, then rerun. Override BUGBOOK_PROFILE_MIC_PERMISSION_TIMEOUT_SECONDS if you need a longer prompt window."
    echo "- Meeting capture also needs system-audio permission via ScreenCaptureKit; approve Screen & System Audio Recording if macOS prompts for it."
    echo "- To open the relevant panes automatically before the next prompt run, add BUGBOOK_PROFILE_OPEN_PRIVACY_SETTINGS=1."
    echo "- macOS may keep stale TCC code requirements after repeated debug signing; reset and re-approve Microphone and Screen & System Audio Recording if TCC rows are allowed but Bugbook still reports permission unavailable."
    if [[ -n "$bundle_id" ]]; then
      echo "- Bundle-specific TCC reset commands for stale debug-signing rows:"
      echo "  \`\`\`sh"
      echo "  tccutil reset Microphone $bundle_id"
      echo "  tccutil reset AudioCapture $bundle_id"
      echo "  tccutil reset ScreenCapture $bundle_id"
      echo "  \`\`\`"
    fi
  } >> "$EVIDENCE_PATH"
}

open_privacy_settings_panes() {
  if ! is_truthy "$OPEN_PRIVACY_SETTINGS"; then
    return
  fi

  echo "Opening macOS Privacy settings panes for Microphone and Screen/System Audio..."
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone" 2>/dev/null || true
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture" 2>/dev/null || \
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" 2>/dev/null || \
    open "x-apple.systempreferences:com.apple.preference.security?Privacy" 2>/dev/null || true
}

append_bundle_privacy_summary() {
  local bundle_id microphone_usage audio_usage audio_entitlement
  bundle_id="$(plutil -extract CFBundleIdentifier raw "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
  microphone_usage="$(plutil -extract NSMicrophoneUsageDescription raw "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
  audio_usage="$(plutil -extract NSAudioCaptureUsageDescription raw "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
  audio_entitlement="$(codesign -d --entitlements :- "$APP_PATH" 2>/dev/null \
    | plutil -p - 2>/dev/null \
    | awk -F'=> ' '/com\.apple\.security\.device\.audio-input/ { gsub(/"/, "", $2); print $2; exit }')"

  {
    echo ""
    echo "## Bundle Privacy Summary"
    echo ""
    echo "- Bundle ID: ${bundle_id:-missing}"
    echo "- NSMicrophoneUsageDescription: ${microphone_usage:+present}"
    echo "- NSAudioCaptureUsageDescription: ${audio_usage:+present}"
    echo "- com.apple.security.device.audio-input entitlement: ${audio_entitlement:-missing}"
  } >> "$EVIDENCE_PATH"
}

bundle_privacy_gate_status() {
  local microphone_usage audio_usage audio_entitlement
  microphone_usage="$(plutil -extract NSMicrophoneUsageDescription raw "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
  audio_usage="$(plutil -extract NSAudioCaptureUsageDescription raw "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
  audio_entitlement="$(codesign -d --entitlements :- "$APP_PATH" 2>/dev/null \
    | plutil -p - 2>/dev/null \
    | awk -F'=> ' '/com\.apple\.security\.device\.audio-input/ { gsub(/"/, "", $2); print $2; exit }')"

  if [[ -n "$microphone_usage" && -n "$audio_usage" && "$audio_entitlement" == "true" ]]; then
    echo "PASS"
  else
    echo "FAIL"
  fi
}

tcc_rows_for_current_bundle() {
  local bundle_id tcc_db
  bundle_id="$(plutil -extract CFBundleIdentifier raw "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
  tcc_db="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
  if [[ -z "$bundle_id" || ! -r "$tcc_db" ]]; then
    return
  fi
  sqlite3 "$tcc_db" "
    select service || char(9) || auth_value || char(9) || hex(csreq)
    from access
    where client = '$bundle_id'
      and service in ('kTCCServiceMicrophone', 'kTCCServiceAudioCapture', 'kTCCServiceScreenCapture')
    order by service;
  " 2>/dev/null || true
}

current_app_cdhash() {
  if [[ -d "$APP_PATH" ]]; then
    codesign -dv --verbose=4 "$APP_PATH" 2>&1 | awk -F= '/^CDHash=/ { value = toupper($2) } END { print value }'
  fi
}

has_authorized_tcc_row() {
  local rows="$1"
  local service="$2"
  local cdhash
  cdhash="$(current_app_cdhash)"
  awk -F '\t' -v service="$service" -v cdhash="$cdhash" '
    function is_cdhash_scoped(csreq) {
      return length(csreq) == 80 && substr(csreq, 1, 40) == "FADE0C0000000028000000010000000800000014"
    }
    $1 == service && $2 == "2" {
      if ($3 == "" || !is_cdhash_scoped($3) || (cdhash != "" && index(toupper($3), cdhash) > 0)) {
        found = 1
      }
    }
    END { exit found ? 0 : 1 }
  ' <<< "$rows"
}

has_tcc_row_for_service() {
  local rows="$1"
  local service="$2"
  awk -F '\t' -v service="$service" '
    $1 == service { found = 1 }
    END { exit found ? 0 : 1 }
  ' <<< "$rows"
}

system_audio_tcc_proxy_status() {
  local rows="$1"
  if has_authorized_tcc_row "$rows" "kTCCServiceAudioCapture" ||
     has_authorized_tcc_row "$rows" "kTCCServiceScreenCapture"; then
    echo "PASS"
  elif has_tcc_row_for_service "$rows" "kTCCServiceAudioCapture" ||
       has_tcc_row_for_service "$rows" "kTCCServiceScreenCapture"; then
    echo "FAIL"
  else
    echo "UNKNOWN"
  fi
}

required_tcc_approval_is_present() {
  local rows
  rows="$(tcc_rows_for_current_bundle)"
  has_authorized_tcc_row "$rows" "kTCCServiceMicrophone"
}

wait_for_privacy_approval_if_requested() {
  if ! is_truthy "$WAIT_FOR_PRIVACY_APPROVAL"; then
    return
  fi

  local timeout_seconds started_at now elapsed initial_rows
  initial_rows="$(tcc_rows_for_current_bundle)"
  if [[ -z "$initial_rows" ]]; then
    if is_truthy "$PREFLIGHT_ONLY"; then
      echo "No current-bundle TCC rows yet; preflight cannot confirm Microphone approval before Bugbook creates the permission prompt/list entry."
    else
      echo "No current-bundle TCC rows yet; launching Bugbook so macOS can create the permission prompt/list entry."
    fi
    return
  fi

  if ! required_tcc_approval_is_present; then
    if is_truthy "$PREFLIGHT_ONLY"; then
      echo "Current-bundle Microphone TCC row is missing, denied, or stale for this signed build."
    else
      echo "Current-bundle Microphone TCC row is missing, denied, or stale; launching Bugbook so macOS can create or refresh the permission prompt/list entry."
    fi
    return
  fi

  timeout_seconds="${WAIT_FOR_PRIVACY_APPROVAL_SECONDS:-300}"
  started_at="$(date +%s)"
  echo "Waiting up to ${timeout_seconds}s for Microphone approval..."

  while true; do
    if required_tcc_approval_is_present; then
      echo "Observed required Bugbook Microphone approval."
      echo "Screen/System Audio TCC rows are advisory; runtime capture is enforced by the meetingSystemAudioCapture marker."
      return
    fi

    now="$(date +%s)"
    elapsed=$(( now - started_at ))
    if (( elapsed >= timeout_seconds )); then
      echo "Timed out waiting for Microphone approval." >&2
      return 1
    fi

    sleep 2
  done
}

start_system_audio_stimulus_if_requested() {
  if ! is_truthy "$SYSTEM_AUDIO_STIMULUS"; then
    return
  fi

  if ! command -v afplay >/dev/null 2>&1; then
    echo "System audio stimulus requested, but afplay is unavailable." >&2
    return 1
  fi

  if [[ ! -f "$SYSTEM_AUDIO_STIMULUS_PATH" ]]; then
    echo "System audio stimulus requested, but sound file is missing: $SYSTEM_AUDIO_STIMULUS_PATH" >&2
    return 1
  fi

  local duration_seconds interval_seconds stimulus_end_at
  duration_seconds="${SYSTEM_AUDIO_STIMULUS_SECONDS%.*}"
  interval_seconds="${SYSTEM_AUDIO_STIMULUS_INTERVAL_SECONDS%.*}"
  if [[ "$duration_seconds" != <-> || "$duration_seconds" -le 0 ]]; then
    duration_seconds=60
  fi
  if [[ "$interval_seconds" != <-> || "$interval_seconds" -le 0 ]]; then
    interval_seconds=5
  fi

  echo "Playing system audio stimulus for ${duration_seconds}s from $SYSTEM_AUDIO_STIMULUS_PATH..."
  stimulus_end_at=$(( $(date +%s) + duration_seconds ))
  (
    while (( $(date +%s) < stimulus_end_at )); do
      afplay "$SYSTEM_AUDIO_STIMULUS_PATH" >/dev/null 2>&1 || true
      sleep "$interval_seconds"
    done
  ) &
  SYSTEM_AUDIO_STIMULUS_PID=$!
}

run_preflight_only() {
  : > "$STDOUT_PATH"
  : > "$MARKER_PATH"
  cat > "$EVIDENCE_PATH" <<EOF
# Bugbook Meeting Soak Preflight

- Started: $STAMP
- Configuration: $PROFILE_CONFIGURATION
- App: $APP_PATH
- Code signing identity override: ${PROFILE_CODE_SIGN_IDENTITY:-none}
- Development team override: ${PROFILE_DEVELOPMENT_TEAM:-none}
- Open privacy settings: ${OPEN_PRIVACY_SETTINGS}
- Wait for privacy approval: ${WAIT_FOR_PRIVACY_APPROVAL}
- Privacy approval wait timeout: ${WAIT_FOR_PRIVACY_APPROVAL_SECONDS}s
- System audio stimulus: ${SYSTEM_AUDIO_STIMULUS}
- System audio stimulus duration: ${SYSTEM_AUDIO_STIMULUS_SECONDS}s
- System audio stimulus interval: ${SYSTEM_AUDIO_STIMULUS_INTERVAL_SECONDS}s
- System audio stimulus path: ${SYSTEM_AUDIO_STIMULUS_PATH}

EOF

  append_bundle_privacy_summary
  append_permission_diagnostics "Preflight-only privacy check"

  local tcc_rows bundle_status microphone_status system_audio_status overall_status
  bundle_status="$(bundle_privacy_gate_status)"
  tcc_rows="$(tcc_rows_for_current_bundle)"
  if has_authorized_tcc_row "$tcc_rows" "kTCCServiceMicrophone"; then
    microphone_status="PASS"
  else
    microphone_status="FAIL"
  fi
  system_audio_status="$(system_audio_tcc_proxy_status "$tcc_rows")"

  if [[ "$bundle_status" == "PASS" && "$microphone_status" == "PASS" && "$system_audio_status" != "FAIL" ]]; then
    overall_status="PASS"
  else
    overall_status="FAIL"
  fi

  {
    echo ""
    echo "## Preflight Gate"
    echo ""
    echo "- Bundle privacy declarations: ${bundle_status}"
    echo "- Microphone authorization: ${microphone_status}"
    echo "- Screen/System Audio TCC DB proxy: ${system_audio_status}"
    echo "- Screen/System Audio runtime gate: meetingSystemAudioCapture required in enforced soak"
    if [[ "$system_audio_status" == "UNKNOWN" ]]; then
      echo "- Screen/System Audio note: no readable user TCC row; macOS may grant ScreenCaptureKit audio without exposing one."
    fi
    echo "- Overall preflight: ${overall_status}"
  } >> "$EVIDENCE_PATH"

  echo "Preflight evidence note written to $EVIDENCE_PATH"
  if [[ "$overall_status" != "PASS" ]]; then
    echo "Preflight failed: approve Microphone and resolve denied or stale Screen/System Audio rows for the Debug bundle, then rerun." >&2
    return 1
  fi
}

sample_memory_until_exit() {
  echo "epoch_seconds	rss_kib" > "$MEMORY_SAMPLES_PATH"
  while kill -0 "$APP_PID" 2>/dev/null; do
    local rss
    rss="$(ps -o rss= -p "$APP_PID" 2>/dev/null | tr -d ' ' || true)"
    if [[ -n "$rss" ]]; then
      printf "%s\t%s\n" "$(date +%s)" "$rss" >> "$MEMORY_SAMPLES_PATH"
    fi
    sleep "$MEMORY_SAMPLE_INTERVAL_SECONDS"
  done
}

wait_for_profile_marker() {
  local marker="$1"
  local timeout_seconds="$2"
  local started_at now elapsed
  started_at="$(date +%s)"

  echo "Waiting up to ${timeout_seconds}s for BUGBOOK_PROFILE_MARKER ${marker} before attaching $TEMPLATE..."
  while true; do
    if grep -q "BUGBOOK_PROFILE_MARKER ${marker}" "$STDOUT_PATH" 2>/dev/null ||
       grep -q "BUGBOOK_PROFILE_MARKER ${marker}" "$MARKER_PATH" 2>/dev/null; then
      echo "Observed BUGBOOK_PROFILE_MARKER ${marker}; attaching $TEMPLATE now."
      return 0
    fi

    if ! kill -0 "$APP_PID" 2>/dev/null; then
      echo "Bugbook exited before marker '${marker}' was observed. See $STDOUT_PATH" >&2
      return 1
    fi

    now="$(date +%s)"
    elapsed=$(( now - started_at ))
    if (( elapsed >= timeout_seconds )); then
      echo "Timed out waiting for marker '${marker}'. See $STDOUT_PATH" >&2
      return 1
    fi

    sleep 1
  done
}

set_profile_launch_env() {
  launchctl setenv BUGBOOK_LEGACY_PANES 0
  launchctl setenv BUGBOOK_PROFILE_MARKERS 1
  launchctl setenv BUGBOOK_PROFILE_MARKER_FILE "$MARKER_PATH"
  launchctl setenv BUGBOOK_DISABLE_SENTRY 1
  launchctl setenv BUGBOOK_SKIP_KEYCHAIN_SECRETS 1
  launchctl setenv BUGBOOK_PROFILE_AUTO_START_MEETING "$AUTO_START_MEETING"
  launchctl setenv BUGBOOK_PROFILE_AUTO_STOP_RECORDING_AFTER_SECONDS "$AUTO_STOP_RECORDING_AFTER_SECONDS"
  launchctl setenv BUGBOOK_PROFILE_ALLOW_PERMISSION_PROMPT "$ALLOW_PERMISSION_PROMPT"
  launchctl setenv BUGBOOK_PROFILE_MIC_PERMISSION_TIMEOUT_SECONDS "$MIC_PERMISSION_TIMEOUT_SECONDS"
  launchctl setenv BUGBOOK_PROFILE_WORKSPACE_PATH "$PROFILE_WORKSPACE_PATH"
  PROFILE_ENV_SET=1
}

unset_profile_launch_env() {
  if [[ "$PROFILE_ENV_SET" != "1" ]]; then
    return
  fi
  launchctl unsetenv BUGBOOK_LEGACY_PANES 2>/dev/null || true
  launchctl unsetenv BUGBOOK_PROFILE_MARKERS 2>/dev/null || true
  launchctl unsetenv BUGBOOK_PROFILE_MARKER_FILE 2>/dev/null || true
  launchctl unsetenv BUGBOOK_DISABLE_SENTRY 2>/dev/null || true
  launchctl unsetenv BUGBOOK_SKIP_KEYCHAIN_SECRETS 2>/dev/null || true
  launchctl unsetenv BUGBOOK_PROFILE_AUTO_START_MEETING 2>/dev/null || true
  launchctl unsetenv BUGBOOK_PROFILE_AUTO_STOP_RECORDING_AFTER_SECONDS 2>/dev/null || true
  launchctl unsetenv BUGBOOK_PROFILE_ALLOW_PERMISSION_PROMPT 2>/dev/null || true
  launchctl unsetenv BUGBOOK_PROFILE_MIC_PERMISSION_TIMEOUT_SECONDS 2>/dev/null || true
  launchctl unsetenv BUGBOOK_PROFILE_WORKSPACE_PATH 2>/dev/null || true
  PROFILE_ENV_SET=0
}

wait_for_app_pid() {
  local timeout_seconds="$1"
  local started_at now elapsed pids_text pid_lines
  started_at="$(date +%s)"

  while true; do
    pids_text="$(pgrep -f "$EXECUTABLE" 2>/dev/null || true)"
    if [[ -n "$pids_text" ]]; then
      pid_lines=("${(@f)pids_text}")
      print -r -- "$pid_lines[1]"
      return 0
    fi

    now="$(date +%s)"
    elapsed=$(( now - started_at ))
    if (( elapsed >= timeout_seconds )); then
      return 1
    fi
    sleep 1
  done
}

launch_bugbook() {
  : > "$STDOUT_PATH"
  : > "$MARKER_PATH"

  if [[ "$LAUNCH_WITH_OPEN" == "1" ]]; then
    echo "Launching Bugbook.app via LaunchServices in default mode..."
    set_profile_launch_env
    open -n "$APP_PATH"
    APP_PID="$(wait_for_app_pid 30)"
  else
    echo "Launching Bugbook executable in default mode..."
    BUGBOOK_LEGACY_PANES=0 \
      BUGBOOK_PROFILE_MARKERS=1 \
      BUGBOOK_PROFILE_MARKER_FILE="$MARKER_PATH" \
      BUGBOOK_DISABLE_SENTRY=1 \
      BUGBOOK_SKIP_KEYCHAIN_SECRETS=1 \
      BUGBOOK_PROFILE_AUTO_START_MEETING="$AUTO_START_MEETING" \
      BUGBOOK_PROFILE_AUTO_STOP_RECORDING_AFTER_SECONDS="$AUTO_STOP_RECORDING_AFTER_SECONDS" \
      BUGBOOK_PROFILE_ALLOW_PERMISSION_PROMPT="$ALLOW_PERMISSION_PROMPT" \
      BUGBOOK_PROFILE_MIC_PERMISSION_TIMEOUT_SECONDS="$MIC_PERMISSION_TIMEOUT_SECONDS" \
      BUGBOOK_PROFILE_WORKSPACE_PATH="$PROFILE_WORKSPACE_PATH" \
      "$EXECUTABLE" > "$STDOUT_PATH" 2>&1 &
    APP_PID=$!
  fi
}

terminate_existing_debug_apps() {
  local pids_text existing_pids
  pids_text="$(pgrep -f "$EXECUTABLE" 2>/dev/null || true)"
  if [[ -z "$pids_text" ]]; then
    return
  fi
  existing_pids=("${(@f)pids_text}")

  echo "Terminating existing debug Bugbook process(es): ${existing_pids[*]}"
  local pid
  for pid in "${existing_pids[@]}"; do
    if [[ -n "$pid" && "$pid" != "$$" ]]; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  for _ in {1..20}; do
    pids_text="$(pgrep -f "$EXECUTABLE" 2>/dev/null || true)"
    if [[ -z "$pids_text" ]]; then
      return
    fi
    sleep 0.25
  done

  pids_text="$(pgrep -f "$EXECUTABLE" 2>/dev/null || true)"
  existing_pids=("${(@f)pids_text}")
  echo "Force terminating lingering debug Bugbook process(es): ${existing_pids[*]}"
  for pid in "${existing_pids[@]}"; do
    if [[ -n "$pid" && "$pid" != "$$" ]]; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  done
  for _ in {1..10}; do
    pids_text="$(pgrep -f "$EXECUTABLE" 2>/dev/null || true)"
    [[ -z "$pids_text" ]] && return
    sleep 0.1
  done
}

cleanup() {
  if [[ -n "$MEMORY_SAMPLER_PID" ]]; then
    kill "$MEMORY_SAMPLER_PID" 2>/dev/null || true
    wait "$MEMORY_SAMPLER_PID" 2>/dev/null || true
  fi
  if [[ -n "$SYSTEM_AUDIO_STIMULUS_PID" ]]; then
    pkill -P "$SYSTEM_AUDIO_STIMULUS_PID" 2>/dev/null || true
    kill "$SYSTEM_AUDIO_STIMULUS_PID" 2>/dev/null || true
    wait "$SYSTEM_AUDIO_STIMULUS_PID" 2>/dev/null || true
  fi
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    for _ in {1..10}; do
      if ! kill -0 "$APP_PID" 2>/dev/null; then
        break
      fi
      sleep 0.2
    done
    if kill -0 "$APP_PID" 2>/dev/null; then
      kill -9 "$APP_PID" 2>/dev/null || true
    fi
  fi
  unset_profile_launch_env
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"
mkdir -p "$PROFILE_WORKSPACE_PATH"

cd "$PROJECT_ROOT"

validate_memory_target
if ! is_truthy "$PREFLIGHT_ONLY"; then
  validate_soak_timing
fi

echo "Building BugbookApp $PROFILE_CONFIGURATION bundle..."
build_args=(
  -project macos/Bugbook.xcodeproj \
  -scheme BugbookApp \
  -configuration "$PROFILE_CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -quiet \
  build
)
if [[ -n "$PROFILE_DEVELOPMENT_TEAM" ]]; then
  build_args+=("DEVELOPMENT_TEAM=$PROFILE_DEVELOPMENT_TEAM")
fi
if [[ -n "$PROFILE_CODE_SIGN_IDENTITY" ]]; then
  build_args+=("CODE_SIGN_IDENTITY=$PROFILE_CODE_SIGN_IDENTITY")
fi
if [[ -n "$PROFILE_ARCHS" ]]; then
  build_args+=("ARCHS=$PROFILE_ARCHS")
fi
if [[ -n "$PROFILE_ONLY_ACTIVE_ARCH" ]]; then
  build_args+=("ONLY_ACTIVE_ARCH=$PROFILE_ONLY_ACTIVE_ARCH")
fi
xcodebuild "${build_args[@]}"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Missing executable: $EXECUTABLE" >&2
  exit 1
fi

if is_truthy "$PREFLIGHT_ONLY"; then
  open_privacy_settings_panes
  if ! wait_for_privacy_approval_if_requested; then
    run_preflight_only
    exit $?
  fi
  run_preflight_only
  exit $?
fi

terminate_existing_debug_apps

open_privacy_settings_panes
if ! wait_for_privacy_approval_if_requested; then
  run_preflight_only
  exit $?
fi
launch_bugbook

sleep 2
if [[ -z "$APP_PID" ]] || ! kill -0 "$APP_PID" 2>/dev/null; then
  echo "Bugbook exited before profiling started. See $STDOUT_PATH" >&2
  exit 1
fi

cat > "$EVIDENCE_PATH" <<EOF
# Bugbook Meeting Soak Trace

- Started: $STAMP
- Duration: $DURATION
- Template: $TEMPLATE
- Configuration: $PROFILE_CONFIGURATION
- App: $APP_PATH
- PID: $APP_PID
- Legacy panes: off (BUGBOOK_LEGACY_PANES=0)
- Profile markers: on (BUGBOOK_PROFILE_MARKERS=1)
- Marker file: $MARKER_PATH
- Sentry: disabled for profiling (BUGBOOK_DISABLE_SENTRY=1)
- Keychain secrets: skipped for profiling (BUGBOOK_SKIP_KEYCHAIN_SECRETS=1)
- Launch via open: ${LAUNCH_WITH_OPEN}
- Code signing identity override: ${PROFILE_CODE_SIGN_IDENTITY:-none}
- Development team override: ${PROFILE_DEVELOPMENT_TEAM:-none}
- Arch override: ${PROFILE_ARCHS:-none}
- Only active arch override: ${PROFILE_ONLY_ACTIVE_ARCH:-none}
- Attach-after marker: ${ATTACH_AFTER_MARKER:-none}
- Auto-start meeting: ${AUTO_START_MEETING}
- Auto-stop recording after: ${AUTO_STOP_RECORDING_AFTER_SECONDS:-none}
- Auto-stop finalization buffer: ${AUTO_STOP_FINALIZATION_BUFFER_SECONDS}
- Allow permission prompt: ${ALLOW_PERMISSION_PROMPT}
- Mic permission prompt timeout override: ${MIC_PERMISSION_TIMEOUT_SECONDS:-default}
- Open privacy settings: ${OPEN_PRIVACY_SETTINGS}
- Wait for privacy approval: ${WAIT_FOR_PRIVACY_APPROVAL}
- Privacy approval wait timeout: ${WAIT_FOR_PRIVACY_APPROVAL_SECONDS}s
- System audio stimulus: ${SYSTEM_AUDIO_STIMULUS}
- System audio stimulus duration: ${SYSTEM_AUDIO_STIMULUS_SECONDS}s
- System audio stimulus interval: ${SYSTEM_AUDIO_STIMULUS_INTERVAL_SECONDS}s
- System audio stimulus path: ${SYSTEM_AUDIO_STIMULUS_PATH}
- Profile workspace: $PROFILE_WORKSPACE_PATH
- RSS samples: $MEMORY_SAMPLES_PATH
- RSS memory target: ${MEMORY_TARGET_RSS_KIB} KiB
- RSS memory target enforcement: ${REQUIRE_MEMORY_TARGETS}
- Trace: $TRACE_PATH
- Stdout/stderr: $STDOUT_PATH

Manual flow while this script records:
1. If BUGBOOK_PROFILE_AUTO_START_MEETING=1, Bugbook creates and starts a profiling meeting automatically.
2. Otherwise, open or create a meeting note and start recording manually.
3. Keep the meeting running for the target soak duration.
4. Stop recording and let Bugbook finish finalizing, or set BUGBOOK_PROFILE_AUTO_STOP_RECORDING_AFTER_SECONDS.
5. Inspect this trace in Instruments and update the committed performance notes or commit message with memory/CPU findings.

EOF

sample_memory_until_exit >/dev/null &
MEMORY_SAMPLER_PID=$!

start_system_audio_stimulus_if_requested

if [[ -n "$ATTACH_AFTER_MARKER" ]]; then
  echo "Use Bugbook now and drive the meeting flow until marker '$ATTACH_AFTER_MARKER' appears."
  if ! wait_for_profile_marker "$ATTACH_AFTER_MARKER" "$ATTACH_AFTER_TIMEOUT_SECONDS"; then
    append_permission_diagnostics "Timed out before profile marker '${ATTACH_AFTER_MARKER}'"
    append_memory_summary || true
    echo "Permission diagnostics written to $EVIDENCE_PATH" >&2
    cleanup
    trap - EXIT
    exit 1
  fi
fi

echo "Recording $TEMPLATE for $DURATION. Complete the meeting flow before the timer ends."
XCTRACE_STATUS=0
if xcrun xctrace record \
    --quiet \
    --no-prompt \
    --template "$TEMPLATE" \
    --time-limit "$DURATION" \
    --output "$TRACE_PATH" \
    --attach "$APP_PID"; then
  XCTRACE_STATUS=0
else
  XCTRACE_STATUS=$?
fi

END_STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
APP_PROCESS_STATUS=0
if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
  APP_PROCESS_STATUS=0
else
  APP_PROCESS_STATUS=1
fi
{
  echo "- Finished: $END_STAMP"
  if (( XCTRACE_STATUS == 0 )); then
    echo "- xctrace exit: success"
  else
    echo "- xctrace exit: failure (${XCTRACE_STATUS})"
  fi
  if (( APP_PROCESS_STATUS == 0 )); then
    echo "- App process alive after trace: PASS"
  else
    echo "- App process alive after trace: FAIL"
  fi
} >> "$EVIDENCE_PATH"

MEETING_SIGNPOST_STATUS=0
INSTRUMENTS_TARGET_STATUS=0
MEMORY_TARGET_STATUS=0
append_run_summary
append_meeting_signpost_summary || MEETING_SIGNPOST_STATUS=$?
append_startup_marker_summary
append_trace_summary || INSTRUMENTS_TARGET_STATUS=$?
append_memory_summary || MEMORY_TARGET_STATUS=$?

if (( XCTRACE_STATUS != 0 )); then
  append_permission_diagnostics "xctrace record failed"
  echo "xctrace failed with status ${XCTRACE_STATUS}. See $EVIDENCE_PATH" >&2
  exit "$XCTRACE_STATUS"
fi

if (( APP_PROCESS_STATUS != 0 )); then
  append_permission_diagnostics "Bugbook process exited during trace"
  echo "Bugbook process exited during trace. See $EVIDENCE_PATH" >&2
  exit "$APP_PROCESS_STATUS"
fi

if (( MEETING_SIGNPOST_STATUS != 0 )); then
  append_permission_diagnostics "Meeting signpost validation failed"
  echo "Meeting signpost validation failed. See $EVIDENCE_PATH" >&2
  exit "$MEETING_SIGNPOST_STATUS"
fi

if (( INSTRUMENTS_TARGET_STATUS != 0 )); then
  append_permission_diagnostics "Instruments target validation failed"
  echo "Instruments target validation failed. See $EVIDENCE_PATH" >&2
  exit "$INSTRUMENTS_TARGET_STATUS"
fi

if (( MEMORY_TARGET_STATUS != 0 )); then
  append_permission_diagnostics "RSS memory target validation failed"
  echo "RSS memory target validation failed. See $EVIDENCE_PATH" >&2
  exit "$MEMORY_TARGET_STATUS"
fi

echo "Trace written to $TRACE_PATH"
echo "Evidence note written to $EVIDENCE_PATH"
