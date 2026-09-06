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

  # w3cdtf lets a curator stop at the year or the month, and the fixture's full
  # date is only one of the three legal shapes. The precision travels with the
  # value because the parse destroys it: 2026 and 2026-01-01 both become the
  # same DateTime, and only the precision tells a display layer which one the
  # record actually claimed.
  describe "dateCreated granularity" do
    def doc_with_date(date, attrs: %(keyDate="yes"))
      doc_with_origin_info(%(<mods:dateCreated #{attrs} encoding="w3cdtf">#{date}</mods:dateCreated>))
    end

    def doc_with_origin_info(body)
      described_class.parse(<<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <mods:mods xmlns:mods="http://www.loc.gov/mods/v3">
          <mods:titleInfo usage="primary"><mods:title>Bare</mods:title></mods:titleInfo>
          <mods:originInfo>
            #{body}
          </mods:originInfo>
        </mods:mods>
      XML
    end

    it "parses a full date at day precision" do
      expect(doc_with_date("2026-02-20").date_created_with_precision)
        .to eq([DateTime.new(2026, 2, 20), "day"])
    end

    it "parses a year-month at month precision, filling the day with the 1st" do
      expect(doc_with_date("2026-02").date_created_with_precision)
        .to eq([DateTime.new(2026, 2, 1), "month"])
    end

    it "parses a bare year at year precision, filling the month and day with the 1st" do
      expect(doc_with_date("2026").date_created_with_precision)
        .to eq([DateTime.new(2026, 1, 1), "year"])
    end

    it "falls to the sentinel for a shape-matched but impossible date" do
      aggregate_failures do
        expect(doc_with_date("2026-13").date_created_with_precision).to eq(["", nil])
        expect(doc_with_date("2026-02-30").date_created_with_precision).to eq(["", nil])
      end
    end

    it "falls to the sentinel for a qualified date outside w3cdtf" do
      expect(doc_with_date("circa 2026").date_created_with_precision).to eq(["", nil])
    end

    it "returns nil for both halves when there is no dateCreated" do
      minimal = described_class.parse(<<~XML)
        <?xml version="1.0"?>
        <mods:mods xmlns:mods="http://www.loc.gov/mods/v3">
          <mods:titleInfo usage="primary"><mods:title>Bare</mods:title></mods:titleInfo>
        </mods:mods>
      XML
      expect(minimal.date_created_with_precision).to eq([nil, nil])
    end

    it "exposes each half on its own so existing value-only callers are unaffected" do
      doc = doc_with_date("2026-02")
      aggregate_failures do
        expect(doc.date_created).to eq(DateTime.new(2026, 2, 1))
        expect(doc.date_created_precision).to eq("month")
      end
    end

    # A cataloguer marked the date doubtful and the page stated it as fact.
    # bdr_43888.mods.xml -- a real Brown record -- does exactly this.
    it "keeps the qualifier the record put on the date" do
      doc = doc_with_date("1930", attrs: %(qualifier="questionable"))
      aggregate_failures do
        expect(doc.date_created).to eq(DateTime.new(1930, 1, 1))
        expect(doc.date_created_qualifier).to eq("questionable")
      end
    end

    it "keeps an unrecognised qualifier, because the record still said something" do
      expect(doc_with_date("1930", attrs: %(qualifier="guessed")).date_created_qualifier).to eq("guessed")
    end

    it "reports no qualifier when the record asserted certainty" do
      expect(doc_with_date("1930", attrs: "").date_created_qualifier).to be_nil
    end

    # MODS lets a record nominate its own principal date. Both repos overruled
    # it with a fixed preference order, which a preservation repository should
    # not do.
    it "reports the keyDate flag the record set" do
      aggregate_failures do
        expect(doc_with_date("1930", attrs: %(keyDate="yes")).date_created_key_date).to be true
        expect(doc_with_date("1930", attrs: "").date_created_key_date).to be false
        expect(described_class.parse("<mods:mods xmlns:mods=\"http://www.loc.gov/mods/v3\"/>")
                              .date_created_key_date).to be_nil
      end
    end

    # The flag and the value used to contradict each other: the flag was
    # computed across every node while the value was read from the first, so a
    # record flagging its second dateCreated sorted on the first and asserted
    # the second.
    describe "a record that flags its principal date" do
      it "reads the value from the flagged node rather than from document order" do
        doc = doc_with_origin_info(<<~XML)
          <mods:dateCreated>1920</mods:dateCreated>
          <mods:dateCreated keyDate="yes">1931</mods:dateCreated>
        XML

        aggregate_failures do
          expect(doc.date_created).to eq(DateTime.new(1931, 1, 1))
          expect(doc.date_created_key_date).to be true
        end
      end

      # The flag can sit on both ends of a range, and the end must not be
      # promoted to the start just because it carries one.
      it "keeps a flagged range the right way round" do
        doc = doc_with_origin_info(<<~XML)
          <mods:dateCreated keyDate="yes" point="end">1940</mods:dateCreated>
          <mods:dateCreated keyDate="yes" point="start">1935</mods:dateCreated>
        XML

        aggregate_failures do
          expect(doc.date_created).to eq(DateTime.new(1935, 1, 1))
          expect(doc.date_created_end).to eq(DateTime.new(1940, 1, 1))
        end
      end

      it "leaves an unflagged repeated date on document order" do
        doc = doc_with_origin_info(<<~XML)
          <mods:dateCreated>1920</mods:dateCreated>
          <mods:dateCreated>1931</mods:dateCreated>
        XML

        expect(doc.date_created).to eq(DateTime.new(1920, 1, 1))
      end
    end

    # #at_xpath took the first node, so one end of a range was promoted to be
    # THE date and the output was indistinguishable from a single certain year.
    describe "a ranged date" do
      let(:ranged) do
        doc_with_origin_info(<<~XML)
          <mods:dateCreated encoding="w3cdtf" point="start" qualifier="approximate">1935-06</mods:dateCreated>
          <mods:dateCreated encoding="w3cdtf" point="end" qualifier="approximate">1940</mods:dateCreated>
        XML
      end

      it "projects both ends, each with its own precision" do
        aggregate_failures do
          expect(ranged.date_created).to eq(DateTime.new(1935, 6, 1))
          expect(ranged.date_created_precision).to eq("month")
          expect(ranged.date_created_end).to eq(DateTime.new(1940, 1, 1))
          expect(ranged.date_created_end_precision).to eq("year")
        end
      end

      it "carries the qualifier that says both ends are guesses" do
        expect(ranged.date_created_qualifier).to eq("approximate")
      end

      # A record is free to write the end first; taking the first node would
      # then invert the range.
      it "reads the points by attribute, not by document order" do
        inverted = doc_with_origin_info(<<~XML)
          <mods:dateCreated point="end">1940</mods:dateCreated>
          <mods:dateCreated point="start">1935</mods:dateCreated>
        XML

        aggregate_failures do
          expect(inverted.date_created).to eq(DateTime.new(1935, 1, 1))
          expect(inverted.date_created_end).to eq(DateTime.new(1940, 1, 1))
        end
      end

      it "leaves the end empty for a single unpointed date" do
        single = doc_with_date("1935", attrs: "")
        aggregate_failures do
          expect(single.date_created).to eq(DateTime.new(1935, 1, 1))
          expect(single.date_created_end).to be_nil
          expect(single.date_created_end_precision).to be_nil
        end
      end

      it "takes the qualifier from the end when only the end carries one" do
        doc = doc_with_origin_info(<<~XML)
          <mods:dateCreated point="start">1935</mods:dateCreated>
          <mods:dateCreated point="end" qualifier="inferred">1940</mods:dateCreated>
        XML

        expect(doc.date_created_qualifier).to eq("inferred")
      end
    end

    # dateCaptured, dateValid, dateOther and dateModified were read by nothing,
    # so a digitisation date a cataloguer keyed reached no consumer at all.
    # They read exactly like the other three, precision and range included.
    it "applies the same shape to the four remaining originInfo dates" do
      doc = doc_with_origin_info(<<~XML)
        <mods:dateCaptured encoding="w3cdtf">2019-04-11</mods:dateCaptured>
        <mods:dateValid encoding="w3cdtf" point="start">1990</mods:dateValid>
        <mods:dateValid encoding="w3cdtf" point="end">2000</mods:dateValid>
        <mods:dateOther qualifier="inferred">1930</mods:dateOther>
        <mods:dateModified encoding="w3cdtf">2024-08</mods:dateModified>
      XML

      aggregate_failures do
        expect(doc.date_captured).to eq(DateTime.new(2019, 4, 11))
        expect(doc.date_captured_precision).to eq("day")
        expect(doc.date_valid).to eq(DateTime.new(1990, 1, 1))
        expect(doc.date_valid_end).to eq(DateTime.new(2000, 1, 1))
        expect(doc.date_other).to eq(DateTime.new(1930, 1, 1))
        expect(doc.date_other_qualifier).to eq("inferred")
        expect(doc.date_modified).to eq(DateTime.new(2024, 8, 1))
        expect(doc.date_modified_precision).to eq("month")
      end
    end

    it "reports the four as absent rather than blank on a record without them" do
      doc = doc_with_date("1930")

      aggregate_failures do
        %i[date_captured date_valid date_other date_modified].each do |field|
          expect(doc.public_send(field)).to be_nil
          expect(doc.public_send(:"#{field}_key_date")).to be_nil
        end
      end
    end

    it "applies the same shape to the other two originInfo dates" do
      doc = doc_with_origin_info(<<~XML)
        <mods:dateIssued keyDate="yes" point="start" qualifier="approximate">1935</mods:dateIssued>
        <mods:dateIssued point="end">1940</mods:dateIssued>
        <mods:copyrightDate>1936</mods:copyrightDate>
      XML

      aggregate_failures do
        expect(doc.date_issued_end).to eq(DateTime.new(1940, 1, 1))
        expect(doc.date_issued_qualifier).to eq("approximate")
        expect(doc.date_issued_key_date).to be true
        expect(doc.copyright_date).to eq(DateTime.new(1936, 1, 1))
        expect(doc.copyright_date_key_date).to be false
      end
    end

    it "projects both keys into to_h" do
      expect(doc_with_date("2026").to_h)
        .to include(date_created: DateTime.new(2026, 1, 1), date_created_precision: "year")
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
        expect(minimal.resource_type).to eq([]) # repeatable, absent -> []
        expect(minimal.permanent_url).to be_nil # node absent -> nil (Atlas parity)
        expect(minimal.date_created).to be_nil
        expect(minimal.date_created_precision).to be_nil
        expect(minimal.names).to eq([])
        expect(minimal.topical_subjects).to eq([])
      end
    end
  end
end
