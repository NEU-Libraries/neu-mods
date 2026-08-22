# frozen_string_literal: true

RSpec.describe NEU::MODS::Document do
  let(:doc) { described_class.parse(fixture("work-mods.xml")) }

  describe "selectors locate the right nodes" do
    it "scopes primary_title_info to the top-level primary (not the relatedItem)" do
      ti = doc.primary_title_info
      expect(ti["usage"]).to eq("primary")
      expect(ti.at_xpath("mods:title", NEU::MODS::NAMESPACE).text).to eq("What's New")
    end

    it "treats authority-bearing and name subjects as non-keyword (curated)" do
      # All subjects in the fixture carry authority or are name-subjects.
      expect(doc.keyword_subjects).to be_empty
    end

    it "builds nodes reusing the existing mods namespace (no re-declared xmlns)" do
      node = doc.build_node("topic", "Hello")
      expect(node.name).to eq("topic")
      expect(node.namespace.href).to eq("http://www.loc.gov/mods/v3")
      expect(node.to_xml).not_to include("xmlns")
    end
  end

  # The access copy is cleaned; the editable parts are not. Both halves matter:
  # Cerberus pre-fills its Metadata and Advanced forms from #title_parts and
  # MODSMerge writes the posted value back into the preservation XML, so
  # normalising there would rewrite the curator's characters on the next save.
  describe "normalisation boundary between the access copy and the edit forms" do
    # Built from codepoints so this spec file stays ASCII, like lib/.
    def cp(*codepoints) = codepoints.pack("U*")

    def doc_with_title(title)
      described_class.parse(<<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <mods:mods xmlns:mods="http://www.loc.gov/mods/v3">
          <mods:titleInfo usage="primary">
            <mods:title>#{title}</mods:title>
          </mods:titleInfo>
        </mods:mods>
      XML
    end

    # A curly quote pair, a thin space, a bidi override and a Windows-1252 C1
    # control -- what a paste out of Word actually carries.
    let(:messy) do
      "The #{cp(0x201C)}Boston#{cp(0x201D)}#{cp(0x2009)}Harbor#{cp(0x202E)}#{cp(0x0092)} Project"
    end

    it "cleans the title Atlas projects into JSON and Solr" do
      expect(doc_with_title(messy).to_h[:main_title][:title])
        .to eq('The "Boston" Harbor Project')
    end

    it "leaves the title the edit forms pre-fill from byte-faithful" do
      expect(doc_with_title(messy).title_parts[:title]).to eq(messy)
    end
  end

  describe "the write-path contract (selectors return live, mutable nodes)" do
    # Reproduces how Cerberus's MODSMerge edits in place: locate the primary
    # title via the gem, mutate it, serialize — and prove curated structure
    # (partName/partNumber) and the nested relatedItem title survive.
    it "edits the primary title without touching siblings or the series title" do
      title_node = doc.primary_title_info.at_xpath("mods:title", NEU::MODS::NAMESPACE)
      title_node.content = "Brand New Title"
      xml = doc.to_xml

      reparsed = described_class.parse(xml)
      expect(reparsed.primary_title_info.at_xpath("mods:title", NEU::MODS::NAMESPACE).text)
        .to eq("Brand New Title")
      expect(reparsed.title_parts[:part_name]).to eq("How We Respond to Disaster")
      expect(reparsed.title_parts[:part_number]).to eq("Episode 1")
      # the nested series title is untouched
      expect(reparsed.related_series).to eq(["What's New Podcast"])
    end
  end

  describe "edge cases on a minimal document" do
    let(:minimal) do
      described_class.parse(<<~XML)
        <?xml version="1.0"?>
        <mods:mods xmlns:mods="http://www.loc.gov/mods/v3">
          <mods:titleInfo usage="primary"><mods:title>Bare</mods:title></mods:titleInfo>
        </mods:mods>
      XML
    end

    it "returns sensible empties for absent fields" do
      aggregate_failures do
        expect(minimal.plain_title).to eq("Bare")
        expect(minimal.abstract).to eq("")
        expect(minimal.resource_type).to eq("") # scalar absent -> "" (Atlas parity)
        expect(minimal.permanent_url).to be_nil # node absent -> nil (Atlas parity)
        expect(minimal.date_created).to be_nil
        expect(minimal.names).to eq([])
        expect(minimal.topical_subjects).to eq([])
      end
    end
  end
end
