#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SmartWindow"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/$APP_NAME.app"
INSTALL_DIR="/Applications/$APP_NAME.app"

printf 'Building %s in release mode...\n' "$APP_NAME"
cd "$ROOT_DIR"
swift build -c release

EXECUTABLE_PATH=""
for candidate in \
    "$ROOT_DIR/.build/release/$APP_NAME" \
    "$ROOT_DIR/.build/arm64-apple-macosx/release/$APP_NAME" \
    "$ROOT_DIR/.build/x86_64-apple-macosx/release/$APP_NAME"
do
    if [ -f "$candidate" ]; then
        EXECUTABLE_PATH="$candidate"
        break
    fi
done

if [ -z "$EXECUTABLE_PATH" ]; then
    printf 'Error: could not find built executable for %s\n' "$APP_NAME" >&2
    exit 1
fi

printf 'Creating app bundle...\n'
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$EXECUTABLE_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [ -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

printf 'Installing to %s...\n' "$INSTALL_DIR"
rm -rf "$INSTALL_DIR"
cp -R "$APP_BUNDLE" "$INSTALL_DIR"

printf 'Done. Installed %s to %s\n' "$APP_NAME" "$INSTALL_DIR"
