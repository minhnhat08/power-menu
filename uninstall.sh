#!/bin/bash
# Remove PowerMenu and its LaunchAgent.
# Usage: curl -fsSL https://raw.githubusercontent.com/minhnhat08/power-menu/main/uninstall.sh | bash
set -euo pipefail

LABEL="com.minhnhat.powermenu"
APP_DEST="$HOME/Applications/PowerMenu.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

if [ "$(uname)" != "Darwin" ]; then
    echo "PowerMenu is macOS only." >&2
    exit 1
fi

launchctl bootout "$DOMAIN" "$PLIST" 2>/dev/null || true
pkill -f "PowerMenu.app/Contents/MacOS/PowerMenu" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$APP_DEST"
echo "PowerMenu removed."
