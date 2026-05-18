#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: APPLE_TEAM_ID=XXX APPLE_ID=you@example.com APPLE_APP_PASSWORD=xxxx ./scripts/build-release.sh 1.0.0}"

: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID env var}"
: "${APPLE_ID:?Set APPLE_ID env var (Apple ID email for notarization)}"
: "${APPLE_APP_PASSWORD:?Set APPLE_APP_PASSWORD env var (app-specific password)}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

BUILD_DIR="$REPO_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/Bugbook.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/Bugbook.app"
DMG_PATH="$BUILD_DIR/Bugbook-${VERSION}.dmg"
SIGNING_IDENTITY="Developer ID Application: ($APPLE_TEAM_ID)"

cleanup() {
    echo "-- Cleaning build directory"
    rm -rf "$BUILD_DIR"
}

cleanup
mkdir -p "$BUILD_DIR"

# --- Generate Xcode project ---
echo "-- Generating Xcode project with xcodegen"
(cd macos && xcodegen generate)

# --- Archive ---
echo "-- Archiving (scheme: BugbookApp, configuration: Release)"
xcodebuild archive \
    -project macos/Bugbook.xcodeproj \
    -scheme BugbookApp \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    MARKETING_VERSION="$VERSION" \
    | tail -1

# --- Patch ExportOptions with real team ID ---
EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"
sed "s/PLACEHOLDER_TEAM_ID/$APPLE_TEAM_ID/" scripts/ExportOptions.plist > "$EXPORT_PLIST"

# --- Export archive ---
echo "-- Exporting archive"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_PLIST" \
    -exportPath "$EXPORT_DIR" \
    | tail -1

# --- Codesign the .app ---
echo "-- Codesigning app"
codesign --force --deep --options runtime \
    --sign "$SIGNING_IDENTITY" \
    "$APP_PATH"

# --- Create DMG ---
echo "-- Creating DMG"
hdiutil create \
    -volname "Bugbook" \
    -srcfolder "$APP_PATH" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# --- Codesign DMG ---
echo "-- Codesigning DMG"
codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"

# --- Notarize ---
echo "-- Submitting DMG for notarization (this may take a few minutes)"
xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait

# --- Staple ---
echo "-- Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"

echo ""
echo "Done! Signed and notarized DMG: $DMG_PATH"
