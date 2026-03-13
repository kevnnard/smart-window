# SmartWindow

<img width="1512" height="982" alt="Screenshot 2026-03-12 at 11 38 55 PM" src="https://github.com/user-attachments/assets/4928ae2f-a722-41e8-9adf-6c85ff78ce71" />

<img width="748" height="18" alt="image" src="https://github.com/user-attachments/assets/9ce56448-bfa2-461b-b00d-f1cf312990a7" />

<img width="1509" height="27" alt="image" src="https://github.com/user-attachments/assets/ade346d4-f75e-48b4-86f6-84a9a99b7e0c" />

SmartWindow is a macOS menu bar replacement inspired by Polybar and Waybar.

It renders a custom top bar across your screens, shows numbered tabs for open windows on the left, and system status on the right. It is built for people who want faster window switching on macOS with a more tiling-WM-like feel.

Current public release: `v0.1.0`

## Highlights

- Numbered window tabs like `1 · Finder`, `2 · Ghostty`, `3 · Brave`
- Click any tab to focus that window
- Global shortcuts for switching windows and toggling the bar
- GPU, CPU, RAM, volume, mic, date, and battery indicators
- Now Playing support for Spotify / Apple Music style media playback
- Multi-monitor support
- Per-screen fullscreen hiding
- Blur / glass-style top bar background
- Menu bar utility app with no Dock icon

## Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| `Option + Escape` | Show / hide SmartWindow |
| `Option + ]` | Focus next window |
| `Option + [` | Focus previous window |
| `Option + 1-9` | Focus tab by number |

## Requirements

- macOS 13 or newer
- Accessibility permission enabled for SmartWindow
- Apple Silicon and Intel should both work, but the project is currently developed primarily on Apple Silicon macOS beta builds

## What It Does

SmartWindow creates a floating `NSPanel` above the native menu bar area and keeps it visible across Spaces.

Main behavior in `v0.1.0`:

- Replaces the visual top bar with a custom blurred overlay
- Detects open windows through the macOS Accessibility API
- Lets you switch windows by clicking tabs or using hotkeys
- Supports multiple screens with one bar per monitor
- Hides only the affected bar when an app enters fullscreen on one monitor
- Shows the current playing track when media is active
- Includes a menu bar dropdown and a polished settings window

## Project Structure

```text
.
├── Package.swift
├── README.md
├── LICENSE
├── Resources/
│   ├── AppIcon.icns
│   └── Info.plist
├── Sources/
│   ├── App/
│   │   └── SmartWindowApp.swift
│   ├── Models/
│   │   ├── AppSettings.swift
│   │   └── WindowInfo.swift
│   ├── Services/
│   │   ├── AccessibilityService.swift
│   │   ├── HotKeyService.swift
│   │   ├── NowPlayingService.swift
│   │   ├── SystemMonitorService.swift
│   │   └── WindowManager.swift
│   └── Views/
│       ├── Components/
│       │   ├── MiniTabView.swift
│       │   └── SystemInfoView.swift
│       ├── MenuBarView.swift
│       ├── OverlayPanel.swift
│       ├── SettingsView.swift
│       └── TabBarView.swift
└── scripts/
    └── install-app.sh
```

## Running From Source

```bash
swift build
swift run
```

## Install As An App

This repo includes a small installer script that builds a release bundle and copies it into `/Applications`.

```bash
./scripts/install-app.sh
```

That installs:

```text
/Applications/SmartWindow.app
```

If macOS warns you the first time, open it manually from Finder and approve it in Privacy & Security if needed.

## Permissions

SmartWindow needs Accessibility access in order to:

- read open windows
- detect focused windows
- switch and raise windows
- read titles and positions
- react to fullscreen state

Grant it at:

`System Settings -> Privacy & Security -> Accessibility`

## Install With Homebrew

SmartWindow is distributed as a Homebrew Cask.

```bash
brew tap kevnnard/tap
brew install --cask smartwindow
```

If you already tapped the repo and want upgrades later:

```bash
brew update
brew upgrade --cask smartwindow
```

To uninstall:

```bash
brew uninstall --cask smartwindow
```

Notes:

- this installs `SmartWindow.app` into `/Applications`
- on first launch, macOS may ask you to approve the app and grant Accessibility access
- Homebrew uses the GitHub release artifact for `v0.1.0`

## Maintainer Release Flow

To publish a new version and update the Homebrew cask in one step:

```bash
./scripts/release-homebrew.sh 0.1.1 "Release notes here"
```

What it does:

- builds a fresh `SmartWindow.zip`
- computes the new SHA256
- pushes the current repo
- creates or updates the GitHub release tag
- updates `kevnnard/homebrew-tap`
- commits and pushes the cask update

Notes:

- run it from a clean git working tree
- it expects the tap repo to exist locally as a sibling directory: `../homebrew-tap`

## Version

This README describes the first main public release:

`v0.1.0`

## License

This project is public and source-available, but commercial use is prohibited.

That means:

- you can use it personally
- you can study it
- you can modify it
- you can share it non-commercially
- you cannot sell it
- you cannot include it in paid/commercial products or services without written permission

See `LICENSE` for the exact terms.
