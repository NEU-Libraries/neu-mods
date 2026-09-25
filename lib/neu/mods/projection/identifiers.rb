# frozen_string_literal: true

require_relative "../namespaces"
require_relative "support"

module NEU
  module MODS
    module Projection
      # Identifiers, classification, location and recordInfo: what the record
      # is called elsewhere and where the resource is held. See docs/other-fields.md.
      module Identifiers
        include Support

        # An LCC or DDC call number, not Atlas's classification_ssim.
        def classification = labeled_texts_at("/mods:mods/mods:classification")

        # Typed, so a display can tell a DOI from an accession number, and
        # flagged when @invalid="yes" marks the identifier dead.
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

        # No href companion: the value is the URL.
        def permanent_url_display_label
          attr_value(handle_node, "displayLabel")
        end

        # The parts stay apart: a shelf mark and a URL are different kinds. The
        # element is shelfLocator; MODS has no shelfLocation.
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

        # recordInfo children, read as one value.
        RECORD_INFO_PARTS = {
          content_source: "mods:recordContentSource",
          origin: "mods:recordOrigin",
          description_standard: "mods:descriptionStandard",
          creation_date: "mods:recordCreationDate",
          change_date: "mods:recordChangeDate",
          language_of_cataloging: "mods:languageOfCataloging/mods:languageTerm"
        }.freeze

        # Who catalogued the record, to what standard, and when.
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
