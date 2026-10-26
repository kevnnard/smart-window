#!/usr/bin/env python3
"""Exercise the public packager in isolated state, never /Applications or a keychain."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ReleasePackagingProbe(unittest.TestCase):
    def exercise(self, missing=False):
        scratch = tempfile.TemporaryDirectory(dir=ROOT / ".build" / "probes")
        self.addCleanup(scratch.cleanup)
        root = Path(scratch.name)
        (root / "scripts").mkdir()
        (root / "Resources").mkdir()
        shutil.copy2(ROOT / "scripts/install-app.sh", root / "scripts/install-app.sh")
        shutil.copy2(ROOT / "Resources/Info.plist", root / "Resources/Info.plist")
        old = root / ".build/release"
        old.mkdir(parents=True)
        (old / "SmartWindow").write_text("obsolete build")
        fresh = root / "current release output"
        fresh.mkdir()
        if not missing:
            (fresh / "SmartWindow").write_text("fresh build")
        bundle = root / "SmartWindow.app"
        bundle.mkdir()
        (bundle / "keep-me").write_text("existing artifact")
        tools = root / "tools"
        tools.mkdir()
        swift = tools / "swift"
        swift.write_text('''#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$FAKE_SWIFT_CALLS"
case "$*" in
  'build -c release') exit 0 ;;
  'build -c release --show-bin-path') printf '%s\\n' "$FAKE_SWIFT_BIN" ;;
  *) exit 2 ;;
esac
''')
        swift.chmod(0o755)
        calls = root / "calls"
        env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}",
                   SMARTWINDOW_SKIP_INSTALL="1", SMARTWINDOW_CODESIGN_IDENTITY="",
                   FAKE_SWIFT_BIN=str(fresh), FAKE_SWIFT_CALLS=str(calls))
        result = subprocess.run(["bash", str(root / "scripts/install-app.sh")],
                                env=env, capture_output=True, text=True)
        return root, fresh, bundle, calls, result

    def test_current_build_wins_over_stale_legacy_executable(self):
        root, fresh, bundle, calls, result = self.exercise()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((bundle / "Contents/MacOS/SmartWindow").read_text(), "fresh build")
        self.assertEqual(result.stderr, "")
        self.assertEqual(result.stdout,
                         "Building SmartWindow in release mode...\nCreating app bundle...\n"
                         "Skipping code signing (set SMARTWINDOW_CODESIGN_IDENTITY to sign releases).\n"
                         "Skipping installation to /Applications (SMARTWINDOW_SKIP_INSTALL=1).\n"
                         f"Done. App bundle ready at {bundle}\n")
        self.assertEqual(calls.read_text().splitlines(),
                         ["build -c release", "build -c release --show-bin-path"])

    def test_missing_current_binary_preserves_existing_bundle(self):
        root, fresh, bundle, calls, result = self.exercise(missing=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "Building SmartWindow in release mode...\n")
        self.assertEqual(result.stderr, f"Error: could not find built executable at {fresh / 'SmartWindow'}\n")
        self.assertEqual((bundle / "keep-me").read_text(), "existing artifact")
        self.assertEqual((root / ".build/release/SmartWindow").read_text(), "obsolete build")
        self.assertEqual(calls.read_text().splitlines(),
                         ["build -c release", "build -c release --show-bin-path"])


if __name__ == "__main__":
    unittest.main()
