# frozen_string_literal: true

# The facts a consumer needs to offer a value as a browse: which vocabulary
# the value was taken from, the composed heading as ONE string, and the MODS
# axis a heading belongs to. Held apart from display_attributes_spec, which is
# about the header and the link a record asks for -- those resolve off a
# PARENT element and these resolve off the value's own, which is the whole
# reason they are two ports rather than one.
RSpec.describe "the vocabulary a value was taken from" do
  def parse(body)
    NEU::MODS::Document.parse(<<~XML)
      <?xml version="1.0"?>
      <mods:mods xmlns:mods="http://www.loc.gov/mods/v3"
                 xmlns:xlink="http://www.w3.org/1999/xlink">
        #{body}
      </mods:mods>
    XML
  end

  def authority_of(entry) = entry.slice(:authority, :authority_uri, :value_uri)

  describe "where the authority is read from" do
    it "reads it off the element holding the value" do
      doc = parse(<<~XML)
        <mods:genre authority="aat" authorityURI="http://vocab.getty.edu/aat"
                    valueURI="http://vocab.getty.edu/aat/300026031">podcasts</mods:genre>
      XML
      expect(authority_of(doc.genres.first)).to eq(
        authority: "aat", authority_uri: "http://vocab.getty.edu/aat",
        value_uri: "http://vocab.getty.edu/aat/300026031"
      )
    end

    # A pre-coordinated heading declares its vocabulary once, on the heading,
    # and every part of it belongs to that vocabulary.
    it "falls back to the enclosing subject, which is where a heading declares it" do
      doc = parse(<<~XML)
        <mods:subject authority="lcsh" valueURI="http://id.loc.gov/authorities/subjects/sh2008119371">
          <mods:topic>Emergency management</mods:topic>
          <mods:topic>Planning</mods:topic>
        </mods:subject>
      XML
      expect(authority_of(doc.subject_headings.first)).to eq(
        authority: "lcsh", authority_uri: nil,
        value_uri: "http://id.loc.gov/authorities/subjects/sh2008119371"
      )
    end

    it "prefers an inner name's own authority to the heading's" do
      doc = parse(<<~XML)
        <mods:subject authority="lcsh">
          <mods:name authority="local_lcnaf">
            <mods:namePart>Northeastern University (Boston, Mass.)</mods:namePart>
          </mods:name>
        </mods:subject>
      XML
      expect(doc.subject_headings.first[:authority]).to eq("local_lcnaf")
    end

    # MODS lets a record declare its vocabulary by URI alone, and DRS holds
    # corporate names in exactly that shape. Requiring @authority would call
    # them uncontrolled and leave them unbrowsable.
    it "reports the URIs of a value that names no authority" do
      doc = parse(<<~XML)
        <mods:name type="corporate" authorityURI="http://id.loc.gov/authorities/names"
                   valueURI="http://id.loc.gov/authorities/names/n78095825">
          <mods:namePart>Northeastern University (Boston, Mass.) Libraries</mods:namePart>
        </mods:name>
      XML
      expect(authority_of(doc.names.first)).to eq(
        authority: nil, authority_uri: "http://id.loc.gov/authorities/names",
        value_uri: "http://id.loc.gov/authorities/names/n78095825"
      )
    end

    # The case a naive "any authority in the subtree" check gets wrong, and it
    # would get it wrong on every depositor-entered creator: the deposit form
    # writes a marcrelator roleTerm on all of them.
    it "ignores an authority on a role, which is the vocabulary of the relator" do
      doc = parse(<<~XML)
        <mods:name type="personal">
          <mods:namePart type="given">Jane</mods:namePart>
          <mods:namePart type="family">Doe</mods:namePart>
          <mods:role><mods:roleTerm authority="marcrelator">Creator</mods:roleTerm></mods:role>
        </mods:name>
      XML
      entry = doc.names.first
      aggregate_failures do
        expect(entry[:name]).to eq("Doe, Jane")
        expect(authority_of(entry)).to eq(authority: nil, authority_uri: nil, value_uri: nil)
      end
    end

    # The trap the separate port exists to avoid: @displayLabel comes off the
    # physicalDescription and @authority comes off the form inside it, so one
    # resolution rule for both would read the authority off the wrong element.
    it "reads a form's authority off the form, not off the physicalDescription its header comes from" do
      doc = parse(<<~XML)
        <mods:physicalDescription displayLabel="Medium">
          <mods:form authority="marcform">electronic</mods:form>
        </mods:physicalDescription>
      XML
      entry = doc.format.first
      aggregate_failures do
        expect(entry[:display_label]).to eq("Medium")
        # The labeled fields other than genre carry no authority at all:
        # nothing gates on their vocabulary.
        expect(entry).not_to have_key(:authority)
      end
    end

    it "reads a language's authority off the languageTerm the term came from" do
      doc = parse(<<~XML)
        <mods:language><mods:languageTerm type="code" authority="iso639-2b">eng</mods:languageTerm></mods:language>
      XML
      entry = doc.languages.first
      aggregate_failures do
        expect(entry[:term]).to eq("English")
        expect(entry[:authority]).to eq("iso639-2b")
      end
    end
  end

  describe "the composed heading" do
    # Joined here rather than by each caller, because the composed heading is
    # both the string a display renders and the string a browse index holds.
    it "joins the parts with the separator DRS displays" do
      doc = parse(<<~XML)
        <mods:subject authority="lcsh">
          <mods:topic>Salt marshes</mods:topic>
          <mods:geographic>Massachusetts</mods:geographic>
          <mods:temporal>20th century</mods:temporal>
        </mods:subject>
      XML
      expect(doc.subject_headings.first[:heading]).to eq("Salt marshes -- Massachusetts -- 20th century")
    end

    it "leaves a single-part heading as the term itself" do
      doc = parse("<mods:subject><mods:topic>Civil society</mods:topic></mods:subject>")
      expect(doc.subject_headings.first[:heading]).to eq("Civil society")
    end

    it "keeps the parts beside the joined form, which the edit form reads" do
      doc = parse(<<~XML)
        <mods:subject><mods:topic>Emergency management--Planning</mods:topic></mods:subject>
      XML
      expect(doc.subject_headings.first[:parts]).to eq(["Emergency management", "Planning"])
    end
  end

  describe "the axis a heading belongs to" do
    # The main heading leads and the subdivisions qualify it, which is the LCSH
    # convention: "Salt marshes -- Massachusetts" is a topic heading with a
    # place subdivision, not a place.
    it "names the element of the first child carrying heading text" do
      doc = parse(<<~XML)
        <mods:subject><mods:topic>Salt marshes</mods:topic><mods:geographic>Massachusetts</mods:geographic></mods:subject>
        <mods:subject><mods:geographic>Belle Isle Marsh (Mass.)</mods:geographic></mods:subject>
        <mods:subject><mods:temporal>21st century</mods:temporal></mods:subject>
        <mods:subject><mods:occupation>Cabinetmakers</mods:occupation></mods:subject>
        <mods:subject><mods:genre>Field recordings</mods:genre></mods:subject>
      XML
      expect(doc.subject_headings.map { |heading| heading[:axis] })
        .to eq(%w[topic geographic temporal occupation genre])
    end

    it "reports a camelCased element as the projection names it" do
      doc = parse(<<~XML)
        <mods:subject>
          <mods:titleInfo><mods:title>The Great Gatsby</mods:title></mods:titleInfo>
        </mods:subject>
        <mods:subject>
          <mods:hierarchicalGeographic><mods:city>Parksville</mods:city></mods:hierarchicalGeographic>
        </mods:subject>
      XML
      expect(doc.subject_headings.map { |heading| heading[:axis] })
        .to eq(%w[title_info hierarchical_geographic])
    end

    # A child with no heading text cannot decide the axis: a record leading
    # with a geographicCode would otherwise report an axis for a part that
    # projects nothing.
    it "skips a child that carries no heading text" do
      doc = parse(<<~XML)
        <mods:subject>
          <mods:geographicCode authority="marcgac">n-us-ma</mods:geographicCode>
          <mods:topic>Boston</mods:topic>
        </mods:subject>
      XML
      expect(doc.subject_headings.first[:axis]).to eq("topic")
    end

    it "splits a name subject by its @type, because a person and an organisation are separate browses" do
      doc = parse(<<~XML)
        <mods:subject><mods:name type="personal"><mods:namePart>Bunker, Ellen</mods:namePart></mods:name></mods:subject>
        <mods:subject><mods:name type="corporate"><mods:namePart>Acme Corp</mods:namePart></mods:name></mods:subject>
      XML
      expect(doc.subject_headings.map { |heading| heading[:axis] })
        .to eq(%w[personal_name corporate_name])
    end
  end

  describe "a subject name with no @type" do
    let(:doc) do
      parse(<<~XML)
        <mods:subject>
          <mods:name authority="local_lcnaf">
            <mods:namePart>Northeastern University (Boston, Mass.)</mods:namePart>
            <mods:namePart>Global Resilience Institute</mods:namePart>
          </mods:name>
        </mods:subject>
      XML
    end

    # It displayed and projected nowhere: #subject_heading_part composes a name
    # without consulting @type, and both axis projections required it.
    it "reaches the corporate axis" do
      aggregate_failures do
        expect(doc.corporate_name_subjects)
          .to eq(["Northeastern University (Boston, Mass.) Global Resilience Institute"])
        expect(doc.personal_name_subjects).to eq([])
      end
    end

    it "reports the corporate axis on its heading" do
      expect(doc.subject_headings.first[:axis]).to eq("corporate_name")
    end

    it "leaves a typed name on its own axis alone" do
      typed = parse(<<~XML)
        <mods:subject><mods:name type="personal"><mods:namePart>Bell, Jen</mods:namePart></mods:name></mods:subject>
        <mods:subject><mods:name type="corporate"><mods:namePart>Acme Corp</mods:namePart></mods:name></mods:subject>
      XML
      aggregate_failures do
        expect(typed.personal_name_subjects).to eq(["Bell, Jen"])
        expect(typed.corporate_name_subjects).to eq(["Acme Corp"])
      end
    end
  end
end
