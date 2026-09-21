# parity

Parity checks between the language implementations of the holidays project.

Every implementation must return the same result for the same call. There is no
scenario where two languages are allowed to differ, so any mismatch reported
here is a bug, never an accepted divergence. No implementation is the
reference: when two disagree, the difference is reported as a difference, and
which side is wrong is decided case by case. Every difference must be stated in
the results. Nothing is skipped, allowlisted, or explained away silently.

This repo is deliberately separate from the implementations. Its checks are
non-blocking for them: a red run here is a signal to go fix something, not a
gate on a PR in `holidays` or `go-holidays`.

| Implementation | Repo | Version under test |
|----------------|------|--------------------|
| Ruby | [holidays/holidays](https://github.com/holidays/holidays) | pinned in `ruby/Gemfile` |
| Go | [holidays/go-holidays](https://github.com/holidays/go-holidays) | pinned in `go/go.mod` |

## Layout

```
definitions/   git submodule: holidays/definitions, the shared region YAML
ruby/          the Ruby oracle (oracle.rb) and its pinned gem (Gemfile)
go/            the Go harness: corpus, exhaustive sweep, oracle client
```

## Design: apples-to-apples

Comparing two engines fairly means separating CODE from DATA. The gem carries
its own bundled data set, which we do not want to depend on:

- **CODE** is each implementation's real resolution logic: the installed gem,
  and the go-holidays module.
- **DATA** is the `definitions/` submodule YAML, loaded into the running gem on
  startup via `Holidays.load_custom`, and compiled into go-holidays at its
  release. The comparison never rides on whatever data the gem happens to bundle.

Both sides then resolve the same holiday rules, so any difference in output is a
real behavioural difference between the engines, not a difference in the data.

**The `definitions/` pin must match the definitions version the pinned
go-holidays release was generated from** (go-holidays pins the same submodule).
If they drift apart, the mismatches are data mismatches, not engine ones. When
bumping go-holidays in `go/go.mod`, bump `definitions/` to the commit
go-holidays pins.

## How it works

```
go/ (Go harness)  --NDJSON request-->  ruby/oracle.rb  (pinned gem + our region YAML)
                  <--NDJSON result--
```

- "Oracle" is only the name of the process that exposes the Ruby gem to the
  harness. It carries no authority over the Go port's results.
- `ruby/oracle.rb` runs the gem, loads the region YAML, and answers one
  line-delimited JSON (NDJSON) request per line on stdin, one response per line
  on stdout (see its RUN CONTRACT header).
- `go/oracle_client.go` starts the oracle as a subprocess and speaks that
  contract.
- `go/parity_test.go` runs a curated corpus through both the Go API and the
  oracle and diffs the results. Each case runs under all four flag combinations:
  plain, observed, informal, informal+observed.
- `go/sweep_parity_test.go` is the exhaustive sweep: every region, every year
  1970-2050, all four flag combinations.
- `ruby/oracle_smoke.sh` is a standalone smoke check of the oracle.
- `ruby/verify_between_equiv.rb` is a manual one-off check for the oracle's
  `year_holidays_range` fast path. Nothing runs it automatically.

## Running

```
make parity
```

**Prerequisites:**
- Go (see `go/go.mod`).
- Ruby with the pinned `holidays` gem installed. The oracle activates
  `ruby/Gemfile` via `bundler/setup`, so run `bundle install` from `ruby/`.
- The `definitions/` submodule checked out (`git submodule update --init
  definitions`). Without it the gem falls back to its own bundled data and
  regions diverge; `make parity` refuses to run in that state.

`make smoke` runs only the Ruby oracle smoke check, and `make vet` vets the Go
harness.

## Scope

The eight result-producing public functions are compared:

| Ruby gem | Go port |
|----------|---------|
| `on` | `On` |
| `between` | `Between` |
| `cache_between` | `CacheBetween` |
| `next_holidays` | `NextHolidays` |
| `year_holidays` | `YearHolidaysFrom` |
| `any_holidays_during_work_week?` | `AnyHolidaysDuringWorkWeek` |
| `available_regions` | `AvailableRegions` |
| `load_custom` | `LoadCustom` |

`year_holidays` is compared against `YearHolidaysFrom(from, opts)` (the from-date
variant that matches the gem's semantics), not `YearHolidays(year)`.

### `load_all` is not compared (N/A)

The gem's `load_all` eagerly loads every region at runtime. The Go port already
loads all regions eagerly via `init()` side effects, so `load_all` would be a
no-op with nothing to compare.

## Known open mismatches

### `next_holidays` for `de` from 2024-03-01

The gem's `next_holidays` windows its search through a `dates_driver` that
buckets each holiday by its *source month* (function/variable holidays such as
Easter offsets live in "month 0") and only reaches out to `from >> 12`. For this
case the 2025 bucket ends at month 4, so the gem **drops** the fixed-date
`Tag der Arbeit` (2025-05-01, month 5) while still **keeping** the Easter-based
`Christi Himmelfahrt` (2025-05-29, month 0) it computes for that year.

Go's `NextHolidays` instead expands year by year until it has `count` holidays,
so it includes `Tag der Arbeit 2025`. The two disagree, which is a parity
failure that has to be resolved in one implementation or the other. The case is
asserted in `go/parity_test.go`, so the `NextHolidays` spec fails on every run
until it is resolved.
