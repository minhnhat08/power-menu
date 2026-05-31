#!/bin/bash
# Build PowerMenu.app from main.swift and install it to ~/Applications.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/PowerMenu.app"
MACOS_DIR="$APP/Contents/MacOS"

rm -rf "$APP"
mkdir -p "$MACOS_DIR"

swiftc -O "$SRC_DIR/main.swift" -o "$MACOS_DIR/PowerMenu"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PowerMenu</string>
    <key>CFBundleDisplayName</key><string>PowerMenu</string>
    <key>CFBundleIdentifier</key><string>com.minhnhat.powermenu</string>
    <key>CFBundleExecutable</key><string>PowerMenu</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built: $APP"
