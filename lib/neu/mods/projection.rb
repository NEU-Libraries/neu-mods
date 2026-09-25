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

      # --- Scalars / simple arrays --------------------------------------------

      # MODS repeats typeOfResource, and repeats physicalDescription (and form and
      # extent within one), so all four are :many. A record that is both text and
      # a still image used to project as text alone.
      def resource_type = labeled_texts_at("/mods:mods/mods:typeOfResource")

      # MODS puts @displayLabel on physicalDescription, not on the form, extent,
      # digitalOrigin, reformattingQuality or note inside it -- so these four
      # take the label off their parent. `from: ".."` says which element the
      # header comes from; the value still comes from the element itself.
      def format = labeled_texts_at("/mods:mods/mods:physicalDescription/mods:form", from: "..")
      def extent = labeled_texts_at("/mods:mods/mods:physicalDescription/mods:extent", from: "..")
      def digital_origin = labeled_texts_at("/mods:mods/mods:physicalDescription/mods:digitalOrigin", from: "..")

      # A genre is a browse axis, so its entry carries the vocabulary the term
      # came from. The other labeled fields do not: nothing gates on their
      # vocabulary, and three more keys on fifteen fields is JSON no consumer
      # reads.
      def genres = labeled_texts_at("/mods:mods/mods:genre", authority: true)

      # Who the resource is for. The last displayed top-level element with no
      # projection at all: a record naming its audience said so to nobody.
      def target_audience = labeled_texts_at("/mods:mods/mods:targetAudience")

      # Read with its line breaks intact. A legacy contents list separates its
      # entries by newline, and the whitespace collapse every other field wants
      # ran the entries together into one line -- there the break IS the
      # structure, not stray formatting. A "--"-separated list is unaffected.
      def table_of_contents
        doc.xpath("/mods:mods/mods:tableOfContents", NAMESPACE).filter_map do |node|
          lines = Canonicalize.canonical_lines(node.text)
          labeled(lines, node) unless lines.empty?
        end
      end

      def reformatting_quality
        labeled_texts_at("/mods:mods/mods:physicalDescription/mods:reformattingQuality", from: "..")
      end

      # A note about the object rather than about the work -- "Scanned at 600
      # dpi" belongs beside the extent, not beside a content note. Projected as
      # plain strings like its physicalDescription siblings: #notes keeps @type
      # because the type changes what a top-level note means, and nothing here
      # turns on it.
      def physical_description_notes = labeled_texts_at("/mods:mods/mods:physicalDescription/mods:note", from: "..")

      # An LCC or DDC call number. Note this is NOT the same concept as Atlas's
      # classification_ssim, which carries a FileSet content-type vocabulary --
      # the name collision is accidental and the consumer has to pick a free
      # Solr field.
      def classification = labeled_texts_at("/mods:mods/mods:classification")

      # Every top-level note, keeping its @type. The type carries meaning -- a
      # "statement of responsibility" is not a "funding" note -- so flattening
      # them into bare strings would repeat the accessCondition mistake.
      def notes
        doc.xpath("/mods:mods/mods:note", NAMESPACE).filter_map do |node|
          value = clean(node.text)
          { type: clean(node["type"]), value: value, **qualifiers_of(node) } if value
        end
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

      private

      # --- helpers -------------------------------------------------------------

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
