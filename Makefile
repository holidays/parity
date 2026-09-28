GO ?= go

.PHONY: parity parity-main parity-latest vet smoke

# parity runs the Ruby<->Go comparison suite (curated corpus plus the exhaustive
# 1970-2050 sweep). Requires Ruby with the gem pinned in ruby/Gemfile installed
# (`bundle install` from ruby/), plus the `definitions/` submodule checked out:
# the oracle loads our region YAML into the gem via load_custom.
# -count=1 is required: go test caches a passing result keyed only on Go inputs,
# but this suite's outcome also depends on the gem, its pin, and definitions/,
# which the cache cannot see, so a cached run can report a stale green.
# See README.md for the design and prerequisites.
parity:
	@ls definitions/*.yaml >/dev/null 2>&1 || { \
		echo "error: definitions/ submodule is empty; the oracle would load no region YAML and every region would mismatch." >&2; \
		echo "Run: git submodule update --init definitions" >&2; \
		exit 1; \
	}
	cd go && $(GO) test -count=1 -v -timeout=20m ./...

# parity-main runs the same suite against go-holidays main and the gem's master
# (the non-blocking check). scripts/use-main.sh rewrites go.mod and the
# definitions checkout, so this works in a temporary copy of the tree and leaves
# yours untouched. Needs an authenticated gh (in Actions, GH_TOKEN).
parity-main:
	@work="$$(mktemp -d)" && trap 'rm -rf "$$work"' EXIT && \
		cp -a . "$$work/parity" && cd "$$work/parity" && \
		scripts/use-main.sh && \
		BUNDLE_GEMFILE="$$PWD/ruby/Gemfile.main" $(MAKE) parity

# parity-latest runs the same suite against the latest published release of
# each implementation (not main tip, and not whatever this repo currently
# pins). scripts/use-latest-release.sh does the rewriting, so this works in a
# temporary copy of the tree and leaves yours untouched. Needs an
# authenticated gh (in Actions, GH_TOKEN).
parity-latest:
	@work="$$(mktemp -d)" && trap 'rm -rf "$$work"' EXIT && \
		cp -a . "$$work/parity" && cd "$$work/parity" && \
		scripts/use-latest-release.sh && \
		BUNDLE_GEMFILE="$$PWD/ruby/Gemfile.latest" $(MAKE) parity

vet:
	cd go && $(GO) vet ./...

# smoke drives the Ruby oracle directly over its NDJSON contract.
smoke:
	ruby/oracle_smoke.sh
