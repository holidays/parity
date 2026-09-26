#!/usr/bin/env bash
# Repoints this working tree at the tip of each implementation's default branch
# instead of the pinned versions, for the non-blocking "main" parity check:
#
#   go-holidays  main    via `go get` in go/ (rewrites go.mod and go.sum)
#   holidays     master  via ruby/Gemfile.main (no lockfile, so bundler resolves
#                        the current tip; the caller sets BUNDLE_GEMFILE to it)
#   definitions          checked out at whatever commit go-holidays main pins,
#                        because Go compiles its definitions in and the oracle
#                        must load the same data or every mismatch is noise
#
# This dirties the working tree (go.mod, go.sum, the definitions checkout).
# `make parity-main` runs it in a temporary copy of the repo for that reason;
# do not run it directly in a tree you are committing from. Needs go, ruby with
# bundler, git, and an authenticated gh (in Actions, set GH_TOKEN).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GO_MODULE=github.com/holidays/go-holidays
GO_REPO=holidays/go-holidays
GO_BRANCH=main
GEMFILE="$ROOT/ruby/Gemfile.main"

# GOPROXY=direct so a cached proxy answer for a branch name can never hide a
# newer commit.
(cd go && GOPROXY=direct go get "$GO_MODULE@$GO_BRANCH")
go_version="$(cd go && go list -m -f '{{.Version}}' "$GO_MODULE")"

rm -f "$GEMFILE.lock"
BUNDLE_GEMFILE="$GEMFILE" bundle install --quiet
gem_sha="$(awk '/^ *revision:/ { print $2 }' "$GEMFILE.lock")"

defs_sha="$(gh api "repos/$GO_REPO/contents/definitions?ref=$GO_BRANCH" --jq .sha)"
git -C definitions fetch --quiet origin "$defs_sha"
git -C definitions checkout --quiet "$defs_sha"

summary="Parity against main:
  go-holidays  $go_version
  holidays gem $gem_sha
  definitions  $defs_sha (pinned by go-holidays $GO_BRANCH)"
echo "$summary"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	printf '```\n%s\n```\n' "$summary" >> "$GITHUB_STEP_SUMMARY"
fi
