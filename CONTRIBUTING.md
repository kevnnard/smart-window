# Contributing to SmartWindow

Thanks for your interest in SmartWindow. This guide covers building from source,
installing a local app bundle, the verification probes, how the repository is
organized, and how maintainers cut a release.

For what the app does and how to use it, see the [README](README.md).

SmartWindow is source-available under the
[SmartWindow Public Non-Commercial License v1.1](LICENSE); read it before contributing.

## Requirements

- **macOS 13 or newer.** Development is primarily on Apple Silicon and macOS beta
  builds; Intel compatibility is not comprehensively verified.
- **Swift 5.9+ toolchain** (Xcode or the Command Line Tools).
- Accessibility permission for the build you run (see [Permissions in development](#permissions-in-development)).

## Build from source

From the repository root:

```bash
swift build
swift run SmartWindow
```

To open Settings at launch:

```bash
swift run SmartWindow --settings
```

A development executable is not a signed app bundle: its icon, version label, and
permission behavior can differ from the installed app. Launch at login is
unavailable in an unbundled debug executable.

### Now Playing in debug runs

The app reads Now Playing sessions through the vendored
[mediaremote-adapter](Vendor/mediaremote-adapter) and its own media sessions helper
(`Helpers/MediaSessions`). `scripts/install-app.sh` builds and bundles them
automatically. For a `swift run` debug build, build them once into `.build/` so the
app can find them:

```bash
./scripts/build-mediaremote-adapter.sh
```

Without them, only Spotify and Music (through AppleScript) are shown.

### Install a local app bundle

```bash
./scripts/install-app.sh
```

This builds a release bundle and **replaces** `/Applications/SmartWindow.app`.
To create the repository-local bundle without replacing the installed app:

```bash
SMARTWINDOW_SKIP_INSTALL=1 ./scripts/install-app.sh
```

Signing is optional for local builds. When a signing identity is supplied
(`SMARTWINDOW_CODESIGN_IDENTITY`), the installer uses
`Resources/SmartWindow.entitlements` by default, including the Apple Events
entitlement needed for player automation.

The packager resolves the executable with `swift build -c release --show-bin-path`.
It stops with `Error: could not find built executable at <path>` before replacing
the bundle if that exact output is missing; it never falls back to an older build.

### Permissions in development

macOS tracks permissions per app identity, so a debug executable, a local bundle and
the Homebrew release are granted separately. Test permission-dependent features
(Accessibility, Automation, Full Disk Access for the Focus name, Focus Status) on the
**installed bundle**. After replacing the bundle, macOS may keep a stale Full Disk
Access entry; remove SmartWindow from Full Disk Access, add it again and relaunch.

## Verification

The package currently has no automated SwiftPM test target. Standalone probes in
`Tests/Probes/` check behavior without touching your real settings, playback, VPN or
login items.

The packaging probe runs the public installer against an isolated fake Swift
toolchain, without installing or signing. It verifies fresh-output selection and
preserves an existing bundle when Swift's reported executable is missing:

```bash
mkdir -p .build/probes
python3 Tests/Probes/ReleasePackagingProbe.py
```

The Tailscale probe covers state parsing, duration boundaries, bounded subprocess
handling, and the sleep-reset notification without changing VPN state:

```bash
swiftc Sources/Services/TailscaleService.swift Tests/Probes/TailscaleProbe.swift -o .build/tailscale-probe
.build/tailscale-probe
```

The keyboard probe checks native source listing, labels, and rejection of an
unknown source without changing the active keyboard:

```bash
mkdir -p .build/probes
swiftc Sources/Services/KeyboardInputService.swift Tests/Probes/KeyboardInputProbe.swift -o .build/probes/keyboard-input-probe
.build/probes/keyboard-input-probe
```

For a live selection and notification check, add `--switch`. This requires two
enabled keyboard sources, briefly changes the active source, and restores the
original source when the check returns, including on reported failures:

```bash
.build/probes/keyboard-input-probe --switch
```

Desktop-controls probes use fake login/player executors and isolated preference
suites; they do not register login items, change playback, or overwrite your settings:

```bash
mkdir -p .build/probes
swiftc Sources/Services/LoginItemService.swift Tests/Probes/LoginItemProbe.swift -o .build/probes/login-item-probe
.build/probes/login-item-probe
swiftc -parse-as-library Tests/Probes/NowPlayingControlsProbe.swift Sources/Services/NowPlayingService.swift \
  Sources/Services/MediaRemoteAdapterClient.swift Sources/Services/MediaRemoteAdapterLocator.swift \
  Sources/Services/MediaSessionsClient.swift -o .build/probes/media-controls-probe
.build/probes/media-controls-probe
swiftc Sources/Models/WindowOverflowPolicy.swift Tests/Probes/WindowOverflowProbe.swift -o .build/probes/overflow-probe
.build/probes/overflow-probe
swiftc Sources/Models/DisplayPreferences.swift Tests/Probes/DisplayPreferencesProbe.swift -o .build/probes/displays-probe
.build/probes/displays-probe
swiftc Sources/Models/FocusMode.swift Sources/Models/DisplayPreferences.swift Tests/Probes/FocusModeProbe.swift -o .build/probes/focus-probe
.build/probes/focus-probe
```

`Tests/Probes/` also holds probes for the notch (hover, settings, system HUD, Focus
HUD), per-display settings and scope, permissions, media sessions and the adapter,
status scrolling, and the release script. Each one is a standalone file; compile it
with `swiftc` together with the `Sources/` files it uses, as in the commands above.
The release script runs every `Tests/Probes/*.py` probe.

Hardware readings, player permissions, and UI behavior still need checks on a real
Mac. The notch was checked on a 14" MacBook display alongside an external monitor;
other MacBook sizes, monitor reconnection and installed login-item flows have not
been fully checked.

## Repository map

```text
SmartWindow/
├── Package.swift                  # macOS executable and dependencies
├── Resources/                     # App icon, Info.plist, entitlements, release notes
├── Sources/
│   ├── App/                       # Lifecycle, settings window, global shortcuts
│   ├── Models/                    # Window models, persisted and per-display settings,
│   │                              # Focus and system HUD state, permissions
│   ├── Services/                  # Accessibility, metrics, media, HUD, Focus, Tailscale
│   └── Views/
│       ├── Components/            # Window tabs and status widgets
│       ├── Notch/                 # Per-screen notch layout, drawer, HUD and panel
│       ├── Settings/              # Display scope helpers for Bar & Notch
│       ├── BarAndNotchPane.swift  # Display map, live preview, Bar/Widgets/Notch tabs
│       ├── PermissionsPane.swift  # Permissions page
│       ├── SettingsView.swift     # Settings sidebar and App panes
│       └── TabBarView.swift       # Main bar composition
├── Helpers/MediaSessions/         # Helper that reads every Now Playing session
├── Vendor/mediaremote-adapter/    # Vendored adapter (BSD-3-Clause)
├── Tests/Probes/                  # Standalone verification probes
├── design/                        # HTML design explorations for notch and Settings
├── docs/images/                   # README images
└── scripts/                       # Local install, adapter build and release tooling
```

### Design explorations

`design/` holds self-contained HTML artboards that explored each larger UI change
before it was built (for example `design/notch-system-hud/` for the volume and
brightness wings, `design/notch-focus-hud/` for Focus, and
`design/settings-unified/` for the display map). Open the `.html` files in a browser;
`design.json` in each folder lists the directions and their tradeoffs.

## Maintainer release workflow

Publishing is separate from building or installing locally. `scripts/release.sh`
cuts a release from `main` with no tracked changes and expects a sibling
`../homebrew-tap` checkout (override with `TAP_DIR`). Preview the plan first, then
release:

```bash
./scripts/release.sh --dry-run 0.5.0   # runs the checks and tests, changes nothing
./scripts/release.sh 0.5.0
```

In order, it:

1. Checks the branch, tracked changes, that `v0.5.0` does not exist locally or on
   `origin`, the tap checkout, the signing environment, and `gh auth`.
2. Runs `swift build -c release` and every `Tests/Probes/*.py` probe.
3. Sets `CFBundleShortVersionString` to `0.5.0`, bumps `CFBundleVersion` in
   `Resources/Info.plist`, and commits `chore(release): v0.5.0`.
4. Builds, signs, and notarizes `SmartWindow.zip` in a temporary directory, so the
   tracked `SmartWindow.zip` is never modified.
5. Tags `v0.5.0`, pushes `main` and the tag, and creates the GitHub release with
   the zip attached.
6. Rewrites `Casks/smartwindow.rb` in the tap with the new version and checksum,
   then commits and pushes the tap.

Release notes come from `Resources/ReleaseNotes-0.5.0.md` when that file exists;
otherwise GitHub generates them. Commit the notes before releasing.

### Signing and notarization

Signing and notarization are required for releases. The script sources
`scripts/release-env.sh` when it exists; copy `scripts/release-env.example.sh` to
create it, or export the variables yourself:

```bash
export SMARTWINDOW_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export SMARTWINDOW_NOTARY_PROFILE="smartwindow-notary"
```

Create the notary profile once:

```bash
xcrun notarytool store-credentials "smartwindow-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

The same signing identity variable also applies to `scripts/install-app.sh`.
`scripts/release-env.sh` is ignored by Git; never commit credentials.

## Roadmap

- Improve overflow behavior with many window tabs.
- Expand hardware and macOS compatibility checks.
- Validate other MacBook notch sizes, monitor reconnection and installed login-item flows.
