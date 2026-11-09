"""Write the Homebrew tap cask for a SmartWindow release.

The cask installs the prebuilt, signed and notarized SmartWindow.zip attached to
the GitHub release. The whole cask is rendered from the template below, so every
release rewrites it. Used by scripts/release.sh; it does not commit or push.

Usage: release_tap.py PATH|- VERSION SHA256   ("-" prints to stdout)
"""
import re
import sys

TEMPLATE = '''cask "smartwindow" do
  version "{version}"
  sha256 "{sha}"

  url "https://github.com/kevnnard/smart-window/releases/download/v#{{version}}/SmartWindow.zip"
  name "SmartWindow"
  desc "Polybar-style macOS top bar with numbered window tabs"
  homepage "https://github.com/kevnnard/smart-window"

  auto_updates true

  app "SmartWindow.app"

  zap trash: [
    "~/Library/Application Support/SmartWindow",
    "~/Library/Preferences/com.kevnnard.smartwindow.plist",
  ]
end
'''


def render(version, sha):
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise SystemExit(f"bad version: {version}")
    if not re.fullmatch(r"[0-9a-f]{64}", sha):
        raise SystemExit(f"bad sha256: {sha}")
    return TEMPLATE.format(version=version, sha=sha)


def main():
    if len(sys.argv) != 4:
        raise SystemExit("usage: release_tap.py PATH|- VERSION SHA256")
    path, version, sha = sys.argv[1:4]
    body = render(version, sha)
    if path == "-":
        sys.stdout.write(body)
    else:
        with open(path, "w") as f:
            f.write(body)


if __name__ == "__main__":
    main()
