# frozen_string_literal: true

require "open3"
require "rbconfig"

# Each file under lib/neu/mods requires what it uses, so a caller can load one
# without the top-level entry file. Run in a fresh process, because this one
# already loaded everything through spec_helper.
RSpec.describe "loading one file on its own" do
  def lib_dir = File.expand_path("../lib", __dir__)

  def run_ruby(script)
    Open3.capture2e(RbConfig.ruby, "-I", lib_dir, "-e", script)
  end

  lib = File.expand_path("../lib", __dir__)
  Dir[File.join(lib, "neu/mods/**/*.rb")].map { |path| path.delete_prefix("#{lib}/").delete_suffix(".rb") }
                                         .each do |feature|
    it "loads #{feature}" do
      output, status = run_ruby("require #{feature.inspect}")
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
    output, status = run_ruby(script)
    expect(status).to be_success, output
  end

  # Selectors used to call a private Projection method, and Projection a
  # private Selectors one, so neither worked without the other.
  it "selects editable creators through Selectors without Projection" do
    script = <<~RUBY
      require "neu/mods/selectors"
      holder = Struct.new(:doc) { include NEU::MODS::Selectors }
      xml = <<~XML
        <mods:mods xmlns:mods="http://www.loc.gov/mods/v3"><mods:name type="corporate">
          <mods:namePart>Acme</mods:namePart><mods:role><mods:roleTerm type="text">Creator</mods:roleTerm></mods:role>
        </mods:name></mods:mods>
      XML
      exit(holder.new(Nokogiri::XML(xml)).editable_creator_nodes("corporate").size == 1)
    RUBY
    output, status = run_ruby(script)
    expect(status).to be_success, output
  end
end
