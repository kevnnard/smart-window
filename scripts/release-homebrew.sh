#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  printf 'Usage: %s <version> [release notes]\n' "$0" >&2
  printf 'Example: %s 0.1.1 "Bug fixes and UI polish"\n' "$0" >&2
  exit 1
fi

RAW_VERSION="$1"
shift || true
VERSION="${RAW_VERSION#v}"
TAG="v${VERSION}"
RELEASE_NOTES="${*:-Release ${TAG}}"

APP_NAME="SmartWindow"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ZIP_PATH="$ROOT_DIR/${APP_NAME}.zip"
TAP_DIR="$(cd "$ROOT_DIR/.." && pwd)/homebrew-tap"
CASK_PATH="$TAP_DIR/Casks/smartwindow.rb"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

require_cmd git
require_cmd gh
require_cmd shasum
require_cmd python3

cd "$ROOT_DIR"

if [ -n "$(git status --porcelain)" ]; then
  printf 'Working tree is not clean. Commit or stash changes before releasing.\n' >&2
  exit 1
fi

if [ ! -d "$TAP_DIR/.git" ]; then
  printf 'Homebrew tap repo not found at %s\n' "$TAP_DIR" >&2
  exit 1
fi

printf 'Building release archive for %s...\n' "$TAG"
"$ROOT_DIR/scripts/build-release-zip.sh"

SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
printf 'Release checksum: %s\n' "$SHA256"

printf 'Pushing current branch...\n'
git push

printf 'Creating or updating GitHub release %s...\n' "$TAG"
if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$ZIP_PATH" --clobber
else
  gh release create "$TAG" "$ZIP_PATH" --title "SmartWindow ${TAG}" --notes "$RELEASE_NOTES"
fi

printf 'Updating Homebrew cask...\n'
python3 - <<PY
from pathlib import Path
import re

path = Path(${CASK_PATH@Q})
text = path.read_text()
text = re.sub(r'version\s+"[^"]+"', f'version "${VERSION}"', text)
text = re.sub(r'sha256\s+"[0-9a-f]+"', f'sha256 "${SHA256}"', text)
path.write_text(text)
PY

cd "$TAP_DIR"

if [ -n "$(git status --porcelain)" ]; then
  git add "$CASK_PATH"
  git commit -m "Update SmartWindow cask ${TAG}"
  git push
else
  printf 'Homebrew cask already up to date.\n'
fi

printf '\nDone.\n'
printf 'Release: https://github.com/kevnnard/smart-window/releases/tag/%s\n' "$TAG"
printf 'Tap repo: https://github.com/kevnnard/homebrew-tap\n'
