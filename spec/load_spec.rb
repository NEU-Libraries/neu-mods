# frozen_string_literal: true

require "open3"
require "rbconfig"

# Each file under lib/neu/mods requires what it uses, so a caller can load one
# without the top-level entry file. Run in a fresh process, because this one
# already loaded everything through spec_helper.
RSpec.describe "loading one file on its own" do
  lib = File.expand_path("../lib", __dir__)

  def run_ruby(lib, script)
    Open3.capture2e(RbConfig.ruby, "-I", lib, "-e", script)
  end

  Dir[File.join(lib, "neu/mods/**/*.rb")].each do |path|
    feature = path.delete_prefix("#{lib}/").delete_suffix(".rb")

    it "loads #{feature}" do
      output, status = run_ruby(lib, "require #{feature.inspect}")
      expect(status).to be_success, output
    end
  end

  it "projects and builds through neu/mods/document alone" do
    script = <<~RUBY
      require "neu/mods/document"
      doc = NEU::MODS::Document.parse(File.read(#{File.join(FIXTURE_DIR, "coverage-mods.xml").inspect}))
      doc.to_h
      doc.doc.root.add_child(doc.build_corporate_name(name: "Acme"))
    RUBY
    output, status = run_ruby(lib, script)
    expect(status).to be_success, output
  end
end
