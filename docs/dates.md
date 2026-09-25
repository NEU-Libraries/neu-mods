# Dates

Each of the seven `originInfo` date elements projects nine flat fields. They
hold the value, its precision, the end of a range, and what the record said
about it. A date is not a scalar, and a preservation repository must not project a
value the record did not give.

Source files:

- `lib/neu/mods/projection/dates.rb`
- `spec/document_spec.rb`, `spec/projection_coverage_spec.rb`

## The generated fields

The accessors are generated from two tables in `dates.rb`, so a search for
`def date_issued_end` finds nothing. Search `DATE_FIELDS` for the prefix and
`DATE_KEYS` for the suffix. Every field is `:one` in `FIELDS`.

| Prefix | MODS element |
|---|---|
| `date_created` | `dateCreated` |
| `date_issued` | `dateIssued` |
| `copyright_date` | `copyrightDate` |
| `date_captured` | `dateCaptured` |
| `date_valid` | `dateValid` |
| `date_other` | `dateOther` |
| `date_modified` | `dateModified` |

| Suffix | Holds |
|---|---|
| (none) | The start value, as a `DateTime` |
| `_precision` | `"year"`, `"month"` or `"day"` |
| `_end` | The end value of a range, as a `DateTime` |
| `_end_precision` | The end value's own precision |
| `_qualifier` | `@qualifier`, from the start, else the end |
| `_key_date` | `true` when any node of the element carries `keyDate="yes"` |
| `_text` | The literal, when the start is not a readable date |
| `_display_label` | `@displayLabel` of the enclosing `originInfo` |
| `_event_type` | `@eventType` of the enclosing `originInfo` |

Every prefix takes every suffix, which gives 63 fields: `date_created`,
`date_created_precision`, `date_created_end` and so on to
`date_modified_event_type`. Each element also has a `*_parts` method that
returns the whole entry as one hash. `date_created_with_precision`,
`date_issued_with_precision` and `copyright_date_with_precision` return
`[value, precision]` for a caller that wants just those two.

To add a date part, add a `DATE_KEYS` row and the matching key in `date_entry`.
To add a date element, add a `DATE_FIELDS` row and add the element to
`DATE_ELEMENTS`. A spec checks that the two lists hold the same elements.
`DATE_ELEMENTS` keeps its own order, the one a place header reads, because
`origin_date_elements` returns elements in that order.

### Why flat fields

The value has three consumers that need a real date object: a Solr sort key, a
citation year and an OAI date. A nested value would make each unpick it. The
same three are why the literal has its own field. A sort key cannot hold
"ca. 1920", and a display can.

### What the elements mean

`dateCaptured` is when the object was digitised, and `dateModified` is when the
resource changed. Both are preservation and cataloguing provenance. A consumer
may keep them off a page, but cannot recover them from anywhere else.
`dateValid` is the period the content holds for. `dateOther` holds a date that
fits no other element, which is where much migrated v1 date data sits.

## Reading one date

### Which node is the date

`date_parts` reads every node of the element and picks them by attribute, not
by position. A record may write `point="end"` first.

1. The start is the node flagged `keyDate="yes"` that is not an end point. The
   flag is the record nominating its own principal date. Reading the value from
   another node would make the flag and the value contradict each other.
2. Otherwise, the start is the node with `point="start"`.
3. Otherwise, the start is the first node that is not an end point.
4. The end is the first node with `point="end"`.

**One date per element.** A range is one date with two ends, which `@point`
models. A repeated date of the same element that is neither ranged nor flagged
is discarded, because every consumer of the value holds exactly one. A
repeated publisher survives because `publication_information` is `:many`.

### The shapes a value may take

A value is read only if it matches a declared shape. The shape also gives the
precision, so the precision is read from the record rather than guessed after
the parse.

| Shape | Example | Precision |
|---|---|---|
| Year | `1920` | `year` |
| Year and month | `1935-06` | `month` |
| Full date | `1935-06-14` | `day` |
| Full date and time | `2026-03-01T10:00:00Z` | `day` |

A timestamp goes through `DateTime.parse`, so the time of day a `dateModified`
states survives. Its precision is `day`, the finest a consumer renders.

The ISO 8601 basic form (`19350614`) is read **only** where the record declares
`@encoding="iso8601"`. The encoding matches with case and hyphens ignored, so
`ISO-8601` counts. Eight bare digits are a date only because the encoding says
so; an accession number is eight digits too.

**Anything else is not a date.** Ruby's `DateTime.parse` fills in what it cannot
find from the current date. The v1 corpus carries "19uu", the standard MARC 008
fill, at scale. That would parse as today at `day` precision. So the value
is `nil`, and the record's literal survives in `_text`. "ca. 1920", "19th
century" and "1918-1921" are all real statements a cataloguer made. The gem
must neither invent a date for them nor delete them.

A value in a valid shape that names an impossible date, such as `2026-13` or
`2026-02-30`, is also `nil` with its literal kept.

Only the start's literal is kept. The corpus writes an unreadable date as one
element, and no record needing a literal on its end point has been seen.

### Range ends and qualifiers

The end carries its own precision. A range from "1935-06" to "1940" is legal.
Giving the end the start's precision would claim a month the end never stated.

The qualifier falls back from the start to the end, because v1's loader applied
it to both points. A record marking only one is still saying the date is
uncertain. MODS enumerates `approximate`, `inferred` and `questionable`, and an
unrecognised value survives as it is.

`_display_label` and `_event_type` come off the enclosing `originInfo`, because
MODS puts both there. A date row is headed by its element, such as "Date
created", and these two attributes are how a record overrides that.

### An absent element

When the record has no node of the element, every field is `nil`, including
`_key_date`. That tells an absent date apart from one that is present and
unreadable, which has a `_text` and a `_key_date` of `false`.
