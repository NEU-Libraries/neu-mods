# Subjects

Every top-level `<subject>` projects twice: as one assembled heading, and as its
parts pooled into one list per axis. The heading keeps what a cataloguer
grouped; the axis lists serve a facet.

Source files:

- `lib/neu/mods/projection/subjects.rb`
- `lib/neu/mods/selectors.rb` — `keyword_subjects`, the set the simple edit form
  manages

## Assembled headings

`subject_headings` returns one entry per `<subject>`:

| Key | Holds |
|---|---|
| `parts` | The heading's parts, in document order |
| `heading` | The parts joined with `HEADING_SEPARATOR` |
| `axis` | The MODS element the heading's main term came from |
| `authority`, `authority_uri`, `value_uri` | The vocabulary, off the main term, then off the `<subject>` |
| `display_label`, `href` | The qualifiers of the `<subject>` |

A pre-coordinated heading such as "Salt marshes--Massachusetts--20th century" is
one statement. The axis lists cannot say which parts belonged together. They
pool every topic on the record, so a fragment of a heading and a whole heading
read alike there.

**The join happens here, not in a consumer.** The composed heading is both the
string a display renders and the string a browse index holds. Two callers
joining independently is how those drift apart. `HEADING_SEPARATOR` is
`" -- "`, the separator DRS has always displayed, and Atlas reads it as
`Projection::HEADING_SEPARATOR`.

`axis` is the first child that carries heading text, reported as its element
name in snake case: `topic`, `geographic`, `hierarchical_geographic`. A consumer
cannot derive it from the parts, which are bare strings. It says which browse a
heading belongs to: "Salt marshes -- Massachusetts" is a topic heading with a
place subdivision, not a place. The browse vocabulary itself stays with the
consumer.

### How each child becomes parts

| Child | Parts |
|---|---|
| `name` | One part, composed through the name port ([`names.md`](names.md)) |
| `titleInfo` | One part, composed and normalised like a title ([`titles.md`](titles.md)) |
| `hierarchicalGeographic` | One part per level, so the place reads as steps of the heading |
| `cartographics`, `geographicCode` | None. One is a coordinate, and the other is a MARC code |
| Anything else | The text, split on `--` |

A cataloguer who typed a whole heading into one element as "A--B--C" made the
same statement as one who structured it into siblings. Splitting on `--` gives
both the same parts.

### Names with no type

A `<subject><name>` with no `@type` reaches the **corporate** axis, and its
heading axis is `corporate_name`. The heading composes such a name either way.
Without this rule it would be a heading a reader sees and no browse holds.
Corporate rather than personal, because MODS expects `@type="personal"` on a
person, and the untyped subject names DRS holds are institutional.

## The axis lists

| Field | Reads |
|---|---|
| `topical_subjects` | Every `topic` under any subject |
| `geographic_subjects`, `temporal_subjects`, `occupation_subjects`, `genre_subjects` | The child of that name |
| `personal_name_subjects`, `corporate_name_subjects` | Names, composed like top-level names |
| `title_subjects` | Titles, composed like the main title |
| `geographic_code_subjects` | MARC GAC codes, as written |
| `hierarchical_geographic_subjects` | `{ continent:, country:, ..., area: }`, one key per level |
| `map_data` | `{ scale:, projection:, coordinates: }` from `cartographics` |

These cover every child a `<subject>` can hold. Cerberus's IPTC ingest writes
`subject/geographic` from the IPTC City and State fields on every batch, so that
axis carries real data.

A GAC code stays a code. Turning it into a place name needs a lookup table, and
the label vocabulary belongs to the consumer, as it does for MARC relators.

`hierarchical_geographic_subjects` and `map_data` stay structured. A consumer
that wants the city alone should not have to take apart "United States -- New
York (State) -- Parksville". The same
holds for scale and coordinates. The eleven levels follow the schema's order,
broadest first. Some records use `hierarchicalGeographic` instead of
`subject/geographic`, so this is the only place they state a place.

`cartographics` carries neither qualifier attribute, so `map_data` takes the
enclosing `<subject>`'s.

## Keywords

`keywords` is the free-text set Cerberus's simple form edits: the topics under
`keyword_subjects`. A keyword subject has no attributes, and every element child
is a `<topic>`. A subject with an authority, or with any other child, is curated
and left alone. `topical_subjects` is different: it harvests every topic for the
access copy.
