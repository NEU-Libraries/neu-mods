# frozen_string_literal: true

require "date"
require_relative "../namespaces"
require_relative "../canonicalize"
require_relative "support"

module NEU
  module MODS
    module Projection
      # The seven originInfo date elements, each projected as flat fields.
      module Dates
        include Support

        # The w3cdtf date shapes a date element may stop at: year, year-month, a
        # full date, or a full date with a time. Matching the shape explicitly,
        # rather than widening DateTime.parse, is what lets the declared precision
        # fall out of the parse instead of being guessed after it.
        #
        # A value outside these shapes is NOT a date, and #parse_w3cdtf says so
        # rather than guessing. Ruby's DateTime.parse fills the components it
        # cannot find from the CURRENT date, so "19uu" -- standard MARC 008 fill,
        # which the v1 corpus carries at scale -- asserted today's date at "day"
        # precision, and the assertion changed daily. What the record actually
        # wrote survives in the matching *_text field instead.
        W3CDTF_DATE = /\A(\d{4})(?:-(\d{2})(?:-(\d{2})(T\S+)?)?)?\z/

        # ISO 8601 basic format: the same year, month and day written without the
        # hyphens. Accepted ONLY where the record declares @encoding="iso8601",
        # because eight bare digits are a date only because the encoding says so
        # -- an accession number is eight digits too, and guessing is the mistake
        # dropping the DateTime.parse fallback exists to prevent.
        ISO8601_BASIC_DATE = /\A(\d{4})(?:(\d{2})(?:(\d{2})(T\S+)?)?)?\z/

        # @encoding, folded. MODS leaves the attribute an open string and records
        # write "iso8601" and "ISO-8601" alike.
        ISO8601_ENCODING = "iso8601"

        # What #date_parts returns when the element is absent entirely, so an
        # absent date is distinguishable from one present and unparseable.
        EMPTY_DATE = { value: nil, precision: nil, end_value: nil, end_precision: nil,
                       qualifier: nil, key_date: nil, text: nil,
                       display_label: nil, event_type: nil }.freeze

        # MODS puts seven date elements under originInfo and this reads all of
        # them. dateCaptured is when the object was digitised and dateModified is
        # when the resource changed -- preservation and cataloguing provenance,
        # which a consumer may keep off a page but cannot recover from anywhere
        # else. dateValid is the period the content holds for, and dateOther is
        # where a date fitting no other element lands, which is where a quantity
        # of migrated v1 date data goes.
        #
        # The seven date elements MODS puts under originInfo, in the order a
        # consumer deciding a place header reads them.
        DATE_ELEMENTS = %w[dateIssued dateCreated copyrightDate dateCaptured
                           dateValid dateOther dateModified].freeze

        def date_created_parts = date_parts("dateCreated")

        def date_issued_parts = date_parts("dateIssued")

        def copyright_date_parts = date_parts("copyrightDate")

        def date_captured_parts = date_parts("dateCaptured")

        def date_valid_parts = date_parts("dateValid")

        def date_other_parts = date_parts("dateOther")

        def date_modified_parts = date_parts("dateModified")

        def date_created = date_created_parts[:value]

        def date_created_precision = date_created_parts[:precision]

        def date_created_end = date_created_parts[:end_value]

        def date_created_end_precision = date_created_parts[:end_precision]

        def date_created_qualifier = date_created_parts[:qualifier]

        def date_created_key_date = date_created_parts[:key_date]

        def date_created_text = date_created_parts[:text]

        def date_created_display_label = date_created_parts[:display_label]

        def date_created_event_type = date_created_parts[:event_type]

        def date_issued = date_issued_parts[:value]

        def date_issued_precision = date_issued_parts[:precision]

        def date_issued_end = date_issued_parts[:end_value]

        def date_issued_end_precision = date_issued_parts[:end_precision]

        def date_issued_qualifier = date_issued_parts[:qualifier]

        def date_issued_key_date = date_issued_parts[:key_date]

        def date_issued_text = date_issued_parts[:text]

        def date_issued_display_label = date_issued_parts[:display_label]

        def date_issued_event_type = date_issued_parts[:event_type]

        def copyright_date = copyright_date_parts[:value]

        def copyright_date_precision = copyright_date_parts[:precision]

        def copyright_date_end = copyright_date_parts[:end_value]

        def copyright_date_end_precision = copyright_date_parts[:end_precision]

        def copyright_date_qualifier = copyright_date_parts[:qualifier]

        def copyright_date_key_date = copyright_date_parts[:key_date]

        def copyright_date_text = copyright_date_parts[:text]

        def copyright_date_display_label = copyright_date_parts[:display_label]

        def copyright_date_event_type = copyright_date_parts[:event_type]

        def date_captured = date_captured_parts[:value]

        def date_captured_precision = date_captured_parts[:precision]

        def date_captured_end = date_captured_parts[:end_value]

        def date_captured_end_precision = date_captured_parts[:end_precision]

        def date_captured_qualifier = date_captured_parts[:qualifier]

        def date_captured_key_date = date_captured_parts[:key_date]

        def date_captured_text = date_captured_parts[:text]

        def date_captured_display_label = date_captured_parts[:display_label]

        def date_captured_event_type = date_captured_parts[:event_type]

        def date_valid = date_valid_parts[:value]

        def date_valid_precision = date_valid_parts[:precision]

        def date_valid_end = date_valid_parts[:end_value]

        def date_valid_end_precision = date_valid_parts[:end_precision]

        def date_valid_qualifier = date_valid_parts[:qualifier]

        def date_valid_key_date = date_valid_parts[:key_date]

        def date_valid_text = date_valid_parts[:text]

        def date_valid_display_label = date_valid_parts[:display_label]

        def date_valid_event_type = date_valid_parts[:event_type]

        def date_other = date_other_parts[:value]

        def date_other_precision = date_other_parts[:precision]

        def date_other_end = date_other_parts[:end_value]

        def date_other_end_precision = date_other_parts[:end_precision]

        def date_other_qualifier = date_other_parts[:qualifier]

        def date_other_key_date = date_other_parts[:key_date]

        def date_other_text = date_other_parts[:text]

        def date_other_display_label = date_other_parts[:display_label]

        def date_other_event_type = date_other_parts[:event_type]

        def date_modified = date_modified_parts[:value]

        def date_modified_precision = date_modified_parts[:precision]

        def date_modified_end = date_modified_parts[:end_value]

        def date_modified_end_precision = date_modified_parts[:end_precision]

        def date_modified_qualifier = date_modified_parts[:qualifier]

        def date_modified_key_date = date_modified_parts[:key_date]

        def date_modified_text = date_modified_parts[:text]

        def date_modified_display_label = date_modified_parts[:display_label]

        def date_modified_event_type = date_modified_parts[:event_type]

        # The [value, precision] pair the precision work introduced. Retained
        # because it is the documented entry point for a caller that wants both
        # halves and nothing else.
        def date_created_with_precision = [date_created, date_created_precision]

        def date_issued_with_precision = [date_issued, date_issued_precision]

        def copyright_date_with_precision = [copyright_date, copyright_date_precision]

        private

        # [DateTime, precision] for a string matching one date shape, or nil for a
        # string that matches none. A shape-matched but impossible date (2026-13,
        # 2026-02-30) reaches DateTime, raises, and is nil like any other
        # unreadable value; the caller keeps its literal text.
        #
        # A full timestamp goes through DateTime.parse rather than being rebuilt,
        # so the time of day a dateModified declares survives. Its precision is
        # "day" because that is the finest granularity a consumer renders.
        def parse_shaped_date(regexp, str)
          m = regexp.match(str)
          return nil unless m
          return [DateTime.parse(str), "day"] if m[4]

          [DateTime.new(m[1].to_i, (m[2] || 1).to_i, (m[3] || 1).to_i), declared_precision(m)]
        rescue Date::Error
          nil
        end

        # [DateTime, precision], reading the shape the record's own @encoding
        # declares. w3cdtf is tried first and unconditionally, because it is what
        # the corpus and Atlas's own MODS template write; the basic ISO form is
        # tried only for a record that asked for it.
        def parse_declared_date(str, encoding)
          parse_shaped_date(W3CDTF_DATE, str) ||
            (iso8601?(encoding) ? parse_shaped_date(ISO8601_BASIC_DATE, str) : nil)
        end

        def iso8601?(encoding)
          encoding.to_s.downcase.delete("-") == ISO8601_ENCODING
        end

        # The granularity the record stopped at, which is the whole point of
        # matching the shape rather than widening the parse.
        def declared_precision(match)
          return "day" if match[3]

          match[2] ? "month" : "year"
        end

        # Everything a record declared about one originInfo date, as
        # { value:, precision:, end_value:, end_precision:, qualifier:, key_date:,
        #   text: }.
        #
        # A date is not a scalar. Precision established that: a year-only date
        # parses to January 1st, and no consumer downstream can tell that month
        # and day from a record that claimed them. A range and a qualifier are the
        # same kind of claim, and dropping them breaks the same rule -- a
        # preservation repository must not project a value the record did not
        # give. A ranged record was worse than that: #at_xpath took the first
        # node, so one end of the range was PROMOTED to be the date, and the
        # output was indistinguishable from a single certain year.
        #
        # The parts are projected as separate flat fields rather than one nested
        # value, because the value half has three consumers that need a real date
        # object -- a Solr sort key, a citation year and an OAI date. Those three
        # are also why the literal gets its own field rather than sharing the
        # value: a sort key cannot hold "ca. 1920", and a display can.
        #
        # One originInfo date element, read by its attributes rather than by
        # position. A record is free to write point="end" first, and taking the
        # first node would then invert the range.
        #
        # ONE DATE PER TYPE is the rule, and a repeated, non-ranged, unflagged
        # date of the same type is discarded. A range is one date with two ends,
        # which @point already models, and every consumer of the value -- a sort
        # key, a citation year, an OAI date -- holds exactly one. Note the
        # contrast with a repeated publisher, which survives because
        # publication_information is :many; dates differ because the value is
        # singular downstream, not because repetition went unnoticed.
        def date_parts(element)
          nodes = doc.xpath("/mods:mods/mods:originInfo/mods:#{element}", NAMESPACE)
          return EMPTY_DATE if nodes.empty?

          finish = nodes.find { |n| attr_value(n, "point") == "end" }
          date_entry(start_date_node(nodes), finish, nodes)
        end

        # The node the value comes from: the flagged one, then the declared
        # start, then document order.
        #
        # keyDate leads because the flag is the record nominating its own
        # principal date. Projecting the flag while reading the value from a
        # different node made the two contradict each other -- a consumer was told
        # the record chose this date and then handed the one before it.
        def start_date_node(nodes)
          nodes.find { |n| attr_value(n, "keyDate") == "yes" && attr_value(n, "point") != "end" } ||
            nodes.find { |n| attr_value(n, "point") == "start" } ||
            nodes.find { |n| attr_value(n, "point") != "end" }
        end

        # The end point carries its OWN precision. "1935-06" to "1940" is legal,
        # and reusing the start's granularity for both would assert something the
        # end never claimed -- the precision bug in a new place.
        #
        # The qualifier falls back from the start to the end because v1's loader
        # applied it to both points, and a record marking only one is still
        # telling us the date is uncertain. An unrecognised value survives as
        # itself: MODS enumerates approximate, inferred and questionable, but the
        # record still said something.
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
            # A date row is headed by its element ("Date created"), and these are
            # the two things a record can say to override that.
            display_label: attr_value(origin, "displayLabel"),
            event_type: attr_value(origin, "eventType")
          }
        end

        # [value, precision, text]. A node whose text is not a w3cdtf date yields
        # no value and keeps its literal instead: "ca. 1920", "19th century" and
        # "1918-1921" in one element are all real statements a cataloguer made,
        # and a preservation repository must neither invent a date for them nor
        # delete them. Only the start node's literal is kept -- the observed
        # corpus writes an unreadable date as one element, and an end point that
        # needs its own literal has never been seen.
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
