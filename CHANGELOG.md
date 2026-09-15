# Changelog

Consumers pin this gem, so a change to a projected SHAPE belongs here: Atlas
derives its access-copy attribute set and its Solr indexer from the projection,
and Cerberus pre-fills its edit forms from it. A shape change that reaches them
unannounced is one they discover as a nil value or a missing display row.

Releases before 0.14.0 are not recorded. Their diffs are in git; this file
starts where the convention does.

## 0.14.0

The projection gains the facts a consumer needs to offer a metadata value as a
browse link. Additive, but four entry shapes grow keys.

### Added

- **The vocabulary a value was taken from**, as `authority:`,
  `authority_uri:` and `value_uri:` on `names`, `origin_agents`, `languages`,
  `genres` and `subject_headings`. Resolved off the element holding the value,
  then off an enclosing `<subject>`; never off a `<role>`/`<roleTerm>`, which
  names the relator's vocabulary rather than the name's. The gem tested these
  attributes to decide editability (`Selectors#editable_creator_name?`,
  `#keyword_subject?`) and projected none of them.
- **`subject_headings[:heading]`** — the parts joined with ` -- `. The join
  moves into the gem because the composed heading is now both the string a
  display renders and the string a browse index holds; two callers joining
  independently is how those two drift apart. `parts:` stays, for the Advanced
  edit form and for a consumer wanting one step.
- **`subject_headings[:axis]`** — the MODS element the heading's main term came
  from, which is its first child carrying heading text. A consumer cannot
  derive it from `parts:`, and it is what says which browse a heading belongs
  to: `Salt marshes -- Massachusetts` is a topic heading with a place
  subdivision, not a place. A `<name>` axis splits by `@type` into
  `personal_name` or `corporate_name`.

### Changed

- **`corporate_name_subjects` now includes a `<subject><name>` with no
  `@type`.** Such a name already displayed, because `#subject_heading_part`
  never consulted `@type`, and it reached no axis, because both axis
  projections required it. Corporate rather than personal: MODS expects
  `@type="personal"` on a person, and the untyped subject names DRS holds are
  institutional. `personal_name_subjects` is unchanged.

### Not changed

- **The per-axis subject projections stay plain string arrays.**
  `topical_subjects` and its siblings carry no authority: `subject_headings`
  reports it per heading, which is what a display and a browse index both read,
  and nothing consumes a vocabulary on the flat axes.
- **The other labeled fields carry no authority either.** `format`, `extent`,
  `classification` and the rest keep `{ value:, display_label:, href: }`.
  Nothing gates on their vocabulary, and three more keys on fifteen fields is
  JSON no consumer reads.
- **No new `FIELDS` entry.** Every change above is a key on an existing entry,
  so a consumer deriving its schema from the registry needs no new column.
