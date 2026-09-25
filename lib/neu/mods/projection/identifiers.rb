# frozen_string_literal: true

require_relative "../namespaces"
require_relative "support"

module NEU
  module MODS
    module Projection
      # Identifiers, classification, location and recordInfo: what the record
      # is called elsewhere and where the resource is held.
      module Identifiers
        include Support

        # An LCC or DDC call number. Note this is NOT the same concept as Atlas's
        # classification_ssim, which carries a FileSet content-type vocabulary --
        # the name collision is accidental and the consumer has to pick a free
        # Solr field.
        def classification = labeled_texts_at("/mods:mods/mods:classification")

        # { type:, value: }, because a DOI, an accession number and a collection
        # id are not the same kind of thing and no consumer can tell them apart
        # from the digits alone -- a reader shown a bare 10.1234/x cannot see it
        # is a DOI, and a display cannot decide to linkify it. The same argument
        # #notes already makes for its @type, and #permanent_url already proves
        # the attribute is load-bearing by special-casing @type='hdl'.
        # @invalid rides along because in MODS it means the identifier is
        # cancelled, superseded or simply wrong. Projected flat, a dead ISBN read
        # exactly like a live one and invited a reader to use it.
        def identifiers
          doc.xpath("/mods:mods/mods:identifier", NAMESPACE).filter_map do |node|
            value = clean(node.text)
            if value
              { type: clean(node["type"]), value: value, invalid: attr_value(node, "invalid") == "yes",
                **qualifiers_of(node) }
            end
          end
        end

        def permanent_url
          clean(handle_node&.text)
        end

        # The handle identifier carries @displayLabel="Permanent URL" in Atlas's
        # own MODS template, so the header a reader sees is one the record states
        # rather than one a decorator invents. No href companion: the value is the
        # URL.
        def permanent_url_display_label
          attr_value(handle_node, "displayLabel")
        end

        # location repeats, and one location mixes kinds: a shelf mark and a URL
        # are not interchangeable, and a consumer has to know which it holds
        # before it can decide to linkify it. So the parts stay apart.
        #
        # The shelf mark is mods:shelfLocator. There is no shelfLocation element
        # in MODS, and the spec fixture carried the same misspelling, so the
        # field was unconditionally nil and the spec asserted nothing.
        def location
          doc.xpath("/mods:mods/mods:location", NAMESPACE).filter_map do |node|
            entry = {
              physical_location: child_text(node, "mods:physicalLocation"),
              shelf_location: child_text(node, "mods:shelfLocator"),
              url: child_text(node, "mods:url")
            }
            entry.merge(qualifiers_of(node)) if entry.values.any?
          end
        end

        # recordInfo children. Read as a single value: the schema repeats the
        # element, but a record with two cataloguing provenances is not a case
        # anyone has, and an array here buys nothing.
        RECORD_INFO_PARTS = {
          content_source: "mods:recordContentSource",
          origin: "mods:recordOrigin",
          description_standard: "mods:descriptionStandard",
          creation_date: "mods:recordCreationDate",
          change_date: "mods:recordChangeDate",
          language_of_cataloging: "mods:languageOfCataloging/mods:languageTerm"
        }.freeze

        # Who catalogued this record, to what standard, and when. It describes the
        # CATALOGUING rather than the resource, which is why it is one value and
        # why a consumer is unlikely to want it beside Publisher -- but dropping a
        # preservation repository's provenance statement on read is wrong on its
        # face, so it is projected and the display question is the consumer's.
        def record_info
          node = doc.at_xpath("/mods:mods/mods:recordInfo", NAMESPACE)
          return nil unless node

          entry = RECORD_INFO_PARTS.transform_values { |xpath| child_text(node, xpath) }
          entry if entry.values.any?
        end

        private

        # The handle identifier, which both the permanent URL and its header
        # are read from.
        def handle_node
          doc.at_xpath("/mods:mods/mods:identifier[@type='hdl']", NAMESPACE)
        end
      end
    end
  end
end
