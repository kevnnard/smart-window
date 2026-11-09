# SmartWindow v0.5.0

## Highlights
- Volume, brightness and Focus in the notch: when you change the volume or brightness, or turn a Focus on or off, the notch shows it for a moment, with the level or the Focus name and icon. The HUD appears on every monitor, including monitors without a camera notch.
- Per-display settings: the new Settings → Bar & Notch page starts with a map of your monitors. Edit the Default for all of them, or customize any bar, widget or notch setting for one monitor. Customized rows are marked Custom and can be reset to Default. A disconnected monitor keeps its settings and can still be edited.
- Simpler Settings: Bar & Notch replaces the Appearance, Widgets, Notch and Displays panes, so each setting appears in exactly one place. The temperature unit moved to General, and the Tailscale page shows status only; its widget is in Bar & Notch → Widgets.
- New Settings → Permissions pane: shows which permissions SmartWindow has (Accessibility, which is required, plus optional Automation for Spotify and Music, Full Disk Access and Focus Status) and a button to grant or open each one.

## Changes
- The "Main display only" notch option was replaced by Show notch for each monitor. An existing choice is converted once on first launch.
- The transparent area around the notch no longer blocks clicks on the windows and menus below it.

## Distribution
- macOS 13 or later; this release ZIP contains an Apple Silicon (arm64) build.
- The release ZIP is signed with Developer ID and notarized by Apple.
- Showing the name of the active Focus needs Full Disk Access, because macOS keeps it in a protected folder. Without it, SmartWindow asks for Focus Status permission and shows a generic Focus.

## Known validation limits
- The Focus HUD was confirmed on an external monitor. The volume and brightness HUDs were checked with probes and simulated events, not with the hardware keys on a MacBook.
- Volume is shown only for outputs that have software volume; monitors that receive audio over DisplayPort or HDMI usually do not. Brightness is shown for the built-in display only.
- Per-display settings were checked with probes and offscreen renders, not on a live setup with several monitors.
- After updating, macOS may keep an old Full Disk Access entry that no longer applies. If the Focus HUD shows nothing, remove SmartWindow from Full Disk Access, add it again and relaunch.
