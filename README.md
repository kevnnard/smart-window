<div align="center">

<img src="Resources/AppIcon.iconset/icon_512x512.png" alt="SmartWindow logo" width="140" />

# SmartWindow

**Your windows, music, and system status. One macOS bar.**

A native SwiftUI menu bar overlay inspired by Polybar and Waybar.<br/>
Switch windows by number, keep your music in sight, and make the bar yours.

[![Release](https://img.shields.io/badge/release-v0.4.0-2f855a?style=for-the-badge)](https://github.com/kevnnard/smart-window/releases/tag/v0.4.0)
[![macOS](https://img.shields.io/badge/macOS-13%2B-black?style=for-the-badge&logo=apple&logoColor=white)](#requirements)
[![Homebrew](https://img.shields.io/badge/Homebrew-cask-f6ad55?style=for-the-badge&logo=homebrew&logoColor=black)](#quick-start)
[![License](https://img.shields.io/badge/license-non--commercial-blue?style=for-the-badge)](LICENSE)

[Quick start](#quick-start) · [Features](#features) · [Settings](#settings) · [Shortcuts](#keyboard-shortcuts) · [Build from source](#build-from-source)

</div>

<p align="center">
  <img width="1512" height="982" alt="SmartWindow window tabs and system widgets on a macOS desktop" src="https://github.com/user-attachments/assets/4928ae2f-a722-41e8-9adf-6c85ff78ce71" />
</p>

<p align="center">
  <img width="1509" height="27" alt="Close-up of the SmartWindow top bar" src="https://github.com/user-attachments/assets/ade346d4-f75e-48b4-86f6-84a9a99b7e0c" />
</p>

> **v0.4.0:** the release includes the features below in a signed, notarized
> **Apple Silicon (arm64)** bundle. See the [release notes](Resources/ReleaseNotes-0.4.0.md)
> for changes and known validation limits. Intel users must build from source.
> The screenshots above are existing project images, not a preview of every setting.

---

## Quick start

### Install the published app

```bash
brew tap kevnnard/tap
brew install --cask smartwindow
```

1. Open **SmartWindow** from Applications.
2. Grant **Accessibility** access in System Settings → Privacy & Security → Accessibility.
3. Click a window tab or press **Option + 1–9** to switch windows.

SmartWindow runs as a menu bar utility, without a Dock icon. Open its menu bar
popover and choose **Open Settings** to customize it.

<details>
<summary>Upgrade or uninstall</summary>

```bash
# Upgrade the published app
brew update
brew upgrade --cask smartwindow

# Uninstall
brew uninstall --cask smartwindow
```

Homebrew installs the release bundle into `/Applications/SmartWindow.app`.

</details>

## Why SmartWindow?

Window switching should be direct, not a search through overlapping apps.
SmartWindow gives each open window a numbered tab and brings the essentials into
one compact bar, without asking you to adopt a tiling window manager.

- **Find the right window:** readable tabs, click-to-focus, and global shortcuts.
- **Keep context visible:** music, hardware readings, and timezones alongside your windows.
- **Fit your desktop:** per-monitor bars, fullscreen awareness, and optional widgets.

SmartWindow draws above the native menu bar; it does not replace macOS system menus
or automatically tile your windows.

## Features

### Window switching

Numbered tabs such as `1 · Finder`, `2 · Ghostty`, and `3 · Safari` let you focus a
window with a click or a shortcut. Each monitor gets its own bar, and entering
fullscreen hides the bar only on the affected screen.

Tabs size to their app names within readable bounds, with consistent spacing and
no width jump when selected. Hover a tab to see its full window title, including
when multiple windows belong to the same app. When tabs no longer fit, `+N` opens
a searchable list of all windows. Search by app or window title; Return selects
the first result. Original ordering, tab numbers, and ⌥1–9 shortcuts are preserved.

When Finder has no ordinary window to focus, selecting its desktop entry opens
the Desktop folder instead of doing nothing.

### Focus mode

Click the **moon** in the bar to hide secondary widgets on every display, leaving
window tabs, the clock and music. Click again to restore your global and per-display
widget choices, unchanged. The moon remains available so you can leave focus mode.
This setting persists across relaunches and is also available in Settings → General.

### Now Playing

A compact notch wraps the MacBook camera notch, or sits below the top edge on
displays without one. Hover or click it to open a drawer below with the artwork,
track, controls and every app currently playing.

<p align="center">
  <img width="640" alt="Compact SmartWindow notch around the MacBook camera" src="docs/images/notch-compact.png" />
</p>
<p align="center">
  <img width="640" alt="Open SmartWindow notch drawer with artwork, controls and source badges" src="docs/images/notch-expanded.png" />
</p>

- **Every Now Playing session:** Spotify, Music and browser media such as YouTube are
  read from macOS Now Playing, with title, artist, progress and artwork.
- **Stays put:** the compact row never moves; the details open underneath it, and the
  drawer closes shortly after the pointer leaves.
- **Choose the main source:** with several apps playing, a badge per app selects which
  one the notch shows.
- **Safe controls:** previous, play/pause and next target Spotify and Music directly. Other
  apps are controlled only while macOS reports them as the current Now Playing app;
  otherwise the controls are disabled with the reason. macOS offers no per-app command,
  so if the current app changes in the instant before a click, that click can reach it.
- **Click to return:** click the artwork to bring the player forward.

On a MacBook the notch is pure black, has no pixels over the camera, and its width
includes the camera notch. Automation permission is required to control Spotify and
Music. Paused browser tabs do not get a badge.

### System widgets

Choose which widgets to show, drag to reorder them, and add separators in Settings.

| Widget | What it reports | Important detail |
|:---|:---|:---|
| CPU | Usage calculated between processor tick samples | Not an average since boot |
| Memory | System memory usage | Displayed as a percentage |
| GPU | IOAccelerator device utilization | Availability depends on hardware and driver |
| Temperature | Readable CPU / GPU die sensors and macOS thermal state | Shows `--` when temperature is unavailable; Celsius or Fahrenheit |
| Microphone | Whether an input device is running | Device activity, not the configured input volume |
| Volume | Default output device volume and mute state | Shows a percentage, `MUTE`, or `--` when software volume is unsupported |
| Battery | Charge level and charging state | Depends on the Mac's battery hardware |
| Tailscale | Tailnet state and observed online duration | Optional; see [Tailscale](#tailscale) |
| Keyboard input | Active macOS keyboard input source | Click to switch between enabled sources; see [Keyboard input](#keyboard-input) |
| Clock | Date, time, and extra timezones | The clock remains at the far right |

Temperature uses private IOHID interfaces, so sensor support can vary between Macs
and macOS releases. An unavailable temperature or software volume is not replaced
with a made-up reading.

## Settings

A resizable window with a System Settings-style sidebar keeps controls grouped by purpose.

| Pane | Controls |
|:---|:---|
| **General** | Shortcut reference, app version, and Accessibility permission status |
| **Appearance** | Bar opacity from 60–100% and a live preview |
| **Widgets** | Global visibility, drag-to-reorder, separators, and temperature unit |
| **Notch** | Visibility (all displays, main display only, or per display), black or bar-colored style, default and per-display size, and expanded width |
| **Displays** | Per-monitor widget visibility: Default, Show, or Hide |
| **Clock** | Displayed timezone and searchable extra timezones |
| **Tailscale** | Installation / connection status, tailnet details, and the widget toggle |

The bar defaults to a neutral dark surface at **94% opacity**; the notch defaults
to **black**. Appearance and widget preferences persist between launches.

**Launch at login** registers the installed app with macOS Login Items using
`SMAppService`. macOS may require approval in System Settings; the General pane
shows that state and offers a link. Registration errors do not turn into a fake
successful toggle. This control is unavailable in an unbundled debug executable.
An old saved startup preference does not automatically register the app.

In **Displays**, choose a connected monitor and override each widget.
**Default** follows global settings; **Show** and **Hide** take precedence on that
monitor. Overrides use the display's CoreGraphics UUID and are retained across
reconnection. Widget order, clock settings and separators remain global.
"Use Default Widgets for This Display" resets only that monitor's overrides.

Every notch setting lives in **Notch**, including which monitors show it and a
custom size per monitor. A monitor set to Show or Hide there ignores the Default
setting. On a MacBook screen, status widgets that do not fit beside the notch scroll
horizontally; the clock stays visible at the right edge.

## Keyboard input

Enable **Keyboard input** in Settings → Widgets to show the active macOS keyboard
input source. Click the widget to open a native menu with the same enabled keyboard
sources and localized names used by the system Input menu; the active one is checked.
For example, **U.S.** appears as `US` in the bar and **Latin American** as `LAT`.
Other sources use a shortened name, with the full name in the menu and tooltip.

Selection uses macOS Text Input Source Services. Changing the source in the system
Input menu or with a macOS shortcut also updates the widget. SmartWindow does not
install or enable keyboard layouts, change your source list, or change the app's
interface language. The optional widget starts hidden and can be reordered like
other widgets.

## Tailscale

Already using [Tailscale](https://tailscale.com/)? Enable **Show Tailscale widget**
in Settings → Tailscale. It is optional and starts hidden. If Tailscale is not
installed, the pane links to the official macOS download and the widget stays hidden.

| Display | Meaning |
|:---|:---|
| Elapsed time, such as `1h 23m` | SmartWindow has continuously observed Tailscale online |
| `OFF` | Stopped, logged out, or awaiting authorization |
| `…` | Connecting |
| `--` | Status could not be read |

The service reads `tailscale status --json` every **five seconds**, using the
standard `/Applications/Tailscale.app` CLI or the Homebrew CLI locations
`/opt/homebrew/bin/tailscale` and `/usr/local/bin/tailscale`. Monitoring is read-only:
SmartWindow does not connect, disconnect, install, or reconfigure your VPN.

**The timer is observed online time, not the tunnel's actual connection age.**
It resets after disconnection, unavailable status, sleep, a long polling gap, or
restarting SmartWindow. Brief state changes between checks may be missed.

Tailscale provides encrypted connections within your tailnet. Being connected
**does not mean all internet traffic goes through a VPN**; that requires a
separately configured exit node.

## Keyboard shortcuts

| Shortcut | Action |
|:---|:---|
| `Option + Escape` | Show / hide SmartWindow |
| `Option + ]` | Focus next window |
| `Option + [` | Focus previous window |
| `Option + 1–9` | Focus tab by number |

Shortcuts are global, so you can use them while another app is focused.

## Requirements

- **macOS 13 or newer.** Development is primarily on Apple Silicon and macOS beta builds; Intel compatibility is not comprehensively verified.
- **Accessibility permission** for listing and focusing windows.
- **Automation permission** for Spotify / Apple Music integration.
- **Swift 5.9+ toolchain** when building from source.
- **Tailscale is optional**, required only for its widget.

### Permissions and troubleshooting

| Symptom | What to check |
|:---|:---|
| Windows are missing or tabs do not focus them | Enable SmartWindow in System Settings → Privacy & Security → Accessibility |
| Spotify or Music controls do nothing | Approve SmartWindow's request to control Spotify or Music under Privacy & Security → Automation |
| Volume shows `--` | Some HDMI / DisplayPort outputs expose no software volume control |
| Temperature shows `--` | The current Mac or macOS version may not expose a readable sensor |
| No Tailscale widget | Enable it in Settings and check that Tailscale is installed in a supported CLI location |
| Tailscale shows `--` | Open Tailscale and check its status; a failed, malformed, or timed-out CLI response is treated as unavailable |

macOS prompts for Automation access when SmartWindow queries a running supported
player. Without permission, that player's metadata cannot be read. When macOS
blocks a downloaded app, review the warning in Privacy & Security; do not disable
system security protections to run it.

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
permission behavior can differ from the installed app.

### Install a local app bundle

```bash
./scripts/install-app.sh
```

This builds a release bundle and **replaces** `/Applications/SmartWindow.app`.
To create the repository-local bundle without replacing the installed app:

```bash
SMARTWINDOW_SKIP_INSTALL=1 ./scripts/install-app.sh
```

Signing is optional for local builds. When a signing identity is supplied, the
installer uses `Resources/SmartWindow.entitlements` by default, including the
Apple Events entitlement needed for player automation.

### Verification

The package currently has no automated SwiftPM test target. The packaging probe
runs the public installer against an isolated fake Swift toolchain, without
installing or signing. It verifies fresh-output selection and preserves an existing
bundle when Swift's reported executable is missing:

```bash
mkdir -p .build/probes
python3 Tests/Probes/ReleasePackagingProbe.py
```

The packager resolves the executable with `swift build -c release --show-bin-path`.
It stops with `Error: could not find built executable at <path>` before replacing
the bundle if that exact output is missing; it never falls back to an older build.

The Tailscale probe
covers state parsing, duration boundaries, bounded subprocess handling, and the
sleep-reset notification without changing VPN state:

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

Hardware readings, player permissions, and UI behavior still need checks on a real
Mac. The notch was checked on a 14" MacBook display alongside an external monitor;
other MacBook sizes have not been checked.

<details>
<summary><strong>Repository map</strong></summary>

```text
SmartWindow/
├── Package.swift                  # macOS executable and dependencies
├── Resources/                     # App icon, Info.plist, Apple Events entitlement
├── Sources/
│   ├── App/                       # Lifecycle, settings window, global shortcuts
│   ├── Models/                    # Window models and persisted settings
│   ├── Services/                  # Accessibility, metrics, media, Tailscale
│   └── Views/
│       ├── Components/            # Window tabs and status widgets
│       ├── Notch/                 # Per-screen Now Playing layout and panel
│       ├── SettingsView.swift     # Settings sidebar and panes
│       └── TabBarView.swift       # Main bar composition
├── Tests/Probes/                  # Standalone verification probes
└── scripts/                       # Local app install and release tooling
```

</details>

<details>
<summary><strong>Maintainer release workflow</strong></summary>

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

Signing and notarization are required. The script sources `scripts/release-env.sh`
when it exists; copy `scripts/release-env.example.sh` to create it, or export the
variables yourself:

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

</details>

## Roadmap

- Improve overflow behavior with many window tabs.
- Expand hardware and macOS compatibility checks.
- Validate other MacBook notch sizes, monitor reconnection and installed login-item flows.

## License

**Source-available, free for non-commercial use.**

Under the [SmartWindow Public Non-Commercial License v1.1](LICENSE):

- **You may** use, study, compile, modify, and share copies for free for personal,
  educational, research, and other non-commercial purposes.
- **You must** preserve the license and copyright notices, share under the same
  terms, and clearly identify modified versions.
- **You may not** sell, resell, monetize access to, or otherwise commercially
  exploit the app or modified versions without prior written permission from
  the copyright holder. This includes bundling it into paid products or services.
- **The copyright holder retains** the right to sell SmartWindow or grant
  separate commercial licenses for the work they own.

Source availability is not permission for commercial use. This is a custom
non-commercial, source-available license, not an open-source license.
Third-party components remain subject to their own licenses, including the
BSD-3-Clause [mediaremote-adapter](Vendor/mediaremote-adapter/LICENSE) used to read
Now Playing sessions.
The full terms in `LICENSE` govern; this section is a summary.

Copyright © 2026 Kevnnard.
