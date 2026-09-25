# frozen_string_literal: true

require_relative "../namespaces"
require_relative "support"

module NEU
  module MODS
    module Projection
      # Top-level relatedItem elements: the series, the host and this work's
      # part within it, and every other relationship with its type. See docs/other-fields.md.
      module RelatedItems
        include Support

        def related_series = related_item_titles("series")

        # The host's title plus THIS work's part within it. Never copy the host's
        # own metadata: it belongs to the other record and would go stale.
        def host_collections
          doc.xpath("/mods:mods/mods:relatedItem[@type='host']", NAMESPACE).filter_map do |node|
            entry = { title: child_text(node, "mods:titleInfo/mods:title"), **host_part(node) }
            entry.merge(qualifiers_of(node)) if entry.values.any?
          end
        end

        # Types with a field of their own, which #related_items skips.
        NAMED_RELATED_ITEM_TYPES = %w[series host].freeze

        # Detail types with a named key on a host entry, which #host_details skips.
        NAMED_HOST_DETAIL_TYPES = %w[volume issue].freeze

        # Every other relatedItem with a title, keeping its @type (nil if untyped).
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

        # In parts, not composed: citation punctuation is display policy. A page
        # extent may omit @unit.
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

        # Every extent except the page range, each with its unit.
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
