# Release on merge to main: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merging a pull request into `main` whose `CHANGELOG.md` names an untagged version tests, tags, packages and uploads ForeverProfessional to CurseForge; any other merge releases nothing.

**Architecture:** The decisions live in one small, tested Python script, `.github/scripts/release_version.py`, with two commands: `check` (which version, and should this commit release it?) and `tag` (tag the commit and push the tag, idempotently). The workflows stay thin: `release.yml` on push to `main` runs `check`, then tests, `tag` and the BigWigs packager in one job; `test.yml` runs the tests on pull requests and previews the release.

**Tech Stack:** GitHub Actions, `BigWigsMods/packager@v2`, Python 3.12 (stdlib only), `unittest`, git.

**Spec:** `docs/superpowers/specs/2026-11-22-release-on-merge-design.md`

## Global Constraints

- Version source: the first `## ForeverProfessional <version>` heading in `CHANGELOG.md`. The version is `X.Y.Z`, optionally `-beta<N>` or `-alpha<N>`.
- Tag `v<version>` exists → "nothing to release". Version not above the newest tag → the run fails.
- The tag goes on the merge commit; the tag step is idempotent (tag already on this commit: fine; on another commit: error).
- Packager arguments: `-n "{package-name}-{project-version}:{package-name} {project-version}"`.
- `release.yml`: push to `main` plus `workflow_dispatch`; no tag-push trigger.
- `test.yml`: pull requests into `main` and `develop`, pushes to `develop`; on pull requests into `main` the summary says "Merging releases 0.2.0" or "Merging won't release".
- Python 3.12, stdlib only, like `tools/`. Don't touch `tools/` (AGENTS.md: ask first).
- Commits: Conventional Commits, no `Co-Authored-By` or AI attribution (user rule). Work on `develop`; never push without the user asking.
- `.github/` is a dotfolder, so the packager never ships it; no `.pkgmeta` change.

## Review Focus

1. **Retry after a failed upload.** The tag is already on the merge commit; "Re-run failed jobs" must release again, not skip. Pinned in Task 1 (`decide` with `tag_on_head=True`, `check` with the tag on `--head`) and Task 2 (`tag` run twice).
2. **A docs or CI merge after a release.** The tag exists on an older commit: skip, don't fail. Pinned in Task 1 (`test_existing_tag_elsewhere_skips`).
3. **Numeric version order.** `0.10.0` is above `0.9.0`; `0.2.0-beta1` is below `0.2.0`. Pinned in Task 1 (`VersionKeyTest`).
4. **CRLF and stray tags.** A Windows checkout gives `CHANGELOG.md` CRLF line endings; tags like `vnext` or `v0.1` exist. Both must work. Pinned in Task 1 (`test_crlf`, `test_ignores_non_version_tags`).
5. **"Re-run all jobs" on a run that already uploaded.** It must not upload the same version twice. Guarded in Task 3 by `gh release view` (the packager makes the GitHub release after the CurseForge upload). It can't run locally; Task 3 Step 5 checks it by reading.

---

### Task 1: `check` command

**Files:**
- Create: `.github/scripts/release_version.py`
- Test: `.github/scripts/test_release_version.py`

**Interfaces:**
- Produces, in `release_version.py`:
  - `class ReleaseError(Exception)`
  - `parse_version(changelog: str) -> str`
  - `version_key(version: str) -> tuple[int, int, int, int, int]`: `(major, minor, patch, stage, n)` with stage alpha=0, beta=1, release=2, and n=0 for a release
  - `decide(version: str, tags: list[str], tag_on_head: bool) -> bool`: True means release
  - `main(argv: list[str] | None = None) -> int`
  - CLI `check [--repo PATH] [--changelog PATH] [--head SHA]`: `--repo` defaults to `.`, `--changelog` to `<repo>/CHANGELOG.md`. It prints three lines, `version=0.2.0`, `tag=v0.2.0`, `release=true|false`, and returns 0. On `ReleaseError` it prints `error: <message>` to stderr and returns 1. The file ends with `if __name__ == "__main__": sys.exit(main())`.
- Produces, in the test module: `make_repo(path: Path) -> GitRepo`, where `GitRepo.commit(version: str) -> str` writes `## ForeverProfessional <version>\n` to `CHANGELOG.md`, commits it and returns the SHA, and `GitRepo.git(*args) -> str` runs git in the repo. `make_repo` runs `git init -q -b main`. Commits use `--allow-empty`, so the same version can be committed twice, and pass `-c user.name=test -c user.email=test@example.invalid`.

- [ ] **Step 1: Write the failing tests**

Build each temp repo with `tempfile.TemporaryDirectory(ignore_cleanup_errors=True)`, since Windows keeps git objects read-only. Capture `main` output with `contextlib.redirect_stdout` and `redirect_stderr`.

```python
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
            with self.subTest(bad), self.assertRaisesRegex(ReleaseError, "is not a version like 0.2.0 or 0.2.0-beta1"):
                parse_version(f"## ForeverProfessional {bad}\n")
    def test_no_heading(self):
        with self.assertRaisesRegex(ReleaseError, 'has no "## ForeverProfessional <version>" heading'):
            parse_version("# Changelog\n")
    def test_repo_changelog_parses(self):  # guards every future release bump
        self.assertRegex(parse_version((ROOT / "CHANGELOG.md").read_text(encoding="utf-8")), r"^\d+\.\d+\.\d+")

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
    # each test: repo = make_repo(tmp); first = repo.commit("0.1.0"); repo.git("tag", "v0.1.0", first)
    def test_new_version_releases(self):
        # head = repo.commit("0.2.0"); main(["check", "--repo", tmp, "--head", head]) == 0
        # stdout lines == ["version=0.2.0", "tag=v0.2.0", "release=true"]
    def test_existing_tag_elsewhere_skips(self):
        # head = repo.commit("0.1.0")
        # stdout contains "release=false"
    def test_tag_on_head_releases(self):
        # main(["check", "--repo", tmp, "--head", first]) → stdout contains "release=true"
    def test_lower_version_fails(self):
        # head = repo.commit("0.0.9"); main(...) == 1; stderr contains "error: version 0.0.9 is not above the newest tag v0.1.0"
```

`ROOT = Path(__file__).resolve().parents[2]`. The `CheckCommandTest` bodies are described in comments; the assertions in them are exact.

- [ ] **Step 2: Run the tests and see them fail**

Run: `mise exec -- python -m unittest discover .github/scripts -v`
Expected: an import error for `release_version`.

- [ ] **Step 3: Implement `release_version.py` (`ReleaseError`, `parse_version`, `version_key`, `decide`, `main` with the `check` command)**

- Version pattern: `\d+\.\d+\.\d+(?:-(?:alpha|beta)\d+)?`. Tag pattern: `v` plus the version pattern.
- `parse_version`: use `splitlines()`. Take the first line starting with `## ForeverProfessional `, strip it, and full-match the rest against the version pattern.
- `decide`: if `f"v{version}"` is in `tags`, return `tag_on_head`. Otherwise drop tags that don't match the tag pattern. If the highest remaining tag's `version_key` is >= the version's key, raise `ReleaseError`.
- `main`: parse with `argparse` subcommands. Read tags with `git tag --list v*`. When `--head` is given and the tag exists, `tag_on_head` compares `git rev-list -n 1 <tag>` with `git rev-parse <head>`. Run git with `subprocess.run([...], cwd=repo, check=True, capture_output=True, text=True)`. Read the changelog as UTF-8.

- [ ] **Step 4: Run the tests and see them pass**

Run: `mise exec -- python -m unittest discover .github/scripts -v`
Expected: all tests pass. Also run `mise exec -- python .github/scripts/release_version.py check` in the repo. Expected: `version=0.1.0`, `tag=v0.1.0`, `release=false`.

- [ ] **Step 5: Commit**

```bash
git add .github/scripts/release_version.py .github/scripts/test_release_version.py
git commit -m "ci: add release version check script"
```

### Task 2: `tag` command

**Files:**
- Modify: `.github/scripts/release_version.py`
- Test: `.github/scripts/test_release_version.py`

**Interfaces:**
- Consumes: `parse_version`, `ReleaseError`, `main`, `make_repo` and `GitRepo` from Task 1.
- Produces: CLI `tag --head SHA [--repo PATH] [--changelog PATH] [--remote NAME]`. `--head` is required and `--remote` defaults to `origin`. It ensures that `v<version>` points at `--head` and pushes `refs/tags/v<version>` to the remote. It prints `tag=v<version>` and returns 0. If the tag is on another commit, it prints `error: tag v0.2.0 is on <short sha>, not on <short sha>` to stderr, pushes nothing and returns 1.

- [ ] **Step 1: Write the failing tests**

Each test adds a bare remote: `git init -q --bare <tmp>/remote.git`, then `repo.git("remote", "add", "origin", <that path>)`.

```python
class TagCommandTest(unittest.TestCase):
    def test_creates_and_pushes(self):
        # head = repo.commit("0.2.0"); main(["tag", "--repo", tmp, "--head", head]) == 0
        # stdout == "tag=v0.2.0\n"; repo.git("ls-remote", "--tags", "origin", "v0.2.0") starts with head
    def test_retry_is_fine(self):
        # run the same main([... "tag" ...]) twice; both return 0; remote tag still at head
    def test_tag_on_other_commit_fails(self):
        # first = repo.commit("0.2.0"); repo.git("tag", "v0.2.0", first); head = repo.commit("0.2.0")
        # main(["tag", ...head]) == 1; stderr contains "error: tag v0.2.0 is on"; ls-remote for v0.2.0 is empty
```

- [ ] **Step 2: Run the tests and see them fail**

Run: `mise exec -- python -m unittest discover .github/scripts -v`
Expected: the three `TagCommandTest` tests fail (argparse rejects `tag` with exit code 2, which shows up as `SystemExit`).

- [ ] **Step 3: Add the `tag` subcommand to `main`**

Create the tag only if it's missing (`git tag <tag> <head>`, a lightweight tag like `v0.1.0`). Compare SHAs as in Task 1. Push with `git push <remote> refs/tags/<tag>`. Pushing a tag that's already on the remote at the same commit succeeds as a no-op.

- [ ] **Step 4: Run the tests and see them pass**

Run: `mise exec -- python -m unittest discover .github/scripts -v`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add .github/scripts/release_version.py .github/scripts/test_release_version.py
git commit -m "ci: add idempotent release tagging"
```

### Task 3: Workflows and docs

**Files:**
- Modify (replace): `.github/workflows/release.yml`
- Create: `.github/workflows/test.yml`
- Modify: `AGENTS.md` (the Layout row for release packaging, the Commands block, the "Releasing" section)

**Interfaces:**
- Consumes: `release_version.py check [--head SHA]` (stdout `version=`, `tag=`, `release=`; exit 1 on error) and `release_version.py tag --head SHA` from Tasks 1 and 2.
- Produces: the job id `test` in `test.yml`, for the ruleset the repo gets once it's public.

- [ ] **Step 1: Write `release.yml`**

- `name: Release`. Triggers: `push: branches: [main]` and `workflow_dispatch:`. Add `concurrency: { group: release, cancel-in-progress: false }`.
- One job, `release`: `if: github.ref == 'refs/heads/main'`, `runs-on: ubuntu-latest`, `permissions: contents: write`.
- Steps, in order:
  1. `actions/checkout@v4` with `fetch-depth: 0` (history and tags).
  2. `actions/setup-python@v5` with `python-version: "3.12"`.
  3. id `check`: `python .github/scripts/release_version.py check --head "$GITHUB_SHA" >> "$GITHUB_OUTPUT"`.
  4. id `go`, `if: steps.check.outputs.release == 'true'`, env `GH_TOKEN: ${{ github.token }}` and `TAG: ${{ steps.check.outputs.tag }}`. If `gh release view "$TAG"` succeeds, write `release=false` to `$GITHUB_OUTPUT` and "$TAG already has a GitHub release, so it was uploaded. Nothing to release." to `$GITHUB_STEP_SUMMARY`. Otherwise write `release=true`.
  5. `if: steps.check.outputs.release != 'true'`: write "Nothing to release: CHANGELOG.md says $VERSION and $TAG already exists." to the summary. Pass the values through `env:`.
  6. Under `if: steps.go.outputs.release == 'true'`: `pip install -r requirements-dev.txt`, then `python -m unittest discover tests`, `python -m unittest discover tools/tests` and `python -m unittest discover .github/scripts`.
  7. Same condition: `python .github/scripts/release_version.py tag --head "$GITHUB_SHA"`.
  8. Same condition: `BigWigsMods/packager@v2` with `args: -n "{package-name}-{project-version}:{package-name} {project-version}"`, env `CF_API_TOKEN: ${{ secrets.CF_API_TOKEN }}` and `GH_API_TOKEN: ${{ secrets.GITHUB_TOKEN }}`.
  9. Same condition: write "Released $TAG to CurseForge and as a GitHub release." to the summary.
- The header comment states the flow in three lines and points to AGENTS.md "Releasing".

- [ ] **Step 2: Write `test.yml`**

- `name: Test`. Triggers: `pull_request: branches: [main, develop]` and `push: branches: [develop]`.
- Job `test`: `runs-on: ubuntu-latest`, `permissions: contents: read`.
- Steps:
  1. Checkout with `fetch-depth: 0`, for the tags.
  2. Python 3.12.
  3. `pip install -r requirements-dev.txt`.
  4. The three test suites from Step 1.6.
  5. id `preview`, `if: github.event_name == 'pull_request' && github.base_ref == 'main'`: run `check` with no `--head` and append to `$GITHUB_OUTPUT`. An error fails the check, so a version below the newest tag is caught before the merge.
  6. Same condition: write "Merging releases $VERSION" when `release` is `true`, else "Merging won't release: $TAG already exists." to the summary.

- [ ] **Step 3: Rewrite the AGENTS.md "Releasing" section and update Layout and Commands**

- Layout: the row `.pkgmeta`, `.github/workflows/release.yml`, `CHANGELOG.md` becomes `.pkgmeta`, `.github/`, `CHANGELOG.md` with "Release packaging and CI: see **Releasing**".
- Commands: add `python -m unittest discover .github/scripts    # release script tests`.
- "Releasing" must say:
  - Releases come from `main`. Merging a PR from `develop` into `main` runs `release.yml`.
  - The version is the first `## ForeverProfessional X.Y.Z` heading. If `vX.Y.Z` exists, nothing is released. Otherwise the run tests, tags the merge commit and uploads to CurseForge (project 1822577) and GitHub.
  - `-beta1` and `-alpha1` make beta and alpha files. A version not above the newest tag fails the run.
  - It needs the secret `CF_API_TOKEN`.
  - `test.yml` runs on PRs into `main` and `develop` and on pushes to `develop`. On a PR into `main`, its summary says whether merging releases.
  - Steps:
    1. On `develop`, rewrite `CHANGELOG.md` with the new heading and this release's player notes only.
    2. Update `## Interface` when the client changes.
    3. When the user asks, push and open a PR from `develop` into `main`, and check its summary.
    4. Merge with "Create a merge commit", never squash or rebase.
    5. If the upload fails, use "Re-run failed jobs".
  - A merge with no version change (docs, CI) releases nothing.
  - Once the repo is public, add a ruleset on `main` that requires a pull request and the `test` check.
  - Keep the existing `@project-version@` and zip-contents paragraphs, and the in-game testing part after them.

- [ ] **Step 4: Run every suite locally**

Run: `mise exec -- python -m unittest discover tests`, then `mise exec -- python -m unittest discover tools/tests`, then `mise exec -- python -m unittest discover .github/scripts`.
Expected: all pass (the first two had 219 and 19 tests).

- [ ] **Step 5: Check the workflows by reading them**

No Actions runner is available locally, and `actionlint` isn't installed. Read both files against Steps 1–2 and check:
- (a) the tag trigger is gone;
- (b) every step after `go` has `if: steps.go.outputs.release == 'true'`;
- (c) values reach scripts through `env:`, not `${{ }}` inside `run:`;
- (d) `test` is the job id.

The first real run in Task 4 proves the YAML is valid.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/release.yml .github/workflows/test.yml AGENTS.md
git commit -m "ci: release on merge to main"
```

### Task 4: First pull request (with the user)

Each step here is the user's to do or to approve. `gh` isn't installed and the repo is private.

- [ ] **Step 1:** Ask the user to approve `git push origin develop`, then push.
- [ ] **Step 2:** The user opens a PR from `develop` into `main` on github.com.
- [ ] **Step 3:** Check (from the user's screenshot) that the **Test** run passed and its summary says "Merging won't release: v0.1.0 already exists." If YAML errors show up, fix them on `develop`, push, and check again.
- [ ] **Step 4:** The user sets Settings → General → Pull Requests to allow merge commits only (squash and rebase unticked).
- [ ] **Step 5:** The user merges with "Create a merge commit".
- [ ] **Step 6:** Check that the **Release** run on `main` passed with "Nothing to release: CHANGELOG.md says 0.1.0 and v0.1.0 already exists.", and that no new tag or CurseForge file appeared. Run `git fetch` and `git log --oneline -1 origin/main` to see the merge commit.

The release path itself (tests, `tag`, packager, and the `ForeverProfessional v0.x.y` label) first runs on the next real version bump.
