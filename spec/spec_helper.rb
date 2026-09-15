# frozen_string_literal: true

require "neu-mods"

FIXTURE_DIR = File.expand_path("fixtures", __dir__)

def fixture(name)
  File.read(File.join(FIXTURE_DIR, name))
end

# The attributes a display reads off an element rather than out of its text:
# the header (@displayLabel), the link (xlink:href), the vocabulary the value
# was taken from, and, on a name, @usage and its alternative names. A spec
# about what an entry holds BESIDE them reads better without those keys
# repeated on every line, so it drops them; each has its own expectations in
# display_attributes_spec.rb.
DISPLAY_ATTRIBUTES = %i[display_label href usage alternative_names
                        authority authority_uri value_uri].freeze

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

# The parts of each assembled subject heading, for a spec about how a heading
# composes rather than about the joined string or the axis it reports.
def parts_of(headings)
  headings.map { |heading| heading[:parts] }
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
