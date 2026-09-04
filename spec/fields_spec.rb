# frozen_string_literal: true

# The registry is the single declaration of what the gem projects, so the specs
# that matter here are the ones tying it to the methods and to #to_h. Without
# them the constant is a comment: a field could sit in FIELDS with no method, or
# a method could declare :many and still return the first match only.
RSpec.describe "NEU::MODS::Projection::FIELDS" do
  let(:registry) { NEU::MODS::Projection::FIELDS }

  # A schema-valid record carrying every element the coverage work touches:
  # two titleInfo including a typed variant, a code-only roleTerm, publisher,
  # dateIssued, copyrightDate, place and edition, a code-only languageTerm, two
  # typeOfResource, a full physicalDescription, two notes, four subject axes,
  # three relatedItem types, a DOI, a location, and two accessCondition types.
  let(:doc) { NEU::MODS::Document.parse(fixture("coverage-mods.xml")) }
  let(:minimal) do
    NEU::MODS::Document.parse(<<~XML)
      <?xml version="1.0"?>
      <mods:mods xmlns:mods="http://www.loc.gov/mods/v3">
        <mods:titleInfo usage="primary"><mods:title>Bare</mods:title></mods:titleInfo>
      </mods:mods>
    XML
  end

  it "is surfaced on the top-level module for consumers deriving a schema" do
    expect(NEU::MODS::FIELDS).to equal(registry)
  end

  it "declares a cardinality of :one or :many for every field" do
    expect(registry.values.uniq - %i[one many]).to be_empty
  end

  it "backs every declared field with a projection method" do
    expect(registry.keys.reject { |f| doc.respond_to?(f) }).to be_empty
  end

  it "derives to_h from the registry, in registry order" do
    expect(doc.to_h.keys).to eq(registry.keys)
  end

  # The check the registry exists for: a field declared :many that still uses
  # at_xpath returns a scalar and fails here, on a record that repeats the
  # element. An Array is :many; anything else is :one.
  it "projects each field at its declared cardinality" do
    aggregate_failures do
      doc.to_h.each do |field, value|
        expect(NEU::MODS::Projection.cardinality_of(value))
          .to eq(registry[field]), "#{field} projected #{value.inspect}"
      end
    end
  end

  # A :many field with nothing to harvest must still be an Array, or a consumer
  # that maps over it breaks on exactly the records that carry the least.
  it "keeps the declared cardinality on a record carrying almost nothing" do
    aggregate_failures do
      minimal.to_h.each do |field, value|
        next unless registry[field] == :many

        expect(value).to eq([]), "#{field} projected #{value.inspect}"
      end
    end
  end
end
