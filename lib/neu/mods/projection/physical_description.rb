# frozen_string_literal: true

require_relative "../namespaces"
require_relative "../canonicalize"
require_relative "support"

module NEU
  module MODS
    module Projection
      # What the resource is and how it is physically described: type, genre,
      # form, extent, notes and the table of contents.
      module PhysicalDescription
        include Support

        # MODS repeats typeOfResource, and repeats physicalDescription (and form and
        # extent within one), so all four are :many. A record that is both text and
        # a still image used to project as text alone.
        def resource_type = labeled_texts_at("/mods:mods/mods:typeOfResource")

        # MODS puts @displayLabel on physicalDescription, not on the form, extent,
        # digitalOrigin, reformattingQuality or note inside it -- so these four
        # take the label off their parent. `from: ".."` says which element the
        # header comes from; the value still comes from the element itself.
        def format = labeled_texts_at("/mods:mods/mods:physicalDescription/mods:form", from: "..")
        def extent = labeled_texts_at("/mods:mods/mods:physicalDescription/mods:extent", from: "..")
        def digital_origin = labeled_texts_at("/mods:mods/mods:physicalDescription/mods:digitalOrigin", from: "..")

        # A genre is a browse axis, so its entry carries the vocabulary the term
        # came from. The other labeled fields do not: nothing gates on their
        # vocabulary, and three more keys on fifteen fields is JSON no consumer
        # reads.
        def genres = labeled_texts_at("/mods:mods/mods:genre", authority: true)

        # Who the resource is for. The last displayed top-level element with no
        # projection at all: a record naming its audience said so to nobody.
        def target_audience = labeled_texts_at("/mods:mods/mods:targetAudience")

        # Read with its line breaks intact. A legacy contents list separates its
        # entries by newline, and the whitespace collapse every other field wants
        # ran the entries together into one line -- there the break IS the
        # structure, not stray formatting. A "--"-separated list is unaffected.
        def table_of_contents
          doc.xpath("/mods:mods/mods:tableOfContents", NAMESPACE).filter_map do |node|
            lines = Canonicalize.canonical_lines(node.text)
            labeled(lines, node) unless lines.empty?
          end
        end

        def reformatting_quality
          labeled_texts_at("/mods:mods/mods:physicalDescription/mods:reformattingQuality", from: "..")
        end

        # A note about the object rather than about the work -- "Scanned at 600
        # dpi" belongs beside the extent, not beside a content note. Projected as
        # plain strings like its physicalDescription siblings: #notes keeps @type
        # because the type changes what a top-level note means, and nothing here
        # turns on it.
        def physical_description_notes = labeled_texts_at("/mods:mods/mods:physicalDescription/mods:note", from: "..")

        # Every top-level note, keeping its @type. The type carries meaning -- a
        # "statement of responsibility" is not a "funding" note -- so flattening
        # them into bare strings would repeat the accessCondition mistake.
        def notes
          doc.xpath("/mods:mods/mods:note", NAMESPACE).filter_map do |node|
            value = clean(node.text)
            { type: clean(node["type"]), value: value, **qualifiers_of(node) } if value
          end
        end
      end
    end
  end
end
