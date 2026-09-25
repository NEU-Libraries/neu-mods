# frozen_string_literal: true

require "date"

require_relative "namespaces"
require_relative "canonicalize"
require_relative "text_normalizer"
require_relative "language_codes"
require_relative "projection/support"
require_relative "projection/name_display"
require_relative "projection/titles"
require_relative "projection/access"
require_relative "projection/subjects"
require_relative "projection/names"
require_relative "projection/languages"
require_relative "projection/dates"
require_relative "projection/origin_info"
require_relative "projection/physical_description"
require_relative "projection/related_items"

module NEU
  module MODS
    # Node -> plain data. The read contract: what a MODS document *projects to* for
    # indexing/display. Behavior-preserving with Atlas's prior `mods`-gem-based
    # extraction (verified by the conformance corpus), reimplemented in Nokogiri so
    # DRS depends on Nokogiri alone. Mixed into Document; operates on `doc`.
    #
    # Empty-value conventions mirror Atlas: scalar fields are "" when absent
    # (matching `.text.squish` on an empty node set), except `permanent_url` and
    # `date_created`, which are nil when their node is absent. Arrays are [].
    # Which fields are scalar and which are arrays is declared in FIELDS, not
    # left to each method to decide.
    module Projection
      include Support
      include NameDisplay
      include Titles
      include Access
      include Subjects
      include Names
      include Languages
      include Dates
      include OriginInfo
      include PhysicalDescription
      include RelatedItems

      # --- Scalars / simple arrays --------------------------------------------

      # An LCC or DDC call number. Note this is NOT the same concept as Atlas's
      # classification_ssim, which carries a FileSet content-type vocabulary --
      # the name collision is accidental and the consumer has to pick a free
      # Solr field.
      def classification = labeled_texts_at("/mods:mods/mods:classification")

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
        node = doc.at_xpath("/mods:mods/mods:identifier[@type='hdl']", NAMESPACE)
        node && clean(node.text)
      end

      # The handle identifier carries @displayLabel="Permanent URL" in Atlas's
      # own MODS template, so the header a reader sees is one the record states
      # rather than one a decorator invents. No href companion: the value is the
      # URL.
      def permanent_url_display_label
        attr_value(doc.at_xpath("/mods:mods/mods:identifier[@type='hdl']", NAMESPACE), "displayLabel")
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

      # --- Full projection -----------------------------------------------------

      # The field registry: the single declaration of what this gem projects.
      # Field name => cardinality, :one or :many. The projection method of the
      # same name owns the XPath; this row says the field exists and whether it
      # is single- or multi-valued. #to_h is derived from it, and Atlas derives
      # its Metadata::MODS attr_json set from it, so a field cannot be projected
      # here and go undeclared there (or the reverse).
      #
      # Cardinality is the half that earns its keep. The at_xpath-versus-xpath
      # choice here and the single-versus-array column choice in Atlas used to be
      # made independently in two repos with nothing tying them together, which is
      # how repeatable MODS elements ended up truncated to their first match.
      # #cardinality_of checks each method against its row.
      FIELDS = {
        # titles
        main_title: :one,
        main_title_display_label: :one,
        alternative_title: :many,
        uniform_title: :many,
        translated_title: :many,
        abbreviated_title: :many,

        names: :many,
        languages: :many,
        abstract: :one,
        abstract_display_label: :one,
        abstract_href: :one,

        # origin
        publication_information: :many,
        place_of_publication: :many,
        origin_agents: :many,
        edition: :many,
        issuance: :many,
        frequency: :many,
        # Seven rows per originInfo date, for each of the seven MODS defines.
        # Flat rather than one nested value, because the value half has
        # consumers that need a real date object.
        date_created: :one,
        date_created_precision: :one,
        date_created_end: :one,
        date_created_end_precision: :one,
        date_created_qualifier: :one,
        date_created_key_date: :one,
        date_created_text: :one,
        date_created_display_label: :one,
        date_created_event_type: :one,
        date_issued: :one,
        date_issued_precision: :one,
        date_issued_end: :one,
        date_issued_end_precision: :one,
        date_issued_qualifier: :one,
        date_issued_key_date: :one,
        date_issued_text: :one,
        date_issued_display_label: :one,
        date_issued_event_type: :one,
        copyright_date: :one,
        copyright_date_precision: :one,
        copyright_date_end: :one,
        copyright_date_end_precision: :one,
        copyright_date_qualifier: :one,
        copyright_date_key_date: :one,
        copyright_date_text: :one,
        copyright_date_display_label: :one,
        copyright_date_event_type: :one,
        date_captured: :one,
        date_captured_precision: :one,
        date_captured_end: :one,
        date_captured_end_precision: :one,
        date_captured_qualifier: :one,
        date_captured_key_date: :one,
        date_captured_text: :one,
        date_captured_display_label: :one,
        date_captured_event_type: :one,
        date_valid: :one,
        date_valid_precision: :one,
        date_valid_end: :one,
        date_valid_end_precision: :one,
        date_valid_qualifier: :one,
        date_valid_key_date: :one,
        date_valid_text: :one,
        date_valid_display_label: :one,
        date_valid_event_type: :one,
        date_other: :one,
        date_other_precision: :one,
        date_other_end: :one,
        date_other_end_precision: :one,
        date_other_qualifier: :one,
        date_other_key_date: :one,
        date_other_text: :one,
        date_other_display_label: :one,
        date_other_event_type: :one,
        date_modified: :one,
        date_modified_precision: :one,
        date_modified_end: :one,
        date_modified_end_precision: :one,
        date_modified_qualifier: :one,
        date_modified_key_date: :one,
        date_modified_text: :one,
        date_modified_display_label: :one,
        date_modified_event_type: :one,

        # physical description
        resource_type: :many,
        target_audience: :many,
        genres: :many,
        format: :many,
        extent: :many,
        digital_origin: :many,
        reformatting_quality: :many,
        physical_description_notes: :many,
        notes: :many,
        table_of_contents: :many,

        # subjects
        subject_headings: :many,
        topical_subjects: :many,
        geographic_subjects: :many,
        temporal_subjects: :many,
        personal_name_subjects: :many,
        corporate_name_subjects: :many,
        occupation_subjects: :many,
        genre_subjects: :many,
        geographic_code_subjects: :many,
        title_subjects: :many,
        hierarchical_geographic_subjects: :many,
        map_data: :many,

        # related items
        related_series: :many,
        host_collections: :many,
        related_items: :many,

        # identifiers and location
        identifiers: :many,
        classification: :many,
        permanent_url: :one,
        permanent_url_display_label: :one,
        record_info: :one,
        location: :many,

        # access
        access_condition: :one,
        access_condition_display_label: :one,
        access_condition_href: :one,
        use_and_reproduction: :one,
        use_and_reproduction_display_label: :one,
        use_and_reproduction_href: :one,
        restriction_on_access: :one,
        restriction_on_access_display_label: :one,
        restriction_on_access_href: :one
      }.freeze

      # The complete read projection, keyed to Atlas's Metadata::MODS attribute
      # names -- a drop-in source for `convert_xml_to_json`.
      def to_h
        FIELDS.keys.to_h { |field| [field, public_send(field)] }
      end

      # The cardinality a projected value actually has, for checking a value
      # against its FIELDS row. An Array is :many and anything else is :one, so a
      # field declared :many that forgot to switch at_xpath for xpath is caught.
      def self.cardinality_of(value) = value.is_a?(Array) ? :many : :one

      # The area mixins' module methods, callable on Projection too. A module
      # method does not travel with `include`, and callers outside the gem name
      # Projection rather than the mixin that owns the method.
      def self.compose_title(parts) = Titles.compose_title(parts)
      def self.join_non_sort(non_sort, title) = Titles.join_non_sort(non_sort, title)
      def self.fold_type(str) = Access.fold_type(str)
    end
  end
end
