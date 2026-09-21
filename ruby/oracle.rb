#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby/oracle.rb
#
# Ruby "oracle" for apples-to-apples parity testing against the Go port.
#
# It runs the installed `holidays` gem (CODE, at the version pinned in ruby/Gemfile)
# but loads OUR region YAML (DATA) from the `definitions/` submodule via
# Holidays.load_custom on startup. So the holiday RULES are identical to what the
# Go port compiles, and any difference in output is a real behavioural difference
# in the engines, not in the data.
#
# ============================================================================
# RUN CONTRACT (stable; the Go harness in a later bead depends on this)
# ============================================================================
#
# Transport: LINE-DELIMITED JSON ("JSON Lines" / NDJSON).
#   - Read: exactly one JSON object per input line on stdin.
#   - Write: exactly one JSON object per output line on stdout, in the same
#     order as the requests. stdout is line-buffered (sync = true), so a Go
#     harness can write a request line and read one response line back.
#   - Blank lines on stdin are ignored.
#   - One malformed/erroring request does NOT abort the process; it yields one
#     error response line, and processing continues with the next line.
#
# REQUEST shape (one JSON object per line):
#   { "func": "<name>", ... }
# Each request MAY carry an "id" passed through verbatim to the response, to
# let the caller correlate out-of-band. Every request carries a "func" naming
# one of the supported functions below, plus that function's arguments.
#
# Dates are always strings "YYYY-MM-DD" (UTC calendar dates, no time/zone).
# Regions are an array of strings, e.g. ["us"] or ["us_va","ca"]; a bare
# string is also accepted and wrapped into a one-element array.
# Options are booleans:
#   "informal": true  -> include informal holidays   (gem flag :informal)
#   "observed": true  -> use observed dates           (gem flag :observed)
#
# RESPONSE shape (one JSON object per line):
#   { "ok": true,  "id": <echoed-or-null>, "func": "<name>", "result": <...> }
#   { "ok": false, "id": <echoed-or-null>, "func": "<name>",
#     "error": "<class>: <message>" }
#
# A "holiday list" result is ALWAYS normalized to a sorted array of objects:
#   [ { "date": "YYYY-MM-DD", "name": "..." }, ... ]
# sorted by date ascending, then by name ascending. (regions and other gem
# fields are dropped: the Go port's public API exposes date+name.)
#
# ----------------------------------------------------------------------------
# SUPPORTED FUNCTIONS
# ----------------------------------------------------------------------------
#
# 1) on
#    req:  { "func":"on", "date":"2024-12-25", "regions":["us"],
#            "informal":false, "observed":false }
#    res:  result = holiday-list   (holidays on that single date)
#
# 2) between
#    req:  { "func":"between", "start":"2024-01-01", "end":"2024-12-31",
#            "regions":["us"], "informal":false, "observed":false }
#    res:  result = holiday-list   (holidays in [start, end] inclusive)
#
# 3) cache_between
#    req:  { "func":"cache_between", "start":"2024-01-01", "end":"2024-12-31",
#            "regions":["us"], "informal":false, "observed":false }
#    res:  result = holiday-list   (the holidays the gem cached for that range;
#                                   gem returns a hash, normalized to the list)
#
# 4) next_holidays
#    req:  { "func":"next_holidays", "count":3, "regions":["us"],
#            "from":"2024-12-01", "informal":false, "observed":false }
#    res:  result = holiday-list   ("from" optional, defaults to gem default)
#
# 5) year_holidays
#    req:  { "func":"year_holidays", "regions":["us"], "from":"2024-01-01",
#            "informal":false, "observed":false }
#    res:  result = holiday-list   (one calendar year starting at "from";
#                                   "from" optional, gem defaults to today)
#
# 6) any_holidays_during_work_week?
#    req:  { "func":"any_holidays_during_work_week?", "date":"2024-12-25",
#            "regions":["us"], "informal":false, "observed":false }
#    res:  result = true | false   (boolean, NOT a holiday list)
#
# 7) available_regions
#    req:  { "func":"available_regions" }
#    res:  result = ["ar","at",...]   (sorted array of region-code strings)
#    This set is DERIVED from the loaded region YAML (the union of every region
#    code appearing in any holiday rule's `regions:` list), matching exactly how
#    the Go port computes holidays.AvailableRegions(). It is deliberately NOT
#    the gem's bundled REGIONS constant, which is baked at compile time and is
#    never refreshed by load_custom.
#
# 8) load_custom
#    req:  { "func":"load_custom", "files":["definitions/us.yaml"] }
#    res:  result = { "loaded": <int> }   (count of files ingested; lets a
#          caller load extra YAML at runtime. The standard region set is
#          already loaded at startup, so this is rarely needed.)
#
# 9) year_holidays_range
#    req:  { "func":"year_holidays_range", "region":"us",
#            "from_year":1970, "to_year":2050,
#            "flag_combos":[{"informal":false,"observed":false}, ...] }
#    res:  result = [ { "year":1970, "informal":false, "observed":false,
#                       "ok":true, "error":null, "holidays":[ {date,name}, ... ] },
#                     ... ]   (one entry per year x flag_combo. Each flag combo is
#          computed as ONE full-span Holidays.between bucketed by year; if that
#          raises, the combo falls back to a per-year year_holidays loop where a
#          per-entry Ruby failure sets ok=false / error=<class>: <msg> /
#          holidays=[] without aborting the batch. Transport-only batching so the
#          exhaustive sweep makes one round-trip per region instead of one per
#          (year, flag). The Go side still compares (date,name) as deduped SETS.)
#
# ----------------------------------------------------------------------------
# STARTUP
# ----------------------------------------------------------------------------
# On boot, every definitions/*.yaml (excluding index.yaml, which is an
# aggregator and not a region) is ingested via Holidays.load_custom. The path
# to definitions/ is resolved relative to this file (../definitions), so the
# oracle can be launched from any working directory.
#
# Re-loading a region YAML that the gem already knew does NOT duplicate holidays:
# load_custom merges by region key and overrides cleanly. Verified: loading
# us.yaml twice still yields exactly one "Christmas Day" on 2024-12-25, and
# US-2024 = 10 holidays.
#
# Note on available_regions: load_custom ingests our region RULES, but it does
# NOT refresh the gem's compile-time REGIONS constant. So the
# region set cannot come from the gem. Instead, while loading each YAML at
# startup we collect the union of every region code in that file's holiday
# entries, and available_regions returns that union. This keeps it apples to
# apples with the Go port, which derives its region set the same way.
# ============================================================================

# Activate ruby/Gemfile.lock so `holidays` resolves to the version pinned in the Gemfile and
# never silently drifts to whatever is "highest installed". __dir__ is ruby/,
# so this holds no matter what working directory the harness launches us from.
ENV["BUNDLE_GEMFILE"] ||= File.expand_path("Gemfile", __dir__)
require "bundler/setup"

require "holidays"
require "json"
require "date"
require "yaml"

# Keep the oracle a closed world over definitions/*.yaml.
#
# The gem ships its OWN vendored copy of the definitions under
# lib/generated_definitions/, frozen at whatever data the gem release was cut
# with. Holidays.load_custom merges our YAML into the same repository those
# vendored rules land in; it does not replace or lock them out. So both can be
# live at once, and then a region resolves to two rule sets.
#
# The gem loads them lazily: for a requested region it looks up a parent region
# and requires that parent's vendored file if it is not already loaded
# (finder/context/parse_options.rb:63-70 -> definition/context/load.rb:11-12).
# Five of our 288 regions map to an aggregate parent we never define, so they
# trigger it:
#   europe <- si, sk     southamerica <- ve     bg <- bg_bg, bg_en
# Querying si therefore pulls in generated_definitions/europe.rb, which carries
# the gem's stale gb rules (pre-fix Christmas/Boxing observed functions). After
# that, gb resolves to BOTH its rules from our YAML and the stale ones, and the sweep
# reports a mismatch that is not real (go-holidays-2z0).
#
# The distinction that matters is WHAT gets merged. Loading a region's own file
# (target :gb -> gb.rb) re-merges only that region and our rules still
# win. Loading an aggregate (target :europe -> europe.rb) merges every European
# region's rules in one go, which is what appends a second, stale set of gb
# rules. So: delegate for real regions, skip for aggregates.
#
# Testing membership against the region set derived from our own YAML keeps this
# self-maintaining. Any aggregate upstream invents later is absent from our data
# too, so it is skipped without needing a hardcoded list.
#
# There is one more path to guard. load_custom DOES register its regions in the
# regions repository (Merger#call -> regions_repo.add), so the gem's non-wildcard
# finder path short-circuits on regions_repo.loaded?(target) and never reaches
# this override for an already-loaded region. The wildcard path
# (load_wildcard_parent! -> load_region!) has no such loaded? guard, so a query
# like :gb_ unconditionally re-runs this override for :gb and merges the gem's
# stale vendored generated_definitions/gb.rb on top of our load_custom'd rules.
# Our custom-YAML parser symbolizes keys only, so our String "informal" type
# never == the vendored :informal Symbol in the merge dedup, and every
# country-wide informal holiday ends up appended twice. To match the gem's own
# non-wildcard behaviour we mirror its loaded?(target) check here: when the
# region is already loaded, return its registered sub-regions (the same shape
# vendored_call returns) instead of re-loading and re-merging.
Holidays::Definition::Context::Load.class_eval do
  alias_method :vendored_call, :call

  def call(region)
    return [] unless AVAILABLE_REGIONS.include?(region.to_s)

    regions_repo = Holidays::Factory::Definition.regions_repository
    return regions_repo.search(region.to_sym) if regions_repo.loaded?(region.to_sym)

    vendored_call(region)
  end
end

# The gem's ported jp_next_weekday method calls Holidays::JP.holidays_by_month,
# a module that only exists when the gem loads its own vendored jp definitions.
# We feed the gem our submodule YAML via load_custom instead, so that module is
# never defined and every jp query raises NameError, which the parity harness
# reads as "oracle unsupported". This shim rebuilds holidays_by_month from the
# repository load_custom populated, filtered to our :jp entries, so jp resolves
# against exactly our own rules. The body reads the repository lazily so it does
# not matter whether this runs before or after load_all_definitions.
module Holidays
  module JP
    def self.holidays_by_month
      out = Hash.new { |h, k| h[k] = [] }
      Holidays::Factory::Definition.holidays_by_month_repository.all.each do |month, defs|
        out[month] = defs.select { |d| Array(d[:regions]).include?(:jp) }
      end
      out
    end
  end
end

DEFINITIONS_DIR = File.expand_path("../definitions", __dir__)

# Union of every region code seen across the loaded region YAML rules. Populated
# by load_all_definitions and returned (sorted) by the available_regions func,
# matching how the Go port derives holidays.AvailableRegions().
AVAILABLE_REGIONS = []

# Collect every region code from a single definitions YAML file into +acc+.
# Each file has months: -> month-number -> [entry, ...], and each entry carries
# a regions: array of region-code strings.
def collect_regions_from_file(path, acc)
  doc = YAML.load_file(path)
  months = doc.is_a?(Hash) ? doc["months"] : nil
  return unless months.is_a?(Hash)

  months.each_value do |entries|
    Array(entries).each do |entry|
      next unless entry.is_a?(Hash)

      Array(entry["regions"]).each { |r| acc << r.to_s }
    end
  end
end

# Ingest our region YAML into the gem and, alongside, collect the union of every
# region code across those files. Returns the count of files loaded.
def load_all_definitions
  files = Dir.glob(File.join(DEFINITIONS_DIR, "*.yaml"))
              .reject { |f| File.basename(f) == "index.yaml" }
              .sort
  seen = []
  files.each do |f|
    Holidays.load_custom(f)
    collect_regions_from_file(f, seen)
  end
  AVAILABLE_REGIONS.replace(seen.uniq.sort)
  files.size
end

# Normalize a "bare string or array" region argument to an array of symbols.
def regions_arg(req)
  raw = req["regions"]
  raw = [raw] unless raw.is_a?(Array)
  raw.compact.map(&:to_sym)
end

# Translate boolean option flags into the gem's trailing symbol flags.
def option_flags(req)
  flags = []
  flags << :informal if req["informal"]
  flags << :observed if req["observed"]
  flags
end

def parse_date(str)
  Date.strptime(str, "%Y-%m-%d")
end

# Normalize any gem holiday collection (array of hashes, or the hash that
# cache_between returns) into a sorted array of {date, name}.
def normalize_holidays(collection)
  list =
    case collection
    when Hash  then collection.values.flatten
    when Array then collection
    else Array(collection)
    end

  list
    .map { |h| { "date" => h[:date].strftime("%Y-%m-%d"), "name" => h[:name] } }
    .sort_by { |h| [h["date"], h["name"]] }
end

# Build the per-year cells for one flag combo of a year_holidays_range request.
#
# Fast path: ONE Holidays.between over the whole [from_year, to_year] span, whose
# rows are then bucketed by Date#year. Holidays.year_holidays(opts, Jan 1 Y) is
# defined as "run the same @definition_search, then keep rows with
# Jan 1 Y <= date <= Dec 31 Y" (finder/context/year_holiday.rb), so bucketing a
# full-span between result by the row's actual year reproduces every per-year
# cell exactly, at ~1.5x less Ruby work than 81 separate year_holidays calls.
#
# Fallback: if the full-span between raises (e.g. a lunar-table boundary year),
# drop back to a per-year year_holidays loop so a single bad year is isolated
# into its own ok=false cell instead of failing the whole span. This preserves
# the pre-batching per-(year, combo) error behaviour.
def year_holidays_range_for_combo(region, from_year, to_year, informal, observed, opts)
  rows = Holidays.between(Date.new(from_year, 1, 1), Date.new(to_year, 12, 31), *opts)
  buckets = Hash.new { |h, k| h[k] = [] }
  Array(rows).each { |h| buckets[h[:date].year] << h }
  (from_year..to_year).map do |y|
    { "year" => y, "informal" => informal, "observed" => observed,
      "ok" => true, "error" => nil,
      "holidays" => normalize_holidays(buckets[y]) }
  end
rescue StandardError
  (from_year..to_year).map do |y|
    begin
      hs = Holidays.year_holidays(opts, Date.new(y, 1, 1))
      { "year" => y, "informal" => informal, "observed" => observed,
        "ok" => true, "error" => nil, "holidays" => normalize_holidays(hs) }
    rescue StandardError => e
      { "year" => y, "informal" => informal, "observed" => observed,
        "ok" => false, "error" => "#{e.class}: #{e.message}", "holidays" => [] }
    end
  end
end

# ---- dispatch ----------------------------------------------------------------

def dispatch(req)
  case req.fetch("func")
  when "on"
    date = parse_date(req.fetch("date"))
    normalize_holidays(Holidays.on(date, *regions_arg(req), *option_flags(req)))

  when "between"
    s = parse_date(req.fetch("start"))
    e = parse_date(req.fetch("end"))
    normalize_holidays(Holidays.between(s, e, *regions_arg(req), *option_flags(req)))

  when "cache_between"
    s = parse_date(req.fetch("start"))
    e = parse_date(req.fetch("end"))
    normalize_holidays(Holidays.cache_between(s, e, *regions_arg(req), *option_flags(req)))

  when "next_holidays"
    count = Integer(req.fetch("count"))
    opts  = regions_arg(req) + option_flags(req)
    if req["from"]
      normalize_holidays(Holidays.next_holidays(count, opts, parse_date(req["from"])))
    else
      normalize_holidays(Holidays.next_holidays(count, opts))
    end

  when "year_holidays"
    opts = regions_arg(req) + option_flags(req)
    if req["from"]
      normalize_holidays(Holidays.year_holidays(opts, parse_date(req["from"])))
    else
      normalize_holidays(Holidays.year_holidays(opts))
    end

  when "year_holidays_range"
    region = req.fetch("region")
    from_year = Integer(req.fetch("from_year"))
    to_year = Integer(req.fetch("to_year"))
    combos = Array(req["flag_combos"])
    combos = [{ "informal" => false, "observed" => false }] if combos.empty?
    entries = []
    combos.each do |combo|
      bi = combo["informal"] ? true : false
      bo = combo["observed"] ? true : false
      opts = [region.to_sym]
      opts << :informal if bi
      opts << :observed if bo
      entries.concat(year_holidays_range_for_combo(region, from_year, to_year, bi, bo, opts))
    end
    entries

  when "any_holidays_during_work_week?"
    date = parse_date(req.fetch("date"))
    Holidays.any_holidays_during_work_week?(date, *regions_arg(req), *option_flags(req))

  when "available_regions"
    AVAILABLE_REGIONS.dup

  when "load_custom"
    files = Array(req.fetch("files"))
    files.each { |f| Holidays.load_custom(f) }
    { "loaded" => files.size }

  else
    raise ArgumentError, "unknown func: #{req["func"].inspect}"
  end
end

# ---- main loop ---------------------------------------------------------------

def main
  $stdout.sync = true
  load_all_definitions

  $stdin.each_line do |line|
    line = line.strip
    next if line.empty?

    req = nil
    begin
      req = JSON.parse(line)
      result = dispatch(req)
      puts JSON.generate("ok" => true, "id" => req["id"],
                         "func" => req["func"], "result" => result)
    rescue StandardError => e
      id   = req.is_a?(Hash) ? req["id"]   : nil
      func = req.is_a?(Hash) ? req["func"] : nil
      puts JSON.generate("ok" => false, "id" => id, "func" => func,
                         "error" => "#{e.class}: #{e.message}")
    end
  end
end

main if $PROGRAM_NAME == __FILE__
