# PowerMenu Distribution Design

- **Date:** 2026-05-31
- **Status:** Approved
- **Scope:** Packaging, distribution, and UI localization. No new app features.

## Problem

PowerMenu is a macOS menu-bar app (single-file Swift, `main.swift`) that can
currently only be built on the author's machine via `build.sh`. There is no way
for other people to install it conveniently. The goal is to make it installable
on other Macs through low-friction channels: a one-line install script,
Homebrew, and `npx`.

### Constraints and facts

- **macOS only.** The app drives `pmset`/`launchctl`; there is no Windows/Linux
  port. Installers must refuse to run on non-macOS.
- **Unsigned distribution.** No Apple Developer Program. The app is ad-hoc
  signed (`codesign --sign -`). Since macOS 15 Sequoia removed the
  right-click -> Open Gatekeeper bypass, each installer strips the quarantine
  attribute (`xattr -dr com.apple.quarantine`) so the app launches cleanly.
- **Universal binary.** Artifacts must run on both Apple Silicon (arm64) and
  Intel (x86_64), produced by compiling both slices and merging with `lipo`.
- **English UI.** All user-facing strings move from Vietnamese to English.
- **Identity.** Repo `github.com/minhnhat08/power-menu`; npm package
  `power-menu` (verified available); Homebrew tap `minhnhat08/homebrew-tap`;
  app name `PowerMenu`; bundle id `com.minhnhat.powermenu` (unchanged);
  LaunchAgent label `com.minhnhat.powermenu` (unchanged).
- **Public repos.** Both `power-menu` and `homebrew-tap` are public. Frictionless
  installs require publicly downloadable release assets and a public raw
  `install.sh` URL; GitHub does not serve private releases or raw files without
  auth. The source contains no secrets, so public exposure is safe.

### Known gap to fix

The README references `~/Library/LaunchAgents/com.minhnhat.powermenu.plist`, but
no plist exists in the repo. It is a manual file on the author's machine. The
installers must generate this plist dynamically, pointing at the installed app's
executable, or "Start at login" will break on other machines.

## Architecture: one artifact, three channels

Every install channel consumes the **same** artifact: a universal, ad-hoc-signed
`PowerMenu.app`, zipped and attached to a GitHub Release. No channel rebuilds
from source on the user's machine.

```
git tag vX.Y.Z
   |
   v
GitHub Actions (macOS runner)
   |- build universal .app (swiftc arm64 + x86_64 -> lipo)
   |- inject version into Info.plist
   |- zip + generate SHA-256 checksum
   |- create GitHub Release + attach PowerMenu.app.zip + checksum
   '- npm publish (package version = tag)
   |
   v
User picks one of three channels --> download release zip --> verify checksum
   --> unzip into ~/Applications --> xattr -dr com.apple.quarantine
   --> generate + load LaunchAgent (optional) --> launch app
```

### Versioning

Single source of truth is the git tag `vX.Y.Z`. CI injects it into the
`Info.plist` `CFBundleShortVersionString`, names the release, and sets the npm
package version. The install script and Homebrew cask fetch the latest release;
the npm package pins the exact matching release version.

## Components

### 1. Source changes (`main.swift`)

- Translate all UI strings to English:
  - "Turn display off after", "Sleep after", "Never", "{n} min",
    "Current (AC): display {…} · sleep {…}", "Start at login", "Quit".
- `pmset`/`launchctl` logic, options arrays, and behavior unchanged.
- Bundle id and LaunchAgent label unchanged.

### 2. Build pipeline (`scripts/build-app.sh`)

Replaces the single-arch logic in `build.sh`:

- Compile `main.swift` for `arm64-apple-macos13` and `x86_64-apple-macos13`.
- `lipo -create` the two slices into one universal executable.
- Assemble the `.app` bundle and write `Info.plist`, taking the version from an
  environment variable (default to a dev placeholder for local builds).
- `codesign --force --sign -` (ad-hoc).
- Output to `dist/PowerMenu.app` (the existing `build.sh` behavior of installing
  to `~/Applications` is preserved as a thin local-dev convenience that calls
  this script, or `build.sh` is kept for local installs and the new script is
  used by CI).

A companion step zips `dist/PowerMenu.app` into `PowerMenu.app.zip` and emits a
SHA-256 checksum file.

### 3. CI/CD (`.github/workflows/release.yml`)

Triggered on tag push `v*`, runs on a macOS runner:

1. `shellcheck` the shell scripts.
2. Build the universal app via `scripts/build-app.sh` with the tag as version.
3. Verify the result: `lipo -info` shows both arches; `codesign -dv` succeeds;
   bundle structure is correct.
4. Zip and checksum.
5. Create the GitHub Release and attach `PowerMenu.app.zip` + checksum.
6. Publish the npm package from `npm/` with the tag version.

### 4. LaunchAgent generation

A template `scripts/launchagent.plist.template` with a placeholder for the
executable path. Installers render it to
`~/Library/LaunchAgents/com.minhnhat.powermenu.plist` with
`ProgramArguments` pointing at
`~/Applications/PowerMenu.app/Contents/MacOS/PowerMenu`, then
`launchctl bootstrap "gui/$UID" <plist>`. Uninstall does `launchctl bootout`
and removes the plist.

## Channels

### Channel A — install script

`install.sh` in the repo root, served via raw URL:

```bash
curl -fsSL https://raw.githubusercontent.com/minhnhat08/power-menu/main/install.sh | bash
```

Steps: assert macOS; fetch latest release metadata via the GitHub API; download
`PowerMenu.app.zip`; verify SHA-256 against the checksum asset; unzip into
`~/Applications/PowerMenu.app` (replacing any existing install); strip
quarantine; generate and load the LaunchAgent; launch the app. A matching
`uninstall.sh` reverses every step.

### Channel B — Homebrew tap

A separate repo `minhnhat08/homebrew-tap` with `Casks/power-menu.rb`:

```bash
brew install --cask minhnhat08/tap/power-menu
```

The cask points at the release zip with its SHA-256, installs
`PowerMenu.app`, uses a `postflight` to strip quarantine and (optionally) load
the LaunchAgent, and a `zap` stanza to remove the app, plist, and preferences on
uninstall. `brew upgrade` handles updates. The cask file is created in the tap
repo; the main repo's release feeds it.

### Channel C — npx package

Package `power-menu` under `npm/` in the repo:

```bash
npx power-menu             # equivalent to: npx power-menu install
npx power-menu uninstall
```

`bin/cli.js` is plain Node (no heavy dependencies). On `install` it downloads
the release zip matching the package version, verifies the checksum, unzips into
`~/Applications`, strips quarantine, generates and loads the LaunchAgent, and
launches the app. It refuses to run on non-macOS with a clear message.
`uninstall` reverses the steps.

## Repository structure

```
power-menu/
├─ main.swift                         # UI strings -> English
├─ build.sh                           # local dev install (calls build-app.sh)
├─ scripts/
│  ├─ build-app.sh                    # universal .app build
│  └─ launchagent.plist.template
├─ install.sh                         # channel A
├─ uninstall.sh
├─ npm/
│  ├─ package.json                    # name: power-menu, bin: power-menu
│  ├─ bin/cli.js
│  └─ lib/                            # download/verify/install helpers
├─ .github/workflows/release.yml      # build + release + npm publish
├─ docs/superpowers/specs/            # this spec
└─ README.md                          # three install methods
```

The Homebrew cask lives in the separate `minhnhat08/homebrew-tap` repo and is
not part of this repository's structure.

## Error handling

- **All installers:** refuse to run unless the OS is macOS (`uname` == Darwin);
  verify the downloaded zip's SHA-256 before installing; replace an existing
  install safely; print a clear message on network or download failure rather
  than leaving a half-installed state.
- **npx:** detect non-macOS early and exit with guidance; surface download and
  unzip errors with actionable text.
- **App runtime:** behavior unchanged from today (admin-auth prompt for `pmset`,
  graceful `NSLog` on `pmset` failure).

## Testing

- **CI:** `shellcheck` on shell scripts; post-build `lipo -info` confirms both
  arches; `codesign -dv` confirms the ad-hoc signature; bundle-structure check.
- **Manual acceptance:** run `install.sh` on a clean macOS user account and
  confirm the app launches with **no** Gatekeeper warning, the menu shows
  English strings, the values reflect `pmset -g custom`, and "Start at login"
  toggles the LaunchAgent. Then run `uninstall.sh` and confirm full removal.
- **Channel parity:** confirm Homebrew and `npx` installs produce the same
  installed state (same app path, same loaded LaunchAgent) as the script.

## Out of scope

- New app features or option changes.
- Localization framework / multi-language support (UI is English only).
- Apple Developer Program signing and notarization.
- Windows/Linux support.
- In-app auto-update (updates happen via re-running the installer or
  `brew upgrade`).
```
