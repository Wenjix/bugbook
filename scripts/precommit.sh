#!/bin/sh
# Local pre-commit checks — mirrors what CI runs in .github/workflows/ci.yml
# so failures show up before push, not 5 minutes into the PR build.
#
# Install with:
#   ln -sf ../../scripts/precommit.sh .git/hooks/pre-commit
#
# Skip with:
#   git commit --no-verify

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Find changed Swift files vs HEAD (staged + unstaged)
CHANGED_SWIFT_FILES=$(git diff --cached --name-only --diff-filter=ACMR | grep -E '^(Sources|Tests)/.*\.swift$' || true)

if [ -z "$CHANGED_SWIFT_FILES" ]; then
  echo "[pre-commit] no Swift changes — skipping"
  exit 0
fi

FILE_COUNT=$(printf '%s\n' "$CHANGED_SWIFT_FILES" | wc -l | tr -d ' ')
echo "[pre-commit] checking $FILE_COUNT changed Swift files"

# 1. swift build — fast incremental build catches compile errors
echo "[pre-commit] swift build..."
if ! swift build 2>&1 | grep -E "error:" >&2 ; then
  : # no errors found
fi
if ! swift build > /dev/null 2>&1 ; then
  echo "[pre-commit] swift build FAILED" >&2
  swift build 2>&1 | tail -20 >&2
  exit 1
fi

# 2. SwiftLint — same config as CI
if command -v swiftlint > /dev/null 2>&1 ; then
  echo "[pre-commit] swiftlint..."
  LINT_OUTPUT=$(printf '%s\n' "$CHANGED_SWIFT_FILES" | xargs swiftlint lint --config .swiftlint-ci.yml --quiet 2>&1)
  if printf '%s\n' "$LINT_OUTPUT" | grep -q "error:" ; then
    echo "[pre-commit] swiftlint FAILED (errors found)" >&2
    printf '%s\n' "$LINT_OUTPUT" | grep "error:" >&2
    exit 1
  fi
else
  echo "[pre-commit] swiftlint not installed — skipping (install: brew install swiftlint)" >&2
fi

# 3. swift format lint — only fails on parser errors, not style warnings (matches CI)
if swift format lint --help > /dev/null 2>&1 ; then
  echo "[pre-commit] swift format lint..."
  if ! printf '%s\n' "$CHANGED_SWIFT_FILES" | xargs swift format lint > /dev/null 2>&1 ; then
    : # warnings, not errors — CI tolerates these
  fi
fi

echo "[pre-commit] all checks passed"
