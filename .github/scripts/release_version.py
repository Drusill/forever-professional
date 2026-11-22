"""Decide whether a commit releases ForeverProfessional, from the version in CHANGELOG.md.

The version is the first "## ForeverProfessional <version>" heading: X.Y.Z, optionally
followed by -alpha<N> or -beta<N>. Used by .github/workflows/release.yml and test.yml.

    check [--head SHA]   print version=, tag= and release=true|false
    tag --head SHA       put tag v<version> on SHA and push it (safe to run again)
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

HEADING = "## ForeverProfessional "
VERSION = r"\d+\.\d+\.\d+(?:-(?:alpha|beta)\d+)?"
VERSION_RE = re.compile(VERSION)
TAG_RE = re.compile("v" + VERSION)
STAGES = {"alpha": 0, "beta": 1}
RELEASE_STAGE = 2


class ReleaseError(Exception):
    pass


def parse_version(changelog: str) -> str:
    for line in changelog.splitlines():
        if line.startswith(HEADING):
            version = line[len(HEADING):].strip()
            if not VERSION_RE.fullmatch(version):
                raise ReleaseError(
                    f'CHANGELOG.md heading "{line.strip()}": "{version}" '
                    "is not a version like 0.2.0 or 0.2.0-beta1"
                )
            return version
    raise ReleaseError('CHANGELOG.md has no "## ForeverProfessional <version>" heading')


def version_key(version: str) -> tuple[int, int, int, int, int]:
    core, _, pre = version.partition("-")
    major, minor, patch = (int(part) for part in core.split("."))
    if not pre:
        return major, minor, patch, RELEASE_STAGE, 0
    stage = pre.rstrip("0123456789")
    return major, minor, patch, STAGES[stage], int(pre[len(stage):])


def decide(version: str, tags: list[str], tag_on_head: bool) -> bool:
    """True if this commit should release `version`. A tag already on the commit is a retry."""
    if f"v{version}" in tags:
        return tag_on_head
    versions = [tag[1:] for tag in tags if TAG_RE.fullmatch(tag)]
    if versions:
        newest = max(versions, key=version_key)
        if version_key(newest) >= version_key(version):
            raise ReleaseError(f"version {version} is not above the newest tag v{newest}")
    return True


def git(repo: Path, *args: str) -> str:
    result = subprocess.run(["git", *args], cwd=repo, capture_output=True, text=True)
    if result.returncode != 0:
        raise ReleaseError(f"git {' '.join(args)} failed:\n{result.stderr.strip()}")
    return result.stdout.strip()


def tag_commit(repo: Path, tag: str) -> str:
    return git(repo, "rev-list", "-n", "1", tag)


def check(repo: Path, changelog: Path, head: str | None) -> None:
    version = parse_version(changelog.read_text(encoding="utf-8"))
    tag = f"v{version}"
    tags = git(repo, "tag", "--list", "v*").splitlines()
    tag_on_head = (
        head is not None and tag in tags
        and tag_commit(repo, tag) == git(repo, "rev-parse", head)
    )
    release = decide(version, tags, tag_on_head)
    print(f"version={version}")
    print(f"tag={tag}")
    print(f"release={'true' if release else 'false'}")


def tag(repo: Path, changelog: Path, head: str, remote: str) -> None:
    """Put v<version> on `head` and push it. A tag already on `head` is fine (a retry)."""
    name = "v" + parse_version(changelog.read_text(encoding="utf-8"))
    head_sha = git(repo, "rev-parse", head)
    if git(repo, "tag", "--list", name):
        tagged = tag_commit(repo, name)
        if tagged != head_sha:
            raise ReleaseError(f"tag {name} is on {tagged[:7]}, not on {head_sha[:7]}")
    else:
        git(repo, "tag", name, head_sha)
    git(repo, "push", "-q", remote, f"refs/tags/{name}")
    print(f"tag={name}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    check_parser = commands.add_parser("check", help="should this commit release?")
    check_parser.add_argument(
        "--head", help="the commit being released; a tag already on it counts as a retry"
    )
    tag_parser = commands.add_parser("tag", help="tag the commit and push the tag")
    tag_parser.add_argument("--head", required=True, help="the commit to tag")
    tag_parser.add_argument("--remote", default="origin")
    for sub in (check_parser, tag_parser):
        sub.add_argument("--repo", type=Path, default=Path("."))
        sub.add_argument("--changelog", type=Path)
    args = parser.parse_args(argv)
    changelog = args.changelog or args.repo / "CHANGELOG.md"
    try:
        if args.command == "check":
            check(args.repo, changelog, args.head)
        else:
            tag(args.repo, changelog, args.head, args.remote)
    except ReleaseError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
