# frozen_string_literal: true

require "neu-mods"

FIXTURE_DIR = File.expand_path("fixtures", __dir__)

def fixture(name)
  File.read(File.join(FIXTURE_DIR, name))
end

# The attributes a display reads off an element rather than out of its text:
# the header (@displayLabel), the link (xlink:href), and on a name the two the
# 2026-09-14 UAT round added. A spec about what an entry holds BESIDE them
# reads better without those keys repeated on every line, so it drops them;
# each has its own expectations in uat_display_spec.rb.
DISPLAY_ATTRIBUTES = %i[display_label href usage alternative_names].freeze

def without_display_attributes(value)
  case value
  when Array then value.map { |member| without_display_attributes(member) }
  when Hash  then value.except(*DISPLAY_ATTRIBUTES)
  else value
  end
end

# The values of a labeled projection, for a spec about what was harvested
# rather than about how it is headed.
def values_of(list)
  list.map { |entry| entry[:value] }
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
