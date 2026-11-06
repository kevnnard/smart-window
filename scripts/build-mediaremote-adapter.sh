#!/usr/bin/env bash
# Builds the vendored mediaremote-adapter framework with clang only (no cmake).
# Mirrors the MediaRemoteAdapter target in Vendor/mediaremote-adapter/CMakeLists.txt:
# same sources, -fobjc-arc -fvisibility=default, Foundation/AppKit/UniformTypeIdentifiers,
# a versioned framework bundle (Versions/A) and an ad-hoc signature.
# Also builds our own media sessions helper (Helpers/MediaSessions) next to it.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor/mediaremote-adapter"
OUT_DIR="$ROOT_DIR/.build/mediaremote-adapter"
NAME="MediaRemoteAdapter"
FRAMEWORK="$OUT_DIR/$NAME.framework"
VERSION_SHORT="0.1"
VERSION="0.1.0"
# Our own multi-session reader (S1): every MediaRemote session, not only the current one.
HELPER_DIR="$ROOT_DIR/Helpers/MediaSessions"
HELPER_DYLIB="$OUT_DIR/libMediaSessionsHelper.dylib"
ARCHS=(${MEDIAREMOTE_ADAPTER_ARCHS:-arm64 x86_64})
MIN_MACOS="${MEDIAREMOTE_ADAPTER_MIN_MACOS:-13.0}"

SOURCES=(
    src/adapter/env.m
    src/adapter/get.m
    src/adapter/globals.m
    src/adapter/keys.m
    src/adapter/now_playing.m
    src/adapter/repeat.m
    src/adapter/seek.m
    src/adapter/send.m
    src/adapter/shuffle.m
    src/adapter/speed.m
    src/adapter/stream.m
    src/adapter/test.m
    src/private/MediaRemote.m
    src/utility/Debounce.m
    src/utility/helpers.m
)

fail() {
    printf 'build-mediaremote-adapter: %s\n' "$1" >&2
    exit 1
}

for cmd in xcrun codesign; do
    command -v "$cmd" >/dev/null 2>&1 || fail "missing required command: $cmd"
done
CLANG="$(xcrun --find clang 2>/dev/null)" || fail "clang not found (install the Xcode command line tools)"
SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)" || fail "macOS SDK not found"

[ -f "$VENDOR_DIR/bin/mediaremote-adapter.pl" ] || fail "vendored perl script missing at $VENDOR_DIR/bin"
for src in "${SOURCES[@]}"; do
    [ -f "$VENDOR_DIR/$src" ] || fail "vendored source missing: $VENDOR_DIR/$src"
done
for src in MediaSessionsHelper.m media-sessions.pl; do
    [ -f "$HELPER_DIR/$src" ] || fail "media sessions helper source missing: $HELPER_DIR/$src"
done

ARCH_FLAGS=()
for arch in "${ARCHS[@]}"; do
    ARCH_FLAGS+=(-arch "$arch")
done

printf 'Building %s.framework (%s, macOS %s+)...\n' "$NAME" "${ARCHS[*]}" "$MIN_MACOS"

# Rebuild from scratch so stale objects or a half-written bundle never survive.
rm -rf "$FRAMEWORK"
mkdir -p "$FRAMEWORK/Versions/A/Resources" "$FRAMEWORK/Versions/A/Headers"

ABS_SOURCES=()
for src in "${SOURCES[@]}"; do
    ABS_SOURCES+=("$VENDOR_DIR/$src")
done

"$CLANG" -x objective-c -dynamiclib "${ARCH_FLAGS[@]}" \
    -isysroot "$SDK" -mmacosx-version-min="$MIN_MACOS" \
    -fobjc-arc -fvisibility=default -O2 \
    -I "$VENDOR_DIR/include" -I "$VENDOR_DIR/src" \
    -install_name "@rpath/$NAME.framework/Versions/A/$NAME" \
    -compatibility_version "$VERSION" -current_version "$VERSION" \
    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
    "${ABS_SOURCES[@]}" \
    -o "$FRAMEWORK/Versions/A/$NAME" \
    || fail "clang failed to build $NAME"

cp "$VENDOR_DIR/include/MediaRemoteAdapter.h" "$FRAMEWORK/Versions/A/Headers/"
cat > "$FRAMEWORK/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>English</string>
    <key>CFBundleExecutable</key>
    <string>$NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.vandenbe.$NAME</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$NAME</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION_SHORT</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleSignature</key>
    <string>????</string>
</dict>
</plist>
PLIST

ln -s A "$FRAMEWORK/Versions/Current"
ln -s "Versions/Current/$NAME" "$FRAMEWORK/$NAME"
ln -s Versions/Current/Headers "$FRAMEWORK/Headers"
ln -s Versions/Current/Resources "$FRAMEWORK/Resources"

# Same as upstream's POST_BUILD step; install-app.sh re-signs with the release identity.
codesign --force --sign - "$FRAMEWORK" >/dev/null 2>&1 || fail "ad-hoc signing of $NAME.framework failed"

cp "$VENDOR_DIR/bin/mediaremote-adapter.pl" "$OUT_DIR/mediaremote-adapter.pl"
chmod 755 "$OUT_DIR/mediaremote-adapter.pl"

printf 'Built %s\n' "$FRAMEWORK"

rm -f "$HELPER_DYLIB"
"$CLANG" -x objective-c -dynamiclib "${ARCH_FLAGS[@]}" \
    -isysroot "$SDK" -mmacosx-version-min="$MIN_MACOS" \
    -fobjc-arc -fvisibility=hidden -O2 \
    -install_name "@rpath/libMediaSessionsHelper.dylib" \
    -framework Foundation \
    "$HELPER_DIR/MediaSessionsHelper.m" \
    -o "$HELPER_DYLIB" \
    || fail "clang failed to build libMediaSessionsHelper.dylib"
codesign --force --sign - "$HELPER_DYLIB" >/dev/null 2>&1 || fail "ad-hoc signing of libMediaSessionsHelper.dylib failed"
cp "$HELPER_DIR/media-sessions.pl" "$OUT_DIR/media-sessions.pl"
chmod 755 "$OUT_DIR/media-sessions.pl"

printf 'Built %s\n' "$HELPER_DYLIB"
