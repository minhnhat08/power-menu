#!/bin/bash
# Local-dev convenience: build the universal app and install it to ~/Applications.
# Distribution to other machines goes through install.sh / Homebrew instead.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/PowerMenu.app"

bash "$SRC_DIR/scripts/build-app.sh"

rm -rf "$APP"
mkdir -p "$HOME/Applications"
ditto "$SRC_DIR/dist/PowerMenu.app" "$APP"
echo "Installed: $APP"
