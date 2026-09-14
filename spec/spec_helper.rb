# frozen_string_literal: true

require "neu-mods"

FIXTURE_DIR = File.expand_path("fixtures", __dir__)

def fixture(name)
  File.read(File.join(FIXTURE_DIR, name))
end

# Every displayed projection now carries the @displayLabel and xlink:href of
# the element a header comes from. A spec about what an entry holds BESIDE that
# pair reads better without two nil keys repeated on every line, so it drops
# them; the pair has its own expectations in uat_display_spec.rb.
def without_qualifiers(value)
  case value
  when Array then value.map { |member| without_qualifiers(member) }
  when Hash  then value.except(:display_label, :href)
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
