#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INDEX_URL="https://cef-builds.spotifycdn.com/index.json"
PINNED_CEF_VERSION="${CEF_VERSION:-139.0.40+g465474a+chromium-139.0.7258.139}"
PINNED_CHANNEL="${CEF_CHANNEL:-stable}"
PINNED_FILE_TYPE="${CEF_FILE_TYPE:-standard}"

case "$(uname -m)" in
  arm64)
    PLATFORM="macosarm64"
    ;;
  x86_64)
    PLATFORM="macosx64"
    ;;
  *)
    echo "Unsupported macOS architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

read -r FILE_NAME FILE_SHA1 <<<"$(python3 - <<'PY' "$INDEX_URL" "$PLATFORM" "$PINNED_CEF_VERSION" "$PINNED_CHANNEL" "$PINNED_FILE_TYPE"
import json
import sys
import urllib.request

index_url, platform, cef_version, channel, file_type = sys.argv[1:6]

with urllib.request.urlopen(index_url, timeout=30) as response:
    payload = json.load(response)

versions = payload.get(platform, {}).get("versions", [])
for build in versions:
    if build.get("cef_version") != cef_version:
        continue
    if build.get("channel") != channel:
        continue
    for file_info in build.get("files", []):
        if file_info.get("type") == file_type:
            print(file_info["name"], file_info["sha1"])
            raise SystemExit(0)

raise SystemExit(f"No {file_type} build found for {platform} at {cef_version} ({channel}).")
PY
)"

DOWNLOAD_DIR="$REPO_ROOT/macos/vendor/cef/downloads/$PLATFORM"
EXTRACT_ROOT="$REPO_ROOT/macos/vendor/cef/$PLATFORM"
DEST_DIR="$EXTRACT_ROOT/$PINNED_CEF_VERSION"
CURRENT_LINK="$REPO_ROOT/macos/vendor/cef/current"
ARCHIVE_PATH="$DOWNLOAD_DIR/$FILE_NAME"
DOWNLOAD_URL="https://cef-builds.spotifycdn.com/$FILE_NAME"

mkdir -p "$DOWNLOAD_DIR" "$EXTRACT_ROOT"

if [ ! -f "$ARCHIVE_PATH" ]; then
  echo "-- Downloading $FILE_NAME"
  curl -L "$DOWNLOAD_URL" -o "$ARCHIVE_PATH.part"
  mv "$ARCHIVE_PATH.part" "$ARCHIVE_PATH"
fi

ACTUAL_SHA1="$(shasum -a 1 "$ARCHIVE_PATH" | awk '{print $1}')"
if [ "$ACTUAL_SHA1" != "$FILE_SHA1" ]; then
  echo "SHA1 mismatch for $ARCHIVE_PATH" >&2
  echo "Expected: $FILE_SHA1" >&2
  echo "Actual:   $ACTUAL_SHA1" >&2
  exit 1
fi

if [ ! -d "$DEST_DIR" ]; then
  echo "-- Extracting $FILE_NAME"
  TMP_DIR="$EXTRACT_ROOT/.tmp-$PINNED_CEF_VERSION"
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"
  tar -xjf "$ARCHIVE_PATH" -C "$TMP_DIR"
  EXTRACTED_DIR="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [ -z "$EXTRACTED_DIR" ]; then
    echo "Failed to locate extracted CEF directory" >&2
    exit 1
  fi
  mv "$EXTRACTED_DIR" "$DEST_DIR"
  rm -rf "$TMP_DIR"
fi

ln -sfn "$PLATFORM/$PINNED_CEF_VERSION" "$CURRENT_LINK"

echo "-- CEF ready at $DEST_DIR"
echo "-- Current link: $CURRENT_LINK"
