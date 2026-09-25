# neu-mods developer docs

Per-component reference that has to version with the code.

## What belongs here

Explanation a developer needs *while changing a specific file*, and that is too
long to sit inside it. For neu-mods that means how each MODS area projects, and
why a projection rejected the obvious reading of the schema. It also means what
the write path promises Cerberus.

Each page names the source files it covers. Those files carry a one-line pointer
back, so you can find either from the other. The pages mirror the mixins under
`lib/neu/mods/projection/` where they can: `projection/subjects.rb` has
`subjects.md`.

## The pages

| Page | Covers |
|---|---|
| [`qualifiers-and-authority.md`](qualifiers-and-authority.md) | The display-label and href pair, the authority triple, and why they resolve differently |
| [`titles.md`](titles.md) | Primary-title selection, the faithful and the access parts, `compose_title` and the nonSort binding |
| [`names.md`](names.md) | The `display_value_w_date` port and its quirks, roles, and editable against preserved names |
| [`subjects.md`](subjects.md) | Assembled headings, the axis lists, the separator, and the typeless-name rule |
| [`dates.md`](dates.md) | The date model: every generated field, shapes, precision, ranges, keyDate, qualifiers and literals |
| [`fields.md`](fields.md) | The `FIELDS` registry, cardinality, the empty values, and adding a field |

## What belongs elsewhere

| Audience or need | Home |
|---|---|
| Installing the gem and calling it from Atlas or Cerberus | [`README.md`](../README.md) |
| A rule that code can check | a spec, not prose |
| How Atlas stores, indexes and displays the projection | Atlas's `docs/` |
| How Cerberus's edit forms write MODS | Cerberus's `docs/` |

Prefer a spec to a page whenever the claim is testable. A spec fails when
someone breaks it; a page does not. The conformance spec
(`spec/conformance_spec.rb`) is the strongest statement this gem makes: it pins
the projection Atlas produced before adopting the gem.

## Writing standard

Plain language, per ISO 24495-1:

- Put the answer first, the evidence after.
- Use the active voice, and name the actor.
- Use one term for one thing. If it is a `titleInfo` in the schema, call it a
  `titleInfo` here.
- Reference code as `path:line` so a reader can open it.
- Describe the current design and its reason. The old design lives in git.

## The density target

A source file should keep its comments under about 35% of its non-blank lines.
That is a target for prose that belongs on a page here, not a rule to satisfy by
deleting knowledge. If a comment would cost someone a bug, keep it and go over.

**Files with fewer than 25 lines of code are exempt.** Density measures comments
against code, so a file that declares rather than computes has no denominator to
earn a budget with.

To measure a file, count the non-blank lines that start with `#` against the
rest, and count `# frozen_string_literal:` and `# rubocop:` as code:

```sh
awk 'NF { if ($1 ~ /^#/ && $0 !~ /# (frozen_string_literal|rubocop):/) c++; else k++ }
     END { printf "%d comment, %d code, %.1f%%\n", c, k, 100 * c / (c + k) }' lib/neu/mods/projection/dates.rb
```

A developer can run the same count from an editor hook. Hooks are
developer-local: `.gitignore` excludes `/.claude`, so none arrives with a clone.

## Adding a page

1. Group by the thing a developer is changing, not by the class name. Several
   files that share one pipeline belong on one page.
2. Name the source files at the top of the page.
3. Leave a pointer in each source file: one line, naming this path.
4. Keep in the source file only what someone editing that specific line must
   not miss. Everything else comes here.
5. Add the page to the table above.
