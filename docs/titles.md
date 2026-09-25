# Titles

A record has one primary title and any number of variants. The primary title is
projected twice: byte-faithful for the edit form, and normalised for the access
copy.

Source files:

- `lib/neu/mods/selectors.rb` — `primary_title_info`, `variant_title?`
- `lib/neu/mods/projection/titles.rb` — the parts, the variants and
  `compose_title`
- `spec/compose_title_spec.rb`

## Choosing the primary title

`primary_title_info` takes the top-level `titleInfo` with `usage="primary"`. If
no element has that, it takes the first top-level `titleInfo` that is not a
variant. It never looks inside a `relatedItem`, so a series title is never the
record's title.

**The fallback never promotes a variant.** MODS does not require
`usage="primary"`, so the fallback runs often. It also decides which node the
edit form writes to: Cerberus's `MODSMerge` overwrites the node this returns.
Promoting an alternative title would let the next title edit destroy it and
leave the record with no primary title. So when every `titleInfo` is a variant,
the answer is `nil`. `MODSMerge` creates a proper primary `titleInfo` from `nil`,
and each variant still reaches a reader under its own field.

Any `@type` marks a variant. MODS enumerates the type as exactly `abbreviated`,
`translated`, `alternative` and `uniform`, all of them variants. Treating any
value as a variant also keeps a misspelled type out of the write path.

**Two unmarked, untyped titles.** When a record carries two untyped `titleInfo`
and marks neither, the first wins and the second reaches no field.

That follows the schema. `@usage` exists to nominate the principal title, and `@type` is
closed. MODS 3.5 gives a legitimate second untyped title an `@altRepGroup` (one
title in two scripts) or an `@otherType`. An unmarked duplicate carries none of these,
so MODS gives it no meaning to preserve. It stays in the preservation XML.

## Faithful parts and access parts

| Method | Normalised | Used by |
|---|---|---|
| `title_parts` | No. Absent parts are `nil` | Cerberus's edit forms (`MODSFields`, `load_advanced!`) |
| `access_title_parts`, alias `main_title` | Yes, through `TextNormalizer.normalize`. Absent parts are `""` | The access copy, Solr and every display |

`title_parts` is faithful on purpose. Cerberus pre-fills its forms from it, and
`MODSMerge` writes back what the form posts. Normalising here would rewrite the
curator's characters in the preservation XML on the next save.

`access_title_parts` normalises every part like the abstract. A curly quote, an
invisible format mark or a Windows-1252 control then cannot reach Solr or a
display template. Titles and prose share one vocabulary. The variant titles, the
subject titles and the titles inside a subject heading all go through
`composed_title_of`, which normalises the same way.

`main_title` is the registry name Atlas uses, and `access_title_parts` says what
it returns. Both names stay.

`main_title_display_label` is the header the record asks for on the title row.
It is rarely set, but "Title" is otherwise the one header a curator could never
change.

## Composing a title

`Titles.compose_title` turns a parts hash into one display string. It needs no
document, so a caller that already holds the parts, such as Atlas's access-copy
model, composes the title without parsing XML. It is exposed as
`NEU::MODS.compose_title` and `Projection.compose_title`, and `plain_title` is
the same composition over the primary title.

The order is nonSort, title, subTitle, partName, partNumber. The librarians
chose it. `titleInfo` is an unordered choice in the schema, so there is no
document order to follow.

| Part | Separator before it |
|---|---|
| subTitle | `": "` |
| partName | `". "` |
| partNumber | `". "` |

The separator travels with its part, so a record giving only a partNumber still
gets the period. Nothing follows the last part. A title is a value, not a
sentence, and a trailing period reads as part of the title everywhere it is
reused. A record with no title composes to `""`.

## Binding the nonSort

MODS says a nonSort carries whatever separator it needs, which suggests plain
concatenation. That relies on an authored trailing space surviving, and it does
not: `child_text` canonicalizes whitespace, so `<nonSort>The </nonSort>` arrives
as `"The"`. `join_non_sort` composes the space instead, so the output is right
whether or not the source kept one. An invisible trailing space is not something
a curator, a hand edit or another producer can be relied on to keep.

A nonSort ending in a space is joined as it is, so a caller that passes the
space (Atlas's access-copy model) gets the same result. A nonSort ending in a
binding character takes no space: an elided article gives "L'Etranger", and a
hyphenated prefix binds the same way. The binding characters are `'`, U+2019
and `-`.
