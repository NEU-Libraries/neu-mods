# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Read this before editing this file

**This file is tooling, not documentation.** It holds instructions about how to
work here and short pointers into the durable record, and nothing the gem
depends on.

**The dependency points one way: this file may cite `docs/`, and `docs/` must
never cite this file.** If you are about to explain a design decision here,
that explanation belongs on a `docs/` page. Write it there and link to it.

`.claude/` stays gitignored. Hooks are per-developer tooling.

## What this is

neu-mods is the MODS v3 reading contract that Atlas and Cerberus share. It
depends on Nokogiri alone. `NEU::MODS::Document` wraps a parsed document and
mixes in three things:

- `Selectors` locate live nodes, for both the read path and Cerberus's edits.
- `Builders` create nodes for Cerberus's `MODSMerge`.
- `Projection` turns the document into plain data, one mixin per MODS area
  under `lib/neu/mods/projection/`.

Start with [`docs/README.md`](docs/README.md) for the page index.

## Development commands

The machine's default Ruby is too old, so select 3.4.10 before `bundle exec`:

```sh
rvm use 3.4.10
bundle exec rake          # specs, then rubocop
bundle exec rspec spec/conformance_spec.rb
bundle exec rubocop
```

## The contract with Atlas and Cerberus

- **Method names are the contract.** Atlas and Cerberus call `Document`'s
  methods by name, and `to_h` calls every `FIELDS` row through `public_send`.
  Renaming a projection method is a breaking change.
- **A few names are reached through `Projection` directly.**
  `spec/consumer_references_spec.rb` pins them. Keep the delegators in
  `lib/neu/mods/projection.rb` when you move a module method.
- **A change to what the gem projects is a contract change.** The conformance
  spec should fail, and the version bump should say so.
- **Bump `.version`** once per branch, as its last commit.

## Comments and `docs/`

A comment explains why the code below it exists, in two or three sentences,
and must make sense with no access to git history. Do not write dates, version
stamps, workstream shorthand, or before-and-after narration ("used to", "no
longer"). Keep the lesson and drop the incident.

The per-component explanation lives on a `docs/` page, and the source file
keeps a one-line pointer plus only the traps someone editing that line must not
miss. Aim for comments under 35% of a file's non-blank lines;
[`docs/README.md`](docs/README.md) says how to measure it. Prefer a spec to a
page when the claim is testable.
