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
end
