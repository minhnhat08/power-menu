# PowerMenu

Menu-bar control panel for macOS AC-power timers, so a lid-open, plugged-in Mac
can be tuned for 24/7 Claude Code Remote Control without opening System Settings.

## What it does

- Menu-bar item (⚡) with two submenus:
  - **Tắt màn hình sau** (display off after): 1 / 2 / 5 / 10 / 15 / 30 min / Never
  - **Máy ngủ sau** (computer sleep after): 30 / 60 / 90 / 120 / 180 min / Never
- "Máy ngủ: Không bao giờ" == keep-awake (sets `pmset -c sleep 0`).
- **Khởi động cùng đăng nhập** toggle: flips the LaunchAgent's
  `launchctl enable/disable` override (no root, does not kill the running app).
- Reads current values from `pmset -g custom` (no root) **each time the menu
  opens**, so the checkmarks and summary line never go stale.
- Writes via `pmset -c <key> <minutes>` behind the **native admin-auth prompt**
  (`do shell script ... with administrator privileges`) — no sudoers edit, no
  stored password. macOS caches the auth for a few minutes, so changing both
  values usually prompts once.
- All changes target **AC power** (`-c`), since the machine is always plugged in.

## Build / install

```bash
bash build.sh                 # builds and installs to ~/Applications/PowerMenu.app
```

## Auto-start at login

LaunchAgent at `~/Library/LaunchAgents/com.minhnhat.powermenu.plist`.

```bash
launchctl bootstrap "gui/$UID" ~/Library/LaunchAgents/com.minhnhat.powermenu.plist  # enable
launchctl bootout    "gui/$UID" ~/Library/LaunchAgents/com.minhnhat.powermenu.plist  # disable
```

## Verify

```bash
pmset -g custom | sed -n '/AC Power:/,$p' | grep -E ' displaysleep| sleep'
```
