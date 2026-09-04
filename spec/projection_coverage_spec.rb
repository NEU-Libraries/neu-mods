# frozen_string_literal: true

# Coverage: what a schema-valid MODS record carries versus what the projection
# reports. Asserted per projection rather than on #to_h wholesale, so a failure
# names the element that regressed.
RSpec.describe "projection coverage" do
  let(:doc) { NEU::MODS::Document.parse(fixture("coverage-mods.xml")) }

  # A minimal record carrying a primary title plus whatever the example needs.
  def doc_with(body)
    NEU::MODS::Document.parse(<<~XML)
      <?xml version="1.0" encoding="UTF-8"?>
      <mods:mods xmlns:mods="http://www.loc.gov/mods/v3">
        <mods:titleInfo usage="primary"><mods:title>Bare</mods:title></mods:titleInfo>
        #{body}
      </mods:mods>
    XML
  end

  # The same, with no title of its own -- the title examples supply their own.
  def untitled_doc_with(body)
    NEU::MODS::Document.parse(<<~XML)
      <?xml version="1.0" encoding="UTF-8"?>
      <mods:mods xmlns:mods="http://www.loc.gov/mods/v3">
        #{body}
      </mods:mods>
    XML
  end

  describe "repeatable elements are harvested, not truncated to the first" do
    it "keeps every typeOfResource" do
      expect(doc.resource_type).to eq(["text", "still image"])
    end

    it "harvests across repeated physicalDescription elements" do
      repeated = doc_with(<<~XML)
        <mods:physicalDescription>
          <mods:form>electronic</mods:form>
          <mods:extent>24 pages</mods:extent>
          <mods:digitalOrigin>born digital</mods:digitalOrigin>
        </mods:physicalDescription>
        <mods:physicalDescription>
          <mods:form>print</mods:form>
          <mods:extent>1 box</mods:extent>
          <mods:digitalOrigin>reformatted digital</mods:digitalOrigin>
        </mods:physicalDescription>
      XML

      aggregate_failures do
        expect(repeated.format).to eq(%w[electronic print])
        expect(repeated.extent).to eq(["24 pages", "1 box"])
        expect(repeated.digital_origin).to eq(["born digital", "reformatted digital"])
      end
    end

    it "drops a blank member rather than projecting nil into the array" do
      expect(doc_with("<mods:typeOfResource>text</mods:typeOfResource><mods:typeOfResource> </mods:typeOfResource>")
               .resource_type).to eq(["text"])
    end
  end

  # MODS does not require usage="primary", so the fallback fires often. It also
  # picks the node MODSMerge writes to, which is why a variant must never reach
  # it: overwriting an alternative title destroys it in the preservation XML.
  describe "the primary-title fallback skips the variants" do
    def titled(*title_infos) = untitled_doc_with(title_infos.join("\n"))

    def title_info(attrs, title) = %(<mods:titleInfo #{attrs}><mods:title>#{title}</mods:title></mods:titleInfo>)

    let(:alternative) { title_info(%(type="alternative"), "An Alternative Title") }
    let(:untyped) { title_info("", "The Real Title") }
    let(:primary) { title_info(%(usage="primary"), "The Primary Title") }

    it "prefers usage=primary over everything, wherever it sits" do
      expect(titled(alternative, untyped, primary).plain_title).to eq("The Primary Title")
    end

    it "takes the untyped title even when a variant comes first in document order" do
      aggregate_failures do
        expect(titled(alternative, untyped).plain_title).to eq("The Real Title")
        expect(titled(untyped, alternative).plain_title).to eq("The Real Title")
      end
    end

    it "returns nothing when every title is a variant" do
      aggregate_failures do
        expect(titled(alternative).primary_title_info).to be_nil
        expect(titled(alternative).plain_title).to eq("")
      end
    end

    it "treats any @type as a variant, since MODS enumerates only variants there" do
      %w[abbreviated translated uniform alternative unrecognised].each do |type|
        variant = title_info(%(type="#{type}"), "X")
        expect(titled(variant).primary_title_info).to be_nil, "@type=#{type} reached the fallback"
      end
    end

    it "keeps the fallback scoped to top-level titleInfo, not a relatedItem's" do
      nested = doc_with(<<~XML)
        <mods:relatedItem type="series"><mods:titleInfo><mods:title>A Series</mods:title></mods:titleInfo></mods:relatedItem>
      XML
      expect(nested.plain_title).to eq("Bare")
    end
  end

  describe "accessCondition is projected per @type" do
    it "keeps a restriction and a licence apart" do
      aggregate_failures do
        expect(doc.restriction_on_access).to eq("Northeastern University only.")
        expect(doc.use_and_reproduction).to eq("CC BY 4.0")
      end
    end

    it "still projects the combined value, which alone carries an untyped one" do
      aggregate_failures do
        expect(doc.access_condition).to eq("Northeastern University only.\n\nCC BY 4.0")
        untyped = doc_with("<mods:accessCondition>No known restrictions.</mods:accessCondition>")
        expect(untyped.access_condition).to eq("No known restrictions.")
        expect(untyped.use_and_reproduction).to eq("")
        expect(untyped.restriction_on_access).to eq("")
      end
    end

    it "matches the @type case-insensitively, as the schema leaves it open" do
      expect(doc_with(%(<mods:accessCondition type="Use And Reproduction">CC BY 4.0</mods:accessCondition>))
               .use_and_reproduction).to eq("CC BY 4.0")
    end

    it "joins several conditions of one type as paragraphs" do
      several = doc_with(<<~XML)
        <mods:accessCondition type="use and reproduction">CC BY 4.0</mods:accessCondition>
        <mods:accessCondition type="use and reproduction">Attribution required.</mods:accessCondition>
      XML
      expect(several.use_and_reproduction).to eq("CC BY 4.0\n\nAttribution required.")
    end
  end
end
