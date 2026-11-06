# mediaremote-adapter (vendored)

- Upstream: https://github.com/ungive/mediaremote-adapter
- Pinned commit: `0e82bf1c44ec39554fbfc402ec88a48c6ae2a0fd` (default branch HEAD, committed 2026-10-17, "Sort projects alphabetically")
- Vendored on: 2026-11-06
- License: BSD-3-Clause, see `LICENSE` (Copyright (c) 2025 Jonas van den Berg)
- Files are byte-identical copies of upstream; nothing was modified.

## Copied files

- `LICENSE`
- `bin/mediaremote-adapter.pl` — run by the app through `/usr/bin/perl`
- `include/MediaRemoteAdapter.h`
- `src/adapter/{env,get,globals,keys,now_playing}.{h,m}`, `src/adapter/{repeat,seek,send,shuffle,speed,stream,test}.m`
- `src/private/MediaRemote.{h,m}`
- `src/utility/{Debounce,helpers}.{h,m}`
- `src/test/NowPlayingTest.h` — header only, imported by `src/adapter/test.m`
- `CMakeLists.txt` — reference only (sources, flags, frameworks, bundle metadata); never run

Not copied: the optional `MediaRemoteAdapterTestClient` sources (`src/test/*.m`), `Makefile`, `scripts/`, editor/format config, README.

## Build

`scripts/build-mediaremote-adapter.sh` reproduces the CMake `MediaRemoteAdapter` framework target with clang:
universal `arm64` + `x86_64`, `-fobjc-arc -fvisibility=default`, Foundation/AppKit/UniformTypeIdentifiers,
`Versions/A` layout, `com.vandenbe.MediaRemoteAdapter` Info.plist (0.1 / 0.1.0), ad-hoc signed.
Output: `.build/mediaremote-adapter/{MediaRemoteAdapter.framework,mediaremote-adapter.pl}`.

## Updating

Copy the same file list from a newer upstream commit, diff `CMakeLists.txt` for source/flag changes,
mirror them in the build script, and update the commit hash and date above.
