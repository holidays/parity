#!/usr/bin/env bash
# Smoke check for ruby/oracle.rb.
#
# Drives the oracle over its line-delimited JSON contract and asserts a few
# known-good results. Run from anywhere:
#
#   ruby/oracle_smoke.sh
#
# Expected: prints each response line, then "SMOKE OK".
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORACLE="$HERE/oracle.rb"

# Each line is one request; responses come back one line each, in order.
REQUESTS=$(cat <<'EOF'
{"id":"xmas","func":"on","date":"2024-12-25","regions":["us"]}
{"id":"year","func":"year_holidays","regions":["us"],"from":"2024-01-01"}
{"id":"regions","func":"available_regions"}
{"id":"workweek","func":"any_holidays_during_work_week?","date":"2024-12-25","regions":["us"]}
EOF
)

OUT=$(printf '%s\n' "$REQUESTS" | ruby "$ORACLE")
echo "$OUT"

# Assert US Christmas 2024 == exactly the expected normalized JSON.
EXPECT_XMAS='{"ok":true,"id":"xmas","func":"on","result":[{"date":"2024-12-25","name":"Christmas Day"}]}'
XMAS_LINE=$(printf '%s\n' "$OUT" | grep '"id":"xmas"')
if [ "$XMAS_LINE" != "$EXPECT_XMAS" ]; then
  echo "FAIL: Christmas line mismatch"
  echo "  expected: $EXPECT_XMAS"
  echo "  got:      $XMAS_LINE"
  exit 1
fi

# Assert US 2024 has 10 holidays (the v7.0.0 expectation).
YEAR_COUNT=$(printf '%s\n' "$OUT" | grep '"id":"year"' | ruby -rjson -e 'puts JSON.parse($stdin.read)["result"].size')
if [ "$YEAR_COUNT" != "10" ]; then
  echo "FAIL: US 2024 expected 10 holidays, got $YEAR_COUNT"
  exit 1
fi

# Assert work-week query is the boolean true.
printf '%s\n' "$OUT" | grep -q '"id":"workweek".*"result":true' || {
  echo "FAIL: work-week query did not return true"; exit 1;
}

echo "SMOKE OK"
