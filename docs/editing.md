# Editing: the write path

Cerberus edits MODS through the same gem that reads it. An edit form changes the
node that the projection's own selector finds. So the two can never disagree
about which element holds a value.

Source files:

- `lib/neu/mods/selectors.rb` — node location, shared by read and write
- `lib/neu/mods/builders.rb` — node creation
- `lib/neu/mods/projection/name_display.rb` — `editable_creator_name?`
- `spec/creators_spec.rb`

The consumer is Cerberus's `app/services/metadata/mods_merge.rb`. It wraps the
document it is editing in `NEU::MODS::Document.new(doc)`, so selectors,
builders and serialization share one Nokogiri instance.

## What `MODSMerge` calls

| Call | Used for |
|---|---|
| `primary_title_info` | The title node to overwrite, or `nil` to create one |
| `abstract_nodes` | The abstracts to replace |
| `keyword_subjects`, `editable_creator_nodes(type)` | The editable nodes to remove before adding the posted set |
| `editable_personal_creators`, `editable_corporate_creators` | The current set, to compare with the posted one |
| `build_node`, `build_personal_name`, `build_corporate_name` | The new elements |
| `NEU::MODS.whitespace_equivalent?`, `NEU::MODS.canonical_ws` | The no-op guard ([`text-normalization.md`](text-normalization.md)) |
| `NEU::MODS::NAMESPACE` | Its own XPath |

**Every name and signature in this table is part of the contract.** Renaming
one breaks Cerberus. The builders' `role:` keyword defaults to `"Creator"`, so a
later role-selectable form is not a breaking change.

## Selectors are shared

A selector returns live Nokogiri nodes. The projection reads their text, and
`MODSMerge` changes them in place. That is why a selector must never return a
node the read path would not project from. `primary_title_info` refuses to fall
back to a variant title for this reason ([`titles.md`](titles.md)).

**Editable and curated.** The simple and advanced forms manage only the plain
elements a depositor could have typed:

- A **keyword subject** has no attributes, and every element child is a
  `<topic>`. A subject with an authority, or with any other child, is curated.
- An **editable creator** has no authority attribute, and its first role is
  Creator ([`names.md`](names.md)).

Everything else is curated and left alone. On save, `MODSMerge` removes the
editable nodes and adds the posted set, so a curated node is never touched.

## Builders

`build_node(name, text = nil)` creates an element in the document's MODS
namespace, reusing the declaration on the root, so new nodes never re-declare
`xmlns`. `build_personal_name` and `build_corporate_name` build a plain creator:
name parts and a text roleTerm, with no authority attribute, so the result reads
back as editable.

**The namespace is found by URI, not by prefix.** A document may bind MODS to
any prefix, or make it the default namespace. An element built outside the MODS
namespace is invisible to every XPath in the gem. The edit would never reach the
access copy. The next save could not find the node to replace, so each save
would add another copy. A document whose root declares no MODS namespace raises
`ArgumentError` rather than receive such an element.

## Normalization stays off the write path

A projection that an edit form reads must stay byte-faithful. `title_parts` is
not normalised, because Cerberus pre-fills its forms from it and writes the
posted value back into the preservation XML. Cleaning it would rewrite the
curator's own characters on the next save. Cerberus takes its editable abstract
from the bare `<abstract>` node, not from `abstract`, for the same reason. To
offer a cleaned value, add a normalised sibling projection.
