# Text normalization

The gem has two text cleaners with different jobs. `Canonicalize` decides
whether an edit changed anything. `TextNormalizer` cleans curator text for the
access copy. Neither ever touches the preservation XML.

Source files:

- `lib/neu/mods/canonicalize.rb` — the no-op guard
- `lib/neu/mods/text_normalizer.rb` — the access-copy cleaner
- `lib/neu-mods.rb` — the `NEU::MODS.*` delegators for both
- `spec/canonicalize_spec.rb`

## The no-op guard: `Canonicalize`

`canonical_ws` folds U+00A0 (no-break space) to a space, collapses every
whitespace run to one space, and strips the ends. Ruby's `\s` does not match
U+00A0, so the fold comes first. `whitespace_equivalent?` compares two values
after that, and Cerberus's `MODSMerge` uses it to skip a save that would mint
an unchanged OCFL version of the MODS.

`canonical_lines` does the same per line and keeps the line breaks, dropping
blank lines. `table_of_contents` uses it, because there a newline separates one
entry from the next.

Most projected fields read their text through `canonical_ws`, by way of `clean`
and `child_text` in `projection/support.rb`.

## The access-copy cleaner: `TextNormalizer`

`TextNormalizer` is a port of Atlas's `TextNormalizer`, which carries DRS v1
prior art, so the gem reproduces Atlas's projection byte for byte. It has two
entry points:

| Method | For | Newlines |
|---|---|---|
| `normalize` | Single-line fields: every title part | Become spaces |
| `normalize_paragraphs` | Prose: the abstract and the access conditions | Two or more become one paragraph break; one becomes a space |

Both run the same pipeline, in this order:

1. Force UTF-8 and drop invalid bytes.
2. Apply Unicode NFC.
3. Map Unicode dashes to `-`. U+2053 (swung dash) maps to `~` instead, as in v1.
4. Transliterate the General Punctuation block (U+2000–U+206F) to ASCII: smart
   quotes, the ellipsis, bullets and so on. Invisible, bidirectional and format
   marks map to nothing, so they cannot leak into the access copy. A codepoint
   the table does not list passes through.
5. Map U+000B and U+000C to a newline.
6. Drop U+00AD (soft hyphen) and the other C0 and C1 controls. Tab and newline
   stay.
7. Collapse runs of horizontal whitespace to one space, and strip.

### Why some characters map where they do

- **Vertical tab and form feed become a newline.** Word writes a manual line
  break as U+000B and a page break as U+000C. Deleting one would run the words
  on either side together. As a newline, `normalize_paragraphs` reads it as the
  soft wrap it was, and `normalize` turns it into a space.
- **The soft hyphen is dropped, not made a hyphen.** It marks where a word may
  break and renders as nothing. Solr discards it, so `co<U+00AD>operation` already
  matches "cooperation". A real hyphen would index "co" and "operation" as two
  tokens.
- **Carriage return is dropped**, which reduces a CRLF line ending to the one
  newline it stands for.

### The source stays ASCII

Every character class is built from codepoint lists through
`char_class`, which writes `\uXXXX` escapes. No literal smart quote, dash or
control byte appears in the Ruby source. A spec checks every file under `lib/`
for non-ASCII bytes. The ISO 639 registry lives in a data file for the same
reason: its English names are not ASCII.

## Where each cleaner applies

Normalization belongs only on projections that feed a display and the index.
Any projection an edit form reads must stay faithful, or saving the form would
rewrite the curator's characters in the preservation XML
([`editing.md`](editing.md)).

| Text | Cleaned by |
|---|---|
| Title parts in `main_title`, the variant titles, subject titles | `normalize` |
| `abstract` and the three access-condition fields | `normalize_paragraphs` |
| `title_parts`, for the edit form | Nothing beyond `canonical_ws` |
| Every other projected string | `canonical_ws` |

## Two definitions of whitespace

The two cleaners disagree about what whitespace is. `canonical_ws` folds Ruby's
`\s` and U+00A0 only. `TextNormalizer` also folds the typographic spaces, such
as U+2003 (em space), U+202F and U+3000.

So an em space survives in a note or an identifier, and does not survive in a
title. The string `a`, em space, `b` is 5 bytes after `canonical_ws` and 3 bytes
after `normalize`.

**This is an open question, and the code does not settle it.** It may be
intended. The no-op guard should not start treating an em space as
insignificant without a decision, because that changes which edits count as
changes. Do not unify the two definitions as a side effect of other work.
