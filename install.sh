#!/bin/bash
# Install PowerMenu on macOS from the latest GitHub Release.
# Usage: curl -fsSL https://raw.githubusercontent.com/minhnhat08/power-menu/main/install.sh | bash
set -euo pipefail

REPO="minhnhat08/power-menu"
LABEL="com.minhnhat.powermenu"
ZIP="PowerMenu.app.zip"
APP_DEST="$HOME/Applications/PowerMenu.app"
EXEC_PATH="$APP_DEST/Contents/MacOS/PowerMenu"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

if [ "$(uname)" != "Darwin" ]; then
    echo "PowerMenu is macOS only." >&2
    exit 1
fi

base="https://github.com/$REPO/releases/latest/download"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading PowerMenu..."
curl -fsSL "$base/$ZIP" -o "$tmp/$ZIP"
curl -fsSL "$base/$ZIP.sha256" -o "$tmp/$ZIP.sha256"

echo "Verifying checksum..."
( cd "$tmp" && shasum -a 256 -c "$ZIP.sha256" )

# Stop any running/registered instance before replacing files.
launchctl bootout "$DOMAIN" "$PLIST" 2>/dev/null || true

echo "Installing to $APP_DEST..."
rm -rf "$APP_DEST"
mkdir -p "$HOME/Applications"
ditto -x -k "$tmp/$ZIP" "$tmp/extracted"
ditto "$tmp/extracted/PowerMenu.app" "$APP_DEST"
# Use the absolute system path: a PyPI `xattr` shim on PATH lacks -r and would
# silently fail to strip quarantine, re-triggering the Gatekeeper warning.
/usr/bin/xattr -dr com.apple.quarantine "$APP_DEST" || true

echo "Setting up Start at login..."
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>$EXEC_PATH</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
</dict>
</plist>
PLIST
launchctl bootstrap "$DOMAIN" "$PLIST"

open "$APP_DEST"
echo "PowerMenu installed. The icon should be in your menu bar."
