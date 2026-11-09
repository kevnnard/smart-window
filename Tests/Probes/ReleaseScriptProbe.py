#!/usr/bin/env python3
"""Exercise scripts/release.sh and scripts/release_tap.py in a scratch repo and tap.

Fake swift and gh record their calls; nothing is built, signed, pushed or published.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SHA = "a" * 64

CASK_9_9_9 = f'''cask "smartwindow" do
  version "9.9.9"
  sha256 "{SHA}"

  url "https://github.com/kevnnard/smart-window/releases/download/v#{{version}}/SmartWindow.zip"
  name "SmartWindow"
  desc "Polybar-style macOS top bar with numbered window tabs"
  homepage "https://github.com/kevnnard/smart-window"

  app "SmartWindow.app"

  zap trash: [
    "~/Library/Application Support/SmartWindow",
    "~/Library/Preferences/com.kevnnard.smartwindow.plist",
  ]
end
'''


def git(cwd, *args):
    return subprocess.run(["git", "-C", str(cwd), *args], check=True, capture_output=True, text=True).stdout


class ReleaseTapProbe(unittest.TestCase):
    def tap(self, *args):
        return subprocess.run(["python3", "-I", str(ROOT / "scripts/release_tap.py"), *args],
                              capture_output=True, text=True)

    def test_renders_the_whole_cask(self):
        result = self.tap("-", "9.9.9", SHA)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, CASK_9_9_9)

    def test_writes_the_cask_file(self):
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "smartwindow.rb"
            result = self.tap(str(path), "9.9.9", SHA)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "")
            self.assertEqual(path.read_text(), CASK_9_9_9)

    def test_rejects_bad_version_and_sha(self):
        for version, sha, message in [("9.9", SHA, "bad version: 9.9"), ("9.9.9", "xyz", "bad sha256: xyz")]:
            with tempfile.TemporaryDirectory() as scratch:
                path = Path(scratch) / "smartwindow.rb"
                result = self.tap(str(path), version, sha)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)
                self.assertFalse(path.exists())


class ReleaseScriptProbe(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        base = Path(scratch.name)
        self.repo = base / "smart-window"
        self.tap_dir = base / "homebrew-tap"
        (self.repo / "scripts").mkdir(parents=True)
        (self.repo / "Resources").mkdir()
        for name in ["release.sh", "release_tap.py"]:
            shutil.copy2(ROOT / "scripts" / name, self.repo / "scripts" / name)
        shutil.copy2(ROOT / "Resources/Info.plist", self.repo / "Resources/Info.plist")
        (self.repo / "Resources/ReleaseNotes-9.9.9.md").write_text("notes\n")
        git(base, "init", "-q", "-b", "main", str(self.repo))
        git(self.repo, "add", ".")
        git(self.repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "init")
        (self.tap_dir / "Casks").mkdir(parents=True)
        self.cask = self.tap_dir / "Casks/smartwindow.rb"
        self.cask.write_text("old cask\n")
        git(base, "init", "-q", "-b", "main", str(self.tap_dir))
        git(self.tap_dir, "add", ".")
        git(self.tap_dir, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "init")
        for checkout in [self.repo, self.tap_dir]:
            remote = base / f"{checkout.name}.git"
            git(base, "init", "-q", "--bare", str(remote))
            git(checkout, "remote", "add", "origin", str(remote))
            git(checkout, "push", "-q", "-u", "origin", "main")
        self.plist = (self.repo / "Resources/Info.plist").read_text()
        self.signing = {"SMARTWINDOW_CODESIGN_IDENTITY": "x", "SMARTWINDOW_NOTARY_PROFILE": "y"}

        tools = base / "tools"
        tools.mkdir()
        self.calls = base / "calls.log"
        for tool in ["swift", "gh"]:
            path = tools / tool
            path.write_text(f'#!/usr/bin/env bash\nprintf "{tool} %s\\n" "$*" >> "$FAKE_CALLS"\n')
            path.chmod(0o755)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("SMARTWINDOW_")}
        self.env.update(PATH=f"{tools}:{os.environ['PATH']}", FAKE_CALLS=str(self.calls), TAP_DIR=str(self.tap_dir))

    def release(self, *args, env=None):
        return subprocess.run([str(self.repo / "scripts/release.sh"), *args], capture_output=True, text=True,
                              env={**self.env, **(env or {})})

    def calls_made(self):
        return self.calls.read_text().splitlines() if self.calls.exists() else []

    def assert_nothing_changed(self):
        self.assertEqual((self.repo / "Resources/Info.plist").read_text(), self.plist)
        self.assertEqual(self.cask.read_text(), "old cask\n")
        self.assertEqual(git(self.repo, "tag"), "")
        self.assertEqual(git(self.repo, "rev-list", "--count", "HEAD").strip(), "1")
        self.assertEqual(git(self.tap_dir, "rev-list", "--count", "HEAD").strip(), "1")
        self.assertNotIn("gh release create", "\n".join(self.calls_made()))

    def test_usage(self):
        for args in [[], ["9.9"], ["--dry-run", "v9.9.9"]]:
            result = self.release(*args)
            self.assertEqual(result.returncode, 2, args)
            self.assertIn("usage:", result.stderr)
            self.assertIn("[--dry-run] X.Y.Z", result.stderr)
            self.assertEqual(result.stdout, "")
        self.assert_nothing_changed()

    def test_dry_run_prints_the_plan_and_changes_nothing(self):
        result = self.release("--dry-run", "9.9.9")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        out = result.stdout
        self.assertIn("[dry-run] would stop: SMARTWINDOW_CODESIGN_IDENTITY is not set", result.stderr)
        for expected in [
            "==> tests",
            "[dry-run] set version 9.9.9",
            '[dry-run] git commit -m chore(release): v9.9.9',
            "[dry-run] build, sign and notarize SmartWindow.zip",
            "[dry-run] git tag -a v9.9.9 -m SmartWindow v9.9.9",
            "[dry-run] git push origin main",
            "[dry-run] git push origin v9.9.9",
            "--notes-file",
            "ReleaseNotes-9.9.9.md",
            'version "9.9.9"',
            "brew update && brew upgrade --cask kevnnard/tap/smartwindow",
        ]:
            self.assertIn(expected, out)
        self.assertIn("swift build -c release", self.calls_made())
        self.assert_nothing_changed()

    def test_dirty_tree_stops_a_real_release(self):
        (self.repo / "Resources/ReleaseNotes-9.9.9.md").write_text("changed\n")
        (self.repo / "untracked.txt").write_text("ignored by the check\n")
        result = self.release("9.9.9", env={"SMARTWINDOW_CODESIGN_IDENTITY": "x", "SMARTWINDOW_NOTARY_PROFILE": "y"})
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr.strip(), "tracked changes present; commit or stash first")
        self.assertEqual(self.calls_made(), [])
        self.assert_nothing_changed()

    def test_untracked_files_do_not_stop_the_dry_run(self):
        (self.repo / "untracked.txt").write_text("x\n")
        result = self.release("--dry-run", "9.9.9", env={"SMARTWINDOW_CODESIGN_IDENTITY": "x",
                                                          "SMARTWINDOW_NOTARY_PROFILE": "y"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("would stop", result.stderr)

    def test_existing_tag_stops_a_real_release(self):
        git(self.repo, "tag", "v9.9.9")
        result = self.release("9.9.9", env={"SMARTWINDOW_CODESIGN_IDENTITY": "x", "SMARTWINDOW_NOTARY_PROFILE": "y"})
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr.strip(), "v9.9.9 already exists")
        self.assertEqual(self.calls_made(), [])
        git(self.repo, "tag", "-d", "v9.9.9")
        self.assert_nothing_changed()

    def test_remote_tag_lookup_failure_stops_a_real_release(self):
        git(self.repo, "remote", "set-url", "origin", str(self.repo.parent / "missing.git"))
        result = self.release("9.9.9", env=self.signing)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr.strip(), "cannot check tags on origin")
        self.assertEqual(self.calls_made(), [])
        self.assert_nothing_changed()

    def test_tap_without_git_or_origin_stops_a_real_release(self):
        git(self.tap_dir, "remote", "remove", "origin")
        result = self.release("9.9.9", env=self.signing)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr.strip(), f"tap checkout has no origin: {self.tap_dir}")
        shutil.rmtree(self.tap_dir / ".git")
        result = self.release("9.9.9", env=self.signing)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr.strip(), f"tap is not a git checkout on a branch: {self.tap_dir}")
        self.assertEqual(self.calls_made(), [])
        self.assertEqual(self.cask.read_text(), "old cask\n")
        self.assertEqual(git(self.repo, "tag"), "")

    def test_unreadable_status_stops_a_real_release(self):
        for checkout, message in [(self.tap_dir, f"cannot read git status: {self.tap_dir}"),
                                  (self.repo, f"cannot read git status: {self.repo}")]:
            index = checkout / ".git/index"
            saved = index.read_bytes()
            index.write_bytes(b"corrupt")
            result = self.release("9.9.9", env=self.signing)
            index.write_bytes(saved)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stderr.strip(), message)
        self.assertEqual(self.calls_made(), [])
        self.assert_nothing_changed()

    def test_missing_signing_stops_a_real_release(self):
        result = self.release("9.9.9")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr.strip(), "SMARTWINDOW_CODESIGN_IDENTITY is not set (source scripts/release-env.sh)")
        self.assertEqual(self.calls_made(), [])
        self.assert_nothing_changed()


if __name__ == "__main__":
    unittest.main()
