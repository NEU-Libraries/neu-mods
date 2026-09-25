# frozen_string_literal: true

require_relative "../namespaces"
require_relative "support"

module NEU
  module MODS
    module Projection
      # Top-level relatedItem elements: the series, the host and this work's
      # part within it, and every other relationship with its type.
      module RelatedItems
        include Support

        def related_series = related_item_titles("series")

        # The host's title plus THIS work's position within it. The host's own
        # name, originInfo and identifier stay out: they belong to the other
        # record, and a transcribed copy goes stale the moment that record is
        # edited. A part is the exception, because a volume, issue and page range
        # describe this article and no other record holds that fact.
        #
        # An entry survives on its part alone. Requiring a title discarded the
        # one piece of the block that was ours along with the metadata that never
        # was, and how to render a titleless host is the consumer's call.
        def host_collections
          doc.xpath("/mods:mods/mods:relatedItem[@type='host']", NAMESPACE).filter_map do |node|
            entry = { title: child_text(node, "mods:titleInfo/mods:title"), **host_part(node) }
            entry.merge(qualifiers_of(node)) if entry.values.any?
          end
        end

        # relatedItem @type values that already have a field of their own, so the
        # catch-all below does not repeat them.
        NAMED_RELATED_ITEM_TYPES = %w[series host].freeze

        # The part detail types volume and issue already have named keys on a
        # host entry, so #host_details does not repeat them -- the same split
        # NAMED_RELATED_ITEM_TYPES makes for relatedItem. A caption is kept
        # because it is the label a cataloguer wrote for the number ("chap."
        # before "3"), which no consumer can reconstruct from an open @type.
        NAMED_HOST_DETAIL_TYPES = %w[volume issue].freeze

        # Every other relatedItem, keeping its @type. MODS also defines
        # constituent, otherFormat, original, preceding, succeeding, isReferencedBy
        # and reviewOf, and a record carrying any of them projected nothing at all.
        # The type rides along because "the print edition" and "reviewed in" are
        # not the same relationship, and no consumer can recover which it holds
        # from the title alone. An untyped relatedItem lands here with a nil type.
        def related_items
          doc.xpath("/mods:mods/mods:relatedItem", NAMESPACE).filter_map do |node|
            type = clean(node["type"])
            next if NAMED_RELATED_ITEM_TYPES.include?(type)

            title = clean(node.at_xpath("mods:titleInfo/mods:title", NAMESPACE)&.text)
            { type: type, title: title, **qualifiers_of(node) } if title
          end
        end

        private

        def related_item_titles(type)
          labeled_texts_at("/mods:mods/mods:relatedItem[@type='#{type}']/mods:titleInfo/mods:title", from: "../..")
        end

        # Kept in parts rather than composed into "24(3), pp. 210-218". The
        # punctuation of a citation is display policy, the same call #map_data
        # makes for cartographics. MODS leaves @unit optional, so a page extent
        # without one is read rather than dropped.
        #
        # Volume, issue and the page range keep named keys because they are the
        # citation and a consumer asks for them by name. Everything else the
        # schema allows under part arrives structured, because detail/@type and
        # extent/@unit are open strings -- a fixed key per type cannot cover a
        # vocabulary the schema does not close. #date is the article's year within
        # the host, which after the title is the most-cited element of a journal
        # citation and was reaching no consumer at all.
        def host_part(node)
          part = node.at_xpath("mods:part", NAMESPACE)
          return {} if part.nil?

          pages = "mods:extent[@unit='page' or not(@unit)]"
          {
            volume: child_text(part, "mods:detail[@type='volume']/mods:number"),
            issue: child_text(part, "mods:detail[@type='issue']/mods:number"),
            start_page: child_text(part, "#{pages}/mods:start"),
            end_page: child_text(part, "#{pages}/mods:end"),
            date: child_text(part, "mods:date"),
            text: child_text(part, "mods:text"),
            details: host_details(part),
            extents: host_extents(part)
          }.reject { |_, value| value.nil? || value == [] }
        end

        def host_details(part)
          part.xpath("mods:detail", NAMESPACE).filter_map do |node|
            type = clean(node["type"])
            next if NAMED_HOST_DETAIL_TYPES.include?(type)

            entry = {
              type: type,
              number: child_text(node, "mods:number"),
              caption: child_text(node, "mods:caption"),
              title: child_text(node, "mods:title")
            }
            entry if entry.except(:type).values.any?
          end
        end

        # Every extent EXCEPT the page range, which start_page and end_page hold.
        # A unit other than page -- the minutes of a recording, the columns of a
        # newspaper -- means nothing without its unit, so the unit travels with
        # the numbers rather than being flattened away.
        def host_extents(part)
          part.xpath("mods:extent", NAMESPACE).filter_map do |node|
            unit = clean(node["unit"])
            next if unit.nil? || unit == "page"

            {
              unit: unit,
              start: child_text(node, "mods:start"),
              end: child_text(node, "mods:end"),
              total: child_text(node, "mods:total"),
              list: child_text(node, "mods:list")
            }
          end
        end
      end
    end
  end
end
