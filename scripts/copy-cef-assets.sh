#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 /path/to/Dahso.app [/path/to/Dahso Helper.app ...]" >&2
  exit 1
fi

APP_PATH="$1"
shift
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CEF_ROOT="$REPO_ROOT/macos/vendor/cef/current"
FRAMEWORK_SOURCE="$CEF_ROOT/Release/Chromium Embedded Framework.framework"
CODE_SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"

codesign_path() {
  codesign --force --sign "$CODE_SIGN_IDENTITY" --timestamp=none "$1"
}

link_helper_framework() {
  local helper_dest="$1"
  local helper_frameworks_dir="$helper_dest/Contents/Frameworks"
  mkdir -p "$helper_frameworks_dir"
  rm -rf "$helper_frameworks_dir/Chromium Embedded Framework.framework"
  ln -sfn "../../../Chromium Embedded Framework.framework" \
    "$helper_frameworks_dir/Chromium Embedded Framework.framework"
}

if [ ! -d "$APP_PATH" ]; then
  echo "App bundle not found at $APP_PATH" >&2
  exit 1
fi

if [ ! -d "$FRAMEWORK_SOURCE" ]; then
  echo "CEF framework not found at $FRAMEWORK_SOURCE" >&2
  echo "Run scripts/fetch-cef.sh before building the Chromium app target." >&2
  exit 1
fi

CONTENTS_DIR="$APP_PATH/Contents"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"
FRAMEWORK_DEST="$FRAMEWORKS_DIR/Chromium Embedded Framework.framework"

echo "-- Copying Chromium Embedded Framework"
rm -rf "$FRAMEWORK_DEST"
rsync -a "$FRAMEWORK_SOURCE" "$FRAMEWORKS_DIR/"
if [ ! -d "$FRAMEWORK_DEST/Versions" ]; then
  echo "-- Normalizing framework bundle layout"
  mkdir -p "$FRAMEWORK_DEST/Versions/A"

  for entry in "Chromium Embedded Framework" Libraries Resources; do
    if [ -e "$FRAMEWORK_DEST/$entry" ] && [ ! -L "$FRAMEWORK_DEST/$entry" ]; then
      mv "$FRAMEWORK_DEST/$entry" "$FRAMEWORK_DEST/Versions/A/$entry"
    fi
  done

  rm -f "$FRAMEWORK_DEST/Info.plist"
  ln -sfn "A" "$FRAMEWORK_DEST/Versions/Current"
  ln -sfn "Versions/Current/Chromium Embedded Framework" "$FRAMEWORK_DEST/Chromium Embedded Framework"
  ln -sfn "Versions/Current/Libraries" "$FRAMEWORK_DEST/Libraries"
  ln -sfn "Versions/Current/Resources" "$FRAMEWORK_DEST/Resources"
fi

echo "-- Re-signing Chromium Embedded Framework"
codesign_path "$FRAMEWORK_DEST"

if [ "$#" -gt 0 ]; then
  for helper in "$@"; do
    if [ ! -d "$helper" ]; then
      echo "Helper bundle not found at $helper" >&2
      exit 1
    fi
    helper_name="$(basename "$helper")"
    helper_dest="$FRAMEWORKS_DIR/$helper_name"
    echo "-- Copying helper bundle $helper_name"
    rsync -a --delete "$helper" "$FRAMEWORKS_DIR/"
    rm -rf "$CONTENTS_DIR/Resources/$helper_name"
    link_helper_framework "$helper_dest"
    codesign_path "$helper_dest"
  done
else
  for helper in "$CEF_ROOT"/Release/*Helper*.app; do
    if [ -d "$helper" ]; then
      helper_name="$(basename "$helper")"
      helper_dest="$FRAMEWORKS_DIR/$helper_name"
      echo "-- Copying helper bundle $helper_name"
      rsync -a --delete "$helper" "$FRAMEWORKS_DIR/"
      rm -rf "$CONTENTS_DIR/Resources/$helper_name"
      link_helper_framework "$helper_dest"
      codesign_path "$helper_dest"
    fi
  done
fi
