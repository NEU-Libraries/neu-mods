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

    # A record template that seeds an empty element for an edit form to fill is
    # normal -- Atlas's MODSBuilder writes an empty <topic> and an empty hdl
    # <identifier> into every new Work -- so a blank member is the common case,
    # not an edge one.
    it "drops a blank member from every string array, not just the widened ones" do
      seeded = doc_with(<<~XML)
        <mods:subject><mods:topic></mods:topic></mods:subject>
        <mods:subject><mods:topic>Interpreting</mods:topic></mods:subject>
        <mods:genre></mods:genre>
        <mods:identifier type="hdl" displayLabel="Permanent URL"></mods:identifier>
      XML

      aggregate_failures do
        expect(seeded.topical_subjects).to eq(["Interpreting"])
        expect(seeded.genres).to eq([])
        expect(seeded.identifiers).to eq([])
        expect(seeded.permanent_url).to be_nil
      end
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

  # Every row below was declared on Atlas's Metadata::MODS and projected by
  # nothing, so it was permanently nil downstream. Asserted per field rather
  # than on #to_h wholesale, so a failure names the element that regressed.
  describe "the fields that had no projection" do
    it "projects the originInfo elements Cerberus's IPTC ingest already writes" do
      aggregate_failures do
        expect(doc.publication_information).to eq(["Northeastern University Press"])
        expect(doc.geographic_subjects).to eq(["Boston (Mass.)"])
      end
    end

    it "projects the other two originInfo dates with their granularity" do
      aggregate_failures do
        expect(doc.date_issued).to eq(DateTime.new(2025, 6, 1))
        expect(doc.date_issued_precision).to eq("day")
        expect(doc.copyright_date).to eq(DateTime.new(2025, 1, 1))
        expect(doc.copyright_date_precision).to eq("year")
      end
    end

    it "projects the edition" do
      expect(doc.edition).to eq(["2nd ed."])
    end

    it "keeps each note's @type, which changes what the note means" do
      expect(doc.notes).to eq([
                                { type: "statement of responsibility", value: "Prepared by the Working Group." },
                                { type: nil, value: "A general note." }
                              ])
    end

    it "projects the remaining subject axes" do
      aggregate_failures do
        expect(doc.temporal_subjects).to eq(["21st century"])
        expect(doc.personal_name_subjects).to eq(["Smith, John"])
        expect(doc.corporate_name_subjects).to eq([])
      end
    end

    it "composes a name subject through the same display port as #names" do
      subject_doc = doc_with(<<~XML)
        <mods:subject><mods:name type="corporate"><mods:namePart>Acme Corp</mods:namePart></mods:name></mods:subject>
        <mods:subject>
          <mods:name type="personal">
            <mods:namePart type="family">Bell</mods:namePart>
            <mods:namePart type="given">Jen</mods:namePart>
            <mods:namePart type="date">1920-1990</mods:namePart>
          </mods:name>
        </mods:subject>
      XML
      aggregate_failures do
        expect(subject_doc.corporate_name_subjects).to eq(["Acme Corp"])
        expect(subject_doc.personal_name_subjects).to eq(["Bell, Jen, 1920-1990"])
      end
    end

    it "projects the host collection alongside the series" do
      aggregate_failures do
        expect(doc.host_collections).to eq(["A Host Collection"])
        expect(doc.related_series).to eq(["A Series"])
      end
    end

    it "catches every other relatedItem type, keeping the relationship" do
      expect(doc.related_items).to eq([{ type: "otherFormat", title: "The Print Edition" }])
    end

    it "does not repeat a relatedItem that already has a field of its own" do
      expect(doc.related_items.map { |item| item[:type] }).not_to include("host", "series")
    end

    it "catches an untyped relatedItem, which no other field would carry" do
      untyped = doc_with(<<~XML)
        <mods:relatedItem><mods:titleInfo><mods:title>Something Related</mods:title></mods:titleInfo></mods:relatedItem>
      XML
      expect(untyped.related_items).to eq([{ type: nil, title: "Something Related" }])
    end

    it "skips a relatedItem with no title, which projects nothing useful" do
      titleless = doc_with(%(<mods:relatedItem type="original"><mods:note>See the file.</mods:note></mods:relatedItem>))
      expect(titleless.related_items).to eq([])
    end

    it "keeps a location's parts apart, so a URL is distinguishable from a shelf" do
      located = doc_with(<<~XML)
        <mods:location>
          <mods:physicalLocation>Snell Library</mods:physicalLocation>
          <mods:shelfLocation>PS3552 .E1</mods:shelfLocation>
          <mods:url>https://example.org/item</mods:url>
        </mods:location>
      XML
      expect(located.location).to eq([{ physical_location: "Snell Library",
                                        shelf_location: "PS3552 .E1",
                                        url: "https://example.org/item" }])
    end

    it "keeps cartographics structured rather than composing a sentence" do
      mapped = doc_with(<<~XML)
        <mods:subject>
          <mods:cartographics>
            <mods:scale>1:24,000</mods:scale>
            <mods:projection>Universal Transverse Mercator</mods:projection>
            <mods:coordinates>W 71 03 00 N 42 21 00</mods:coordinates>
          </mods:cartographics>
        </mods:subject>
      XML
      expect(mapped.map_data).to eq([{ scale: "1:24,000",
                                       projection: "Universal Transverse Mercator",
                                       coordinates: "W 71 03 00 N 42 21 00" }])
    end

    it "projects each title variant under its own field" do
      variants = doc_with(<<~XML)
        <mods:titleInfo type="alternative"><mods:title>An Alternative Title</mods:title></mods:titleInfo>
        <mods:titleInfo type="uniform"><mods:title>A Uniform Title</mods:title></mods:titleInfo>
        <mods:titleInfo type="translated"><mods:title>A Translated Title</mods:title></mods:titleInfo>
        <mods:titleInfo type="abbreviated"><mods:title>An Abbrev. Title</mods:title></mods:titleInfo>
      XML
      aggregate_failures do
        expect(variants.alternative_title).to eq(["An Alternative Title"])
        expect(variants.uniform_title).to eq(["A Uniform Title"])
        expect(variants.translated_title).to eq(["A Translated Title"])
        expect(variants.abbreviated_title).to eq(["An Abbrev. Title"])
        expect(variants.plain_title).to eq("Bare")
      end
    end

    it "composes and normalises a variant title the way it does the main one" do
      variant = doc_with(<<~XML)
        <mods:titleInfo type="alternative">
          <mods:nonSort>The</mods:nonSort>
          <mods:title>Real Thing</mods:title>
          <mods:subTitle>A Study</mods:subTitle>
        </mods:titleInfo>
      XML
      expect(variant.alternative_title).to eq(["The Real Thing: A Study"])
    end

    it "harvests every titleInfo of a type, since MODS repeats the element" do
      two = doc_with(<<~XML)
        <mods:titleInfo type="alternative"><mods:title>First Alternative</mods:title></mods:titleInfo>
        <mods:titleInfo type="alternative"><mods:title>Second Alternative</mods:title></mods:titleInfo>
      XML
      expect(two.alternative_title).to eq(["First Alternative", "Second Alternative"])
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
