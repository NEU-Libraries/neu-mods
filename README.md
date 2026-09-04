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
                   #    byte-faithful -- the edit forms pre-fill from these
doc.abstract       # => normalized, paragraph-joined String
doc.languages      # => ["English"]   a code-only <languageTerm>eng</> included
doc.topical_subjects # => ["Civil society", ...]   (every <topic>, for the access copy)
doc.keywords       # => [...]   (only the editable attribute-free keyword subjects)
doc.date_created_parts
                   # => { value:, precision:, end_value:, end_precision:,
                   #      qualifier:, key_date: }   everything the record
                   #    declared about one date. w3cdtf YYYY, YYYY-MM and
                   #    YYYY-MM-DD all parse, and the precision says which
                   #    shape it gave, so display cannot invent a month or a
                   #    day. The points are read by @point, not by document
                   #    order, and the end carries its OWN precision.
                   #    Same for date_issued_parts and copyright_date_parts;
                   #    each part is also a reader of its own, e.g.
                   #    doc.date_created_qualifier.
doc.notes          # => [{ type: "funding", value: "..." }, ...]
doc.related_items  # => [{ type: "otherFormat", title: "..." }, ...]
                   #    every relatedItem that is not a series or a host
doc.location       # => [{ physical_location:, shelf_location:, url: }, ...]
doc.map_data       # => [{ scale:, projection:, coordinates: }, ...]
doc.to_h           # => full projection, keyed to Atlas's Metadata::MODS attributes

# The field registry -- the single declaration of what this gem projects.
# name => :one or :many. to_h is derived from it, and a consumer builds its own
# schema from it rather than re-listing the field set by hand. Cardinality
# follows what MODS marks repeatable, so a field can never silently truncate.
NEU::MODS::FIELDS  # => { main_title: :one, names: :many, ... }

# Pure title composition (no document needed) — for callers that already hold
# the parts (e.g. Atlas's access-copy model) and must not re-parse XML on read.
NEU::MODS.compose_title(non_sort: "", title: "What's New",
                        part_name: "How We Respond to Disaster", part_number: "Episode 1")
# => "What's New - How We Respond to Disaster, Episode 1"   (== doc.plain_title)

# Selectors (live nodes — for editing)
node = doc.primary_title_info.at_xpath("mods:title", NEU::MODS::NAMESPACE)
node.content = "New Title" unless NEU::MODS.whitespace_equivalent?(node.text, "New Title")
doc.to_xml

# Editable creators (for an "advanced metadata" form): structured read,
# node selection (for replace-on-save), and structure-aware build.
doc.editable_personal_creators   # => [{ given:, family: }]  (plain, Creator role)
doc.editable_corporate_creators  # => [{ name: }]
doc.preserved_names              # => [{ name:, role: }]  (authority-bearing / non-Creator — read-only)
doc.editable_creator_nodes("personal")            # => live <name> nodes to replace
doc.build_personal_name(given: "Jenny", family: "Smith")      # => a plain personal <name> node
doc.build_corporate_name(name: "Northeastern University")     # => a plain corporate <name> node
```

The "editable creator" set is plain names — **no `@authority`/`@authorityURI`/
`@valueURI`** — with a **Creator** role; everything else (authority-controlled or
other-role names) is `preserved_names`, shown read-only. This mirrors the
keyword-subject curated-vs-editable split. `build_*_name`'s `role:` defaults to
`"Creator"` but is parameterised, so a later role-selectable form is non-breaking.

## Two normalizers, two jobs

- `NEU::MODS.whitespace_equivalent?` / `.canonical_ws` — the **no-op guard**: did an
  edit change anything, or only insignificant whitespace? (Used to avoid minting
  an unchanged OCFL MODS version.)
- `NEU::MODS.normalize_paragraphs` / `.normalize` — clean **curator freetext** for
  the JSON/Solr access copy (dash/smart-punctuation transliteration, control
  stripping, paragraph handling). The XML preservation copy is never touched.

Titles and prose share the one freetext vocabulary: `to_h[:main_title]` is
normalized like `abstract`, so an invisible format mark, a Windows-1252 control
or an exotic space cannot reach Solr or a display template.

**The boundary matters.** Normalization belongs on projections that only feed
display and the index. `title_parts` is deliberately *not* normalized, because
Cerberus pre-fills its Metadata and Advanced forms from it and `MODSMerge` writes
the posted value back into the MODS XML — cleaning there would rewrite the
curator's own characters in the preservation copy on the next save. Cerberus
makes the same call for prose: its editable source is the bare `<abstract>` node,
not `doc.abstract`. Add a normalized *sibling* rather than normalizing a
projection an edit form reads.

## Behavior fidelity & known caveats

The projection is **behavior-preserving** with Atlas's prior `mods`-gem-based
extraction, pinned by `spec/conformance_spec.rb` against `work-mods.xml`. Two
intentional notes:

- **Name display** reproduces the `mods` gem's `display_value_w_date` *including
  its quirks* (e.g. multiple `given` nameParts concatenate with no separator),
  to preserve existing Solr/display output. Cleanups are a deliberate future
  contract change, not a silent one.
- **Languages are translated; roles are not.** Both read the `type="text"` term
  first. A code-only `languageTerm` is then translated through the vendored ISO
  639 registry (`lib/neu/mods/data/iso639-2.txt`, from the Library of Congress),
  so `eng` projects `English`. That happens here rather than in a consumer's
  display layer because otherwise Solr indexes `eng` while the page shows
  `English`, and the language facet reads in codes.
  A code-only `roleTerm` stays raw. A MARC relator is a display *label*, and the
  label vocabulary belongs to the consumer — Cerberus's edit form and Atlas's
  display word the same role differently. An unrecognised language code also
  stays raw, since the record still said something.
- **`description` is not projected.** MODS does define `name/description`, but
  that annotates a *name*, not the resource, so it is not the field Atlas once
  called `description`. The two candidates for that one — an `abstract` variant
  and `physicalDescription/note` — describe different things. Projecting a guess
  would put wrong data in the field rather than leave an empty one, so it waits
  on a decision.
- **A date carries more than a value.** Each of `dateCreated`, `dateIssued` and
  `copyrightDate` projects a value, its precision, an end value with its own
  precision, the `@qualifier` and the `@keyDate` flag. The gem does not *pick*
  the key date, because "which date to sort on" and "which date to display" are
  not necessarily the same answer, and choosing is the consumer's job.

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
