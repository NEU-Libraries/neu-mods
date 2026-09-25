# The field registry

`FIELDS` is the one declaration of what this gem projects. Every other list of
fields — `to_h`, Atlas's `Metadata::MODS` attribute set, this page — is derived
from it or checked against it.

Source files:

- `lib/neu/mods/projection.rb` — `FIELDS`, `to_h`, `cardinality_of`
- `lib/neu-mods.rb` — `NEU::MODS::FIELDS`, the top-level name consumers use
- `spec/fields_spec.rb` — the checks that make the registry more than a comment

## One row per field

A row maps a field name to its cardinality, `:one` or `:many`. The projection
method of the same name owns the XPath; the row says the field exists and
whether it holds one value or a list.

`to_h` calls every row's method through `public_send`, in registry order. Atlas
builds its `attr_json` set from the same rows, so a field cannot be projected
here and go undeclared there, or the reverse. That also means **a method name is
part of the contract**: renaming one renames a column in Atlas.

The 63 date rows are generated. `Dates::DATE_FIELD_ROWS` holds them, and
[`dates.md`](dates.md) lists every one.

## Cardinality

Cardinality is the half of the row that earns its keep. The choice between
`at_xpath` and `xpath` in a projection, and between a scalar and an array column
in Atlas, must agree. A repeatable MODS element read with `at_xpath` loses every
match after the first, and nothing else notices.

`fields_spec.rb` projects `spec/fixtures/coverage-mods.xml`, which repeats the
repeatable elements it carries, and checks each value with `Projection.cardinality_of`: an `Array` is `:many`, and
anything else is `:one`. A field declared `:many` that still uses `at_xpath`
fails there. A second example checks that every `:many` field is `[]`, not
`nil`, on a record that carries almost nothing.

## Empty values

| Field | Absent value |
|---|---|
| Every `:many` field | `[]` |
| `abstract`, `access_condition`, `use_and_reproduction`, `restriction_on_access` | `""`, because each joins its elements' paragraphs into one string |
| `main_title` | A parts hash whose parts are all `""` |
| Every other `:one` field | `nil` |

Inside an entry, an absent key is `nil`. An entry whose every value is absent
drops out of its list rather than arriving as a hash of `nil`s.

## Adding a field

1. Write the projection method in the mixin for its MODS area, under
   `lib/neu/mods/projection/`.
2. Add a row to `FIELDS`, in the group for that area.
3. Add the element to `spec/fixtures/coverage-mods.xml` if the fixture does not
   carry it, repeated if MODS lets it repeat.
4. Tell Atlas. A plain string field needs no change there, because Atlas
   derives its attribute from the row. A field whose values are hashes, dates or
   booleans also needs a type in Atlas's `Metadata::MODS::TYPES`.

## Names reached through `Projection`

A module method does not travel with `include`, so a method defined on an area
mixin, such as `Titles.compose_title`, is not callable as
`Projection.compose_title`. Atlas calls `Projection.fold_type` and
`Projection::HEADING_SEPARATOR` by those names, so `projection.rb` keeps a
delegator for each area module method. `spec/consumer_references_spec.rb` pins
every such name.
