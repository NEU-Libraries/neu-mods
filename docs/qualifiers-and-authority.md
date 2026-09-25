# Qualifiers and authority

Two sets of attributes ride along with a projected value, and they resolve by
different rules. The **qualifiers** say how a display should head and link the
value. The **authority** says which vocabulary the value came from.

Source files:

- `lib/neu/mods/projection/support.rb` — `qualifiers_of`, `authority_of`,
  `labeled`, `labeled_texts_at`, `first_attr`, `first_href`
- `lib/neu/mods/projection/name_display.rb` — `editable_creator_name?`, which
  reads the authority attributes the same way

## The qualifier pair

`qualifiers_of` returns `{ display_label:, href: }`: the header the record asked
for (`@displayLabel`) and the link it attached (`@xlink:href`). They travel as
one pair on the entry, so a consumer never zips two parallel lists.

The two attributes are allowed on overlapping sets of elements. MODS 3.8 puts
`@displayLabel` on 26 elements and `@xlink:href` on 14, including `titleInfo`,
`name`, `alternativeName`, `agent`, `subject`, `abstract`, `tableOfContents`,
`note`, `relatedItem`, `accessCondition` and `physicalLocation`. The gem reads
both off every element anyway. An element the schema does not let carry one
projects `nil` for it, and a consumer does not have to know the two lists.

**An href with no text displays nothing.** A link needs text to hang on, so an
element with an href and no text drops out, like every other element with no
value. The librarians set this rule.

### Where the header comes from

The header often comes from a **parent** element. MODS puts `@displayLabel` on
`originInfo` and `physicalDescription`, never on the `publisher`, `place`,
`extent` or `digitalOrigin` inside them. So `labeled_texts_at` takes a `from:`
XPath, relative to the element holding the text, that names the ancestor to read
the pair from. The value still comes from the element itself. Six projections
pass `from:`.

### Fields that join several elements

`abstract` and the three access-condition fields join several elements into one
string, because their consumers (the OAI `dc:description`, the citation and
`description_tsim`) hold one string. Those fields cannot carry a pair per
element, so each has **companion scalars** instead: `abstract_display_label`,
`abstract_href` and so on. Each companion takes the first element that states
the attribute (`first_attr`, `first_href`). A record that labels only its second
abstract still meant the label.

## The authority triple

`authority_of` returns `{ authority:, authority_uri:, value_uri: }`. It is what
tells a controlled term apart from one a depositor typed. Names, origin agents,
languages, genres and subject headings carry it.

A consumer deciding whether to offer a value as a browse link asks for **any of
the three**. MODS lets a record declare its vocabulary by URI alone, so requiring
`@authority` would call an `authorityURI`-bearing name uncontrolled.

### Why it is not part of the qualifier pair

The two resolve by opposite rules. A header often comes from a parent. An
authority never does: `<form authority="marcform">` carries it on the element
holding the text. Reading the authority off the header's element would find
nothing there, or would attribute a parent's vocabulary to a child. So
`labeled_texts_at(authority: true)` reads the authority off the text-bearing
element even where `from:` points the header at an ancestor.

### How it resolves

Each attribute resolves on the element, then on an enclosing `<subject>`. A
pre-coordinated heading declares its vocabulary once, on the heading, and every
part of it belongs to that vocabulary. The `<subject>` is matched by namespace
URI, not by prefix, because a document can bind MODS to any prefix.

**A `<role>` or `<roleTerm>` authority is never read.** It is the vocabulary of
the relator, not of the name. The deposit form writes a `marcrelator` roleTerm
on every creator it collects, so reading authority anywhere in the subtree would
call every depositor-entered name controlled.

A blank attribute is no authority. `attr_value` canonicalizes whitespace and
maps blank to `nil`, and `editable_creator_name?` reads the same attributes the
same way. So a name the projection calls uncontrolled is always one the edit
form can manage.
