# SmartWindow v0.8.1

## Fixes
- Launch at login could not be turned on: the switch in Settings → General stayed greyed out until SmartWindow had been registered once, which it never could be. It now works from the first time.
- When macOS asks you to allow SmartWindow to open at login, Settings opens Login Items in System Settings for you, and the switch shows the real state when you come back.
- Turning it off removes SmartWindow from your login items.

## Distribution
- macOS 13 or later; this release ZIP contains an Apple Silicon (arm64) build.
- The release ZIP is signed with Developer ID and notarized by Apple.
- From v0.8.0 you can install this update from Settings → General → Update to v0.8.1.

## Known validation limits
- Launch at login was checked with probes; registering with macOS was not yet tried on the installed app.
