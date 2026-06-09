# frozen_string_literal: true

require_relative "lib/neu/mods/version"

Gem::Specification.new do |spec|
  spec.name = "neu-mods"
  spec.version = NEU::MODS::VERSION
  spec.authors = ["David Cliff"]
  spec.email = ["d.cliff@northeastern.edu"]

  spec.summary = "Northeastern-flavored MODS XML projection + selection for the DRS."
  spec.description = "Nokogiri-native, dependency-light reading/projection contract over MODS v3 " \
                     "documents, shared by the DRS front end (Cerberus) and API backend (Atlas). " \
                     "Pure functions over a document: selectors that locate nodes (for editing) and " \
                     "projections that return plain data (for indexing/display). No Rails, no persistence, no HTTP."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:test|spec|features)/|\.(?:git|github|rspec|rubocop))})
    end
  end
  spec.require_paths = ["lib"]

  # The whole point: depend on Nokogiri alone (floor only, no upper cap — never
  # block a security upgrade). NOT the sul-dlss `mods`/`nom-xml` stack.
  spec.add_dependency "nokogiri", ">= 1.13"

  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rubocop", "~> 1.60"

  spec.metadata["rubygems_mfa_required"] = "false"
end
