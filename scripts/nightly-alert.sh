#!/usr/bin/env bash
# Turns a nightly parity result into a GitHub issue, so a failure reaches a
# person by email instead of sitting in the Actions tab:
#
#   nightly-alert.sh failure   open an issue assigned to $ALERT_ASSIGNEE, or
#                              comment on the one already open
#   nightly-alert.sh success   close the open issue, if any, with a comment
#
# Each workflow has at most one open alert issue, found by its exact title, so
# a run that keeps failing adds comments rather than new issues. The assignee
# is subscribed to the issue, so GitHub emails them on open, on every comment,
# and on close (given email is on for participating notifications).
#
# Needs: GH_TOKEN (with issues: write), GITHUB_REPOSITORY, ALERT_TITLE,
# ALERT_ASSIGNEE, RUN_URL, and VERSIONS (a one-line description of what ran).
set -euo pipefail

outcome="${1:-}"

existing="$(gh issue list --repo "$GITHUB_REPOSITORY" --state open \
	--search "\"$ALERT_TITLE\" in:title" --json number,title \
	--jq "map(select(.title == \"$ALERT_TITLE\")) | .[0].number // empty")"

case "$outcome" in
failure)
	body="Nightly run failed: $RUN_URL

Versions: $VERSIONS

See the run log for every mismatch."
	if [ -n "$existing" ]; then
		gh issue comment "$existing" --repo "$GITHUB_REPOSITORY" --body "$body"
		exit 0
	fi
	gh issue create --repo "$GITHUB_REPOSITORY" --title "$ALERT_TITLE" \
		--assignee "$ALERT_ASSIGNEE" --body "$body

This issue stays open while the nightly run keeps failing (each failure adds a comment) and closes itself on the next passing run."
	;;
success)
	if [ -z "$existing" ]; then
		exit 0
	fi
	gh issue close "$existing" --repo "$GITHUB_REPOSITORY" \
		--comment "Nightly run passed again: $RUN_URL

Versions: $VERSIONS"
	;;
*)
	echo "usage: nightly-alert.sh failure|success" >&2
	exit 2
	;;
esac
