#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SmartWindow"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/$APP_NAME.app"
ZIP_PATH="$ROOT_DIR/${APP_NAME}.zip"
NOTARY_ZIP_PATH="$ROOT_DIR/${APP_NAME}-notary.zip"
NOTARY_PROFILE="${SMARTWINDOW_NOTARY_PROFILE:-}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

notarize_app_bundle() {
  if [ -z "$NOTARY_PROFILE" ]; then
    printf 'Skipping notarization (set SMARTWINDOW_NOTARY_PROFILE to notarize release builds).\n'
    return
  fi

  require_cmd xcrun

  if [ -z "${SMARTWINDOW_CODESIGN_IDENTITY:-}" ]; then
    printf 'SMARTWINDOW_NOTARY_PROFILE is set, but SMARTWINDOW_CODESIGN_IDENTITY is missing.\n' >&2
    printf 'Notarization requires a Developer ID-signed app bundle.\n' >&2
    exit 1
  fi

  printf 'Creating notarization archive %s...\n' "$NOTARY_ZIP_PATH"
  rm -f "$NOTARY_ZIP_PATH"
  ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$NOTARY_ZIP_PATH"

  printf 'Submitting %s for notarization using profile %s...\n' "$NOTARY_ZIP_PATH" "$NOTARY_PROFILE"
  xcrun notarytool submit "$NOTARY_ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

  printf 'Stapling notarization ticket...\n'
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"

  rm -f "$NOTARY_ZIP_PATH"
}

SMARTWINDOW_SKIP_INSTALL=1 "$ROOT_DIR/scripts/install-app.sh"
notarize_app_bundle

printf 'Creating release archive %s...\n' "$ZIP_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

printf 'Done. Release archive created at %s\n' "$ZIP_PATH"
