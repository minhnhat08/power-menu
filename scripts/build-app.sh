#!/bin/bash
# Build a universal (arm64 + x86_64), ad-hoc-signed PowerMenu.app into dist/.
# VERSION env var sets CFBundleShortVersionString (defaults to a dev placeholder).
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.0.0-dev}"
DIST="$SRC_DIR/dist"
APP="$DIST/PowerMenu.app"
MACOS_DIR="$APP/Contents/MacOS"

rm -rf "$APP"
mkdir -p "$MACOS_DIR"

swiftc -O -target arm64-apple-macos13.0 "$SRC_DIR/main.swift" -o "$DIST/PowerMenu-arm64"
swiftc -O -target x86_64-apple-macos13.0 "$SRC_DIR/main.swift" -o "$DIST/PowerMenu-x86_64"
lipo -create "$DIST/PowerMenu-arm64" "$DIST/PowerMenu-x86_64" -output "$MACOS_DIR/PowerMenu"
rm -f "$DIST/PowerMenu-arm64" "$DIST/PowerMenu-x86_64"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PowerMenu</string>
    <key>CFBundleDisplayName</key><string>PowerMenu</string>
    <key>CFBundleIdentifier</key><string>com.minhnhat.powermenu</string>
    <key>CFBundleExecutable</key><string>PowerMenu</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built: $APP ($VERSION)"
