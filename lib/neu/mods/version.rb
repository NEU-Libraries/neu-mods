# frozen_string_literal: true

module NEU
  module MODS
    # Current gem version, read from the `.version` file at the repo root at load
    # time (mirrors the atlas_rb convention so a single `.version` bump drives the
    # gem version + `bundler/gem_tasks` release).
    VERSION = File.read(File.expand_path("../../../.version", __dir__)).strip
  end
end
