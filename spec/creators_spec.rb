# frozen_string_literal: true

RSpec.describe "Creator read / select / build" do
  let(:doc) { NEU::MODS::Document.parse(fixture("work-mods.xml")) }

  describe "the editable predicate on work-mods.xml (all names authority-bearing)" do
    it "finds no editable creators (every name carries authority markers)" do
      aggregate_failures do
        expect(doc.editable_personal_creators).to eq([])
        expect(doc.editable_corporate_creators).to eq([])
        expect(doc.editable_creator_nodes("personal")).to be_empty
        expect(doc.editable_creator_nodes("corporate")).to be_empty
      end
    end

    it "exposes all of them as preserved (read-only) names with roles" do
      expect(doc.preserved_names).to eq(
        [
          { name: "Cohen, Daniel J.(Daniel Jared), 1968-", role: "Creator", affiliation: [] },
          { name: "Northeastern University (Boston, Mass.) Libraries", role: "Creator", affiliation: [] },
          { name: "Flynn, Stephen E.", role: "Contributor", affiliation: [] }
        ]
      )
    end
  end

  describe "building + round-tripping plain creators" do
    let(:blank) do
      NEU::MODS::Document.parse(<<~XML)
        <?xml version="1.0"?>
        <mods:mods xmlns:mods="http://www.loc.gov/mods/v3">
          <mods:titleInfo usage="primary"><mods:title>T</mods:title></mods:titleInfo>
        </mods:mods>
      XML
    end

    it "builds a plain personal creator that reads back as editable + Creator" do
      blank.doc.root.add_child(blank.build_personal_name(given: "Jenny", family: "Smith"))
      reparsed = NEU::MODS::Document.parse(blank.to_xml)

      expect(reparsed.editable_personal_creators).to eq([{ given: "Jenny", family: "Smith" }])
      # and it shows up as a plain Creator name, NOT in the preserved set
      expect(reparsed.preserved_names).to eq([])
    end

    it "builds a plain corporate creator that reads back as editable" do
      blank.doc.root.add_child(blank.build_corporate_name(name: "Northeastern University"))
      reparsed = NEU::MODS::Document.parse(blank.to_xml)

      expect(reparsed.editable_corporate_creators).to eq([{ name: "Northeastern University" }])
    end

    it "emits no authority markers and a text Creator roleTerm" do
      node = blank.build_personal_name(given: "A", family: "B")
      xml = node.to_xml
      aggregate_failures do
        expect(xml).not_to include("authority")
        expect(xml).not_to include("valueURI")
        expect(node.at_xpath("mods:role/mods:roleTerm[@type='text']", NEU::MODS::NAMESPACE).text).to eq("Creator")
        expect(node["type"]).to eq("personal")
      end
    end

    it "role is parameterised (defaults to Creator) for a future role-selectable form" do
      node = blank.build_personal_name(given: "A", family: "B", role: "Editor")
      expect(node.at_xpath("mods:role/mods:roleTerm", NEU::MODS::NAMESPACE).text).to eq("Editor")
      # a non-Creator plain name is NOT editable (preserved), by the predicate
      blank.doc.root.add_child(node)
      expect(NEU::MODS::Document.parse(blank.to_xml).editable_personal_creators).to eq([])
    end
  end

  describe "editable_creator_nodes selects only plain Creator names of the type" do
    let(:mixed) do
      NEU::MODS::Document.parse(<<~XML)
        <?xml version="1.0"?>
        <mods:mods xmlns:mods="http://www.loc.gov/mods/v3">
          <mods:name type="personal" authority="lcnaf"><mods:namePart type="family">Curated</mods:namePart>
            <mods:role><mods:roleTerm type="text">Creator</mods:roleTerm></mods:role></mods:name>
          <mods:name type="personal"><mods:namePart type="given">Plain</mods:namePart><mods:namePart type="family">Creator</mods:namePart>
            <mods:role><mods:roleTerm type="text">Creator</mods:roleTerm></mods:role></mods:name>
          <mods:name type="corporate"><mods:namePart>Org</mods:namePart>
            <mods:role><mods:roleTerm type="text">Creator</mods:roleTerm></mods:role></mods:name>
        </mods:mods>
      XML
    end

    it "returns only the plain personal Creator, not the authority one" do
      nodes = mixed.editable_creator_nodes("personal")
      expect(nodes.size).to eq(1)
      expect(nodes.first.at_xpath("mods:namePart[@type='given']", NEU::MODS::NAMESPACE).text).to eq("Plain")
    end

    it "scopes by @type" do
      expect(mixed.editable_creator_nodes("corporate").size).to eq(1)
      expect(mixed.editable_corporate_creators).to eq([{ name: "Org" }])
    end
  end
end
