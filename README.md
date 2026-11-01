# parity

| Check | Status |
|-------|--------|
| Pinned (blocking) | [![pinned](https://img.shields.io/github/actions/workflow/status/holidays/parity/parity-pinned.yml?branch=main&event=push&label=pinned)](https://github.com/holidays/parity/actions/workflows/parity-pinned.yml?query=branch%3Amain+event%3Apush) |
| Nightly: latest releases | [![latest](https://img.shields.io/github/actions/workflow/status/holidays/parity/parity-latest.yml?branch=main&event=schedule&label=nightly%20latest)](https://github.com/holidays/parity/actions/workflows/parity-latest.yml?query=event%3Aschedule) |
| Nightly: unreleased main | [![unreleased](https://img.shields.io/github/actions/workflow/status/holidays/parity/parity-main.yml?branch=main&event=schedule&label=nightly%20unreleased)](https://github.com/holidays/parity/actions/workflows/parity-main.yml?query=event%3Aschedule) |

Parity checks between the language implementations of the holidays project.

Every implementation must return the same result for the same call. There is no
scenario where any projects are allowed to differ, so any mismatch reported
here is a bug, never an accepted divergence. No implementation is the
reference: when projects disagree, the difference is reported as a
difference, and which one is wrong is decided case by case. Every difference must be stated in
the results. Nothing is skipped, allowlisted, or explained away silently.

This repo is deliberately separate from the implementations. Its checks never
gate a PR in `holidays` or `go-holidays`: a red run here is a signal to go fix
something.

| Implementation | Repo | Pinned version | Tracked branch |
|----------------|------|----------------|----------------|
| Ruby | [holidays/holidays](https://github.com/holidays/holidays) | 11.8.0 (`ruby/Gemfile`) | `master` |
| Go | [holidays/go-holidays](https://github.com/holidays/go-holidays) | v1.2.0 (`go/go.mod`) | `main` |
| Data | [holidays/definitions](https://github.com/holidays/definitions) | v9.3.0 (`definitions/` submodule) | whatever go-holidays pins |

The pinned versions are the ones the blocking `Pinned` job tests. Keep them in
step: `definitions/` must be the commit the pinned go-holidays release pins,
and the gem should be the release that ships the same definitions version.
When you bump a pin, update this table too.

## Three checks

The same suite runs three times, against three different reference points that
never move backwards relative to each other: `pinned <= latest release <= main
tip`.

| Check (job name in CI) | Versions | Blocking? |
|-------|----------|-----------|
| `Pinned (blocking): Go go-holidays <v> = Ruby holidays <v>, definitions <v>` | the pins in this repo | Yes. If the pinned versions disagree, that has to be fixed. |
| `Latest releases (non-blocking): Go go-holidays <v> = Ruby holidays <v>, definitions <v>` | the newest published release of go-holidays and of the gem, resolved fresh each run | No. Never make it required. A red run means a release has already shipped that breaks parity: the pin needs bumping, or the new release needs fixing. |
| `Unreleased (non-blocking): Go go-holidays main@<sha> = Ruby holidays master@<sha>, definitions <v>` | tip of go-holidays `main` and the gem's `master` | No. Never make it required. A red run is an early warning that unreleased work would break parity before it ever ships. |

Each job name lists the exact versions it tested (worked out first by
`scripts/resolve-versions.sh`), and `=` means every call gave identical output.
A red job means the implementations disagree, and its log lists every
difference.

The checks can coincide (nothing released past the pin, or nothing on `main`
past the latest tag), but they answer different questions and diverge as soon
as a release ships or a commit lands. Both non-blocking checks also run
nightly. A failing nightly opens (or comments on) an issue assigned to ppeble,
so GitHub emails them, and the next passing nightly closes it (see
`scripts/nightly-alert.sh`).

To save runner time, a new push to a PR cancels its older runs, docs-only
changes skip the non-blocking checks, and the latest check skips its comparison
when the latest releases are exactly the pins.

For `latest release` and `main`, `definitions/` is checked out at the commit
that go-holidays version pins, via `scripts/use-latest-release.sh` and
`scripts/use-main.sh`. Bumping a pin in `go/go.mod`, `ruby/Gemfile`, or
`definitions/` makes a new release the blocking baseline.

## Running

```
make parity          # the pinned versions (the blocking check)
make parity-latest   # latest published release of each (non-blocking)
make parity-main     # go-holidays main + gem master (non-blocking)
```

`make parity-latest` and `make parity-main` both work in a temporary copy of
the tree, so your `go/go.mod` and `definitions/` checkout are left alone. Both
need an authenticated `gh`.

**Prerequisites:**
- Go (see `go/go.mod`).
- Ruby with the pinned `holidays` gem installed. The oracle activates
  `ruby/Gemfile` via `bundler/setup`, so run `bundle install` from `ruby/`.
- The `definitions/` submodule checked out (`git submodule update --init
  definitions`). Without it the gem falls back to its own bundled data and
  regions diverge; `make parity` refuses to run in that state.

`make smoke` runs only the Ruby oracle smoke check, and `make vet` vets the Go
harness.
