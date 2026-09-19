#!/usr/bin/env bash
#
# Builds Softfall.app from the SwiftPM target.
#
# There is no Xcode project on purpose: a plain package plus this script is far
# easier to read, review and reproduce than a generated pbxproj, and it builds
# identically on a laptop and on a CI runner.
#
# Usage: Scripts/build-app.sh [version] [--dev]
#
#   --dev  builds a side-by-side development copy: its own name, its own bundle
#          identifier, its own saved settings, and only your machine's
#          architecture so it takes seconds rather than minutes.
#
# The point of --dev is that a source build and an installed copy used to share
# the identifier io.github.zorhehs.softfall. macOS then treats them as one app,
# so `open -a Softfall` picks whichever it likes and you cannot tell which
# binary you are looking at. A separate identifier ends that for good, and means
# testing a branch no longer needs a release to carry it to you.

set -euo pipefail

VERSION=""
DEV=0
for arg in "$@"; do
    case "$arg" in
        --dev) DEV=1 ;;
        *)     VERSION="$arg" ;;
    esac
done
VERSION="${VERSION:-0.1.0}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $DEV -eq 1 ]]; then
    APP_NAME="SoftfallDev"
    DISPLAY_NAME="Softfall Dev"
    BUNDLE_ID="io.github.zorhehs.softfall.dev"
    VERSION="$VERSION-dev"
else
    APP_NAME="Softfall"
    DISPLAY_NAME="Softfall"
    BUNDLE_ID="io.github.zorhehs.softfall"
fi
APP="$ROOT/dist/$APP_NAME.app"

cd "$ROOT"
rm -rf dist

if [[ $DEV -eq 1 ]]; then
    # One architecture, because the only machine that has to run it is this one.
    echo "==> Building $DISPLAY_NAME $VERSION (this Mac only)"
    swift build -c release
else
    echo "==> Building Softfall $VERSION (universal)"
    swift build -c release --arch arm64 --arch x86_64
fi

# SwiftPM puts a multi-architecture build somewhere different from a
# single-architecture one, so look in both places.
BINARY=""
for candidate in \
    ".build/apple/Products/Release/Softfall" \
    ".build/release/Softfall"
do
    if [[ -f "$candidate" ]]; then BINARY="$candidate"; break; fi
done

if [[ -z "$BINARY" ]]; then
    echo "error: could not find the built binary" >&2
    exit 1
fi

echo "==> Assembling the bundle"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Keep local builds out of Spotlight so a dev copy never clutters search.
: > "$ROOT/dist/.metadata_never_index"
cp "$BINARY" "$APP/Contents/MacOS/Softfall"
chmod +x "$APP/Contents/MacOS/Softfall"

echo "==> Building the icon"
ICONSET="$ROOT/dist/AppIcon.iconset"
mkdir -p "$ICONSET"
SRC="$ROOT/Resources/icon-1024.png"
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"
do
    set -- $spec
    sips -z "$1" "$1" "$SRC" --out "$ICONSET/icon_$2.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$DISPLAY_NAME</string>
    <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>Softfall</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <!-- No LSUIElement on purpose. Softfall is a regular app: Dock icon, window
         and menu bar, plus a status item. Adding LSUIElement back here would
         fight main.swift's .regular activation policy. -->
    <key>NSHumanReadableCopyright</key><string>MIT licensed</string>
</dict>
</plist>
PLIST

echo "==> Signing"
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp \
             --sign "$CODESIGN_IDENTITY" "$APP"
    echo "    signed with $CODESIGN_IDENTITY"
else
    # Ad-hoc signature. Enough for the app to run locally; see the README for
    # what this means for Gatekeeper when distributing it.
    codesign --force --deep --sign - "$APP"
    echo "    ad-hoc signed (no Developer ID configured)"
fi

echo "==> Done: $APP"
if [[ $DEV -eq 1 ]]; then
    echo
    echo "    open \"$APP\""
    echo
    echo "    Runs alongside the installed Softfall with its own settings."
    echo "    Quit it from its own menu bar icon when you are finished."
fi
