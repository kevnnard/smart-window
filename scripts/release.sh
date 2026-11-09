#!/usr/bin/env bash
# Cut a SmartWindow release: test, bump the bundle version, build a signed and
# notarized SmartWindow.zip, tag, publish the GitHub release with the zip, and
# point the Homebrew tap cask at it.
#
# Usage: scripts/release.sh [--dry-run] X.Y.Z
# Env:   TAP_DIR  path to the homebrew-tap checkout (default ../homebrew-tap)
#        SMARTWINDOW_CODESIGN_IDENTITY, SMARTWINDOW_NOTARY_PROFILE
#        (read from scripts/release-env.sh when it exists)
set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then DRY_RUN=1; shift; fi
VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $0 [--dry-run] X.Y.Z" >&2
  exit 2
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TAP_DIR="${TAP_DIR:-$REPO_DIR/../homebrew-tap}"
TAG="v$VERSION"
CASK="Casks/smartwindow.rb"
PLIST="Resources/Info.plist"
NOTES="Resources/ReleaseNotes-$VERSION.md"

run() {
  if [[ $DRY_RUN -eq 1 ]]; then echo "[dry-run] $*"; else "$@"; fi
}

# fail stops a real release; a dry run reports it and keeps going.
fail() {
  if [[ $DRY_RUN -eq 1 ]]; then echo "[dry-run] would stop: $*" >&2; else echo "$*" >&2; exit 1; fi
}

cd "$REPO_DIR"

# Local signing configuration; never echoed.
if [[ -f scripts/release-env.sh ]]; then
  # shellcheck source=/dev/null
  source scripts/release-env.sh
fi

# Preflight: fail before changing anything.
# tracked_changes prints a checkout's tracked changes; a failed status stops, never reads as clean.
tracked_changes() {
  git -C "$1" status --porcelain --untracked-files=no 2>/dev/null || { echo "cannot read git status: $1" >&2; exit 1; }
}

[[ "$(git branch --show-current)" == "main" ]] || fail "release from main only"
REPO_CHANGES="$(tracked_changes "$REPO_DIR")"
if [[ -n "$REPO_CHANGES" ]]; then
  fail "tracked changes present; commit or stash first"
fi
# ls-remote --exit-code: 0 = tag found, 2 = no match, anything else = lookup failed.
REMOTE_TAG=0
git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1 || REMOTE_TAG=$?
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || [[ $REMOTE_TAG -eq 0 ]]; then
  fail "$TAG already exists"
elif [[ $REMOTE_TAG -ne 2 ]]; then
  fail "cannot check tags on origin"
fi
[[ -f "$TAP_DIR/$CASK" ]] || fail "tap cask not found at $TAP_DIR/$CASK (set TAP_DIR)"
# The tap must be its own checkout on a branch with an origin, or the final push would fail
# after the app release is already public.
if [[ "$(git -C "$TAP_DIR" rev-parse --show-toplevel 2>/dev/null)" != "$(cd "$TAP_DIR" 2>/dev/null && pwd -P)" ]] \
  || [[ -z "$(git -C "$TAP_DIR" branch --show-current 2>/dev/null)" ]]; then
  fail "tap is not a git checkout on a branch: $TAP_DIR"
elif ! git -C "$TAP_DIR" remote get-url origin >/dev/null 2>&1; then
  fail "tap checkout has no origin: $TAP_DIR"
else
  TAP_CHANGES="$(tracked_changes "$TAP_DIR")"
  [[ -z "$TAP_CHANGES" ]] || fail "tap checkout has tracked changes: $TAP_DIR"
fi
[[ -n "${SMARTWINDOW_CODESIGN_IDENTITY:-}" ]] || fail "SMARTWINDOW_CODESIGN_IDENTITY is not set (source scripts/release-env.sh)"
[[ -n "${SMARTWINDOW_NOTARY_PROFILE:-}" ]] || fail "SMARTWINDOW_NOTARY_PROFILE is not set (source scripts/release-env.sh)"
gh auth status >/dev/null 2>&1 || fail "gh is not authenticated"

echo "==> tests"
swift build -c release
shopt -s nullglob
for probe in Tests/Probes/*.py; do
  python3 -I "$probe"
done
shopt -u nullglob

echo "==> version bump"
BUILD=$(( $(plutil -extract CFBundleVersion raw "$PLIST") + 1 ))
if [[ $DRY_RUN -eq 1 ]]; then
  echo "[dry-run] set version $VERSION (build $BUILD)"
else
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$PLIST"
  plutil -replace CFBundleVersion -string "$BUILD" "$PLIST"
fi
run git add "$PLIST"
run git commit -m "chore(release): $TAG"

echo "==> build, sign and notarize"
# Build into a scratch directory so the tracked SmartWindow.zip never changes.
ZIP=""
if [[ $DRY_RUN -eq 1 ]]; then
  echo "[dry-run] build, sign and notarize SmartWindow.zip"
else
  ZIP="$(mktemp -d)/SmartWindow.zip"
  export SMARTWINDOW_CODESIGN_IDENTITY SMARTWINDOW_NOTARY_PROFILE
  SMARTWINDOW_ZIP_PATH="$ZIP" scripts/build-release-zip.sh
fi

echo "==> tag and push"
run git tag -a "$TAG" -m "SmartWindow $TAG"
run git push origin main
run git push origin "$TAG"

echo "==> zip hash"
SHA="0000000000000000000000000000000000000000000000000000000000000000"
if [[ $DRY_RUN -eq 0 ]]; then
  SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
fi
echo "sha256 $SHA"

echo "==> GitHub release"
if [[ -f "$NOTES" ]]; then NOTES_ARGS=(--notes-file "$NOTES"); else NOTES_ARGS=(--generate-notes); fi
run gh release create "$TAG" ${ZIP:+"$ZIP"} --title "SmartWindow $TAG" "${NOTES_ARGS[@]}"

echo "==> tap cask"
if [[ $DRY_RUN -eq 1 ]]; then
  python3 -I "$REPO_DIR/scripts/release_tap.py" - "$VERSION" "$SHA"
  echo "[dry-run] would write $TAP_DIR/$CASK (above), then commit and push the tap"
else
  python3 -I "$REPO_DIR/scripts/release_tap.py" "$TAP_DIR/$CASK" "$VERSION" "$SHA"
  git -C "$TAP_DIR" add "$CASK"
  git -C "$TAP_DIR" commit -m "smartwindow $TAG"
  git -C "$TAP_DIR" push origin HEAD
fi

echo "==> done: $TAG"
echo "   brew update && brew upgrade --cask kevnnard/tap/smartwindow"
