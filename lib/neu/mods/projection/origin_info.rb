# frozen_string_literal: true

require_relative "../namespaces"
require_relative "support"
require_relative "names"
require_relative "dates"

module NEU
  module MODS
    module Projection
      # The non-date originInfo children, each carrying its block's header
      # attributes. See docs/other-fields.md.
      module OriginInfo
        include Support
        include Names
        include Dates

        # Headed by the enclosing originInfo: MODS puts neither attribute on its
        # children.
        def publication_information = origin_texts_at("mods:publisher")
        def edition = origin_texts_at("mods:edition")

        # A bare marccountry code ("mau") is not a place name, so it drops.
        # TODO: expand marccountry codes through a vendored registry, as
        # LanguageCodes does for eng -> English.
        MARC_COUNTRY_AUTHORITY = "marccountry"

        def place_of_publication
          doc.xpath("/mods:mods/mods:originInfo/mods:place", NAMESPACE).filter_map do |place|
            value = place_term_value(place)
            next unless value

            { value: value, **origin_qualifiers_of(place.parent),
              date_elements: origin_date_elements(place.parent) }
          end
        end

        # originInfo/agent, composed like a top-level name.
        def origin_agents
          doc.xpath("/mods:mods/mods:originInfo/mods:agent", NAMESPACE).filter_map do |node|
            entry = name_entry(node)
            entry.merge(event_type: attr_value(node.parent, "eventType")) if entry[:name]
          end
        end

        def place_term_value(place)
          text = clean(place.at_xpath("mods:placeTerm[@type='text']", NAMESPACE)&.text)
          return text if text

          code = place.at_xpath("mods:placeTerm", NAMESPACE)
          return nil if attr_value(code, "authority") == MARC_COUNTRY_AUTHORITY

          clean(code&.text)
        end

        def issuance = origin_texts_at("mods:issuance")

        def frequency = origin_texts_at("mods:frequency")

        private

        # The general pair plus @eventType, which MODS puts on originInfo alone.
        def origin_qualifiers_of(node)
          qualifiers_of(node).merge(event_type: attr_value(node, "eventType"))
        end

        # `xpath` is relative to each originInfo, which the qualifiers come from.
        def origin_texts_at(xpath)
          doc.xpath("/mods:mods/mods:originInfo", NAMESPACE).flat_map do |origin|
            origin.xpath(xpath, NAMESPACE).filter_map do |node|
              value = clean(node.text)
              { value: value, **origin_qualifiers_of(origin) } if value
            end
          end
        end

        # The date elements beside a place, which decide how its row is headed.
        def origin_date_elements(origin)
          return [] unless origin

          DATE_ELEMENTS.select { |name| origin.at_xpath("mods:#{name}", NAMESPACE) }
        end
      end
    end
  end
end
