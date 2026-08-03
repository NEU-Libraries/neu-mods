# frozen_string_literal: true

# The pure display-title composer, exercised independently of XML parsing --
# this is the path Atlas's MODSDecoration uses, feeding it the access-copy
# model's parts so the title never gets recomposed by hand (or re-parsed from
# XML on the read path). Document#plain_title is the same logic over title_parts;
# the conformance/document specs pin its XML-driven behavior.
RSpec.describe "NEU::MODS.compose_title" do
  it "composes all parts in order: non_sort+title, : subtitle, - part_name, , part_number" do
    parts = {
      non_sort: "The ", title: "Hobbit", subtitle: "There and Back Again",
      part_name: "Book One", part_number: "Episode 1"
    }
    expect(NEU::MODS.compose_title(parts))
      .to eq("The Hobbit: There and Back Again - Book One, Episode 1")
  end

  it "drops absent optional parts (nil or blank) but keeps non_sort+title" do
    expect(NEU::MODS.compose_title(non_sort: "", title: "What's New",
                                   part_name: "How We Respond", part_number: "Episode 1"))
      .to eq("What's New - How We Respond, Episode 1")
  end

  it "returns just non_sort+title when only those are present" do
    expect(NEU::MODS.compose_title(title: "Bare")).to eq("Bare")
    expect(NEU::MODS.compose_title(non_sort: "A ", title: "Title")).to eq("A Title")
  end

  # The separator is composed, not inherited. #child_text canonicalizes
  # whitespace, so a nonSort authored as "The " reaches the composer as "The"
  # and used to produce "TheHobbit". Both shapes must land on one space -- and
  # an elided article must still take none.
  describe "the nonSort separator" do
    {
      "inserts a space when canonicalization stripped it" => ["The", "Hobbit", "The Hobbit"],
      "does not double the space when the caller kept it" => ["The ", "Hobbit", "The Hobbit"],
      "binds an elided article with no space" => ["L'", "Étranger", "L'Étranger"],
      "binds a curly-apostrophe elision too" => ["L’", "Étranger", "L’Étranger"],
      "binds a hyphenated prefix" => ["D-", "Day", "D-Day"],
      "omits the separator entirely when there is no nonSort" => ["", "Title", "Title"],
      "treats a nil nonSort as absent" => [nil, "Title", "Title"]
    }.each do |desc, (non_sort, title, expected)|
      it desc do
        expect(NEU::MODS.compose_title(non_sort: non_sort, title: title)).to eq(expected)
      end
    end

    it "still composes the optional parts after the joined title" do
      expect(NEU::MODS.compose_title(non_sort: "The", title: "Hobbit", subtitle: "There and Back Again"))
        .to eq("The Hobbit: There and Back Again")
    end
  end

  it "returns \"\" when the title is absent, nil, or whitespace (regardless of other parts)" do
    aggregate_failures do
      expect(NEU::MODS.compose_title({})).to eq("")
      expect(NEU::MODS.compose_title(title: nil, subtitle: "Sub")).to eq("")
      expect(NEU::MODS.compose_title(title: "   ", part_name: "Part")).to eq("")
    end
  end

  it "treats nil and \"\" parts identically (Atlas model passes \"\", parser passes nil)" do
    nils = NEU::MODS.compose_title(non_sort: nil, title: "T", subtitle: nil,
                                   part_name: nil, part_number: nil)
    empties = NEU::MODS.compose_title(non_sort: "", title: "T", subtitle: "",
                                      part_name: "", part_number: "")
    expect(nils).to eq("T")
    expect(empties).to eq("T")
  end

  it "is what Document#plain_title delegates to (same result over title_parts)" do
    doc = NEU::MODS::Document.parse(fixture("work-mods.xml"))
    expect(doc.plain_title).to eq(NEU::MODS.compose_title(doc.title_parts))
    expect(doc.plain_title).to eq("What's New - How We Respond to Disaster, Episode 1")
  end
end
