# SmartWindow

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

## Homebrew

Yes, this can be distributed with Homebrew, but the normal flow is:

1. publish the project on GitHub
2. create a tagged release like `v0.1.0`
3. attach or generate a stable `.app` / zip artifact
4. create a Homebrew Cask or personal tap

For this app, a Homebrew Cask is the better fit than a regular formula because this is a GUI macOS app bundle, not just a CLI binary.

If you want, the next step after GitHub can be preparing:

- a release zip for `SmartWindow.app`
- a Homebrew Cask file
- a tap repository layout

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
