# frozen_string_literal: true

require_relative "../namespaces"
require_relative "../canonicalize"
require_relative "support"

module NEU
  module MODS
    module Projection
      # What the resource is and how it is physically described: type, genre,
      # form, extent, notes and the table of contents. See docs/other-fields.md.
      module PhysicalDescription
        include Support

        # MODS repeats typeOfResource, so a record can be text and a still image.
        def resource_type = labeled_texts_at("/mods:mods/mods:typeOfResource")

        # Headed by physicalDescription, which is where MODS puts @displayLabel.
        def format = labeled_texts_at("/mods:mods/mods:physicalDescription/mods:form", from: "..")
        def extent = labeled_texts_at("/mods:mods/mods:physicalDescription/mods:extent", from: "..")
        def digital_origin = labeled_texts_at("/mods:mods/mods:physicalDescription/mods:digitalOrigin", from: "..")

        # The one labeled field with its vocabulary, because a genre is a browse axis.
        def genres = labeled_texts_at("/mods:mods/mods:genre", authority: true)

        def target_audience = labeled_texts_at("/mods:mods/mods:targetAudience")

        # Line breaks kept: here a newline separates one entry from the next.
        def table_of_contents
          doc.xpath("/mods:mods/mods:tableOfContents", NAMESPACE).filter_map do |node|
            lines = Canonicalize.canonical_lines(node.text)
            labeled(lines, node) unless lines.empty?
          end
        end

        def reformatting_quality
          labeled_texts_at("/mods:mods/mods:physicalDescription/mods:reformattingQuality", from: "..")
        end

        # About the object, not the work, so no @type is kept.
        def physical_description_notes = labeled_texts_at("/mods:mods/mods:physicalDescription/mods:note", from: "..")

        # Every top-level note, keeping its @type, which changes what it means.
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
