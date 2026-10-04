#!/usr/bin/env bash
# Repoints this working tree at the tip of each implementation's default branch
# instead of the pinned versions, for the non-blocking "main" parity check:
#
#   go-holidays  main    via `go get` in go/ (rewrites go.mod and go.sum)
#   holidays     master  via ruby/Gemfile.main, pinned here to the resolved
#                        commit (the caller sets BUNDLE_GEMFILE to it)
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
GEMFILE="$ROOT/ruby/Gemfile.main"

# Test exactly the versions CI named the job after (passed in as PARITY_*),
# or resolve them now when run by hand.
if [ -n "${PARITY_GO_REF:-}" ]; then
	go="$PARITY_GO" go_ref="$PARITY_GO_REF"
	ruby="$PARITY_RUBY" ruby_ref="$PARITY_RUBY_REF"
	defs="$PARITY_DEFS" defs_sha="$PARITY_DEFS_SHA"
else
	eval "$(scripts/resolve-versions.sh main)"
fi

# GOPROXY=direct so a cached proxy answer can never hide a newer commit.
(cd go && GOPROXY=direct go get "$GO_MODULE@$go_ref")

# Pin the gem to the resolved commit in this (temporary) copy's Gemfile, so
# the oracle loads exactly that commit every time it starts.
sed -i.bak "s/branch: \"master\"/ref: \"$ruby_ref\"/" "$GEMFILE" && rm -f "$GEMFILE.bak"
grep -q "ref: \"$ruby_ref\"" "$GEMFILE"
rm -f "$GEMFILE.lock"
BUNDLE_GEMFILE="$GEMFILE" bundle install --quiet

git -C definitions fetch --quiet origin "$defs_sha"
git -C definitions checkout --quiet "$defs_sha"

summary="Parity against main:
  go-holidays  $go ($go_ref)
  holidays gem $ruby ($ruby_ref)
  definitions  $defs ($defs_sha, pinned by go-holidays $go)"
echo "$summary"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	printf '```\n%s\n```\n' "$summary" >> "$GITHUB_STEP_SUMMARY"
fi
