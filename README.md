# neu-mods

Northeastern-flavored MODS v3 **projection + selection** for the DRS, shared by
[Cerberus](https://github.com/NEU-Libraries/cerberus) (front end) and
[Atlas](https://github.com/NEU-Libraries/atlas) (API backend).

It is a **Nokogiri-native, dependency-light contract over MODS documents** — pure
functions over a parsed document, nothing else. No Rails, no persistence, no
HTTP. It answers two questions:

- **"Where is X?"** — `Selectors` return *live Nokogiri nodes*, so they serve both
  the read path (projection reads their text) and the write path (an editor
  mutates the returned node in place). The node an editor changes is provably the
  node the projection reads.
- **"What does this project to?"** — `Projection` returns *plain data*
  (hashes/strings/arrays — never opaque typed objects) for indexing/display.

It depends on **Nokogiri alone** — deliberately *not* the `sul-dlss/mods` +
`nom-xml` stack (which is sunsetting alongside Stanford's move to Cocina). See
the design note in the DRS gap-reports for the full rationale.

## Usage

```ruby
require "neu-mods"

doc = NEU::MODS::Document.parse(xml_string)

# Projection (plain data)
doc.plain_title    # => "What's New - How We Respond to Disaster, Episode 1"
doc.title_parts    # => { non_sort:, subtitle:, title:, part_name:, part_number: }
doc.abstract       # => normalized, paragraph-joined String
doc.topical_subjects # => ["Civil society", ...]   (every <topic>, for the access copy)
doc.keywords       # => [...]   (only the editable attribute-free keyword subjects)
doc.to_h           # => full projection, keyed to Atlas's Metadata::MODS attributes

# Pure title composition (no document needed) — for callers that already hold
# the parts (e.g. Atlas's access-copy model) and must not re-parse XML on read.
NEU::MODS.compose_title(non_sort: "", title: "What's New",
                        part_name: "How We Respond to Disaster", part_number: "Episode 1")
# => "What's New - How We Respond to Disaster, Episode 1"   (== doc.plain_title)

# Selectors (live nodes — for editing)
node = doc.primary_title_info.at_xpath("mods:title", NEU::MODS::NAMESPACE)
node.content = "New Title" unless NEU::MODS.whitespace_equivalent?(node.text, "New Title")
doc.to_xml
```

## Two normalizers, two jobs

- `NEU::MODS.whitespace_equivalent?` / `.canonical_ws` — the **no-op guard**: did an
  edit change anything, or only insignificant whitespace? (Used to avoid minting
  an unchanged OCFL MODS version.)
- `NEU::MODS.normalize_paragraphs` / `.normalize` — clean **curator freetext** for
  the JSON/Solr access copy (dash/smart-punctuation transliteration, control
  stripping, paragraph handling). The XML preservation copy is never touched.

## Behavior fidelity & known caveats

The projection is **behavior-preserving** with Atlas's prior `mods`-gem-based
extraction, pinned by `spec/conformance_spec.rb` against `work-mods.xml`. Two
intentional notes:

- **Name display** reproduces the `mods` gem's `display_value_w_date` *including
  its quirks* (e.g. multiple `given` nameParts concatenate with no separator),
  to preserve existing Solr/display output. Cleanups are a deliberate future
  contract change, not a silent one.
- **Roles & languages** read the `type="text"` term and fall back to the **raw
  code** — they are *not* MARC-relator / ISO-639 translated. Records carrying
  text forms (the norm) are unaffected; code-only records would differ. Vendoring
  those lookup tables (or depending on `iso-639`) is deferred to keep the gem
  Nokogiri-only and small.

## Source convention

Every character-class regex in `TextNormalizer` is built **programmatically from
codepoints**, so the source stays pure ASCII (no literal smart-quotes/dashes, no
raw control bytes). A spec enforces this. Keep it that way.

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

Versioned via the `.version` file (read by `lib/neu/mods/version.rb`); released
with `bundler/gem_tasks` (`rake release`), mirroring `atlas_rb`.
