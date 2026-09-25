# neu-mods

The MODS v3 reading contract for Northeastern's DRS, shared by
[Cerberus](https://github.com/NEU-Libraries/cerberus) (front end) and
[Atlas](https://github.com/NEU-Libraries/atlas) (API backend).

It is pure functions over a parsed MODS document, with no Rails, no persistence
and no HTTP. It depends on Nokogiri alone, not on the `sul-dlss/mods` and
`nom-xml` stack. It answers two questions:

- **"Where is X?"** `Selectors` return live Nokogiri nodes. They serve the read
  path and the write path, so the node an editor changes is the node the
  projection reads.
- **"What does this project to?"** `Projection` returns plain data: hashes,
  strings and arrays, for indexing and display.

## Installation

```ruby
# Gemfile
gem "neu-mods"
```

The gem needs Ruby 3.0 or later.

## Usage

```ruby
require "neu-mods"

doc = NEU::MODS::Document.parse(xml_string)

# Projection: plain data
doc.to_h           # => every field in NEU::MODS::FIELDS
doc.plain_title    # => "What's New. How We Respond to Disaster. Episode 1"
doc.title_parts    # => { non_sort:, subtitle:, title:, part_name:, part_number: }
doc.names          # => [{ name: "Cohen, Daniel J.(Daniel Jared), 1968-", roles: ["Creator"], ... }]
doc.subject_headings
                   # => [{ parts: [...], heading: "Salt marshes -- Massachusetts",
                   #      axis: "topic", authority: "lcsh", ... }]
doc.date_issued    # => a DateTime or nil, beside date_issued_precision, _end, ...

# The field registry: field name => :one or :many
NEU::MODS::FIELDS  # => { main_title: :one, names: :many, ... }

# Title composition over parts a caller already holds, with no XML
NEU::MODS.compose_title(title: "What's New", part_name: "How We Respond to Disaster",
                        part_number: "Episode 1")
# => "What's New. How We Respond to Disaster. Episode 1"

# Selectors: live nodes, for editing
node = doc.primary_title_info.at_xpath("mods:title", NEU::MODS::NAMESPACE)
node.content = "New Title" unless NEU::MODS.whitespace_equivalent?(node.text, "New Title")

# Builders: new nodes in the document's MODS namespace
doc.doc.root.add_child(doc.build_corporate_name(name: "Northeastern University"))
doc.to_xml
```

What each field holds, and why, is documented per MODS area in
[`docs/`](docs/README.md). Start with [`docs/fields.md`](docs/fields.md).

## Behavior fidelity and known caveats

The projection preserves the output of Atlas's earlier `mods`-gem-based
extraction. `spec/conformance_spec.rb` pins it against `work-mods.xml`, so a
change to what the gem projects is a deliberate contract change.

- **Name display reproduces the `mods` gem's `display_value_w_date`, quirks
  included.** For example, two `given` name parts join with no separator. This
  preserves Atlas's Solr and display output. A cleanup would be a contract
  change. See [`docs/names.md`](docs/names.md).
- **Languages are translated; roles are not.** A code-only `languageTerm` is
  read through the vendored ISO 639 registry, so `eng` projects "English", and
  Solr and the page agree. A code-only `roleTerm` stays raw, because a MARC
  relator is a display label and each consumer words it differently. An
  unrecognised language code also stays raw.
- **`description` is not projected.** MODS `name/description` annotates a name,
  not the resource. The two candidates for a resource description, an
  `abstract` variant and `physicalDescription/note`, describe different things.
  A guess would put wrong data in the field, so it waits on a decision.
- **A date carries more than a value.** Each of the seven `originInfo` date
  elements projects its value, precision, range end, qualifier, key-date flag,
  literal text and block header. The gem does not choose which date to sort on
  or display; that is the consumer's call. See [`docs/dates.md`](docs/dates.md).

## Development

```sh
bundle install
bundle exec rake    # specs, then rubocop
```

The version lives in `.version`, which `lib/neu/mods/version.rb` reads. Release
with `bundler/gem_tasks` (`rake release`).
