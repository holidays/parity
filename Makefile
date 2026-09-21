GO ?= go

.PHONY: parity vet smoke

# parity runs the Ruby<->Go comparison suite (curated corpus plus the exhaustive
# 1970-2050 sweep). Requires Ruby with the gem pinned in ruby/Gemfile installed
# (`bundle install` from ruby/), plus the `definitions/` submodule checked out:
# the oracle loads our region YAML into the gem via load_custom.
# See README.md for the design and prerequisites.
parity:
	@ls definitions/*.yaml >/dev/null 2>&1 || { \
		echo "error: definitions/ submodule is empty; the oracle would load no region YAML and every region would mismatch." >&2; \
		echo "Run: git submodule update --init definitions" >&2; \
		exit 1; \
	}
	cd go && $(GO) test -v -timeout=20m ./...

vet:
	cd go && $(GO) vet ./...

# smoke drives the Ruby oracle directly over its NDJSON contract.
smoke:
	ruby/oracle_smoke.sh
