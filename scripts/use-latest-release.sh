#!/usr/bin/env bash
# Repoints this working tree at the latest published release of each
# implementation, for the non-blocking "latest release" parity check:
#
#   go-holidays  latest tagged release  via `go get` in go/
#   holidays     latest published gem   via ruby/Gemfile.latest, pinned here to
#                                       the resolved release (the caller sets
#                                       BUNDLE_GEMFILE to it)
#   definitions          checked out at whatever commit that go-holidays
#                        release pins, for the same reason as use-main.sh
#
# The versions come from scripts/resolve-versions.sh latest. Unlike
# use-main.sh, this never touches an unreleased commit: the highest release tag
# and rubygems.org's current release are both tagged, published versions. It
# diverges from `make parity` (the pinned check) only once a release ships that this repo's pins have not caught up to yet, and
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
GEMFILE="$ROOT/ruby/Gemfile.latest"

# Test exactly the versions CI named the job after (passed in as PARITY_*),
# or resolve them now when run by hand.
if [ -n "${PARITY_GO_REF:-}" ]; then
	go="$PARITY_GO" go_ref="$PARITY_GO_REF"
	ruby="$PARITY_RUBY" ruby_ref="$PARITY_RUBY_REF"
	defs="$PARITY_DEFS" defs_sha="$PARITY_DEFS_SHA"
else
	eval "$(scripts/resolve-versions.sh latest)"
fi

(cd go && GOPROXY=direct go get "$GO_MODULE@$go_ref")

# Pin the gem to the resolved release in this (temporary) copy's Gemfile, so
# the oracle loads exactly that release every time it starts.
sed -i.bak "s/^gem \"holidays\"\$/gem \"holidays\", \"$ruby_ref\"/" "$GEMFILE" && rm -f "$GEMFILE.bak"
grep -q "gem \"holidays\", \"$ruby_ref\"" "$GEMFILE"
rm -f "$GEMFILE.lock"
BUNDLE_GEMFILE="$GEMFILE" bundle install --quiet

git -C definitions fetch --quiet origin "$defs_sha"
git -C definitions checkout --quiet "$defs_sha"

summary="Parity against latest release:
  go-holidays  $go
  holidays gem $ruby
  definitions  $defs ($defs_sha, pinned by go-holidays $go)"
echo "$summary"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	printf '```\n%s\n```\n' "$summary" >> "$GITHUB_STEP_SUMMARY"
fi
