# frozen_string_literal: true

require "date"

# The behavior-preserving safety net. Golden values were captured from the
# `mods` gem's actual output for this fixture (the projection Atlas produces
# today), so adopting neu-mods in Atlas is provably non-regressive. If a future
# change to the projection alters any of these, that is a deliberate,
# reviewed contract change — bump the gem accordingly.
RSpec.describe "Conformance: work-mods.xml projection" do
  let(:doc) { NEU::MODS::Document.parse(fixture("work-mods.xml")) }
  let(:projection) { doc.to_h }

  it "projects the scoped primary title parts (not the nested relatedItem title)" do
    expect(projection[:main_title]).to eq(
      non_sort: "", subtitle: "", title: "What's New",
      part_name: "How We Respond to Disaster", part_number: "Episode 1"
    )
  end

  it "composes plain_title from the primary title only" do
    expect(doc.plain_title).to eq("What's New - How We Respond to Disaster, Episode 1")
  end

  it "reproduces the mods-gem name display_value_w_date (quirks included)" do
    expect(projection[:names]).to eq(
      [
        { name: "Cohen, Daniel J.(Daniel Jared), 1968-", role: "Creator" },
        { name: "Northeastern University (Boston, Mass.) Libraries", role: "Creator" },
        { name: "Flynn, Stephen E.", role: "Contributor" }
      ]
    )
  end

  it "harvests every topic across all subjects (topical_subjects)" do
    expect(projection[:topical_subjects]).to eq(
      ["Civil society", "Organizational resilience", "First responders",
       "Emergency management", "Planning", "September 11 Terrorist Attacks, 2001"]
    )
  end

  it "exposes only the editable attribute-free keyword subjects (none here)" do
    # Every subject in the fixture is authority-bearing or a name-subject, so the
    # simple form's editable keyword set is empty — distinct from topical_subjects.
    expect(doc.keywords).to eq([])
  end

  it "projects the remaining scalar/array fields" do
    aggregate_failures do
      expect(projection[:languages]).to eq(["English"])
      expect(projection[:resource_type]).to eq("sound recording")
      expect(projection[:genres]).to eq(["podcasts"])
      expect(projection[:format]).to eq("electronic")
      expect(projection[:extent]).to eq("00:34:45")
      expect(projection[:digital_origin]).to eq("born digital")
      expect(projection[:related_series]).to eq(["What's New Podcast"])
      expect(projection[:identifiers]).to eq(["http://hdl.handle.net/2047/D20254217"])
      expect(projection[:permanent_url]).to eq("http://hdl.handle.net/2047/D20254217")
      expect(projection[:date_created]).to eq(DateTime.parse("2017-09-19"))
    end
  end

  it "normalizes the single-paragraph abstract (no soft-wrap artifacts)" do
    expect(doc.abstract).to start_with("How do people and cities respond")
    expect(doc.abstract).to end_with("the most stressful moments.")
    expect(doc.abstract).not_to include("\n")
    expect(doc.abstract).not_to include("  ")
  end

  it "joins multi-element accessCondition as paragraphs, collapsing soft wraps" do
    ac = projection[:access_condition]
    expect(ac).to include("In Copyright: This Item is protected")
    # soft wrap "related rights\n        legislation" collapses to a single space
    expect(ac).to include("related rights legislation that applies to your use")
    expect(ac).to end_with("\n\nCopyright restrictions may apply.")
  end

  it "keys to_h to Atlas's Metadata::MODS attribute names" do
    expect(projection.keys).to contain_exactly(
      :main_title, :names, :languages, :date_created, :resource_type, :genres,
      :format, :extent, :digital_origin, :abstract, :related_series,
      :topical_subjects, :identifiers, :permanent_url, :access_condition
    )
  end
end
