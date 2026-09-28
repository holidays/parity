#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby/verify_between_equiv.rb
#
# MANUAL one-off equivalence check. NOT run by CI, NOT part of `make test` or
# `make parity`. Nothing invokes this file automatically.
#
# It asserts that the fast path in oracle.rb's year_holidays_range handler
# (year_holidays_range_for_combo: ONE full-span Holidays.between bucketed by
# Date#year) produces row-for-row identical cells to the old per-year
# Holidays.year_holidays(Jan 1 Y) loop, for every region in AVAILABLE_REGIONS
# and all four flag combos across 1970-2050.
#
# Run once when touching that handler:
#   ruby ruby/verify_between_equiv.rb
# Needs Ruby + the pinned holidays gem + a populated definitions/ submodule.
# Exits 0 on full equivalence, 1 on any mismatch.

require_relative "oracle"

FROM_YEAR = 1970
TO_YEAR = 2050
COMBOS = [
  [false, false],
  [true,  false],
  [false, true],
  [true,  true],
].freeze

# The pre-batching reference: one year_holidays call per year, same shape the
# oracle used to emit.
def per_year_reference(informal, observed, opts)
  (FROM_YEAR..TO_YEAR).map do |y|
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

load_all_definitions
regions = AVAILABLE_REGIONS.dup
year_span = TO_YEAR - FROM_YEAR + 1
puts "verify_between_equiv: #{regions.size} regions x #{COMBOS.size} combos x #{year_span} years"

mismatch_count = 0

regions.each do |region|
  COMBOS.each do |(informal, observed)|
    opts = [region.to_sym]
    opts << :informal if informal
    opts << :observed if observed

    fast = year_holidays_range_for_combo(region, FROM_YEAR, TO_YEAR, informal, observed, opts)
    ref  = per_year_reference(informal, observed, opts)

    next if fast == ref

    mismatch_count += 1
    fast.zip(ref).each do |f, r|
      next if f == r

      puts "MISMATCH region=#{region} informal=#{informal} observed=#{observed} year=#{f['year']}"
      puts "  fast: #{f.inspect}"
      puts "  ref : #{r.inspect}"
      break
    end
  end
  $stdout.write(".")
  $stdout.flush
end
puts

if mismatch_count.zero?
  puts "OK: bucketed full-span between == per-year year_holidays for every region/combo/year"
  exit 0
end

puts "FAIL: #{mismatch_count} region/combo mismatch(es)"
exit 1
