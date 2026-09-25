# frozen_string_literal: true

require_relative "../namespaces"
require_relative "../text_normalizer"
require_relative "../selectors"
require_relative "support"

module NEU
  module MODS
    module Projection
      # The primary title, the variant titles and the composition of both.
      module Titles
        include Support
        include Selectors

        # Structured primary-title parts, byte-faithful to the document. nil for an
        # absent part (the Cerberus form treats nil as "not present"); to_h coerces
        # to "" for the Atlas main_title.
        #
        # Faithful on purpose: this is what Cerberus pre-fills its edit forms from
        # (MODSFields for the Metadata tab, load_advanced! for the Advanced tab),
        # and MODSMerge writes back whatever the form posts. Normalising here would
        # rewrite the curator's characters in the preservation XML on the next save.
        # #access_title_parts is the normalised surface.
        def title_parts
          title_parts_of(primary_title_info)
        end

        # The variant titles, each composed and normalised like the main title.
        # MODS repeats titleInfo, so a record may carry more than one of a type.
        # These are what keeps the primary-title fallback's refusal to promote a
        # variant from hiding anything: the variant still reaches a reader, under
        # a label that says which kind of title it is.
        def alternative_title = variant_titles("alternative")

        def uniform_title = variant_titles("uniform")

        def translated_title = variant_titles("translated")

        def abbreviated_title = variant_titles("abbreviated")

        # Composed display title (the former Atlas MODSDecoration#plain_title), driven
        # off the scoped primary title.
        def plain_title
          Titles.compose_title(title_parts)
        end

        # Pure title composition over a parts hash, factored out of #plain_title so
        # callers that already hold the parts -- e.g. Atlas's access-copy model --
        # can compose the display title WITHOUT re-parsing XML on the read path
        # (reaching for Nokogiri in a decorator is the smell this avoids). Keys:
        # :non_sort :title :subtitle :part_name :part_number (nil or "" for absent).
        # Returns "" when there is no title. Exposed as NEU::MODS.compose_title.
        #
        # nonSort, title, subtitle, partName, partNumber -- the order the
        # librarians chose. titleInfo is an unordered choice in the schema, so no
        # document order is available to follow and the composer has to fix one.
        #
        # A period separates the title or subtitle from the parts, and one part
        # from the next. The separator travels with its part rather than with the
        # position, so a record giving only a partNumber still gets the period.
        # Nothing is appended after the last part: a title is a value, not a
        # sentence, and a trailing period reads as part of the title everywhere
        # the value is re-used.
        TITLE_SEPARATORS = [[": ", :subtitle], [". ", :part_name], [". ", :part_number]].freeze

        def self.compose_title(parts)
          return "" if parts[:title].to_s.strip.empty?

          suffix = TITLE_SEPARATORS.filter_map do |separator, key|
            "#{separator}#{parts[key]}" unless parts[key].to_s.strip.empty?
          end.join
          "#{join_non_sort(parts[:non_sort], parts[:title])}#{suffix}"
        end

        # Characters that bind a nonSort to the word after it. An elided article
        # takes no space -- "L'Etranger", not "L' Etranger" -- and the same holds
        # for a hyphenated prefix. U+2019 is the curly apostrophe, escaped rather
        # than literal to keep lib/ pure ASCII (see the source-purity spec).
        NON_SORT_BINDING = ["'", "\u2019", "-"].freeze

        # MODS says a nonSort carries whatever separator it needs, so the historical
        # composition simply concatenated. That only holds while the authored
        # trailing space survives, and it does not: #child_text canonicalizes
        # whitespace on read, so `<nonSort>The </nonSort>` arrives here as "The" and
        # the title came out as "TheHobbit". Composing the separator instead makes
        # the output right whether or not the source kept one -- which matters,
        # because an invisible trailing space is not something a curator, a
        # hand-edit or a third-party producer can be relied on to preserve.
        #
        # Callers that DO pass the space (Atlas's access-copy model) are unaffected:
        # a nonSort already ending in whitespace is joined as-is.
        def self.join_non_sort(non_sort, title)
          prefix = non_sort.to_s
          return title.to_s if prefix.empty?
          return "#{prefix}#{title}" if prefix.end_with?(" ") || prefix.end_with?(*NON_SORT_BINDING)

          "#{prefix} #{title}"
        end

        # The title parts as the access copy wants them: normalised like the
        # abstract, so a curly quote, an invisible format mark or a Windows-1252
        # control cannot reach Solr or a display template. Titles and prose share
        # one vocabulary -- the asymmetry where only prose was cleaned was the bug.
        def access_title_parts
          title_parts.transform_values { |value| TextNormalizer.normalize(value.to_s) }
        end

        # Atlas names this field main_title; the registry requires a method per
        # field name, and #access_title_parts is the descriptive name for what it
        # returns. Kept as an alias rather than a rename so both read well.
        def main_title = access_title_parts

        # What the record wants the title row headed, which is almost never set --
        # but a record that does set it means it, and "Title" is the one header a
        # display would otherwise never let a curator change.
        def main_title_display_label = attr_value(primary_title_info, "displayLabel")

        private

        # Byte-faithful title parts off any titleInfo node, shared by #title_parts
        # (which Cerberus pre-fills its edit forms from) and the variant titles.
        def title_parts_of(node)
          {
            non_sort: child_text(node, "mods:nonSort"),
            subtitle: child_text(node, "mods:subTitle"),
            title: child_text(node, "mods:title"),
            part_name: child_text(node, "mods:partName"),
            part_number: child_text(node, "mods:partNumber")
          }
        end

        # One titleInfo composed the way the access copy wants it, shared by the
        # subject-title axis and the assembled heading so the two cannot drift.
        def composed_title_of(node)
          parts = title_parts_of(node).transform_values { |value| TextNormalizer.normalize(value.to_s) }
          clean(Titles.compose_title(parts))
        end

        # A variant title composed the way the access copy wants it: normalised
        # first, like #access_title_parts, so a curly quote or an invisible format
        # mark cannot reach Solr or a display template through this route either.
        def variant_titles(type)
          doc.xpath("/mods:mods/mods:titleInfo[@type='#{type}']", NAMESPACE).filter_map do |node|
            value = composed_title_of(node)
            labeled(value, node) if value
          end
        end
      end
    end
  end
end
