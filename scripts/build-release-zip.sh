#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SmartWindow"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/$APP_NAME.app"
ZIP_PATH="$ROOT_DIR/${APP_NAME}.zip"

"$ROOT_DIR/scripts/install-app.sh"

printf 'Creating release archive %s...\n' "$ZIP_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

printf 'Done. Release archive created at %s\n' "$ZIP_PATH"
