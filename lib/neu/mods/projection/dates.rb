# frozen_string_literal: true

require "date"
require_relative "../namespaces"
require_relative "../canonicalize"
require_relative "support"

module NEU
  module MODS
    module Projection
      # The seven originInfo date elements, each projected as nine flat fields.
      # See docs/dates.md, which lists every generated field.
      module Dates
        include Support

        # Year, year-month, full date, or full date with a time. Never fall back
        # to a bare DateTime.parse: it fills missing parts from TODAY, so "19uu"
        # would parse as the current date.
        W3CDTF_DATE = /\A(\d{4})(?:-(\d{2})(?:-(\d{2})(T\S+)?)?)?\z/

        # The same shapes without hyphens, read ONLY under @encoding="iso8601":
        # an accession number is eight digits too.
        ISO8601_BASIC_DATE = /\A(\d{4})(?:(\d{2})(?:(\d{2})(T\S+)?)?)?\z/

        # @encoding, folded, so "ISO-8601" matches too.
        ISO8601_ENCODING = "iso8601"

        # Field prefix => the MODS element it reads, in FIELDS order. Written out
        # rather than derived, so a search for a field name lands here.
        DATE_FIELDS = {
          date_created: "dateCreated",
          date_issued: "dateIssued",
          copyright_date: "copyrightDate",
          date_captured: "dateCaptured",
          date_valid: "dateValid",
          date_other: "dateOther",
          date_modified: "dateModified"
        }.freeze

        # Field suffix => the key of the #date_parts entry it reads. Each element
        # projects one field per row.
        DATE_KEYS = {
          "" => :value,
          "_precision" => :precision,
          "_end" => :end_value,
          "_end_precision" => :end_precision,
          "_qualifier" => :qualifier,
          "_key_date" => :key_date,
          "_text" => :text,
          "_display_label" => :display_label,
          "_event_type" => :event_type
        }.freeze

        # What #date_parts returns when the element is absent entirely, so an
        # absent date is distinguishable from one present and unparseable.
        EMPTY_DATE = DATE_KEYS.values.to_h { |key| [key, nil] }.freeze

        # The FIELDS rows for the generated fields, each element's rows together.
        DATE_FIELD_ROWS = DATE_FIELDS.keys.product(DATE_KEYS.keys)
                                     .to_h { |field, suffix| [:"#{field}#{suffix}", :one] }.freeze

        # The same seven elements as DATE_FIELDS, in the order a consumer deciding
        # a place header reads them. Keep this order: #origin_date_elements
        # returns elements in it.
        DATE_ELEMENTS = %w[dateIssued dateCreated copyrightDate dateCaptured
                           dateValid dateOther dateModified].freeze

        # A *_parts method per element and an accessor per DATE_FIELDS and
        # DATE_KEYS pair (date_issued_end, date_created_text, ...). A search for
        # `def date_issued_end` finds nothing; search the two tables instead.
        DATE_FIELDS.each do |field, element|
          define_method(:"#{field}_parts") { date_parts(element) }
          DATE_KEYS.each do |suffix, key|
            define_method(:"#{field}#{suffix}") { date_parts(element)[key] }
          end
        end

        # [value, precision], for a caller that wants those two alone.
        def date_created_with_precision = [date_created, date_created_precision]
        def date_issued_with_precision = [date_issued, date_issued_precision]
        def copyright_date_with_precision = [copyright_date, copyright_date_precision]

        private

        # [DateTime, precision], or nil for no shape or an impossible date
        # (2026-02-30). A timestamp is parsed whole, so its time of day survives.
        def parse_shaped_date(regexp, str)
          m = regexp.match(str)
          return nil unless m
          return [DateTime.parse(str), "day"] if m[4]

          [DateTime.new(m[1].to_i, (m[2] || 1).to_i, (m[3] || 1).to_i), declared_precision(m)]
        rescue Date::Error
          nil
        end

        # w3cdtf always, then the basic ISO form only if the record declares it.
        def parse_declared_date(str, encoding)
          parse_shaped_date(W3CDTF_DATE, str) ||
            (iso8601?(encoding) ? parse_shaped_date(ISO8601_BASIC_DATE, str) : nil)
        end

        def iso8601?(encoding)
          encoding.to_s.downcase.delete("-") == ISO8601_ENCODING
        end

        # The granularity the record stopped at.
        def declared_precision(match)
          return "day" if match[3]

          match[2] ? "month" : "year"
        end

        # Everything a record declared about one date element. Nodes are chosen
        # by @point and @keyDate, never by position: a record may write the end
        # first. One date per element; see docs/dates.md.
        def date_parts(element)
          nodes = doc.xpath("/mods:mods/mods:originInfo/mods:#{element}", NAMESPACE)
          return EMPTY_DATE if nodes.empty?

          finish = nodes.find { |n| attr_value(n, "point") == "end" }
          date_entry(start_date_node(nodes), finish, nodes)
        end

        # The flagged node, then the declared start, then document order. The
        # flag leads so the value and #key_date always describe the same node.
        def start_date_node(nodes)
          nodes.find { |n| attr_value(n, "keyDate") == "yes" && attr_value(n, "point") != "end" } ||
            nodes.find { |n| attr_value(n, "point") == "start" } ||
            nodes.find { |n| attr_value(n, "point") != "end" }
        end

        # The end carries its OWN precision ("1935-06" to "1940" is legal). The
        # qualifier falls back from the start to the end, because v1 applied it
        # to both points.
        def date_entry(start, finish, nodes)
          value, precision, text = node_date(start)
          end_value, end_precision = node_date(finish)
          origin = (start || finish)&.parent
          {
            value: value,
            precision: precision,
            end_value: end_value,
            end_precision: end_precision,
            qualifier: attr_value(start, "qualifier") || attr_value(finish, "qualifier"),
            key_date: nodes.any? { |n| attr_value(n, "keyDate") == "yes" },
            text: text,
            # Off the enclosing originInfo, because that is where MODS puts both.
            display_label: attr_value(origin, "displayLabel"),
            event_type: attr_value(origin, "eventType")
          }
        end

        # [value, precision, text]. An unreadable date keeps its literal as text
        # ("ca. 1920") instead of a value: never invent a date, never drop one.
        def node_date(node)
          return [nil, nil, nil] unless node

          str = Canonicalize.canonical_ws(node.text)
          return [nil, nil, nil] if str.empty?

          parsed = parse_declared_date(str, attr_value(node, "encoding"))
          return [parsed[0], parsed[1], nil] if parsed

          [nil, nil, str]
        end
      end
    end
  end
end
