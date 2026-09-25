# Names

A top-level `<name>` projects in one of three ways:

- a composed display entry, for the access copy
- structured parts, for the edit form
- a read-only entry, for a name the form does not manage

Source files:

- `lib/neu/mods/projection/name_display.rb` — the display-value port, roles,
  and the editable predicate
- `lib/neu/mods/projection/names.rb` — `names`, `name_entry`, the editable and
  preserved sets
- `spec/creators_spec.rb`, `spec/conformance_spec.rb`

Subject names ([`subjects.md`](subjects.md)) and origin agents
([`other-fields.md`](other-fields.md)) compose through the same port, so one
person reads the same wherever they appear.

## The display value

`name_display_value_w_date` is a faithful port of the `mods` gem's
`display_value_w_date`, quirks included. Atlas's Solr and display output came
from that gem, and the conformance spec pins it. A cleanup would be a
deliberate contract change.

1. A non-blank `displayForm` wins.
2. A `personal` name composes "family, given", or whichever of the two it has.
   Terms of address follow: the first after a space, the rest after a comma.
3. Any other name, or a personal name with neither family nor given, joins its
   non-date parts with a space.
4. Each date part is appended after ", ", unless the value already ends with it.

**Quirk: parts of one type join with no separator.** The `mods` gem joined
same-typed parts through `NodeSet#text`, so two `given` parts become "A.(B)".
The port does the same.

Every part is whitespace-canonicalized before composition, so the separators the
port adds are the only whitespace in the result. A pretty-printer's indented
`<namePart>\n  Doe\n</namePart>` would otherwise compose as "Doe ,  John", and no
outer strip can reach the spaces around the comma.

An `alternativeName` (MODS 3.7) is a second form of the same name. It composes
with the **enclosing** name's `@type`, because it carries `@altType` rather than
`@type`. Read from its own attributes, an alternative for a personal name would
compose as "Doe Jane" beside a main name of "Doe, Jane".

## Roles

A name's roles are every `<role>` it carries, because a cataloguer who records
that a person both wrote and edited a work means both. Each role prefers its
`type="text"` roleTerm and falls back to the raw code. **A MARC relator code is
not translated.** It is a display label, and the label vocabulary belongs to
each consumer: Cerberus's edit form and Atlas's display word the same role
differently.

## The entry

`name_entry` returns `name`, `roles`, `affiliation`, `usage`,
`alternative_names`, the authority triple and the qualifier pair.

- `affiliation` is how a reader tells one J. Doe from another. It repeats in
  the schema, so it is a list. It sits on the entry, so a consumer cannot pair a
  name with the wrong affiliation.
- `usage` is `"primary"` or `nil`. The schema fixes `@usage` to `primary` to
  nominate the principal name. Without it, a consumer grouping names that have
  no role can only guess which leads.
- The authority is read off the `<name>` alone. A `marcrelator` roleTerm inside
  it says what the person did, not which list the name came from (see
  [`qualifiers-and-authority.md`](qualifiers-and-authority.md)).

`names` drops a name with no name text. A `<name>` carrying only a role would
otherwise project `{ name: nil, roles: ["edt"] }`, which a display renders as a
labelled empty row. `preserved_names` keeps such a name, because that list tells
a curator what the XML holds. An element they need to fix has to stay visible.

## Editable and preserved names

The edit form manages **plain creators**: names with no authority attribute
and a Creator role. `editable_creator_name?` decides. `editable_creator_nodes`
(in `Selectors`) uses it to find the nodes to replace on save, and the
`editable_*_creators` projections use it to pre-fill the form. Every other name
is in `preserved_names`, shown read-only.

| Method | Returns |
|---|---|
| `editable_personal_creators` | `[{ given:, family: }]`, with `""` for a blank part so the form renders an empty input |
| `editable_corporate_creators` | `[{ name: }]` |
| `preserved_names` | `name_entry` for every name the form does not manage |

**Only the first role decides.** `name_role` is the first declared role, not
"any role is Creator". Widening it would hand the form a name whose other roles
it cannot represent, and saving would drop them from the preservation XML.

**A blank authority attribute is no authority.** The predicate reads the
authority attributes through `attr_value`, as `authority_of` does, so
`authority=" "` counts as absent in both. A name the projection reports as
uncontrolled is always one the form can edit.
