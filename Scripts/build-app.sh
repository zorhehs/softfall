#!/usr/bin/env bash
#
# Builds Softfall.app from the SwiftPM target.
#
# There is no Xcode project on purpose: a plain package plus this script is far
# easier to read, review and reproduce than a generated pbxproj, and it builds
# identically on a laptop and on a CI runner.
#
# Usage: Scripts/build-app.sh [version]

set -euo pipefail

VERSION="${1:-0.1.0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/Softfall.app"
BUNDLE_ID="io.github.zorhehs.softfall"

echo "==> Building Softfall $VERSION (universal)"
cd "$ROOT"
rm -rf dist
swift build -c release --arch arm64 --arch x86_64

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

# Keep local builds out of Spotlight. A source build and an installed copy share
# a bundle identifier, so LaunchServices treats them as the same app and picks
# between them on its own terms — which means `open -a Softfall` can silently
# launch the wrong one. Launch test builds by path instead: open dist/Softfall.app
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
    <key>CFBundleName</key><string>Softfall</string>
    <key>CFBundleDisplayName</key><string>Softfall</string>
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
