#!/usr/bin/env bash
# perf-compare.sh — Run performance tests and report regressions.
# Usage: ./scripts/perf-compare.sh [baseline_tsv]
#
# The regression policy (20% relative threshold + per-metric absolute noise
# floor, both read from Tests/BugbookTests/perf_baseline.tsv) lives in
# PerfBaseline.record (Tests/BugbookTests/PerformanceTests.swift). This script
# does not re-implement it: it runs the tests and surfaces the comparison
# lines they print — one policy, one owner.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BASELINE="${1:-$PROJECT_ROOT/Tests/BugbookTests/perf_baseline.tsv}"

cd "$PROJECT_ROOT"

if [ ! -f "$BASELINE" ]; then
    echo "No baseline found at $BASELINE"
    echo "Running tests to generate initial baseline..."
    swift test --filter Performance 2>&1 | tail -30
    echo ""
    echo "Baseline generated at $BASELINE"
    exit 0
fi

echo "Running performance tests..."
if ! OUTPUT="$(swift test --filter Performance 2>&1)"; then
    echo "$OUTPUT" | tail -40
    echo "Performance tests failed."
    exit 1
fi
echo "$OUTPUT" | tail -5

echo ""
echo "=== Performance Comparison ==="
echo ""
echo "$OUTPUT" | grep -E '^[[:space:]]+[A-Za-z0-9_]+: .*ms' || echo "(no comparison lines found)"

REGRESSIONS="$(echo "$OUTPUT" | grep -c 'REGRESSION' || true)"

echo ""
if [ "$REGRESSIONS" -gt 0 ]; then
    echo "Found $REGRESSIONS regression(s)."
    exit 1
else
    echo "All benchmarks within tolerance."
    exit 0
fi
