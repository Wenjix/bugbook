#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v jq >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "[smoke] jq not found; installing with Homebrew"
    brew install jq
  else
    echo "jq is required for smoke-cli.sh. Install it with Homebrew ('brew install jq') and rerun."
    exit 1
  fi
fi

WS="$(mktemp -d)"
trap 'rm -rf "$WS"' EXIT
echo "[smoke] workspace: $WS"

run_bb() {
  swift run DahsoCLI "$@"
}

INIT_JSON="$(run_bb agent init --workspace "$WS" --write-agents-md)"
echo "$INIT_JSON" | jq -e '.initialized == true' >/dev/null

echo "[smoke] init: ok"

TASK_JSON="$(run_bb agent task create --workspace "$WS" --title 'Smoke Task' --status todo --assignee codex --label smoke --path Sources/Dahso)"
TASK_ID="$(echo "$TASK_JSON" | jq -r '.id')"
[ -n "$TASK_ID" ] && [ "$TASK_ID" != "null" ]
echo "[smoke] task create: ok ($TASK_ID)"

RUN_JSON="$(run_bb agent run start --workspace "$WS" --task "$TASK_ID" --agent codex --cwd "$ROOT_DIR" --branch 'codex/smoke')"
RUN_ID="$(echo "$RUN_JSON" | jq -r '.id')"
[ -n "$RUN_ID" ] && [ "$RUN_ID" != "null" ]
echo "[smoke] run start: ok ($RUN_ID)"

EVENT_JSON="$(run_bb agent event log --workspace "$WS" --run-id "$RUN_ID" --task "$TASK_ID" --level info --message 'Smoke event logged')"
echo "$EVENT_JSON" | jq -e '.runId == '"\"$RUN_ID\"" >/dev/null
echo "[smoke] event log: ok"

FINISH_JSON="$(run_bb agent run finish "$RUN_ID" --workspace "$WS" --status succeeded --summary 'Smoke run complete' --commit 'abc1234')"
echo "$FINISH_JSON" | jq -e '.status == "succeeded" and .commit == "abc1234"' >/dev/null
echo "[smoke] run finish: ok"

UPDATE_JSON="$(run_bb agent task update "$TASK_ID" --workspace "$WS" --status done)"
echo "$UPDATE_JSON" | jq -e '.status == "done"' >/dev/null
echo "[smoke] task update: ok"

DASH_JSON="$(run_bb agent dashboard --workspace "$WS")"
echo "$DASH_JSON" | jq -e '.recentRuns | length >= 1' >/dev/null
echo "$DASH_JSON" | jq -e '.recentEvents | length >= 1' >/dev/null
echo "$DASH_JSON" | jq -e '.taskCounts.done == 1' >/dev/null
echo "[smoke] dashboard: ok"

[ -f "$WS/.dahso/agents/tasks.json" ]
[ -f "$WS/.dahso/agents/runs.jsonl" ]
[ -f "$WS/.dahso/agents/events.jsonl" ]
[ -f "$WS/AGENTS.md" ]
echo "[smoke] files: ok"

echo "[smoke] ALL_SMOKE_TESTS_PASSED"
