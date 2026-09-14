# frozen_string_literal: true

# The projection changes asked for by the librarians' 2026-09-14 UAT pass
# (DRS_2.0_Metadata_and_Display_Notes). Kept in one file so a reviewer can read
# the round as a round; the older coverage rounds stay where they are.
RSpec.describe "2026-09-14 UAT projection changes" do
  def parse(body)
    NEU::MODS::Document.parse(<<~XML)
      <?xml version="1.0"?>
      <mods:mods xmlns:mods="http://www.loc.gov/mods/v3"
                 xmlns:xlink="http://www.w3.org/1999/xlink">
        #{body}
      </mods:mods>
    XML
  end

  describe "insignificant whitespace in a name part" do
    # A pretty-printed or hand-edited record indents the content of an element,
    # and the name composition joins its parts with separators of its own -- so
    # the space has to go before the join, not after it.
    it "does not carry the indentation of a namePart into the composed name" do
      doc = parse(<<~XML)
        <mods:name type="personal">
          <mods:namePart type="family">
            Doe
          </mods:namePart>
          <mods:namePart type="given">
            Jane
          </mods:namePart>
          <mods:namePart type="date">
            1900-1980
          </mods:namePart>
        </mods:name>
      XML
      expect(doc.names.first[:name]).to eq("Doe, Jane, 1900-1980")
    end

    it "canonicalizes a corporate name assembled from several parts" do
      doc = parse(<<~XML)
        <mods:name type="corporate">
          <mods:namePart>  Northeastern   University  </mods:namePart>
          <mods:namePart>  Library  </mods:namePart>
        </mods:name>
      XML
      expect(doc.names.first[:name]).to eq("Northeastern University Library")
    end

    it "canonicalizes a displayForm and a term of address" do
      doc = parse(<<~XML)
        <mods:name type="personal">
          <mods:namePart type="family"> Doe </mods:namePart>
          <mods:namePart type="termsOfAddress"> Dr. </mods:namePart>
        </mods:name>
        <mods:name type="personal">
          <mods:displayForm>
            Jane Doe
          </mods:displayForm>
        </mods:name>
      XML
      expect(doc.names.map { |entry| entry[:name] }).to eq(["Doe Dr.", "Jane Doe"])
    end
  end

  describe "@displayLabel and xlink:href" do
    it "carries the label and the link of the element holding the value" do
      doc = parse(<<~XML)
        <mods:genre displayLabel="Photo type" xlink:href="https://vocab.getty.edu/aat/300128347">
          photographs
        </mods:genre>
      XML
      expect(doc.genres).to eq(
        [{ value: "photographs", display_label: "Photo type",
           href: "https://vocab.getty.edu/aat/300128347" }]
      )
    end

    # MODS puts @displayLabel on originInfo and physicalDescription, never on
    # the publisher, place, extent or digitalOrigin inside them, so a label a
    # record can actually write has to be read off the parent.
    it "takes an originInfo child's label off the originInfo block" do
      doc = parse(<<~XML)
        <mods:originInfo displayLabel="Issued by">
          <mods:publisher>Northeastern University Press</mods:publisher>
          <mods:place><mods:placeTerm type="text">Boston</mods:placeTerm></mods:place>
          <mods:edition>2nd ed.</mods:edition>
        </mods:originInfo>
      XML
      aggregate_failures do
        expect(doc.publication_information.first[:display_label]).to eq("Issued by")
        expect(doc.place_of_publication.first[:display_label]).to eq("Issued by")
        expect(doc.edition.first[:display_label]).to eq("Issued by")
      end
    end

    it "takes a physicalDescription child's label off the physicalDescription" do
      doc = parse(<<~XML)
        <mods:physicalDescription displayLabel="Technical details">
          <mods:extent>24 pages</mods:extent>
          <mods:digitalOrigin>born digital</mods:digitalOrigin>
          <mods:note>Scanned at 600 dpi.</mods:note>
        </mods:physicalDescription>
      XML
      aggregate_failures do
        expect(doc.extent.first[:display_label]).to eq("Technical details")
        expect(doc.digital_origin.first[:display_label]).to eq("Technical details")
        expect(doc.physical_description_notes.first[:display_label]).to eq("Technical details")
      end
    end

    it "labels each block separately, so two originInfo blocks do not share one header" do
      doc = parse(<<~XML)
        <mods:originInfo displayLabel="Published by"><mods:publisher>Beacon</mods:publisher></mods:originInfo>
        <mods:originInfo displayLabel="Distributed by"><mods:publisher>Ingram</mods:publisher></mods:originInfo>
      XML
      expect(doc.publication_information.map { |entry| entry[:display_label] })
        .to eq(["Published by", "Distributed by"])
    end

    # A document may bind XLink to any prefix, so the attribute is read by
    # namespace rather than by the literal "xlink:" spelling.
    it "reads xlink:href under a prefix of the document's choosing" do
      doc = NEU::MODS::Document.parse(<<~XML)
        <?xml version="1.0"?>
        <mods:mods xmlns:mods="http://www.loc.gov/mods/v3"
                   xmlns:xl="http://www.w3.org/1999/xlink">
          <mods:note xl:href="https://example.org/note">See the finding aid.</mods:note>
        </mods:mods>
      XML
      expect(doc.notes.first[:href]).to eq("https://example.org/note")
    end

    it "gives an element with a link and no text no value at all" do
      doc = parse(%(<mods:genre xlink:href="https://example.org/g"></mods:genre>))
      expect(doc.genres).to eq([])
    end

    it "carries the label on every entry-shaped projection" do
      doc = parse(<<~XML)
        <mods:name type="personal" displayLabel="Photographer">
          <mods:namePart>Ansel Adams</mods:namePart>
        </mods:name>
        <mods:subject displayLabel="Depicts"><mods:topic>Salt marshes</mods:topic></mods:subject>
        <mods:location displayLabel="Held at"><mods:physicalLocation>Snell</mods:physicalLocation></mods:location>
        <mods:identifier type="doi" displayLabel="Cite as">10.1234/x</mods:identifier>
        <mods:relatedItem type="otherFormat" displayLabel="Also as">
          <mods:titleInfo><mods:title>The print edition</mods:title></mods:titleInfo>
        </mods:relatedItem>
      XML
      aggregate_failures do
        expect(doc.names.first[:display_label]).to eq("Photographer")
        expect(doc.subject_headings.first[:display_label]).to eq("Depicts")
        expect(doc.location.first[:display_label]).to eq("Held at")
        expect(doc.identifiers.first[:display_label]).to eq("Cite as")
        expect(doc.related_items.first[:display_label]).to eq("Also as")
      end
    end

    # cartographics carries neither attribute; the subject around it does.
    it "takes a map's label off the subject that encloses the cartographics" do
      doc = parse(<<~XML)
        <mods:subject displayLabel="Surveyed as">
          <mods:cartographics><mods:scale>1:24,000</mods:scale></mods:cartographics>
        </mods:subject>
      XML
      expect(doc.map_data.first[:display_label]).to eq("Surveyed as")
    end

    # #abstract and the three accessCondition fields each join several elements
    # into one string, so their qualifiers are companion scalars.
    it "projects the abstract's and the access conditions' qualifiers as companions" do
      doc = parse(<<~XML)
        <mods:abstract displayLabel="Summary" xlink:href="https://example.org/full">A study.</mods:abstract>
        <mods:accessCondition type="use and reproduction" displayLabel="Licence"
                              xlink:href="https://creativecommons.org/licenses/by/4.0/">CC BY 4.0</mods:accessCondition>
      XML
      aggregate_failures do
        expect(doc.abstract_display_label).to eq("Summary")
        expect(doc.abstract_href).to eq("https://example.org/full")
        expect(doc.use_and_reproduction_display_label).to eq("Licence")
        expect(doc.use_and_reproduction_href).to eq("https://creativecommons.org/licenses/by/4.0/")
        expect(doc.restriction_on_access_display_label).to be_nil
      end
    end

    it "reads the header the MODS template puts on the handle identifier" do
      doc = parse(%(<mods:identifier type="hdl" displayLabel="Permanent URL">http://hdl.handle.net/2047/1</mods:identifier>))
      aggregate_failures do
        expect(doc.permanent_url).to eq("http://hdl.handle.net/2047/1")
        expect(doc.permanent_url_display_label).to eq("Permanent URL")
      end
    end

    it "reads the header a record puts on its primary title" do
      doc = parse(<<~XML)
        <mods:titleInfo usage="primary" displayLabel="Caption">
          <mods:title>A marsh</mods:title>
        </mods:titleInfo>
      XML
      expect(doc.main_title_display_label).to eq("Caption")
    end
  end

  describe "targetAudience" do
    it "projects the audience a record names, which reached no consumer before" do
      doc = parse(<<~XML)
        <mods:targetAudience authority="marctarget">juvenile</mods:targetAudience>
        <mods:targetAudience displayLabel="Intended for">Undergraduates</mods:targetAudience>
      XML
      expect(doc.target_audience).to eq(
        [{ value: "juvenile", display_label: nil, href: nil },
         { value: "Undergraduates", display_label: "Intended for", href: nil }]
      )
    end
  end

  describe "originInfo @eventType and the block's dates" do
    it "carries the block's eventType onto every child of the block" do
      doc = parse(<<~XML)
        <mods:originInfo eventType="production">
          <mods:publisher>The studio</mods:publisher>
          <mods:place><mods:placeTerm type="text">Boston</mods:placeTerm></mods:place>
          <mods:dateCreated>1935</mods:dateCreated>
        </mods:originInfo>
      XML
      aggregate_failures do
        expect(doc.publication_information.first[:event_type]).to eq("production")
        expect(doc.place_of_publication.first[:event_type]).to eq("production")
        expect(doc.date_created_event_type).to eq("production")
      end
    end

    it "keeps two originInfo blocks' event types apart" do
      doc = parse(<<~XML)
        <mods:originInfo eventType="publication"><mods:publisher>Beacon</mods:publisher></mods:originInfo>
        <mods:originInfo eventType="distribution"><mods:publisher>Ingram</mods:publisher></mods:originInfo>
      XML
      expect(doc.publication_information.map { |entry| entry[:event_type] })
        .to eq(%w[publication distribution])
    end

    # A place is headed "Creation place" or "Publication place" by the date
    # beside it, and the place element says nothing about the event itself.
    it "names the date elements the place's own block carries" do
      doc = parse(<<~XML)
        <mods:originInfo>
          <mods:place><mods:placeTerm type="text">Boston</mods:placeTerm></mods:place>
          <mods:dateCreated>1935</mods:dateCreated>
        </mods:originInfo>
        <mods:originInfo>
          <mods:place><mods:placeTerm type="text">New York</mods:placeTerm></mods:place>
          <mods:dateIssued>1998</mods:dateIssued>
        </mods:originInfo>
      XML
      expect(doc.place_of_publication.map { |entry| entry[:date_elements] })
        .to eq([["dateCreated"], ["dateIssued"]])
    end

    it "gives a place in a dateless block no date elements" do
      doc = parse(<<~XML)
        <mods:originInfo><mods:place><mods:placeTerm type="text">Boston</mods:placeTerm></mods:place></mods:originInfo>
      XML
      expect(doc.place_of_publication.first[:date_elements]).to eq([])
    end

    it "reads the displayLabel a block puts over its date" do
      doc = parse(<<~XML)
        <mods:originInfo displayLabel="Photographed">
          <mods:dateCreated encoding="w3cdtf">1935-06</mods:dateCreated>
        </mods:originInfo>
      XML
      aggregate_failures do
        expect(doc.date_created_display_label).to eq("Photographed")
        expect(doc.date_created_precision).to eq("month")
        expect(doc.date_issued_display_label).to be_nil
      end
    end
  end

  describe "originInfo/agent (MODS 3.8)" do
    it "composes an agent the way it composes a top-level name" do
      doc = parse(<<~XML)
        <mods:originInfo eventType="production">
          <mods:agent type="personal">
            <mods:namePart type="family">Adams</mods:namePart>
            <mods:namePart type="given">Ansel</mods:namePart>
            <mods:role><mods:roleTerm type="text">Photographer</mods:roleTerm></mods:role>
          </mods:agent>
        </mods:originInfo>
      XML
      expect(doc.origin_agents).to eq(
        [{ name: "Adams, Ansel", roles: ["Photographer"], affiliation: [],
           usage: nil, alternative_names: [],
           display_label: nil, href: nil, event_type: "production" }]
      )
    end

    it "drops an agent with no name text, as #names does" do
      doc = parse(<<~XML)
        <mods:originInfo><mods:agent><mods:role><mods:roleTerm>pbl</mods:roleTerm></mods:role></mods:agent></mods:originInfo>
      XML
      expect(doc.origin_agents).to eq([])
    end
  end

  describe "name @usage and alternativeName" do
    it "carries the @usage a record puts on its principal name" do
      doc = parse(<<~XML)
        <mods:name type="personal" usage="primary">
          <mods:namePart type="family">Adams</mods:namePart>
        </mods:name>
        <mods:name type="personal"><mods:namePart type="family">Doe</mods:namePart></mods:name>
      XML
      expect(doc.names.map { |entry| entry[:usage] }).to eq(["primary", nil])
    end

    # alternativeName carries @altType, not @type, so it composes with the
    # enclosing name's type -- read from its own attributes a personal
    # alternative would compose "Doe Jane" under a name composing "Doe, Jane".
    it "composes an alternativeName with the enclosing name's type" do
      doc = parse(<<~XML)
        <mods:name type="personal">
          <mods:namePart type="family">Clemens</mods:namePart>
          <mods:namePart type="given">Samuel</mods:namePart>
          <mods:alternativeName altType="pseudonym">
            <mods:namePart type="family">Twain</mods:namePart>
            <mods:namePart type="given">Mark</mods:namePart>
          </mods:alternativeName>
        </mods:name>
      XML
      entry = doc.names.first
      aggregate_failures do
        expect(entry[:name]).to eq("Clemens, Samuel")
        expect(entry[:alternative_names]).to eq(["Twain, Mark"])
      end
    end

    it "reads a corporate alternativeName as a corporate name" do
      doc = parse(<<~XML)
        <mods:name type="corporate">
          <mods:namePart>Northeastern University Library</mods:namePart>
          <mods:alternativeName><mods:namePart>Snell Library</mods:namePart></mods:alternativeName>
        </mods:name>
      XML
      expect(doc.names.first[:alternative_names]).to eq(["Snell Library"])
    end

    it "gives a name with no alternative an empty list rather than nil" do
      doc = parse(%(<mods:name type="personal"><mods:namePart>Jane Doe</mods:namePart></mods:name>))
      expect(doc.names.first[:alternative_names]).to eq([])
    end
  end
end
