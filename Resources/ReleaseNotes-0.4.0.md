# SmartWindow v0.4.0

## Highlights
- New Now Playing notch: a compact row around the MacBook camera notch that opens a drawer below with artwork, track details, progress and controls. The compact row never moves while the drawer opens or closes.
- Reads every macOS Now Playing session, including browser media such as YouTube, alongside Spotify and Music. With several apps playing, a badge per app selects the one the notch shows.
- Safe controls: Spotify and Music are controlled directly; other apps only while macOS reports them as the current Now Playing app, so another app is never paused by mistake.
- New Settings → Notch pane with every notch setting: visibility per display, black or bar-colored style, default and per-display size, and expanded width.
- On MacBook screens, status widgets that do not fit beside the notch scroll horizontally while the clock stays visible.
- Hover and the pointing-hand cursor apply only over the visible notch; the transparent area around it passes clicks through.

## Fixes
- Fixed a crash caused by reentrant Now Playing polling.
- The open drawer's shadow is no longer cut off at the window edges.

## Distribution
- macOS 13 or later; this release ZIP contains an Apple Silicon (arm64) build.
- Bundles the BSD-3-Clause mediaremote-adapter to read Now Playing sessions.
- Developer ID signing and Apple notarization are checked during release packaging.

## Known validation limits
- Notch layout was checked on a 14" MacBook Pro display and an external monitor; other MacBook sizes were not checked.
- Browser playback can be read but is controlled only while it is the current Now Playing app; paused browser tabs get no badge.
- When Music is the source, the notch may show the Music app icon instead of the album artwork.
