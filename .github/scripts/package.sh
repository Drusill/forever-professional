#!/usr/bin/env bash
# Runs the BigWigs packager: release.sh from BigWigsMods/packager v2, the script the packager
# action runs, with our file name and CurseForge label. Extra arguments pass through
# (-d skips the upload). Used by release.yml and test.yml.
set -euo pipefail

release_sh="${RUNNER_TEMP:?}/release.sh"
curl -fsSL --retry 3 https://raw.githubusercontent.com/BigWigsMods/packager/v2/release.sh -o "$release_sh"

# On a push to a branch, release.sh skips packaging when HEAD already has a tag ("Found future
# tag ..., not packaging.") and still exits 0. release.yml tags HEAD just before packaging, so
# present the run as a manual one; release.sh reads GITHUB_EVENT_NAME only for that check.
# A workflow's env: can't override GITHUB_* variables, so it's set on this command.
GITHUB_EVENT_NAME=workflow_dispatch bash "$release_sh" \
  -n "{package-name}-{project-version}:{package-name}-{project-version}" "$@"
