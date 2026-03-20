#!/bin/zsh
# perf-compare.sh — Compare current performance test results against baseline.
# Usage: ./scripts/perf-compare.sh [baseline_tsv]
#
# Reads the baseline TSV (default: Tests/BugbookTests/perf_baseline.tsv),
# runs performance tests, and reports regressions.
# Uses zsh for associative array support on macOS (bash 3.x lacks it).

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
BASELINE="${1:-$PROJECT_ROOT/Tests/BugbookTests/perf_baseline.tsv}"

if [ ! -f "$BASELINE" ]; then
    echo "No baseline found at $BASELINE"
    echo "Running tests to generate initial baseline..."
    cd "$PROJECT_ROOT"
    swift test --filter Performance 2>&1 | tail -30
    echo ""
    echo "Baseline generated at $BASELINE"
    exit 0
fi

# Snapshot current baseline
typeset -A OLD_VALUES
while IFS=$'\t' read -r name metric value timestamp; do
    [ "$name" = "test_name" ] && continue
    OLD_VALUES[$name]="$value"
done < "$BASELINE"

echo "Running performance tests..."
cd "$PROJECT_ROOT"
swift test --filter Performance 2>&1 | tail -30

echo ""
echo "=== Performance Comparison ==="
echo ""

REGRESSIONS=0
while IFS=$'\t' read -r name metric value timestamp; do
    [ "$name" = "test_name" ] && continue
    old="${OLD_VALUES[$name]:-}"
    if [ -z "$old" ]; then
        printf "  %-30s %8sms (new)\n" "$name" "$value"
        continue
    fi

    pct=$(awk "BEGIN { printf \"%.0f\", (($value - $old) / $old) * 100 }")
    if [ "$pct" -gt 0 ]; then
        direction="slower"
    else
        direction="faster"
        pct=$(( -pct ))
    fi

    if [ "$pct" -gt 20 ] && [ "$direction" = "slower" ]; then
        symbol="REGRESSION"
        REGRESSIONS=$((REGRESSIONS + 1))
    else
        symbol="ok"
    fi

    printf "  %-30s %8sms -> %8sms (%d%% %s) %s\n" "$name" "$old" "$value" "$pct" "$direction" "$symbol"
done < "$BASELINE"

echo ""
if [ "$REGRESSIONS" -gt 0 ]; then
    echo "Found $REGRESSIONS regression(s)."
    exit 1
else
    echo "All benchmarks within tolerance."
    exit 0
fi
