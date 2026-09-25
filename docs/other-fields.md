# Other fields

The MODS areas that are too small for a page of their own. Each section says
what the area projects and the rules that are not obvious from the code.

Source files:

- `lib/neu/mods/projection/origin_info.rb`
- `lib/neu/mods/projection/physical_description.rb`
- `lib/neu/mods/projection/access.rb`
- `lib/neu/mods/projection/related_items.rb`
- `lib/neu/mods/projection/identifiers.rb`
- `lib/neu/mods/projection/languages.rb`, `lib/neu/mods/language_codes.rb`

Two rules from [`qualifiers-and-authority.md`](qualifiers-and-authority.md)
run through every section. A labeled value is `{ value:, display_label:, href: }`.
Its header comes from the element MODS puts `@displayLabel` on, which is often a
parent.

## Origin information

`originInfo` repeats, and so do `publisher` and `edition` within one block. So
`publication_information`, `edition`, `issuance` and `frequency` are lists of
labeled values. Each takes its qualifiers off the enclosing `originInfo`, and
adds that block's `@eventType` as `event_type`. MODS puts both attributes on the
block, never on its children. The librarians asked that `@eventType` head a
block that states no `@displayLabel`. Cerberus's IPTC ingest writes the
publisher from the IPTC Source field on every batch.

A frequency's `@authority` is not projected. The gem reads authority only where
a consumer gates a browse link on it.

### Places

`place_of_publication` prefers each place's `type="text"` placeTerm and falls
back to a coded one. Each entry also carries `date_elements`, the names of the
date elements in the same block. A place is headed "Creation place" or
"Publication place" by the date beside it, and the place itself says nothing
about the event. Which dates are present is data. The header wording is display
policy and stays with the consumer.

**A bare `marccountry` code drops.** "mau" is not a place name, and it would
reach the display and the Solr places facet beside Boston. A code under any
other authority survives, because there the code may be the only statement the
record made. Expanding `marccountry` codes needs a vendored registry, like the
one `LanguageCodes` uses. That is a recorded `TODO:` in the code.

### Agents

`origin_agents` reads `originInfo/agent` (MODS 3.8), the name of who performed
the event the block records. It composes through the name port
([`names.md`](names.md)), so a publisher recorded as an agent reads the way a
creator does and carries its roles. Its entry adds the block's `event_type`.

## Physical description, genre and notes

| Field | Reads | Header from |
|---|---|---|
| `resource_type` | `typeOfResource` | The element |
| `genres` | `genre`, with the authority triple | The element |
| `target_audience` | `targetAudience` | The element |
| `format`, `extent`, `digital_origin`, `reformatting_quality`, `physical_description_notes` | The child of `physicalDescription` | `physicalDescription` |
| `notes` | Top-level `note`, as `{ type:, value: }` plus the pair | The element |
| `table_of_contents` | `tableOfContents` | The element |

All are lists. MODS repeats `typeOfResource` and `physicalDescription`, and
`form` and `extent` within one, so a record can be both text and a still image.

`genres` is the one labeled field that carries its vocabulary, because a genre
is a browse axis. Nothing gates on the vocabulary of the others.

A top-level note keeps its `@type`, because the type changes what the note
means: a "statement of responsibility" is not a "funding" note. A note inside
`physicalDescription` is about the object, such as "Scanned at 600 dpi". Nothing
turns on its type, so it is a labeled value like its siblings.

`table_of_contents` keeps its line breaks, through `canonical_lines`. A legacy
contents list separates its entries by newline, so there the break is the
structure. Blank lines drop, and a "--"-separated list is unaffected.

## Abstract and access conditions

| Field | Joins |
|---|---|
| `abstract` | Every top-level `abstract` |
| `access_condition` | Every top-level `accessCondition`, whatever its type |
| `use_and_reproduction` | Those typed "use and reproduction" |
| `restriction_on_access` | Those typed "restriction on access" |

Each joins its elements' paragraphs into one string, normalised through
`TextNormalizer.normalize_paragraphs` ([`text-normalization.md`](text-normalization.md)).
Each has `_display_label` and `_href` companion scalars. A licence URI belongs
beside the licence text a reader is given.

**The two typed fields exist so a restriction is never shown as a licence.**
That is the one mistake in this area that misinforms a reader about their
rights, rather than hiding a field.

`@type` is an open string, and records write "Use and Reproduction",
"useAndReproduction" and "restriction-on-access" as readily as the MODS casing.
So the type matches on a folded key, `Access.fold_type`, which keeps letters and
digits only and lower-cases them. Atlas calls it as `Projection.fold_type`. A
type that still matches neither falls through to `access_condition` alone. That
is why `access_condition` exists: it is the only field that carries an untyped
or unrecognised condition.

The companions read the same node set as their text, so a header can never come
from a different element than the value it heads.

## Related items

| Field | Reads |
|---|---|
| `related_series` | The titles of `relatedItem[@type='series']`, as labeled values |
| `host_collections` | Each host's title plus this work's `part` within it |
| `related_items` | Every other `relatedItem` with a title, as `{ type:, title: }` plus the pair |

`related_items` covers `constituent`, `otherFormat`, `original`, `preceding`,
`succeeding`, `isReferencedBy`, `reviewOf` and untyped items (a `nil` type). The
type is kept because "the print edition" and "reviewed in" are different
relationships, and the title alone cannot say which.

### The host part

A host entry holds the host's title and **this work's position in it**. The
host's own name, `originInfo` and identifier stay out. They belong to the other
record, and a copy here would go stale when that record is edited. The part is
the exception, because a volume, issue and page range describe this article and
no other record holds them. An entry survives on its part alone, and how to
render a titleless host is the consumer's choice.

| Key | Holds |
|---|---|
| `volume`, `issue` | The `number` of that `detail` type |
| `start_page`, `end_page` | The extent with `unit="page"` or no unit, since `@unit` is optional |
| `date` | The article's date within the host |
| `text` | The part's free text |
| `details` | Every other `detail`, as `{ type:, number:, caption:, title: }` |
| `extents` | Every extent in another unit, as `{ unit:, start:, end:, total:, list: }` |

Absent keys are left out. The part stays in pieces rather than being composed
into "24(3), pp. 210-218", because citation punctuation is display policy.
`detail/@type` and `extent/@unit` are open strings, so the other details and
extents arrive structured. A detail's `caption` is the label a cataloguer wrote
for its number ("chap."), and an extent's unit is what gives its numbers
meaning.

## Identifiers, classification, location and record info

`identifiers` is `{ type:, value:, invalid: }` plus the pair. A DOI, an
accession number and a collection id cannot be told apart from their digits. A
display needs the type to decide whether to link one. `invalid` is `true`
when `@invalid="yes"`, which in MODS means cancelled, superseded or wrong. A
dead ISBN must not read like a live one.

`permanent_url` is the text of the `hdl` identifier, or `nil`.
`permanent_url_display_label` is its `@displayLabel`, which Atlas's MODS template
sets to "Permanent URL". It has no href companion, because the value is the URL.

`classification` is an LCC or DDC call number. It is not Atlas's
`classification_ssim`, which holds a FileSet content-type vocabulary. The names
collide by accident, so a consumer has to pick a free Solr field.

`location` is `{ physical_location:, shelf_location:, url: }` plus the pair. A
shelf mark and a URL are different kinds, and a consumer must know which it
holds before it links one. The shelf mark is read from `shelfLocator`; MODS has
no `shelfLocation` element.

`record_info` is one hash of `recordInfo`'s children: content source, origin,
description standard, creation and change dates, and language of cataloguing.
It describes the cataloguing, not the resource. It is one value although the
schema repeats the element, because no record has two cataloguing provenances.
A consumer may never display it, but a preservation repository does not drop a
provenance statement on read.

## Languages

`languages` is `{ term:, object_part:, script: }` plus the authority triple and
the pair, one per `language` element.

- **The term** prefers the `type="text"` languageTerm. A code-only term is
  translated through the vendored ISO 639-2 registry, so `eng` projects
  "English". The translation happens here, so Solr and the display hold the
  same value and the language facet does not read in codes. An unrecognised code
  survives as itself.
- **`object_part`** changes the claim. `<language objectPart="subtitles">`
  says the subtitles are Spanish, not the resource.
- **`script`** prefers the text scriptTerm and is never translated. The ISO
  15924 list is not vendored, and a half-translation would be worse than what
  the record wrote.
- **The authority** comes off the languageTerm the term was read from, never
  off the `language` around it. MODS puts `@authority` on the term.

`lib/neu/mods/language_codes.rb` explains the registry and its source.
