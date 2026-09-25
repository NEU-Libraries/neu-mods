# frozen_string_literal: true

# Names that Atlas and Cerberus reach through NEU::MODS::Projection rather than
# through a Document. The projection is split into area mixins, and a module
# method does not travel with `include`, so these pin each name where the
# consumers call it.
RSpec.describe "Projection names the consumers call" do
  it "keeps HEADING_SEPARATOR reachable on Projection (Atlas's WorkDecorator)" do
    expect(NEU::MODS::Projection::HEADING_SEPARATOR).to eq(" -- ")
  end

  it "keeps fold_type callable on Projection (Atlas's WorkDecorator)" do
    expect(NEU::MODS::Projection.fold_type("Use and Reproduction")).to eq("useandreproduction")
  end

  it "keeps compose_title callable on Projection and NEU::MODS" do
    parts = { non_sort: "The", title: "Hobbit" }
    aggregate_failures do
      expect(NEU::MODS::Projection.compose_title(parts)).to eq("The Hobbit")
      expect(NEU::MODS.compose_title(parts)).to eq("The Hobbit")
    end
  end

  it "keeps FIELDS on Projection and the top-level module" do
    expect(NEU::MODS::FIELDS).to equal(NEU::MODS::Projection::FIELDS)
  end
end
