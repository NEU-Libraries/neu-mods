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

    # The fixture carries a ranged, approximate dateCreated and nominates
    # dateIssued as its key date, so a consumer of this record can be checked
    # against all three attributes without inventing a document.
    it "projects the range, the qualifier and the key date the record declares" do
      aggregate_failures do
        expect(doc.date_created).to eq(DateTime.new(1935, 6, 1))
        expect(doc.date_created_precision).to eq("month")
        expect(doc.date_created_end).to eq(DateTime.new(1940, 1, 1))
        expect(doc.date_created_end_precision).to eq("year")
        expect(doc.date_created_qualifier).to eq("approximate")
        expect(doc.date_created_key_date).to be false
        expect(doc.date_issued_key_date).to be true
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

    it "keeps a note about the object apart from a note about the work" do
      scanned = doc_with(<<~XML)
        <mods:note>A general note.</mods:note>
        <mods:physicalDescription>
          <mods:extent>24 pages</mods:extent>
          <mods:note>Scanned at 600 dpi.</mods:note>
        </mods:physicalDescription>
      XML
      aggregate_failures do
        expect(scanned.physical_description_notes).to eq(["Scanned at 600 dpi."])
        expect(scanned.notes).to eq([{ type: nil, value: "A general note." }])
      end
    end

    describe "the assembled subject heading" do
      it "keeps one pre-coordinated heading together, in document order" do
        lcsh = doc_with(<<~XML)
          <mods:subject authority="lcsh">
            <mods:topic>Salt marshes</mods:topic>
            <mods:geographic>Massachusetts</mods:geographic>
            <mods:temporal>20th century</mods:temporal>
          </mods:subject>
          <mods:subject authority="lcsh"><mods:topic>Coastal ecology</mods:topic></mods:subject>
        XML
        expect(lcsh.subject_headings).to eq([
                                              { parts: ["Salt marshes", "Massachusetts", "20th century"] },
                                              { parts: ["Coastal ecology"] }
                                            ])
      end

      it "reads a heading typed flat into one element as the same parts" do
        flat = doc_with(<<~XML)
          <mods:subject><mods:topic>Salt marshes--Massachusetts--20th century</mods:topic></mods:subject>
        XML
        expect(flat.subject_headings).to eq([{ parts: ["Salt marshes", "Massachusetts", "20th century"] }])
      end

      it "composes a name and a title part through their own display ports" do
        composed = doc_with(<<~XML)
          <mods:subject>
            <mods:name type="personal">
              <mods:namePart type="family">Bell</mods:namePart>
              <mods:namePart type="given">Jen</mods:namePart>
            </mods:name>
            <mods:topic>Correspondence</mods:topic>
          </mods:subject>
          <mods:subject>
            <mods:titleInfo><mods:nonSort>The</mods:nonSort><mods:title>Real Thing</mods:title></mods:titleInfo>
          </mods:subject>
        XML
        expect(composed.subject_headings).to eq([
                                                  { parts: ["Bell, Jen", "Correspondence"] },
                                                  { parts: ["The Real Thing"] }
                                                ])
      end

      it "makes each hierarchical level a step of the heading" do
        place = doc_with(<<~XML)
          <mods:subject>
            <mods:hierarchicalGeographic>
              <mods:country>United States</mods:country>
              <mods:state>New York</mods:state>
              <mods:city>Parksville</mods:city>
            </mods:hierarchicalGeographic>
          </mods:subject>
        XML
        expect(place.subject_headings).to eq([{ parts: ["United States", "New York", "Parksville"] }])
      end

      it "omits the two children that carry no heading text" do
        omitted = doc_with(<<~XML)
          <mods:subject>
            <mods:topic>Boston</mods:topic>
            <mods:geographicCode authority="marcgac">n-us-ma</mods:geographicCode>
            <mods:cartographics><mods:coordinates>42.36,-71.06</mods:coordinates></mods:cartographics>
          </mods:subject>
        XML
        expect(omitted.subject_headings).to eq([{ parts: ["Boston"] }])
      end

      it "drops a subject whose children are all blank or omitted" do
        empty = doc_with(<<~XML)
          <mods:subject><mods:topic></mods:topic></mods:subject>
          <mods:subject><mods:geographicCode>n-us-ma</mods:geographicCode></mods:subject>
        XML
        expect(empty.subject_headings).to eq([])
      end

      it "leaves the per-axis fields alone, since the facets read them" do
        lcsh = doc_with(<<~XML)
          <mods:subject>
            <mods:topic>Salt marshes</mods:topic>
            <mods:geographic>Massachusetts</mods:geographic>
          </mods:subject>
        XML
        aggregate_failures do
          expect(lcsh.topical_subjects).to eq(["Salt marshes"])
          expect(lcsh.geographic_subjects).to eq(["Massachusetts"])
        end
      end
    end

    it "projects subject/occupation, the last member of the subject set" do
      occupations = doc_with(<<~XML)
        <mods:subject><mods:occupation>Cabinetmakers</mods:occupation></mods:subject>
        <mods:subject><mods:occupation>Shipwrights</mods:occupation></mods:subject>
      XML
      expect(occupations.occupation_subjects).to eq(%w[Cabinetmakers Shipwrights])
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
        expect(doc.host_collections).to eq([{ title: "A Host Collection" }])
        expect(doc.related_series).to eq(["A Series"])
      end
    end

    it "carries this work's position in its host, which no other record holds" do
      article = doc_with(<<~XML)
        <mods:relatedItem type="host">
          <mods:titleInfo><mods:title>Estuaries</mods:title></mods:titleInfo>
          <mods:part>
            <mods:detail type="volume"><mods:number>24</mods:number></mods:detail>
            <mods:detail type="issue"><mods:number>3</mods:number></mods:detail>
            <mods:extent unit="page"><mods:start>210</mods:start><mods:end>218</mods:end></mods:extent>
          </mods:part>
        </mods:relatedItem>
      XML
      expect(article.host_collections).to eq([{ title: "Estuaries", volume: "24", issue: "3",
                                                start_page: "210", end_page: "218" }])
    end

    it "reads a page extent that omits @unit, which MODS leaves optional" do
      unitless = doc_with(<<~XML)
        <mods:relatedItem type="host">
          <mods:titleInfo><mods:title>Estuaries</mods:title></mods:titleInfo>
          <mods:part><mods:extent><mods:start>210</mods:start></mods:extent></mods:part>
        </mods:relatedItem>
      XML
      expect(unitless.host_collections).to eq([{ title: "Estuaries", start_page: "210" }])
    end

    it "omits the part members a record does not carry rather than nilling them" do
      volume_only = doc_with(<<~XML)
        <mods:relatedItem type="host">
          <mods:titleInfo><mods:title>Estuaries</mods:title></mods:titleInfo>
          <mods:part><mods:detail type="volume"><mods:number>24</mods:number></mods:detail></mods:part>
        </mods:relatedItem>
      XML
      expect(volume_only.host_collections).to eq([{ title: "Estuaries", volume: "24" }])
    end

    # A host block carrying volume, issue and pages but no titleInfo used to
    # project nothing, discarding the one piece of it that describes this work
    # along with the metadata that belongs to the other record.
    it "keeps a host that carries a part and no title" do
      titleless = doc_with(<<~XML)
        <mods:relatedItem type="host">
          <mods:part>
            <mods:detail type="issue"><mods:number>3</mods:number></mods:detail>
          </mods:part>
        </mods:relatedItem>
      XML
      expect(titleless.host_collections).to eq([{ title: nil, issue: "3" }])
    end

    it "drops a host that carries neither a title nor a part" do
      empty = doc_with('<mods:relatedItem type="host"><mods:note>Nothing</mods:note></mods:relatedItem>')
      expect(empty.host_collections).to eq([])
    end

    # part/date is the article's year within the host -- after the title, the
    # element a reader most needs to find the article offline.
    it "reads the part's date and text, which reached no consumer before" do
      dated = doc_with(<<~XML)
        <mods:relatedItem type="host">
          <mods:titleInfo><mods:title>Estuaries</mods:title></mods:titleInfo>
          <mods:part>
            <mods:date>1998</mods:date>
            <mods:text>Special issue</mods:text>
          </mods:part>
        </mods:relatedItem>
      XML
      expect(dated.host_collections)
        .to eq([{ title: "Estuaries", date: "1998", text: "Special issue" }])
    end

    # detail/@type is an open xs:string, so a named key per type cannot cover
    # the vocabulary. The caption travels because it is the label a cataloguer
    # wrote for the number.
    it "keeps every detail type beyond volume and issue, with its caption" do
      chaptered = doc_with(<<~XML)
        <mods:relatedItem type="host">
          <mods:titleInfo><mods:title>Salt Marshes</mods:title></mods:titleInfo>
          <mods:part>
            <mods:detail type="volume"><mods:number>2</mods:number></mods:detail>
            <mods:detail type="chapter">
              <mods:caption>chap.</mods:caption>
              <mods:number>7</mods:number>
              <mods:title>Tidal Range</mods:title>
            </mods:detail>
          </mods:part>
        </mods:relatedItem>
      XML
      expect(chaptered.host_collections)
        .to eq([{ title: "Salt Marshes", volume: "2",
                  details: [{ type: "chapter", number: "7", caption: "chap.", title: "Tidal Range" }] }])
    end

    it "carries an extent at a unit other than page, unit and all" do
      recording = doc_with(<<~XML)
        <mods:relatedItem type="host">
          <mods:titleInfo><mods:title>Field Recordings</mods:title></mods:titleInfo>
          <mods:part>
            <mods:extent unit="page"><mods:start>1</mods:start></mods:extent>
            <mods:extent unit="minutes"><mods:start>0</mods:start><mods:end>45</mods:end></mods:extent>
          </mods:part>
        </mods:relatedItem>
      XML
      expect(recording.host_collections)
        .to eq([{ title: "Field Recordings", start_page: "1",
                  extents: [{ unit: "minutes", start: "0", end: "45", total: nil, list: nil }] }])
    end

    it "keeps the part out of a series, which has no volume or page range" do
      series = doc_with(<<~XML)
        <mods:relatedItem type="series">
          <mods:titleInfo><mods:title>A Series</mods:title></mods:titleInfo>
          <mods:part><mods:detail type="volume"><mods:number>9</mods:number></mods:detail></mods:part>
        </mods:relatedItem>
      XML
      expect(series.related_series).to eq(["A Series"])
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
          <mods:shelfLocator>PS3552 .E1</mods:shelfLocator>
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

  # A cataloguer was given a column for each of these, so the production corpus
  # carries them. The projection dropped the attribute that says what the value
  # IS, which is the same defect class as the accessCondition collapse: not a
  # missing field, but a value a reader cannot interpret.
  describe "the attributes that say what a value is" do
    it "keeps each identifier's @type, so a DOI is not just digits" do
      doc = doc_with(<<~XML)
        <mods:identifier type="doi">10.1234/x</mods:identifier>
        <mods:identifier type="COLID">bdr:12345</mods:identifier>
        <mods:identifier>2047/D20254217</mods:identifier>
      XML

      expect(doc.identifiers).to eq([
                                      { type: "doi", value: "10.1234/x" },
                                      { type: "COLID", value: "bdr:12345" },
                                      { type: nil, value: "2047/D20254217" }
                                    ])
    end

    it "still resolves the permanent URL off the hdl identifier" do
      doc = doc_with(%(<mods:identifier type="hdl">http://hdl.handle.net/2047/D1</mods:identifier>))
      expect(doc.permanent_url).to eq("http://hdl.handle.net/2047/D1")
    end

    it "drops an identifier with no value rather than projecting a typed blank" do
      expect(doc_with(%(<mods:identifier type="hdl"></mods:identifier>)).identifiers).to eq([])
    end

    it "keeps every role on a name, since MODS repeats the element" do
      two_roles = doc_with(<<~XML)
        <mods:name type="personal">
          <mods:namePart>Doe, Jane</mods:namePart>
          <mods:role><mods:roleTerm type="text">Creator</mods:roleTerm></mods:role>
          <mods:role><mods:roleTerm type="text">Contributor</mods:roleTerm></mods:role>
        </mods:name>
      XML
      expect(two_roles.names.first[:roles]).to eq(%w[Creator Contributor])
    end

    it "gives a name with no role an empty list, not a nil member" do
      expect(doc_with("<mods:name><mods:namePart>Anon</mods:namePart></mods:name>")
               .names.first[:roles]).to eq([])
    end

    # A name element carrying only a role is not a name, and it reached a
    # display as a labelled empty row. The three shapes a record writes it in
    # are an absent namePart, an empty one, and a whitespace-only one.
    it "drops a name with a role and no name text, in all three shapes" do
      roles_only = doc_with(<<~XML)
        <mods:name type="corporate">
          <mods:role><mods:roleTerm type="code">edt</mods:roleTerm></mods:role>
        </mods:name>
        <mods:name type="corporate">
          <mods:namePart></mods:namePart>
          <mods:role><mods:roleTerm type="code">edt</mods:roleTerm></mods:role>
        </mods:name>
        <mods:name type="personal">
          <mods:namePart type="family">   </mods:namePart>
          <mods:role><mods:roleTerm type="code">edt</mods:roleTerm></mods:role>
        </mods:name>
      XML
      expect(roles_only.names).to eq([])
    end

    # #preserved_names is the list that tells a curator what the XML holds, so
    # an element they need to fix has to stay visible in it.
    it "keeps a nameless name in the preserved list, which reports the XML" do
      roles_only = doc_with(<<~XML)
        <mods:name type="corporate">
          <mods:role><mods:roleTerm type="code">edt</mods:roleTerm></mods:role>
        </mods:name>
      XML
      expect(roles_only.preserved_names).to eq([{ name: nil, roles: ["edt"], affiliation: [] }])
    end

    # The simple form writes one Creator role back, so it must not claim a name
    # carrying roles it cannot represent -- saving would drop them from the
    # preservation XML.
    it "leaves the editable-creator boundary on the first role, not on any role" do
      second_role_creator = doc_with(<<~XML)
        <mods:name type="personal">
          <mods:namePart type="given">Jen</mods:namePart>
          <mods:namePart type="family">Bell</mods:namePart>
          <mods:role><mods:roleTerm type="text">Editor</mods:roleTerm></mods:role>
          <mods:role><mods:roleTerm type="text">Creator</mods:roleTerm></mods:role>
        </mods:name>
      XML
      aggregate_failures do
        expect(second_role_creator.editable_personal_creators).to eq([])
        expect(second_role_creator.preserved_names)
          .to eq([{ name: "Bell, Jen", roles: %w[Editor Creator], affiliation: [] }])
      end
    end

    # How a reader tells one J. Doe from another, and the basis of any future
    # department browse.
    it "projects a name's affiliations, which repeat in the schema" do
      doc = doc_with(<<~XML)
        <mods:name type="personal">
          <mods:namePart type="family">Doe</mods:namePart>
          <mods:namePart type="given">Jane</mods:namePart>
          <mods:affiliation>Department of Physics</mods:affiliation>
          <mods:affiliation>Northeastern University</mods:affiliation>
          <mods:role><mods:roleTerm type="text">Creator</mods:roleTerm></mods:role>
        </mods:name>
      XML

      expect(doc.names).to eq([{ name: "Doe, Jane", roles: ["Creator"],
                                 affiliation: ["Department of Physics", "Northeastern University"] }])
    end

    it "gives a name with no affiliation an empty list, not a nil" do
      doc = doc_with("<mods:name><mods:namePart>Anon</mods:namePart></mods:name>")
      expect(doc.names.first[:affiliation]).to eq([])
    end

    it "carries the affiliation into the preserved (read-only) names too" do
      doc = doc_with(<<~XML)
        <mods:name type="personal" authority="naf">
          <mods:namePart>Doe, Jane</mods:namePart>
          <mods:affiliation>Northeastern University</mods:affiliation>
        </mods:name>
      XML

      expect(doc.preserved_names.first[:affiliation]).to eq(["Northeastern University"])
    end
  end

  # A cataloguer was given a spreadsheet column for each of these, so the
  # production corpus carries them, and each one projected nothing.
  describe "the corpus-proven elements that had no projection" do
    it "projects the remaining originInfo elements" do
      aggregate_failures do
        expect(doc.place_of_publication).to eq(["Boston"])
        expect(doc.issuance).to eq(["monographic"])
        expect(doc.frequency).to eq(["Quarterly"])
      end
    end

    # A marccountry code is not a place name, and unfiltered it reached the
    # display and the Solr places facet beside real ones.
    it "prefers a place's text term over its code" do
      coded = doc_with(<<~XML)
        <mods:originInfo>
          <mods:place>
            <mods:placeTerm type="code" authority="marccountry">mau</mods:placeTerm>
            <mods:placeTerm type="text">Boston</mods:placeTerm>
          </mods:place>
        </mods:originInfo>
      XML
      expect(coded.place_of_publication).to eq(["Boston"])
    end

    # Dropping the code would lose the only statement the record made about
    # where this was published.
    it "falls back to the code when the place gives nothing else" do
      code_only = doc_with(<<~XML)
        <mods:originInfo>
          <mods:place><mods:placeTerm type="code" authority="marccountry">mau</mods:placeTerm></mods:place>
        </mods:originInfo>
      XML
      expect(code_only.place_of_publication).to eq(["mau"])
    end

    it "reads each place separately, so two originInfo places both survive" do
      two = doc_with(<<~XML)
        <mods:originInfo>
          <mods:place><mods:placeTerm type="text">Boston</mods:placeTerm></mods:place>
          <mods:place><mods:placeTerm type="text">London</mods:placeTerm></mods:place>
        </mods:originInfo>
      XML
      expect(two.place_of_publication).to eq(%w[Boston London])
    end

    it "projects the contents list and the reformatting quality" do
      aggregate_failures do
        expect(doc.table_of_contents).to eq(["Chapter 1 -- Chapter 2"])
        expect(doc.reformatting_quality).to eq(["preservation"])
      end
    end

    # An LCC or DDC call number. Not the same concept as Atlas's
    # classification_ssim, which carries a FileSet content-type vocabulary.
    it "projects the call number" do
      expect(doc.classification).to eq(["PS3552.E1"])
    end

    it "projects the two flat subject axes that were missing" do
      aggregate_failures do
        expect(doc.genre_subjects).to eq(["Field recordings"])
        expect(doc.geographic_code_subjects).to eq(["n-us-ny"])
      end
    end

    # A subject that is a work has a nonSort like any other title, so it
    # composes through the same port rather than taking titleInfo/title alone.
    it "composes a title subject the way it composes the main title" do
      expect(doc.title_subjects).to eq(["The Great Gatsby"])
    end

    # bdr_43888.mods.xml carries this axis and NO subject/geographic at all, so
    # that record projected no place. A live ingest path, not a hypothetical.
    it "keeps a hierarchical place structured rather than flattening it" do
      entry = doc.hierarchical_geographic_subjects.first

      aggregate_failures do
        expect(entry[:country]).to eq("United States")
        expect(entry[:state]).to eq("New York")
        expect(entry[:city]).to eq("Parksville")
        expect(entry[:continent]).to be_nil
      end
    end

    it "covers every level the schema allows, including the camelCase one" do
      doc = doc_with(<<~XML)
        <mods:subject>
          <mods:hierarchicalGeographic>
            <mods:citySection>Back Bay</mods:citySection>
            <mods:island>Nantucket</mods:island>
          </mods:hierarchicalGeographic>
        </mods:subject>
      XML

      entry = doc.hierarchical_geographic_subjects.first
      aggregate_failures do
        expect(entry[:city_section]).to eq("Back Bay")
        expect(entry[:island]).to eq("Nantucket")
      end
    end

    it "skips a hierarchicalGeographic that names no level" do
      doc = doc_with("<mods:subject><mods:hierarchicalGeographic/></mods:subject>")
      expect(doc.hierarchical_geographic_subjects).to eq([])
    end

    # Describes the cataloguing rather than the resource. Dropping a
    # preservation repository's provenance statement on read is wrong on its
    # face, whatever a consumer then decides to show.
    it "projects the cataloguing provenance as one structured value" do
      expect(doc.record_info).to eq({
                                      content_source: "Northeastern University Libraries",
                                      origin: "Created by a batch load",
                                      description_standard: "rda",
                                      creation_date: "2025-01-15",
                                      change_date: "2025-02-01",
                                      language_of_cataloging: "English"
                                    })
    end

    it "reports no record info at all rather than a hash of nils" do
      aggregate_failures do
        expect(doc_with("").record_info).to be_nil
        expect(doc_with("<mods:recordInfo/>").record_info).to be_nil
      end
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
