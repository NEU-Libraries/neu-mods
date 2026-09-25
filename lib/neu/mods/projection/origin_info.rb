# frozen_string_literal: true

require_relative "../namespaces"
require_relative "support"
require_relative "names"
require_relative "dates"

module NEU
  module MODS
    module Projection
      # The non-date originInfo children: publisher, place, agent, edition,
      # issuance and frequency, each carrying its block's header attributes.
      module OriginInfo
        include Support
        include Names
        include Dates

        # originInfo repeats, and so do publisher and edition within one. Cerberus's
        # IPTC ingest writes the publisher from the IPTC Source field on every batch,
        # so this element was being written into the preservation XML and then read
        # back by nothing.
        # @displayLabel and @eventType sit on originInfo, not on the publisher,
        # place, edition, issuance or frequency inside it, so each of these takes
        # its header off the parent block.
        def publication_information = origin_texts_at("mods:publisher")

        def edition = origin_texts_at("mods:edition")

        # Prefer the type="text" term per place, falling back to a coded one --
        # the pattern #role_term_value and #languages already use.
        #
        # A bare marccountry code is the exception, and it drops. "mau" is not a
        # place name, and unfiltered it reached the display and the Solr places
        # facet as one, sitting in the list beside Boston. That is the call
        # #geographic_code_subjects already makes for a MARC GAC code. A code
        # under any other authority survives, because there the code may be the
        # only statement the record made and nothing here can say it is not text.
        #
        # TODO: expand a marccountry code through a registry, as LanguageCodes
        # does for eng -> English. That needs a vendored code list, and would let
        # this project "Massachusetts" instead of dropping the element.
        MARC_COUNTRY_AUTHORITY = "marccountry"

        def place_of_publication
          doc.xpath("/mods:mods/mods:originInfo/mods:place", NAMESPACE).filter_map do |place|
            value = place_term_value(place)
            next unless value

            { value: value, **origin_qualifiers_of(place.parent),
              date_elements: origin_date_elements(place.parent) }
          end
        end

        # originInfo/agent, new in MODS 3.8: who performed the event the block
        # records. Read through the same port as a top-level name, so a publisher
        # recorded as an agent composes the way a creator does and carries its
        # roles -- which is what a consumer heads the row with when the block
        # states no displayLabel or eventType.
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

        # Serials. The @authority a record puts on a frequency is not projected:
        # authority handling is a question the gem defers everywhere else -- for
        # genre, subject and name -- and answering it for one field would be
        # inconsistent.
        def frequency = origin_texts_at("mods:frequency")

        private

        # The qualifiers of an originInfo block. @eventType says what the block
        # records -- a publication, a production, a distribution -- and the
        # librarians asked that its value head the block when no displayLabel
        # does. MODS puts it on originInfo alone, so it is not part of the
        # general pair.
        def origin_qualifiers_of(node)
          qualifiers_of(node).merge(event_type: attr_value(node, "eventType"))
        end

        # An originInfo child, carrying the block's header attributes. `xpath` is
        # relative to the originInfo, which is the element the qualifiers come
        # from -- MODS puts neither attribute on the children.
        def origin_texts_at(xpath)
          doc.xpath("/mods:mods/mods:originInfo", NAMESPACE).flat_map do |origin|
            origin.xpath(xpath, NAMESPACE).filter_map do |node|
              value = clean(node.text)
              { value: value, **origin_qualifiers_of(origin) } if value
            end
          end
        end

        # The date elements the enclosing originInfo carries. A place is headed
        # "Creation place" or "Publication place" depending on which date sits
        # beside it, and the place element itself says nothing about the event.
        # Which dates are present is data; the header text is display policy and
        # stays with the consumer.
        def origin_date_elements(origin)
          return [] unless origin

          DATE_ELEMENTS.select { |name| origin.at_xpath("mods:#{name}", NAMESPACE) }
        end
      end
    end
  end
end
