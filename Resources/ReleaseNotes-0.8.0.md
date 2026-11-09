# SmartWindow v0.8.0

## Highlights
- Updates in one click: SmartWindow looks for a new version when it starts and once a day. When there is one, Settings → General and the menu bar menu show **Update to vX**. One click downloads it, checks it, replaces the app and reopens it.

## Changes
- Before installing, SmartWindow checks that the download is SmartWindow, is the version offered and newer than yours, is signed with the same Developer ID as the installed app, and is notarized by Apple. A download that fails any check is deleted and nothing changes.
- It never updates without your click. Turn off **Check for updates automatically** in Settings → General to check only with **Check Now**.
- The Homebrew cask now says the app updates itself, so `brew upgrade` leaves it alone.
- Development builds do not update themselves; Settings says so.

## Distribution
- macOS 13 or later; this release ZIP contains an Apple Silicon (arm64) build.
- The release ZIP is signed with Developer ID and notarized by Apple.

## Known validation limits
- The checks were tested against the signed, notarized v0.7.0 app and tampered, ad-hoc signed and wrong-version copies. Updating from v0.8.0 to a newer release in one click can only be tried once a newer release exists.
- If SmartWindow cannot write to the folder it is installed in, it says so; update with Homebrew instead.
