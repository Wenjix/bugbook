#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

INSTALL_DIR="${BUGBOOK_INSTALL_DIR:-/Applications}"
APP_NAME="Bugbook.app"
APP_PATH="$INSTALL_DIR/$APP_NAME"
BUNDLE_ID="${BUGBOOK_BUNDLE_ID:-com.maxforsey.Bugbook}"
DERIVED_DATA="$REPO_ROOT/.build/release-derived-data"

VERSION="0.$(git rev-list --count HEAD 2>/dev/null || echo 1)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

echo "-- Building Bugbook $VERSION (build $BUILD_NUMBER, $GIT_SHA)"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen is required for release builds" >&2
    exit 1
fi

if [ ! -d "$REPO_ROOT/macos/vendor/cef/current/Release/Chromium Embedded Framework.framework" ]; then
    bash "$REPO_ROOT/scripts/fetch-cef.sh"
fi

echo "-- Generating Xcode project"
(
    cd "$REPO_ROOT/macos"
    xcodegen generate
)

echo "-- Building Xcode app target"
rm -rf "$DERIVED_DATA"
# arm64-only: the vendored frameworks (CEF, GhosttyKit) ship arm64 slices only,
# so a universal build fails at the x86_64 link step.
xcodebuild \
    -project "$REPO_ROOT/macos/Bugbook.xcodeproj" \
    -scheme BugbookApp \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    -arch arm64 \
    ONLY_ACTIVE_ARCH=YES \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    build

BUILT_APP="$DERIVED_DATA/Build/Products/Release/Bugbook.app"
if [ ! -d "$BUILT_APP" ]; then
    echo "ERROR: Built app not found at $BUILT_APP" >&2
    exit 1
fi

echo "-- Codesigning (ad-hoc)"
codesign --force --deep --sign - "$BUILT_APP"

echo "-- Installing to $APP_PATH"
mkdir -p "$INSTALL_DIR"
pkill -f "$APP_PATH/Contents/MacOS/Bugbook" 2>/dev/null || true
sleep 0.5

rm -rf "$APP_PATH"
cp -R "$BUILT_APP" "$APP_PATH"

echo ""
echo "Done! Bugbook $VERSION installed to $APP_PATH"
echo "  Bundle ID:  $BUNDLE_ID"
echo "  Version:    $VERSION (build $BUILD_NUMBER)"
echo "  Git:        $GIT_SHA"
echo ""
echo "Launch with:  open $APP_PATH"
