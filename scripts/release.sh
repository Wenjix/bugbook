#!/usr/bin/env bash
# release.sh — Build Bugbook.app and install to ~/Applications
#
# Usage:  ./scripts/release.sh
#
# Builds using swift build (Release config), creates a proper .app bundle,
# and copies it to ~/Applications/Bugbook.app. The release build uses a
# different bundle identifier (com.bugbook.Bugbook) so it can run alongside
# the Xcode dev build (com.maxforsey.Bugbook.dev).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

INSTALL_DIR="$HOME/Applications"
APP_NAME="Bugbook.app"
APP_PATH="$INSTALL_DIR/$APP_NAME"
BUNDLE_ID="com.bugbook.Bugbook"

contains_item() {
    local needle="$1"
    shift

    local item
    for item in "$@"; do
        if [ "$item" = "$needle" ]; then
            return 0
        fi
    done

    return 1
}

copy_swift_runtime_libraries() {
    local queue=()
    local copied=()
    local search_dirs=()
    local library=""
    local dependency=""
    local search_dir=""
    local source_path=""
    local i=0

    while IFS= read -r library; do
        [ -n "$library" ] && queue+=("$library")
    done < <(otool -L "$MACOS_DIR/Bugbook" | awk '$1 ~ /^@rpath\/libswift.*\.dylib$/ { sub("^@rpath/", "", $1); print $1 }')

    while IFS= read -r search_dir; do
        [ -d "$search_dir" ] && search_dirs+=("$search_dir")
    done < <(otool -l "$MACOS_DIR/Bugbook" | awk '$1 == "path" && $2 ~ /^\// { print $2 }')

    for ((i = 0; i < ${#queue[@]}; i++)); do
        library="${queue[$i]}"

        if [ ${#copied[@]} -gt 0 ] && contains_item "$library" "${copied[@]}"; then
            continue
        fi

        source_path=""
        for search_dir in "${search_dirs[@]}"; do
            if [ -f "$search_dir/$library" ]; then
                source_path="$search_dir/$library"
                break
            fi
        done

        if [ -z "$source_path" ]; then
            echo "ERROR: Swift runtime library not found: $library"
            exit 1
        fi

        cp -R "$source_path" "$FRAMEWORKS_DIR/"
        copied+=("$library")

        while IFS= read -r dependency; do
            [ -n "$dependency" ] && queue+=("$dependency")
        done < <(otool -L "$source_path" | awk '$1 ~ /^@rpath\/libswift.*\.dylib$/ { sub("^@rpath/", "", $1); print $1 }')
    done
}

# --- Version from git ---
VERSION="0.$(git rev-list --count HEAD 2>/dev/null || echo 1)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

echo "-- Building Bugbook $VERSION (build $BUILD_NUMBER, $GIT_SHA)"

# --- Build release binary ---
echo "-- swift build --configuration release --product Bugbook"
swift build --configuration release --product Bugbook 2>&1 | tail -5

BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY="$BIN_DIR/Bugbook"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

# --- Construct .app bundle ---
echo "-- Assembling $APP_NAME bundle"
STAGE_DIR="$REPO_ROOT/.build/release-app"
rm -rf "$STAGE_DIR"

CONTENTS="$STAGE_DIR/$APP_NAME/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS_DIR="$CONTENTS/Frameworks"

mkdir -p "$MACOS_DIR" "$RESOURCES" "$FRAMEWORKS_DIR"

# Copy binary
cp "$BINARY" "$MACOS_DIR/Bugbook"

# Teach the SwiftPM-built executable to resolve bundled frameworks.
if ! otool -l "$MACOS_DIR/Bugbook" | grep -Fq "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/Bugbook"
fi

# Copy runtime frameworks, bundles, and dylibs emitted by SwiftPM.
shopt -s nullglob
for framework in "$BIN_DIR"/*.framework; do
    cp -R "$framework" "$FRAMEWORKS_DIR/"
done
for library in "$BIN_DIR"/*.dylib; do
    cp -R "$library" "$FRAMEWORKS_DIR/"
done
for bundle in "$BIN_DIR"/*.bundle; do
    cp -R "$bundle" "$RESOURCES/"
done
shopt -u nullglob

# Bundle non-system Swift runtime libraries referenced through @rpath.
copy_swift_runtime_libraries

# Compile asset catalog if actool is available, otherwise skip
XCASSETS="$REPO_ROOT/macos/App/Assets.xcassets"
if command -v actool &>/dev/null && [ -d "$XCASSETS" ]; then
    echo "-- Compiling asset catalog"
    actool "$XCASSETS" \
        --compile "$RESOURCES" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --app-icon AppIcon \
        --accent-color AccentColor \
        --output-partial-info-plist /dev/null 2>/dev/null || true
else
    # Copy icon PNG as a fallback
    ICON_SRC="$REPO_ROOT/macos/App/Assets.xcassets/AppIcon.appiconset/icon_512x512.png"
    if [ -f "$ICON_SRC" ]; then
        cp "$ICON_SRC" "$RESOURCES/AppIcon.png"
    fi
fi

# Generate Info.plist
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Bugbook</string>
    <key>CFBundleExecutable</key>
    <string>Bugbook</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Bugbook</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Bugbook needs microphone access to record meeting audio for live transcription.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Bugbook uses speech recognition to transcribe meeting recordings in real-time.</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>BugbookGitSHA</key>
    <string>${GIT_SHA}</string>
</dict>
</plist>
PLIST

# Write entitlements
cat > "$STAGE_DIR/Bugbook.entitlements" <<ENTITLEMENTS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

# Ad-hoc codesign for local use
echo "-- Codesigning (ad-hoc)"
codesign --force --deep \
    --sign - \
    --entitlements "$STAGE_DIR/Bugbook.entitlements" \
    "$STAGE_DIR/$APP_NAME"

# --- Install ---
echo "-- Installing to $APP_PATH"
mkdir -p "$INSTALL_DIR"

# Kill running release Bugbook if present (ignore errors)
pkill -f "$APP_PATH/Contents/MacOS/Bugbook" 2>/dev/null || true
sleep 0.5

rm -rf "$APP_PATH"
cp -R "$STAGE_DIR/$APP_NAME" "$APP_PATH"

# Clean up staging
rm -rf "$STAGE_DIR"

echo ""
echo "Done! Bugbook $VERSION installed to $APP_PATH"
echo "  Bundle ID:  $BUNDLE_ID"
echo "  Version:    $VERSION (build $BUILD_NUMBER)"
echo "  Git:        $GIT_SHA"
echo ""
echo "Launch with:  open $APP_PATH"
