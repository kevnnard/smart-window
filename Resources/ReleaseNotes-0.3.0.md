# SmartWindow v0.3.0

## Highlights
- Compact, content-sized window tabs with searchable overflow and full-title tooltips; existing Option shortcuts and window ordering are preserved.
- Real CPU, memory, GPU, temperature/thermal-state, microphone and audio-device metrics, with unavailable readings shown honestly.
- Spotify and Music metadata, artwork, paused-player badges and playback controls; per-display notch geometry.
- Redesigned native Settings, appearance controls, widget ordering and visibility, and searchable time zones.
- Native macOS login-item controls and keyboard input-source selection.
- Optional read-only Tailscale status with continuously observed online duration.
- Persistent per-monitor overrides and Focus mode without erasing widget preferences.
- Finder desktop activation fix and safer packaging of the current Swift build output.
- Updated documentation and clarified non-commercial source-available licensing; the copyright holder retains commercialization rights.

## Distribution
- macOS 13 or later; this release ZIP contains an Apple Silicon (arm64) build.
- Developer ID signing and Apple notarization are checked during release packaging.
- Existing ZIP and app bundle are backed up before replacement. Packaging does not install the app locally.

## Known validation limits
- Tested on an external display; physical-notch hardware and a real second-monitor reconnection were not exercised.
- Signed-installed login registration/permissions and some popover/Displays-pane interactions still require hands-on validation.
- Independent verification was unavailable. The maintainer explicitly authorized publication with these gaps and disabled RDD for this clone after native reviewer configuration proved unavailable; no native approval is claimed.
- Media integration supports Spotify and Music, not browser playback. Tailscale duration is an observation window, not authoritative tunnel age.
