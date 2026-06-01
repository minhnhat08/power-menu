# PowerMenu Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make PowerMenu installable on any Mac via an install script, Homebrew tap, and `npx`, all consuming one universal ad-hoc-signed GitHub Release artifact, with the UI translated to English.

**Architecture:** A CI workflow builds a universal (arm64 + x86_64) ad-hoc-signed `PowerMenu.app`, zips it with a SHA-256 checksum, and attaches both to a GitHub Release on tag push (and publishes the npm package). Three installers (`install.sh`, Homebrew cask, npm CLI) each download that release zip, verify the checksum, unzip into `~/Applications` with `ditto`, strip the quarantine attribute so the unsigned app launches cleanly, and generate + bootstrap a LaunchAgent so "Start at login" works.

**Tech Stack:** Swift (`swiftc` + `lipo` + `codesign`), Bash, Node.js (built-ins only, no dependencies — `node:test` for unit tests), GitHub Actions, Homebrew cask, npm.

**Spec:** `docs/superpowers/specs/2026-05-31-power-menu-distribution-design.md`

---

## Testing note

This project is packaging and scripting, not application logic. Unit tests apply only to the pure Node helpers (URL building, path derivation, plist rendering) and use the built-in `node:test` runner with `node:assert` — no dependencies. Shell scripts, the Swift source, the CI workflow, and the cask are verified by running them and checking observable output (`lipo -info`, `codesign -dv`, `shellcheck`, manual install/uninstall on a clean account), because there is no test harness for them and adding one would be over-engineering.

## External prerequisites (manual, done by the repo owner)

These are not code tasks but are required for the channels to work end to end. The plan notes them where relevant:

- Repo `github.com/minhnhat08/power-menu` is **public**.
- A GitHub Actions secret `NPM_TOKEN` (an npm automation token) is added under the repo Settings → Secrets and variables → Actions, used by the npm publish job.
- A second **public** repo `github.com/minhnhat08/homebrew-tap` hosts the cask (Task 10).

## File structure

```
power-menu/
├─ main.swift                         # MODIFY: UI strings -> English
├─ build.sh                           # MODIFY: local-dev install, delegates to build-app.sh
├─ scripts/
│  ├─ build-app.sh                    # CREATE: universal .app build
│  └─ launchagent.plist.template      # CREATE: canonical LaunchAgent template (dev/reference)
├─ install.sh                         # CREATE: channel A (curl | bash)
├─ uninstall.sh                       # CREATE: channel A removal
├─ npm/
│  ├─ package.json                    # CREATE: name power-menu, bin power-menu
│  ├─ bin/cli.js                      # CREATE: CLI entry (install | uninstall)
│  ├─ lib/config.js                   # CREATE: paths + asset URL helpers (pure)
│  ├─ lib/launchagent.js              # CREATE: renderPlist (pure)
│  ├─ lib/download.js                 # CREATE: fetch + sha256
│  ├─ lib/install.js                  # CREATE: install/uninstall orchestration
│  └─ test/
│     ├─ config.test.js               # CREATE: unit tests for config
│     └─ launchagent.test.js          # CREATE: unit tests for renderPlist
├─ .github/workflows/release.yml      # CREATE: build + release + npm publish
├─ LICENSE                            # CREATE: MIT (npm package references it)
├─ README.md                          # MODIFY: three install methods
└─ docs/superpowers/…                 # spec + this plan
```

The Homebrew cask `Casks/power-menu.rb` lives in the separate `homebrew-tap` repo (Task 10), not in this repo.

---

### Task 1: Translate UI strings to English

**Files:**
- Modify: `main.swift`

- [ ] **Step 1: Replace the `minutesLabel` helper**

In `main.swift`, replace:

```swift
    private func minutesLabel(_ m: Int) -> String { m == 0 ? "Không bao giờ" : "\(m) phút" }
```

with:

```swift
    private func minutesLabel(_ m: Int) -> String { m == 0 ? "Never" : "\(m) min" }
```

- [ ] **Step 2: Replace the menu item titles in `menuNeedsUpdate`**

In `main.swift`, replace these four assignments (keep the surrounding code identical):

```swift
        let display = NSMenuItem(title: "Tắt màn hình sau", action: nil, keyEquivalent: "")
```
```swift
        let sleep = NSMenuItem(title: "Máy ngủ sau", action: nil, keyEquivalent: "")
```
```swift
        let summary = NSMenuItem(
            title: "Hiện tại (sạc): màn \(minutesLabel(state.displaySleep)) · ngủ \(minutesLabel(state.systemSleep))",
            action: nil, keyEquivalent: "")
```
```swift
        let login = NSMenuItem(title: "Khởi động cùng đăng nhập",
                               action: #selector(toggleLogin), keyEquivalent: "")
```

with:

```swift
        let display = NSMenuItem(title: "Turn display off after", action: nil, keyEquivalent: "")
```
```swift
        let sleep = NSMenuItem(title: "Sleep after", action: nil, keyEquivalent: "")
```
```swift
        let summary = NSMenuItem(
            title: "Current (AC): display \(minutesLabel(state.displaySleep)) · sleep \(minutesLabel(state.systemSleep))",
            action: nil, keyEquivalent: "")
```
```swift
        let login = NSMenuItem(title: "Start at login",
                               action: #selector(toggleLogin), keyEquivalent: "")
```

- [ ] **Step 3: Update the source comments to English**

In `main.swift`, the header comment (lines 3-6) and inline comments are already English — leave them. Confirm no Vietnamese strings remain.

Run: `grep -nE 'phút|Không|màn|ngủ|Khởi|sạc|Hiện' main.swift`
Expected: no output (exit code 1).

- [ ] **Step 4: Build and verify the app still compiles and runs**

Run: `bash build.sh && open ~/Applications/PowerMenu.app`
Expected: build succeeds, the menu-bar icon appears, and the menu shows English labels ("Turn display off after", "Sleep after", "Never", "Start at login", "Quit").

- [ ] **Step 5: Commit**

```bash
git add main.swift
git commit -m "feat: translate PowerMenu UI to English"
```

---

### Task 2: Universal build script

**Files:**
- Create: `scripts/build-app.sh`
- Modify: `.gitignore`

- [ ] **Step 1: Create `scripts/build-app.sh`**

```bash
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
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x scripts/build-app.sh`

- [ ] **Step 3: Add `dist/` to `.gitignore`**

Append to `.gitignore`:

```
# Universal build output (scripts/build-app.sh)
dist/
```

- [ ] **Step 4: Run the build and verify it is universal and signed**

Run:
```bash
VERSION=9.9.9 bash scripts/build-app.sh
lipo -info dist/PowerMenu.app/Contents/MacOS/PowerMenu
codesign -dv dist/PowerMenu.app 2>&1 | head -2
grep -A1 CFBundleShortVersionString dist/PowerMenu.app/Contents/Info.plist
```
Expected: `lipo -info` prints `Architectures in the fat file: ... are: x86_64 arm64`; `codesign -dv` prints an `Identifier=...` line (ad-hoc); version shows `9.9.9`.

- [ ] **Step 5: Commit**

```bash
git add scripts/build-app.sh .gitignore
git commit -m "feat: add universal app build script"
```

---

### Task 3: Refactor `build.sh` to a local-dev installer

**Files:**
- Modify: `build.sh`

- [ ] **Step 1: Replace the entire contents of `build.sh`**

```bash
#!/bin/bash
# Local-dev convenience: build the universal app and install it to ~/Applications.
# Distribution to other machines goes through install.sh / Homebrew / npx instead.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/PowerMenu.app"

bash "$SRC_DIR/scripts/build-app.sh"

rm -rf "$APP"
mkdir -p "$HOME/Applications"
ditto "$SRC_DIR/dist/PowerMenu.app" "$APP"
echo "Installed: $APP"
```

- [ ] **Step 2: Verify local install still works**

Run: `bash build.sh && test -x "$HOME/Applications/PowerMenu.app/Contents/MacOS/PowerMenu" && echo OK`
Expected: prints `Built: ...`, `Installed: ...`, then `OK`.

- [ ] **Step 3: Commit**

```bash
git add build.sh
git commit -m "refactor: build.sh delegates to build-app.sh for local install"
```

---

### Task 4: LaunchAgent template

**Files:**
- Create: `scripts/launchagent.plist.template`

This is the canonical reference form of the LaunchAgent. `install.sh` and the npm CLI embed their own copies (they run detached from a repo checkout), so this file documents the format and is usable by local-dev tooling. The placeholder `__EXEC_PATH__` is replaced with the installed executable path.

- [ ] **Step 1: Create `scripts/launchagent.plist.template`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.minhnhat.powermenu</string>
    <key>ProgramArguments</key>
    <array><string>__EXEC_PATH__</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
</dict>
</plist>
```

- [ ] **Step 2: Verify the placeholder renders correctly**

Run: `sed 's|__EXEC_PATH__|/tmp/x/PowerMenu|' scripts/launchagent.plist.template | grep -q '<string>/tmp/x/PowerMenu</string>' && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add scripts/launchagent.plist.template
git commit -m "feat: add LaunchAgent plist template"
```

---

### Task 5: Install script (channel A)

**Files:**
- Create: `install.sh`

The script downloads from the GitHub "latest release" redirect URL (`/releases/latest/download/<asset>`), which needs no API call or `jq`.

- [ ] **Step 1: Create `install.sh`**

```bash
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
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x install.sh`

- [ ] **Step 3: Verify the script parses and is shellcheck-clean (locally if available)**

Run: `bash -n install.sh && echo "syntax OK"`
Expected: `syntax OK`. (Full `shellcheck` runs in CI — Task 8.)

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "feat: add curl|bash install script"
```

> End-to-end run of this script requires a published release (Task 8) and is exercised in the final acceptance step at the end of the plan.

---

### Task 6: Uninstall script (channel A)

**Files:**
- Create: `uninstall.sh`

- [ ] **Step 1: Create `uninstall.sh`**

```bash
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
```

- [ ] **Step 2: Make it executable and check syntax**

Run: `chmod +x uninstall.sh && bash -n uninstall.sh && echo "syntax OK"`
Expected: `syntax OK`.

- [ ] **Step 3: Commit**

```bash
git add uninstall.sh
git commit -m "feat: add uninstall script"
```

---

### Task 7: npm package (channel C)

**Files:**
- Create: `npm/package.json`, `npm/lib/config.js`, `npm/lib/launchagent.js`, `npm/lib/download.js`, `npm/lib/install.js`, `npm/bin/cli.js`
- Test: `npm/test/config.test.js`, `npm/test/launchagent.test.js`
- Create: `LICENSE`

This task uses TDD for the two pure helper modules (`config.js`, `launchagent.js`). The I/O-heavy modules (`download.js`, `install.js`, `cli.js`) are verified manually against a real release, because mocking the network and filesystem here would add more code than it protects.

- [ ] **Step 1: Create `npm/package.json`**

```json
{
  "name": "power-menu",
  "version": "1.0.0",
  "description": "Menu-bar control panel for macOS AC-power timers",
  "bin": {
    "power-menu": "bin/cli.js"
  },
  "files": [
    "bin",
    "lib"
  ],
  "scripts": {
    "test": "node --test"
  },
  "os": [
    "darwin"
  ],
  "engines": {
    "node": ">=22"
  },
  "license": "MIT",
  "repository": {
    "type": "git",
    "url": "git+https://github.com/minhnhat08/power-menu.git"
  },
  "homepage": "https://github.com/minhnhat08/power-menu#readme"
}
```

- [ ] **Step 2: Write the failing test for `config.js`**

Create `npm/test/config.test.js`:

```js
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { paths, assetUrl } = require('../lib/config');

test('paths derives app and plist locations from a home dir', () => {
  const p = paths('/Users/test');
  assert.strictEqual(p.appDir, '/Users/test/Applications');
  assert.strictEqual(p.appDest, '/Users/test/Applications/PowerMenu.app');
  assert.strictEqual(
    p.execPath,
    '/Users/test/Applications/PowerMenu.app/Contents/MacOS/PowerMenu'
  );
  assert.strictEqual(
    p.plistPath,
    '/Users/test/Library/LaunchAgents/com.minhnhat.powermenu.plist'
  );
});

test('assetUrl builds a version-pinned release download URL', () => {
  assert.strictEqual(
    assetUrl('1.2.3', 'PowerMenu.app.zip'),
    'https://github.com/minhnhat08/power-menu/releases/download/v1.2.3/PowerMenu.app.zip'
  );
});
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd npm && node --test test/config.test.js`
Expected: FAIL — cannot find module `../lib/config`.

- [ ] **Step 4: Implement `npm/lib/config.js`**

```js
'use strict';
const os = require('os');
const path = require('path');

const REPO = 'minhnhat08/power-menu';
const LABEL = 'com.minhnhat.powermenu';
const APP_NAME = 'PowerMenu.app';

function paths(home = os.homedir()) {
  const appDir = path.join(home, 'Applications');
  const appDest = path.join(appDir, APP_NAME);
  return {
    appDir,
    appDest,
    execPath: path.join(appDest, 'Contents', 'MacOS', 'PowerMenu'),
    plistPath: path.join(home, 'Library', 'LaunchAgents', `${LABEL}.plist`),
  };
}

function assetUrl(version, asset) {
  return `https://github.com/${REPO}/releases/download/v${version}/${asset}`;
}

module.exports = { REPO, LABEL, APP_NAME, paths, assetUrl };
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd npm && node --test test/config.test.js`
Expected: PASS (2 tests).

- [ ] **Step 6: Write the failing test for `launchagent.js`**

Create `npm/test/launchagent.test.js`:

```js
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { renderPlist } = require('../lib/launchagent');

test('renderPlist embeds the label, executable path, and RunAtLoad', () => {
  const xml = renderPlist(
    '/Users/test/Applications/PowerMenu.app/Contents/MacOS/PowerMenu'
  );
  assert.match(xml, /<string>com\.minhnhat\.powermenu<\/string>/);
  assert.match(
    xml,
    /<string>\/Users\/test\/Applications\/PowerMenu\.app\/Contents\/MacOS\/PowerMenu<\/string>/
  );
  assert.match(xml, /<key>RunAtLoad<\/key><true\/>/);
});
```

- [ ] **Step 7: Run the test to verify it fails**

Run: `cd npm && node --test test/launchagent.test.js`
Expected: FAIL — cannot find module `../lib/launchagent`.

- [ ] **Step 8: Implement `npm/lib/launchagent.js`**

```js
'use strict';
const { LABEL } = require('./config');

function renderPlist(execPath) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array><string>${execPath}</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
</dict>
</plist>
`;
}

module.exports = { renderPlist };
```

- [ ] **Step 9: Run the test to verify it passes**

Run: `cd npm && node --test test/launchagent.test.js`
Expected: PASS (1 test).

- [ ] **Step 10: Implement `npm/lib/download.js`**

```js
'use strict';
const https = require('https');
const crypto = require('crypto');

// GET a URL into a Buffer, following GitHub's redirects to release storage.
function fetch(url) {
  return new Promise((resolve, reject) => {
    https
      .get(url, { headers: { 'User-Agent': 'power-menu-cli' } }, (res) => {
        const { statusCode, headers } = res;
        if (statusCode >= 300 && statusCode < 400 && headers.location) {
          res.resume();
          resolve(fetch(headers.location));
          return;
        }
        if (statusCode !== 200) {
          res.resume();
          reject(new Error(`Request to ${url} failed: HTTP ${statusCode}`));
          return;
        }
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => resolve(Buffer.concat(chunks)));
      })
      .on('error', reject);
  });
}

function sha256(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

module.exports = { fetch, sha256 };
```

- [ ] **Step 11: Implement `npm/lib/install.js`**

```js
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const { paths, assetUrl } = require('./config');
const { fetch, sha256 } = require('./download');
const { renderPlist } = require('./launchagent');

const ZIP = 'PowerMenu.app.zip';

function assertMacOS() {
  if (process.platform !== 'darwin') {
    throw new Error('PowerMenu is macOS only.');
  }
}

function bootoutAgent(p) {
  const domain = `gui/${process.getuid()}`;
  try {
    execFileSync('/bin/launchctl', ['bootout', domain, p.plistPath], {
      stdio: 'ignore',
    });
  } catch {
    // not loaded — fine
  }
}

async function install(version) {
  assertMacOS();
  const p = paths();
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'power-menu-'));
  try {
    console.log(`Downloading PowerMenu v${version}...`);
    const zip = await fetch(assetUrl(version, ZIP));
    const sumText = (await fetch(assetUrl(version, `${ZIP}.sha256`))).toString(
      'utf8'
    );
    const expected = sumText.trim().split(/\s+/)[0];
    const actual = sha256(zip);
    if (expected !== actual) {
      throw new Error(`Checksum mismatch: expected ${expected}, got ${actual}`);
    }

    const zipPath = path.join(tmp, ZIP);
    fs.writeFileSync(zipPath, zip);

    bootoutAgent(p);
    fs.rmSync(p.appDest, { recursive: true, force: true });
    fs.mkdirSync(p.appDir, { recursive: true });

    execFileSync('/usr/bin/ditto', ['-x', '-k', zipPath, tmp]);
    fs.renameSync(path.join(tmp, 'PowerMenu.app'), p.appDest);
    execFileSync('/usr/bin/xattr', [
      '-dr',
      'com.apple.quarantine',
      p.appDest,
    ]);

    fs.mkdirSync(path.dirname(p.plistPath), { recursive: true });
    fs.writeFileSync(p.plistPath, renderPlist(p.execPath));
    execFileSync('/bin/launchctl', [
      'bootstrap',
      `gui/${process.getuid()}`,
      p.plistPath,
    ]);

    execFileSync('/usr/bin/open', [p.appDest]);
    console.log(`Installed to ${p.appDest}`);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

function uninstall() {
  assertMacOS();
  const p = paths();
  bootoutAgent(p);
  fs.rmSync(p.plistPath, { force: true });
  fs.rmSync(p.appDest, { recursive: true, force: true });
  console.log('PowerMenu removed.');
}

module.exports = { install, uninstall, assertMacOS };
```

- [ ] **Step 12: Implement `npm/bin/cli.js`**

```js
#!/usr/bin/env node
'use strict';
const { install, uninstall } = require('../lib/install');
const { version } = require('../package.json');

async function main() {
  const cmd = process.argv[2] || 'install';
  try {
    if (cmd === 'install') {
      await install(version);
    } else if (cmd === 'uninstall') {
      uninstall();
    } else {
      console.error(
        `Unknown command: ${cmd}\nUsage: power-menu [install|uninstall]`
      );
      process.exit(1);
    }
  } catch (err) {
    console.error(`Error: ${err.message}`);
    process.exit(1);
  }
}

main();
```

- [ ] **Step 13: Make the CLI executable**

Run: `chmod +x npm/bin/cli.js`

- [ ] **Step 14: Create `LICENSE` (MIT)**

```
MIT License

Copyright (c) 2026 minhnhat08

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 15: Run the full npm test suite**

Run: `cd npm && node --test`
Expected: all tests PASS (3 tests total across `config.test.js` and `launchagent.test.js`).

- [ ] **Step 16: Commit**

```bash
git add npm LICENSE
git commit -m "feat: add npx installer package"
```

---

### Task 8: CI release workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Create `.github/workflows/release.yml`**

```yaml
name: release

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: macos-14
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4

      - name: Install shellcheck
        run: brew install shellcheck

      - name: Lint shell scripts
        run: shellcheck install.sh uninstall.sh build.sh scripts/build-app.sh

      - name: Build universal app
        run: VERSION="${GITHUB_REF_NAME#v}" bash scripts/build-app.sh

      - name: Verify artifact
        run: |
          info="$(lipo -info dist/PowerMenu.app/Contents/MacOS/PowerMenu)"
          echo "$info"
          echo "$info" | grep -q 'arm64'
          echo "$info" | grep -q 'x86_64'
          codesign -dv dist/PowerMenu.app

      - name: Package and checksum
        run: |
          cd dist
          ditto -c -k --keepParent PowerMenu.app PowerMenu.app.zip
          shasum -a 256 PowerMenu.app.zip > PowerMenu.app.zip.sha256

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: |
            dist/PowerMenu.app.zip
            dist/PowerMenu.app.zip.sha256

  publish-npm:
    needs: release
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '22'
          registry-url: 'https://registry.npmjs.org'

      - name: Set package version from tag
        run: cd npm && npm version "${GITHUB_REF_NAME#v}" --no-git-tag-version --allow-same-version

      - name: Run tests
        run: cd npm && node --test

      - name: Publish to npm
        run: cd npm && npm publish --access public
        env:
          NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}
```

- [ ] **Step 2: Validate the workflow YAML parses**

Run: `node -e "const fs=require('fs');const s=fs.readFileSync('.github/workflows/release.yml','utf8');if(!/on:\s/.test(s)||!/jobs:/.test(s))throw new Error('missing keys');console.log('yaml shape OK')"`
Expected: `yaml shape OK`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: build, release, and publish on tag push"
```

- [ ] **Step 4: Confirm the NPM_TOKEN secret prerequisite**

This is a manual repo-owner action, not code. Confirm the `NPM_TOKEN` Actions secret exists (Settings → Secrets and variables → Actions). The `publish-npm` job fails without it. No commit.

---

### Task 9: README with three install methods

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace the "Build / install" and "Auto-start at login" sections**

In `README.md`, replace everything from the `## Build / install` heading through the end of the `## Auto-start at login` section with:

````markdown
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
````

- [ ] **Step 2: Verify the README mentions all three channels**

Run: `grep -qE 'brew install --cask' README.md && grep -q 'install.sh' README.md && grep -q 'npx power-menu' README.md && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document Homebrew, install script, and npx install methods"
```

---

### Task 10: Homebrew tap + cask (separate repo)

This task operates on the **separate** public repo `minhnhat08/homebrew-tap`. It depends on at least one published release (Task 8) so the cask's `sha256` and `version` are real. The cask is not stored in the `power-menu` repo.

- [ ] **Step 1: Create the tap repo (if it does not exist)**

Run: `gh repo create minhnhat08/homebrew-tap --public --description "Homebrew tap for minhnhat08 tools" --clone && cd homebrew-tap && mkdir -p Casks`
Expected: repo created and cloned, `Casks/` directory exists.

- [ ] **Step 2: Fetch the released zip's version and checksum**

Run (replace `vX.Y.Z` with the actual latest tag if needed):
```bash
gh release download --repo minhnhat08/power-menu --pattern 'PowerMenu.app.zip.sha256' --output /tmp/pm.sha256
cat /tmp/pm.sha256
gh release view --repo minhnhat08/power-menu --json tagName --jq .tagName
```
Expected: prints `<sha256>  PowerMenu.app.zip` and the tag like `v1.0.0`. Use the hash (first field) and the tag without the leading `v` as the version below.

- [ ] **Step 3: Create `Casks/power-menu.rb` in the tap repo**

Substitute `VERSION_HERE` (e.g. `1.0.0`) and `SHA256_HERE` (the hash from Step 2):

```ruby
cask "power-menu" do
  version "VERSION_HERE"
  sha256 "SHA256_HERE"

  url "https://github.com/minhnhat08/power-menu/releases/download/v#{version}/PowerMenu.app.zip"
  name "PowerMenu"
  desc "Menu-bar control panel for macOS AC-power timers"
  homepage "https://github.com/minhnhat08/power-menu"

  depends_on macos: ">= :ventura"

  app "PowerMenu.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/PowerMenu.app"]
    plist = File.expand_path("~/Library/LaunchAgents/com.minhnhat.powermenu.plist")
    File.write(plist, <<~XML)
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
          <key>Label</key><string>com.minhnhat.powermenu</string>
          <key>ProgramArguments</key>
          <array><string>#{appdir}/PowerMenu.app/Contents/MacOS/PowerMenu</string></array>
          <key>RunAtLoad</key><true/>
          <key>KeepAlive</key><false/>
      </dict>
      </plist>
    XML
    system_command "/bin/launchctl", args: ["bootout", "gui/#{Process.uid}", plist], must_succeed: false
    system_command "/bin/launchctl", args: ["bootstrap", "gui/#{Process.uid}", plist]
  end

  uninstall launchctl: "com.minhnhat.powermenu"

  zap trash: [
    "~/Library/LaunchAgents/com.minhnhat.powermenu.plist",
  ]
end
```

- [ ] **Step 4: Validate and test-install the cask**

Run:
```bash
brew style --cask Casks/power-menu.rb
brew install --cask ./Casks/power-menu.rb
test -d "/Applications/PowerMenu.app" -o -d "$HOME/Applications/PowerMenu.app" && echo "cask install OK"
```
Expected: `brew style` passes, install succeeds, prints `cask install OK`, and the bolt icon appears with no Gatekeeper warning.

- [ ] **Step 5: Commit and push the tap**

```bash
git add Casks/power-menu.rb
git commit -m "feat: add power-menu cask"
git push -u origin main
```

- [ ] **Step 6: Verify the public tap install path**

Run: `brew uninstall --cask power-menu 2>/dev/null; brew install --cask minhnhat08/tap/power-menu && echo "tap install OK"`
Expected: `tap install OK`.

---

## Final acceptance (after first release is published)

These steps validate the whole pipeline end to end. Run them once Task 8 has produced a release (push a tag, e.g. `git tag v1.0.0 && git push origin v1.0.0`, and wait for the Actions run to finish).

- [ ] **A1: Release artifacts exist**

Run: `gh release view --repo minhnhat08/power-menu --json assets --jq '.assets[].name'`
Expected: lists `PowerMenu.app.zip` and `PowerMenu.app.zip.sha256`.

- [ ] **A2: Install script path**

Run: `curl -fsSL https://raw.githubusercontent.com/minhnhat08/power-menu/main/install.sh | bash`
Expected: downloads, verifies checksum, the bolt icon appears with **no** Gatekeeper warning, menu is in English. Then run the `uninstall.sh` one-liner and confirm `~/Applications/PowerMenu.app` and the plist are gone.

- [ ] **A3: npx path**

Run: `npx power-menu@latest` then `npx power-menu@latest uninstall`
Expected: same installed state as A2 (app at `~/Applications/PowerMenu.app`, LaunchAgent loaded), then clean removal.

- [ ] **A4: Channel parity**

Confirm all three channels install to `~/Applications/PowerMenu.app` (Homebrew may use `/Applications` per cask `appdir`) and register the same LaunchAgent label `com.minhnhat.powermenu`, and that "Start at login" toggles correctly in each.

---

## Self-review notes

- **Spec coverage:** UI→English (Task 1), universal build (Task 2), build.sh refactor (Task 3), LaunchAgent generation (Tasks 4/5/7/10), install script + uninstall (Tasks 5/6), npx package (Task 7), CI build+release+publish (Task 8), README three methods (Task 9), Homebrew tap/cask (Task 10), public-repo + NPM_TOKEN prerequisites (Prerequisites + Task 8 Step 4). Error handling (macOS guard, checksum verify, safe replace) is in install.sh, uninstall.sh, and install.js. Testing (shellcheck, lipo/codesign, manual acceptance) is in Task 8 and Final acceptance.
- **Naming consistency:** asset names (`PowerMenu.app.zip`, `PowerMenu.app.zip.sha256`), label (`com.minhnhat.powermenu`), bundle id, repo (`minhnhat08/power-menu`), tap (`minhnhat08/homebrew-tap`), and npm name (`power-menu`) are identical across all tasks. The "latest release redirect" URL is used by `install.sh`; the version-pinned `releases/download/v<version>/` URL is used by the npm CLI and cask — intentional and consistent with the spec's versioning section.
- **Cross-language duplication:** the LaunchAgent plist appears in the template (Task 4), install.sh (Task 5), launchagent.js (Task 7), and the cask (Task 10). This is intentional — the installers run detached from a repo checkout and in different languages, so a single shared file is not reachable. All copies use the same label, RunAtLoad, and KeepAlive.

## Post-implementation deltas

The shipped code is the source of truth. During the two-stage review the
following hardening was added beyond the task snippets above (the snippets are
left as the original plan for the record):

- `install.sh`: uses the absolute `/usr/bin/xattr` instead of bare `xattr`. A
  PyPI `xattr` shim on `PATH` lacks the `-r` flag and would silently fail to
  strip the quarantine attribute, re-triggering the Gatekeeper warning. (Task 5)
- `install.sh`: the final echo drops the emoji (project rule: no emojis). (Task 5)
- `npm/package.json`: adds `"engines": { "node": ">=22" }`. (Task 7)
- `npm/lib/download.js`: `fetch` takes a redirect budget (default 5) and rejects
  on too many redirects, preventing an unbounded recursion. (Task 7)
- `npm/lib/launchagent.js`: `renderPlist` XML-escapes the executable path. (Task 7)
- `npm/lib/install.js`: guards a malformed/empty SHA-256 file, asserts the
  extracted `PowerMenu.app` exists before rename, and makes the final `open`
  non-fatal so a launch failure does not mask a successful install. (Task 7)
