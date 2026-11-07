#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SmartWindow"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/$APP_NAME.app"
INSTALL_DIR="/Applications/$APP_NAME.app"
SKIP_INSTALL="${SMARTWINDOW_SKIP_INSTALL:-0}"
CODESIGN_IDENTITY="${SMARTWINDOW_CODESIGN_IDENTITY:-}"
CODESIGN_ENTITLEMENTS="${SMARTWINDOW_CODESIGN_ENTITLEMENTS:-$ROOT_DIR/Resources/SmartWindow.entitlements}"
CODESIGN_OPTIONS="${SMARTWINDOW_CODESIGN_OPTIONS:-runtime}"

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'Missing required command: %s\n' "$1" >&2
        exit 1
    fi
}

sign_app_bundle() {
    if [ -z "$CODESIGN_IDENTITY" ]; then
        printf 'Skipping code signing (set SMARTWINDOW_CODESIGN_IDENTITY to sign releases).\n'
        return
    fi

    require_cmd codesign

    printf 'Signing nested MediaRemoteAdapter.framework with identity: %s\n' "$CODESIGN_IDENTITY"
    codesign --force --sign "$CODESIGN_IDENTITY" --timestamp --options "$CODESIGN_OPTIONS" \
        "$ADAPTER_BUNDLE_DIR/MediaRemoteAdapter.framework"

    printf 'Signing nested libMediaSessionsHelper.dylib with identity: %s\n' "$CODESIGN_IDENTITY"
    codesign --force --sign "$CODESIGN_IDENTITY" --timestamp --options "$CODESIGN_OPTIONS" \
        "$ADAPTER_BUNDLE_DIR/libMediaSessionsHelper.dylib"

    printf 'Signing app bundle with identity: %s\n' "$CODESIGN_IDENTITY"

    SIGN_ARGS=(
        --force
        --sign "$CODESIGN_IDENTITY"
        --timestamp
        --options "$CODESIGN_OPTIONS"
    )

    if [ -n "$CODESIGN_ENTITLEMENTS" ]; then
        SIGN_ARGS+=(--entitlements "$CODESIGN_ENTITLEMENTS")
    fi

    codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE"

    printf 'Verifying code signature...\n'
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
}

printf 'Building %s in release mode...\n' "$APP_NAME"
cd "$ROOT_DIR"
swift build -c release

# Query this toolchain/build system, rather than accidentally packaging an older
# executable left behind by a different Swift build layout.
BIN_PATH="$(swift build -c release --show-bin-path)"
EXECUTABLE_PATH="$BIN_PATH/$APP_NAME"
if [ ! -f "$EXECUTABLE_PATH" ]; then
    printf 'Error: could not find built executable at %s\n' "$EXECUTABLE_PATH" >&2
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

# Now Playing source (S9): MediaRemote only answers Apple-signed clients, so the
# app runs the vendored adapter through /usr/bin/perl (see MediaRemoteAdapterLocator).
bash "$ROOT_DIR/scripts/build-mediaremote-adapter.sh"
ADAPTER_BUILD_DIR="$ROOT_DIR/.build/mediaremote-adapter"
ADAPTER_BUNDLE_DIR="$APP_BUNDLE/Contents/Resources/MediaRemoteAdapter"
mkdir -p "$ADAPTER_BUNDLE_DIR"
cp -R "$ADAPTER_BUILD_DIR/MediaRemoteAdapter.framework" "$ADAPTER_BUNDLE_DIR/"
cp "$ADAPTER_BUILD_DIR/mediaremote-adapter.pl" "$ADAPTER_BUNDLE_DIR/"
# Every Now Playing session (S1), read by our own helper in the same perl host.
cp "$ADAPTER_BUILD_DIR/libMediaSessionsHelper.dylib" "$ADAPTER_BUNDLE_DIR/"
cp "$ADAPTER_BUILD_DIR/media-sessions.pl" "$ADAPTER_BUNDLE_DIR/"
# Ends the adapter stream when the app exits, even after a crash (S11).
cp "$ADAPTER_BUILD_DIR/parent-guard.pl" "$ADAPTER_BUNDLE_DIR/"
# BSD-3-Clause requires the notice in binary distributions.
cp "$ROOT_DIR/Vendor/mediaremote-adapter/LICENSE" "$ADAPTER_BUNDLE_DIR/LICENSE"

xattr -cr "$APP_BUNDLE" 2>/dev/null || true
sign_app_bundle

if [ "$SKIP_INSTALL" = "1" ]; then
    printf 'Skipping installation to /Applications (SMARTWINDOW_SKIP_INSTALL=1).\n'
else
    printf 'Installing to %s...\n' "$INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
    cp -R "$APP_BUNDLE" "$INSTALL_DIR"
fi

printf 'Done. App bundle ready at %s\n' "$APP_BUNDLE"
