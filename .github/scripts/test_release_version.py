"""Tests for release_version.py. Run: python -m unittest discover .github/scripts"""

import contextlib
import io
import subprocess
import tempfile
import unittest
from pathlib import Path

from release_version import ReleaseError, decide, main, parse_version, version_key

ROOT = Path(__file__).resolve().parents[2]


class GitRepo:
    """A throwaway git repository whose commits each set CHANGELOG.md to one version."""

    def __init__(self, path: Path):
        self.path = Path(path)

    def git(self, *args: str) -> str:
        result = subprocess.run(
            ["git", *args], cwd=self.path, check=True, capture_output=True, text=True
        )
        return result.stdout.strip()

    def commit(self, version: str) -> str:
        (self.path / "CHANGELOG.md").write_text(
            f"## ForeverProfessional {version}\n", encoding="utf-8"
        )
        self.git("add", "CHANGELOG.md")
        self.git(
            "-c", "user.name=test", "-c", "user.email=test@example.invalid",
            "commit", "-q", "--allow-empty", "-m", version,
        )
        return self.git("rev-parse", "HEAD")


def make_repo(path: Path) -> GitRepo:
    repo = GitRepo(path)
    repo.git("init", "-q", "-b", "main")
    return repo


def run_main(*argv: str) -> tuple[int, str, str]:
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = main(list(argv))
    return code, out.getvalue(), err.getvalue()


class ParseVersionTest(unittest.TestCase):
    def test_reads_first_heading(self):
        text = "## ForeverProfessional 0.2.0\n\nNotes\n\n## ForeverProfessional 0.1.0\n"
        self.assertEqual(parse_version(text), "0.2.0")

    def test_accepts_prerelease(self):
        self.assertEqual(parse_version("## ForeverProfessional 0.2.0-beta1\n"), "0.2.0-beta1")
        self.assertEqual(parse_version("## ForeverProfessional 1.0.0-alpha12\n"), "1.0.0-alpha12")

    def test_crlf(self):
        self.assertEqual(parse_version("## ForeverProfessional 0.2.0\r\n\r\nNotes\r\n"), "0.2.0")

    def test_rejects_malformed(self):
        for bad in ("0.2", "0.2.0-rc1", "0.2.0-beta", "v0.2.0"):
            with self.subTest(bad), self.assertRaisesRegex(
                ReleaseError, "is not a version like 0.2.0 or 0.2.0-beta1"
            ):
                parse_version(f"## ForeverProfessional {bad}\n")

    def test_no_heading(self):
        with self.assertRaisesRegex(ReleaseError, 'has no "## ForeverProfessional <version>" heading'):
            parse_version("# Changelog\n")

    def test_repo_changelog_parses(self):
        # Guards every future release bump of the real CHANGELOG.md.
        changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
        self.assertRegex(parse_version(changelog), r"^\d+\.\d+\.\d+")


class VersionKeyTest(unittest.TestCase):
    def test_order(self):
        ordered = ["0.2.0-alpha1", "0.2.0-alpha2", "0.2.0-beta1", "0.2.0", "0.2.1", "0.9.0", "0.10.0"]
        self.assertEqual(sorted(reversed(ordered), key=version_key), ordered)


class DecideTest(unittest.TestCase):
    def test_existing_tag_elsewhere_skips(self):
        self.assertFalse(decide("0.1.0", ["v0.1.0"], tag_on_head=False))

    def test_existing_tag_on_head_is_a_retry(self):
        self.assertTrue(decide("0.1.0", ["v0.1.0"], tag_on_head=True))

    def test_new_version_above_newest_releases(self):
        self.assertTrue(decide("0.2.0", ["v0.1.0"], tag_on_head=False))
        self.assertTrue(decide("0.2.0", ["v0.2.0-beta1"], tag_on_head=False))
        self.assertTrue(decide("0.2.0", [], tag_on_head=False))

    def test_ignores_non_version_tags(self):
        self.assertTrue(decide("0.2.0", ["vnext", "v0.1", "v0.1.0"], tag_on_head=False))

    def test_lower_version_fails(self):
        with self.assertRaisesRegex(ReleaseError, "version 0.0.9 is not above the newest tag v0.1.0"):
            decide("0.0.9", ["v0.1.0"], tag_on_head=False)
        with self.assertRaisesRegex(ReleaseError, "not above the newest tag v0.2.0"):
            decide("0.2.0-beta1", ["v0.2.0"], tag_on_head=False)


class CheckCommandTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(ignore_cleanup_errors=True)
        self.addCleanup(tmp.cleanup)
        self.tmp = tmp.name
        self.repo = make_repo(Path(self.tmp))
        self.first = self.repo.commit("0.1.0")
        self.repo.git("tag", "v0.1.0", self.first)

    def test_new_version_releases(self):
        head = self.repo.commit("0.2.0")
        code, out, _ = run_main("check", "--repo", self.tmp, "--head", head)
        self.assertEqual(code, 0)
        self.assertEqual(out.splitlines(), ["version=0.2.0", "tag=v0.2.0", "release=true"])

    def test_existing_tag_elsewhere_skips(self):
        head = self.repo.commit("0.1.0")
        code, out, _ = run_main("check", "--repo", self.tmp, "--head", head)
        self.assertEqual(code, 0)
        self.assertIn("release=false", out.splitlines())

    def test_tag_on_head_releases(self):
        code, out, _ = run_main("check", "--repo", self.tmp, "--head", self.first)
        self.assertEqual(code, 0)
        self.assertIn("release=true", out.splitlines())

    def test_lower_version_fails(self):
        head = self.repo.commit("0.0.9")
        code, _, err = run_main("check", "--repo", self.tmp, "--head", head)
        self.assertEqual(code, 1)
        self.assertIn("error: version 0.0.9 is not above the newest tag v0.1.0", err)


if __name__ == "__main__":
    unittest.main()
