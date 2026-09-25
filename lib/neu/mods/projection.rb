# frozen_string_literal: true

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
require_relative "projection/identifiers"

module NEU
  module MODS
    # Node -> plain data: what a MODS document projects to for indexing and
    # display. Each MODS area is its own mixin under projection/; this module
    # composes them and owns FIELDS. See docs/fields.md.
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
      include Identifiers

      # Field name => :one or :many. #to_h and Atlas's Metadata::MODS attribute
      # set are both derived from it, so each key is a public method name that
      # a consumer depends on. See docs/fields.md.
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
        # Nine generated rows for each of the seven date elements (docs/dates.md).
        **Dates::DATE_FIELD_ROWS,

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

      # The cardinality a projected value has, for checking it against its FIELDS
      # row: an Array is :many and anything else is :one.
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
