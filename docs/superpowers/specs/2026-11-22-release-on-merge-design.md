# Release on merge to main: design

**Intent.** Releasing should be a pull request from `develop` into `main`, not a hand-pushed tag. When the merged pull request carries a new version in `CHANGELOG.md`, the merge alone tests, tags, packages and uploads the addon to CurseForge (project 1822577) and as a GitHub release.

**Today.** `release.yml` runs on any `v*` tag push and uploads with the BigWigs packager; `v0.1.0` went up that way and is under review. `main` is still just "Initial commit", 57 commits behind `develop`. The CurseForge project is **unlisted**, so approved files are visible only by link until the user switches it to listed in the General tab. That covers "publish hidden", so nothing in the pipeline has to hide files.

## Goals

- A merge into `main` whose `CHANGELOG.md` heading names a version with no tag yet releases it. Any other merge (docs, CI) releases nothing.
- Pull requests show the tests and whether merging will release, before the merge.
- CurseForge files get a readable name: `ForeverProfessional v0.2.0`, not `v0.2.0-forever`.

**Non-goals.** Automatic version bumps, release-please, Wago and WoWInterface uploads, switching the project to listed.

**Anti-goals.** Uploading a file with no addon changes (CurseForge bans it). Uploading one version twice. A failed upload leaving a tag that blocks the retry.

## Approaches

- **A. The CHANGELOG version decides (picked by the user).** The pull request updates `## ForeverProfessional X.Y.Z` and the notes. Merging it releases that version if no tag `vX.Y.Z` exists yet. Releases stay deliberate, and the player-facing notes stay hand-written.
- **B. release-please.** Needs conventional commit prefixes, which the repo doesn't use, and writes the changelog from commit messages. Rejected.
- **C. Every merge releases.** Docs-only or CI-only merges would upload files with no changes. Rejected.

## Design

1. **Version source.** The first `## ForeverProfessional <version>` heading in `CHANGELOG.md`. The version is `X.Y.Z`, optionally with `-beta` or `-alpha` and a number after it. The packager makes a tag containing "beta" or "alpha" a beta or alpha file.
2. **`release.yml`** runs on push to `main`, plus a manual "Run workflow" button.
   - It reads the version. If tag `v<version>` exists, it stops with "nothing to release".
   - If the version doesn't sort above the newest existing tag, it fails, so a typo can't publish an older number.
   - Otherwise it runs both test suites. Then it creates and pushes the tag on the merge commit and runs the packager in the same job. A tag pushed with the workflow token doesn't start other workflows, so everything happens in this one run.
   - The tag step is idempotent: a tag already on this commit is fine, and a tag on another commit is an error. So if the upload fails, "Re-run failed jobs" retries it.
   - The packager gets `-n "{package-name}-{project-version}:{package-name} {project-version}"` for the file name and label.
   - The tag-push trigger goes away, so `main` is the only way to release.
3. **`test.yml`** runs on pull requests into `main` and `develop`, and on pushes to `develop`. It runs both test suites. On pull requests into `main` it also writes "Merging releases 0.2.0" or "Merging won't release" to the run summary.
4. **Branching.** Work stays on `develop`. Releases are a pull request from `develop` into `main`, merged with a **merge commit**, never squash or rebase, so tags stay on both branches' history. The repo settings should allow only merge commits.
5. **First pull request.** It brings all 57 commits plus this change into `main`. `CHANGELOG.md` still says 0.1.0 and `v0.1.0` exists, so merging it releases nothing. That run also tests the skip path.
6. **Docs.** AGENTS.md "Releasing" is rewritten for this flow.

**Constraints.**
- The private repo on GitHub Free can't enforce "pull requests only" on `main`. Once the repo is public, add a ruleset that requires a pull request and the `test` check.
- `gh` isn't installed, so the user opens and merges pull requests on github.com.

**Left to the builder.** The exact YAML, the version regex, and how the summary is worded.
