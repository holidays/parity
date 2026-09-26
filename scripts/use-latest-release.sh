#!/usr/bin/env bash
# Repoints this working tree at the latest published release of each
# implementation, for the non-blocking "latest release" parity check:
#
#   go-holidays  latest tagged release  via `go get pkg@latest` in go/
#   holidays     latest published gem   via ruby/Gemfile.latest (no lockfile,
#                                       so bundler resolves rubygems.org's
#                                       current release each run; the caller
#                                       sets BUNDLE_GEMFILE to it)
#   definitions          checked out at whatever commit that go-holidays
#                        release pins, for the same reason as use-main.sh
#
# Unlike use-main.sh, this never touches an unreleased commit: `go get @latest`
# and an unpinned Gemfile against rubygems.org both resolve only to tagged,
# published versions. It diverges from `make parity` (the pinned check) only
# once a release ships that this repo's pins have not caught up to yet, and
# diverges from `make parity-main` whenever a default branch carries commits
# past its latest tag.
#
# This dirties the working tree (go.mod, go.sum, the definitions checkout).
# `make parity-latest` runs it in a temporary copy of the repo for that reason;
# do not run it directly in a tree you are committing from. Needs go, ruby with
# bundler, git, and an authenticated gh (in Actions, set GH_TOKEN).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GO_MODULE=github.com/holidays/go-holidays
GO_REPO=holidays/go-holidays
GEMFILE="$ROOT/ruby/Gemfile.latest"

# GOPROXY=direct so a cached proxy answer can never hide a tag published
# minutes ago.
(cd go && GOPROXY=direct go get "$GO_MODULE@latest")
go_version="$(cd go && go list -m -f '{{.Version}}' "$GO_MODULE")"

rm -f "$GEMFILE.lock"
BUNDLE_GEMFILE="$GEMFILE" bundle install --quiet
gem_version="$(awk '/^ *holidays \(/ { gsub(/[()]/, ""); print $2; exit }' "$GEMFILE.lock")"

defs_sha="$(gh api "repos/$GO_REPO/contents/definitions?ref=$go_version" --jq .sha)"
git -C definitions fetch --quiet origin "$defs_sha"
git -C definitions checkout --quiet "$defs_sha"

summary="Parity against latest release:
  go-holidays  $go_version
  holidays gem $gem_version
  definitions  $defs_sha (pinned by go-holidays $go_version)"
echo "$summary"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	printf '```\n%s\n```\n' "$summary" >> "$GITHUB_STEP_SUMMARY"
fi
