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
  swift run BugbookCLI "$@"
}

INIT_JSON="$(run_bb agent init --workspace "$WS" --write-agents-md)"
echo "$INIT_JSON" | jq -e '.initialized == true' >/dev/null

echo "[smoke] init: ok"

TASK_JSON="$(run_bb agent task create --workspace "$WS" --title 'Smoke Task' --status todo --assignee codex --label smoke --path Sources/Bugbook)"
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

[ -f "$WS/.bugbook/agents/tasks.json" ]
[ -f "$WS/.bugbook/agents/runs.jsonl" ]
[ -f "$WS/.bugbook/agents/events.jsonl" ]
[ -f "$WS/AGENTS.md" ]
echo "[smoke] files: ok"

mkdir -p "$WS/.smoke"
cat > "$WS/.smoke/good.html" <<'HTML'
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="bugbook-artifact" content="1">
<meta name="bugbook-title" content="Sleep Trends">
<meta name="bugbook-generator" content="smoke-cli">
<style>body { font-family: -apple-system, sans-serif; }</style>
</head>
<body>
<h1>Sleep Trends</h1>
<script type="application/json" id="data">[{"day":"2026-06-01","hours":7.4}]</script>
<script>document.body.append(JSON.parse(document.getElementById("data").textContent).length + " rows");</script>
</body>
</html>
HTML

ART_JSON="$(run_bb artifact create 'Weekly Review/sleep-trends.html' --workspace "$WS" --content-file "$WS/.smoke/good.html")"
echo "$ART_JSON" | jq -e '.created == true and .relative_path == "Weekly Review/sleep-trends.html"' >/dev/null
echo "$ART_JSON" | jq -e '.markdown_link == "[Sleep Trends](Weekly Review/sleep-trends.html)"' >/dev/null
echo "[smoke] artifact create: ok"

VAL_JSON="$(run_bb artifact validate 'Weekly Review/sleep-trends.html' --workspace "$WS")"
echo "$VAL_JSON" | jq -e '.valid == true' >/dev/null
echo "[smoke] artifact validate: ok"

cat > "$WS/.smoke/bad.html" <<'HTML'
<!DOCTYPE html>
<html>
<head>
<meta name="bugbook-artifact" content="1">
<meta name="bugbook-title" content="Bad">
<script src="https://cdn.example.com/chart.min.js"></script>
</head>
<body></body>
</html>
HTML

if BAD_JSON="$(run_bb artifact create 'bad-artifact.html' --workspace "$WS" --content-file "$WS/.smoke/bad.html")"; then
  echo "[smoke] artifact create should have failed on a CDN reference"
  exit 1
fi
echo "$BAD_JSON" | jq -e '.created == false and (.errors | length >= 1)' >/dev/null
[ ! -f "$WS/bad-artifact.html" ]
echo "[smoke] artifact rejects CDN: ok"

LIST_JSON="$(run_bb artifact list --workspace "$WS")"
echo "$LIST_JSON" | jq -e 'length == 1 and .[0].relative_path == "Weekly Review/sleep-trends.html" and .[0].title == "Sleep Trends"' >/dev/null
echo "[smoke] artifact list: ok"

echo "[smoke] ALL_SMOKE_TESTS_PASSED"
