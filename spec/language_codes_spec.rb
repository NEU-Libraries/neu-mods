# frozen_string_literal: true

RSpec.describe NEU::MODS::LanguageCodes do
  def doc_with_language(term)
    NEU::MODS::Document.parse(<<~XML)
      <?xml version="1.0" encoding="UTF-8"?>
      <mods:mods xmlns:mods="http://www.loc.gov/mods/v3">
        <mods:titleInfo usage="primary"><mods:title>Bare</mods:title></mods:titleInfo>
        <mods:language>#{term}</mods:language>
      </mods:mods>
    XML
  end

  describe ".term" do
    it "translates a bibliographic alpha-3 code, which is what MODS declares most" do
      expect(described_class.term("eng")).to eq("English")
    end

    it "translates the terminologic alpha-3 code as well as the bibliographic one" do
      aggregate_failures do
        expect(described_class.term("ger")).to eq("German")
        expect(described_class.term("deu")).to eq("German")
      end
    end

    it "translates an alpha-2 code, since iso639-1 is a valid authority too" do
      expect(described_class.term("fr")).to eq("French")
    end

    it "takes the first synonym, so a facet value stays clickable" do
      aggregate_failures do
        expect(described_class.term("spa")).to eq("Spanish")
        expect(described_class.term("dut")).to eq("Dutch")
      end
    end

    it "folds case, because a record is not obliged to lowercase its code" do
      expect(described_class.term("ENG")).to eq("English")
    end

    # Losing an unrecognised value would be worse than showing a code: the
    # record still said something, and nothing downstream could recover it.
    it "returns an unrecognised code unchanged" do
      expect(described_class.term("zzz")).to eq("zzz")
    end

    it "returns an empty string for a blank code rather than raising" do
      aggregate_failures do
        expect(described_class.term("")).to eq("")
        expect(described_class.term(nil)).to eq("")
      end
    end
  end

  describe "the vendored registry" do
    it "covers every code form the registry defines" do
      expect(described_class::TERMS.size).to be > 600
    end

    it "is frozen, since it is read on every projection" do
      expect(described_class::TERMS).to be_frozen
    end
  end

  describe "the projection" do
    it "prefers an authored text term over the code" do
      term = <<~XML
        <mods:languageTerm type="code">eng</mods:languageTerm>
        <mods:languageTerm type="text">English (US)</mods:languageTerm>
      XML
      expect(doc_with_language(term).languages).to eq(["English (US)"])
    end

    it "translates a code-only term" do
      term = %(<mods:languageTerm type="code" authority="iso639-2b">eng</mods:languageTerm>)
      expect(doc_with_language(term).languages).to eq(["English"])
    end

    it "translates a languageTerm carrying no @type at all" do
      expect(doc_with_language("<mods:languageTerm>fre</mods:languageTerm>").languages).to eq(["French"])
    end

    it "drops a language element with no term" do
      expect(doc_with_language("").languages).to eq([])
    end
  end
end
