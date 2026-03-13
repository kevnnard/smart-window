#!/usr/bin/env bash

# Copy this file to scripts/release-env.sh and fill in your Apple ID / notary profile.
# Then run: source scripts/release-env.sh

export SMARTWINDOW_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export SMARTWINDOW_NOTARY_PROFILE="smartwindow-notary"

# Optional if you later add entitlements:
# export SMARTWINDOW_CODESIGN_ENTITLEMENTS="Resources/SmartWindow.entitlements"

# Optional override; default already uses runtime:
# export SMARTWINDOW_CODESIGN_OPTIONS="runtime"

# One-time notary profile setup:
# xcrun notarytool store-credentials "$SMARTWINDOW_NOTARY_PROFILE" \
#   --apple-id "your-apple-id@example.com" \
#   --team-id "TEAMID" \
#   --password "your-app-specific-password"
