# frozen_string_literal: true

require_relative "../namespaces"
require_relative "../text_normalizer"
require_relative "../selectors"
require_relative "support"

module NEU
  module MODS
    module Projection
      # The primary title, the variant titles and the composition of both.
      # See docs/titles.md.
      module Titles
        include Support
        include Selectors

        # Byte-faithful, nil for an absent part. Do not normalise here: Cerberus
        # pre-fills its edit forms from this and writes back what the form posts,
        # so normalising would rewrite the preservation XML. #access_title_parts
        # is the normalised surface.
        def title_parts
          title_parts_of(primary_title_info)
        end

        # Each composed and normalised like the main title. MODS repeats
        # titleInfo, so a record may carry several of one type.
        def alternative_title = variant_titles("alternative")
        def uniform_title = variant_titles("uniform")
        def translated_title = variant_titles("translated")
        def abbreviated_title = variant_titles("abbreviated")

        # The composed display title of the primary title.
        def plain_title
          Titles.compose_title(title_parts)
        end

        # The separator before each part, in the order the librarians chose. Each
        # separator travels with its part, and nothing follows the last one.
        TITLE_SEPARATORS = [[": ", :subtitle], [". ", :part_name], [". ", :part_number]].freeze

        # Pure composition over a parts hash (:non_sort :title :subtitle
        # :part_name :part_number), so a caller holding the parts need not parse
        # XML. "" when there is no title.
        def self.compose_title(parts)
          return "" if parts[:title].to_s.strip.empty?

          suffix = TITLE_SEPARATORS.filter_map do |separator, key|
            "#{separator}#{parts[key]}" unless parts[key].to_s.strip.empty?
          end.join
          "#{join_non_sort(parts[:non_sort], parts[:title])}#{suffix}"
        end

        # Characters that bind a nonSort to the next word ("L'Etranger"). U+2019 is
        # escaped, not literal, to keep lib/ pure ASCII (see the source-purity spec).
        NON_SORT_BINDING = ["'", "\u2019", "-"].freeze

        # Composes the space rather than trusting the source's: #child_text strips
        # the trailing space an authored `<nonSort>The </nonSort>` carries. A
        # nonSort that still ends in a space is joined as it is.
        def self.join_non_sort(non_sort, title)
          prefix = non_sort.to_s
          return title.to_s if prefix.empty?
          return "#{prefix}#{title}" if prefix.end_with?(" ") || prefix.end_with?(*NON_SORT_BINDING)

          "#{prefix} #{title}"
        end

        # The title parts as the access copy wants them, normalised like the
        # abstract so no curly quote or control character reaches Solr.
        def access_title_parts
          title_parts.transform_values { |value| TextNormalizer.normalize(value.to_s) }
        end

        # The registry name Atlas uses for #access_title_parts.
        def main_title = access_title_parts

        # The header the record asks for on the title row.
        def main_title_display_label = attr_value(primary_title_info, "displayLabel")

        private

        # Byte-faithful title parts off any titleInfo node.
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
