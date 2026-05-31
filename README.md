# PowerMenu

Menu-bar control panel for macOS AC-power timers, so a lid-open, plugged-in Mac
can be tuned for 24/7 Claude Code Remote Control without opening System Settings.

## What it does

- Menu-bar item (⚡) with two submenus:
  - **Turn display off after**: 1 / 2 / 5 / 10 / 15 / 30 min / Never
  - **Sleep after**: 30 / 60 / 90 / 120 / 180 min / Never
- "Sleep: Never" == keep-awake (sets `pmset -c sleep 0`).
- **Start at login** toggle: flips the LaunchAgent's
  `launchctl enable/disable` override (no root, does not kill the running app).
- Reads current values from `pmset -g custom` (no root) **each time the menu
  opens**, so the checkmarks and summary line never go stale.
- Writes via `pmset -c <key> <minutes>` behind the **native admin-auth prompt**
  (`do shell script ... with administrator privileges`) — no sudoers edit, no
  stored password. macOS caches the auth for a few minutes, so changing both
  values usually prompts once.
- All changes target **AC power** (`-c`), since the machine is always plugged in.

## Install

PowerMenu is macOS only (it drives `pmset`/`launchctl`) and runs on both Apple
Silicon and Intel. The app is unsigned; every installer below strips the
quarantine attribute so it launches without a Gatekeeper warning.

### Homebrew (recommended)

```bash
brew install --cask minhnhat08/tap/power-menu
```

Updates come with `brew upgrade`.

### Install script

```bash
curl -fsSL https://raw.githubusercontent.com/minhnhat08/power-menu/main/install.sh | bash
```

Uninstall:

```bash
curl -fsSL https://raw.githubusercontent.com/minhnhat08/power-menu/main/uninstall.sh | bash
```

### npx

```bash
npx power-menu              # install
npx power-menu uninstall    # remove
```

All three install to `~/Applications/PowerMenu.app`, register a LaunchAgent at
`~/Library/LaunchAgents/com.minhnhat.powermenu.plist` (so "Start at login"
works), and launch the app.

## Build from source (local dev)

```bash
bash build.sh   # builds the universal app and installs it to ~/Applications
```

`scripts/build-app.sh` produces the universal, ad-hoc-signed bundle in `dist/`;
`build.sh` wraps it to install locally.

## Verify

```bash
pmset -g custom | sed -n '/AC Power:/,$p' | grep -E ' displaysleep| sleep'
```
