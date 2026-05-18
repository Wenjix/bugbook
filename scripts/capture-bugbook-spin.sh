#!/usr/bin/env bash
set -euo pipefail

# Captures diagnostics when Bugbook appears to be spinning (high sustained CPU).
#
# Usage:
#   ./scripts/capture-bugbook-spin.sh
# Optional env vars:
#   APP_MATCH=Bugbook
#   CPU_THRESHOLD=70
#   CONSECUTIVE_SAMPLES=4
#   INTERVAL=1
#   TIMEOUT=180
#   OUT_DIR="$HOME/Desktop/bugbook-spin-diagnostics"

APP_MATCH="${APP_MATCH:-Bugbook}"
CPU_THRESHOLD="${CPU_THRESHOLD:-70}"
CONSECUTIVE_SAMPLES="${CONSECUTIVE_SAMPLES:-4}"
INTERVAL="${INTERVAL:-1}"
TIMEOUT="${TIMEOUT:-180}"
OUT_DIR="${OUT_DIR:-$HOME/Desktop/bugbook-spin-diagnostics}"

mkdir -p "$OUT_DIR"

echo "Watching for high CPU process matching: $APP_MATCH"
echo "Threshold: >=${CPU_THRESHOLD}% for ${CONSECUTIVE_SAMPLES} consecutive samples"
echo "Timeout: ${TIMEOUT}s"
echo

hits=0
deadline=$((SECONDS + TIMEOUT))

while ((SECONDS < deadline)); do
    line="$(ps -axo pid=,pcpu=,comm= \
        | awk -v app="$APP_MATCH" 'tolower($0) ~ tolower(app) { print }' \
        | sort -k2 -nr \
        | head -n 1)"

    if [[ -z "${line}" ]]; then
        printf "\rNo matching process...                      "
        hits=0
        sleep "$INTERVAL"
        continue
    fi

    pid="$(awk '{print $1}' <<<"$line")"
    cpu="$(awk '{print $2}' <<<"$line")"
    cpu_int="${cpu%.*}"
    if [[ -z "${cpu_int}" ]]; then
        cpu_int=0
    fi

    if ((cpu_int >= CPU_THRESHOLD)); then
        hits=$((hits + 1))
    else
        hits=0
    fi

    printf "\rPID %s CPU %s%% spike-count %s/%s   " "$pid" "$cpu" "$hits" "$CONSECUTIVE_SAMPLES"

    if ((hits >= CONSECUTIVE_SAMPLES)); then
        ts="$(date +%Y%m%d-%H%M%S)"
        base="${OUT_DIR}/bugbook-spin-${ts}"
        echo
        echo "High CPU sustained. Capturing diagnostics..."

        top -l 1 -pid "$pid" -stats pid,cpu,mem,time,command > "${base}.top.txt" 2>/dev/null || true
        sample "$pid" 10 -file "${base}.sample.txt" >/dev/null 2>&1 || true
        spindump "$pid" 8 1 -file "${base}.spindump.txt" >/dev/null 2>&1 || true
        log show --style compact --last 3m --predicate 'process == "Bugbook" OR process == "bugbook"' > "${base}.log.txt" 2>/dev/null || true

        echo "Saved diagnostics:"
        ls -1 "${base}".* 2>/dev/null || true
        exit 0
    fi

    sleep "$INTERVAL"
done

echo
echo "No sustained spike detected before timeout."
exit 1
