#!/usr/bin/env bash
# Resolves the exact versions one parity tier compares, so CI can put them in
# the job name and the switching scripts test exactly those versions:
#
#   resolve-versions.sh pinned   the pins in this repo
#   resolve-versions.sh latest   the newest published release of each
#   resolve-versions.sh main     the tip of each default branch
#
# Prints key=value lines (and appends them to $GITHUB_OUTPUT when set):
#
#   go         go-holidays, for display    (v1.1.0, or main@<short sha>)
#   go_ref     what `go get` should fetch  (v1.1.0, or a full sha)
#   ruby       the gem, for display        (11.7.0, or master@<short sha>)
#   ruby_ref   what bundler should install (11.7.0, or a full sha)
#   defs       definitions, for display    (v9.2.0, or a short sha if untagged)
#   defs_sha   the definitions commit to check out
#
# latest and main need an authenticated gh (in Actions, set GH_TOKEN); pinned
# only reads files in this repo plus public git refs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GO_MODULE=github.com/holidays/go-holidays
GO_REPO=holidays/go-holidays
GEM_REPO=holidays/holidays
DEFS_REPO=holidays/definitions

tier="${1:-}"

# defs_label names a definitions commit by its release tag, falling back to the
# short sha when the commit is not a tagged release.
defs_label() {
	local sha="$1" tag
	tag="$(git ls-remote --tags "https://github.com/$DEFS_REPO.git" |
		awk -v sha="$sha" '$1 == sha { sub("refs/tags/", "", $2); sub(/\^\{\}$/, "", $2); print $2; exit }')"
	echo "${tag:-${sha:0:7}}"
}

# defs_pinned_by returns the definitions commit a go-holidays ref pins.
defs_pinned_by() {
	gh api "repos/$GO_REPO/contents/definitions?ref=$1" --jq .sha
}

# branch_sha returns the commit at the tip of a branch.
branch_sha() {
	git ls-remote "https://github.com/$1.git" "refs/heads/$2" | awk '{ print $1 }'
}

case "$tier" in
pinned)
	go_ref="$(awk -v m="$GO_MODULE" '$1 == m { print $2; exit }' go/go.mod)"
	go="$go_ref"
	ruby_ref="$(awk '/^ *holidays \(/ { gsub(/[()]/, ""); print $2; exit }' ruby/Gemfile.lock)"
	ruby="$ruby_ref"
	defs_sha="$(git ls-tree HEAD definitions | awk '{ print $3 }')"
	;;
latest)
	# Highest release tag, which is what `go get @latest` resolves to.
	go_ref="$(git ls-remote --tags --refs "https://github.com/$GO_REPO.git" |
		awk '{ sub("refs/tags/", "", $2); print $2 }' |
		grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)"
	go="$go_ref"
	ruby_ref="$(curl -fsSL https://rubygems.org/api/v1/versions/holidays/latest.json |
		ruby -rjson -e 'puts JSON.parse($stdin.read).fetch("version")')"
	ruby="$ruby_ref"
	defs_sha="$(defs_pinned_by "$go_ref")"
	;;
main)
	go_ref="$(branch_sha "$GO_REPO" main)"
	go="main@${go_ref:0:7}"
	ruby_ref="$(branch_sha "$GEM_REPO" master)"
	ruby="master@${ruby_ref:0:7}"
	defs_sha="$(defs_pinned_by "$go_ref")"
	;;
*)
	echo "usage: $0 pinned|latest|main" >&2
	exit 2
	;;
esac

for v in go_ref ruby_ref defs_sha; do
	if [ -z "${!v}" ]; then
		echo "resolve-versions: could not resolve $v for $tier" >&2
		exit 1
	fi
done
defs="$(defs_label "$defs_sha")"

out="go=$go
go_ref=$go_ref
ruby=$ruby
ruby_ref=$ruby_ref
defs=$defs
defs_sha=$defs_sha"
echo "$out"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
	echo "$out" >> "$GITHUB_OUTPUT"
fi
