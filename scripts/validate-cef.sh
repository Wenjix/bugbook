#!/usr/bin/env bash
set -euo pipefail

if [ -n "${SRCROOT:-}" ]; then
  REPO_ROOT="$(cd "$SRCROOT/.." && pwd)"
else
  REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi
CEF_ROOT="$REPO_ROOT/macos/vendor/cef/current"
FRAMEWORK_SOURCE="$CEF_ROOT/Release/Chromium Embedded Framework.framework"

if [ ! -d "$FRAMEWORK_SOURCE" ]; then
  echo "Missing CEF runtime at $FRAMEWORK_SOURCE" >&2
  echo "Run scripts/fetch-cef.sh before building the Chromium-backed DahsoApp target." >&2
  exit 1
fi
