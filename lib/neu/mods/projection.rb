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

      # --- Subjects ------------------------------------------------------------

      # The editable free-text keyword set (Cerberus simple form): topics under the
      # attribute-free keyword subjects only.
      def keywords
        keyword_subjects.flat_map { |s| texts_under(s, "mods:topic") }
      end

      # Neither child carries heading text: cartographics is a structured
      # coordinate a reader reaches through #map_data, and geographicCode is a
      # MARC code rather than a place name.
      HEADING_OMITTED_CHILDREN = %w[cartographics geographicCode].freeze

      # What a cataloguer puts between the steps of a pre-coordinated heading.
      # Here rather than with the consumer because the composed heading is a
      # projected value now: a display and an index that both read it cannot
      # separate it differently. Spaces included, which is the separator DRS
      # has displayed for years.
      HEADING_SEPARATOR = " -- "

      # A <subject><name> with no @type reaches the corporate axis. The display
      # already composes such a name, because #subject_heading_part never
      # consulted @type, so the alternative is a heading a reader sees and no
      # browse holds. Corporate rather than personal: MODS expects
      # @type="personal" on a person, and the untyped subject names DRS holds
      # are institutional.
      TYPELESS_NAME_SUBJECT_TYPE = "corporate"

      # Every top-level <subject> as ONE heading, its parts in document order.
      # A pre-coordinated heading like "Salt marshes--Massachusetts--20th
      # century" is a single statement, and the per-axis fields below cannot say
      # which parts belonged together: they pool every topic on the record into
      # one list, so a fragment of a heading and a whole heading read alike.
      #
      # The parts stay, because the Advanced edit form and a consumer wanting
      # one step of a heading both ask for them. `heading:` is the same parts
      # joined, and it is here rather than left to each caller because the
      # composed heading is now BOTH the string a display renders and the
      # string a browse index holds. Two callers joining independently is how
      # a displayed value and an indexed value drift apart, and this join
      # makes them the same string rather than two that happen to match.
      #
      # `axis:` names the MODS element the heading's MAIN term came from, which
      # is the first child that carries heading text. A consumer cannot derive
      # it from the parts -- they are bare strings -- and it is the fact that
      # says which browse a heading belongs to: "Salt marshes -- Massachusetts"
      # is a topic heading with a place subdivision, not a place. Reported as
      # the element name, so the browse vocabulary stays with the consumer.
      def subject_headings
        doc.xpath("/mods:mods/mods:subject", NAMESPACE).filter_map do |node|
          axis_node = heading_axis_node(node)
          parts = subject_heading_parts(node)
          next if axis_node.nil? || parts.empty?

          { parts: parts, heading: parts.join(HEADING_SEPARATOR), axis: heading_axis(axis_node),
            **authority_of(axis_node), **qualifiers_of(node) }
        end
      end

      # Every <topic> under any top-level <subject> (the access-copy projection,
      # equivalent to Atlas's extract_topical_subjects).
      def topical_subjects = texts_at("/mods:mods/mods:subject/mods:topic")

      # The other subject axes. Cerberus's IPTC ingest writes subject/geographic
      # from the IPTC City and State fields, so this one was also being written
      # on every batch and read back by nothing.
      def geographic_subjects = texts_at("/mods:mods/mods:subject/mods:geographic")
      def temporal_subjects = texts_at("/mods:mods/mods:subject/mods:temporal")

      # Name subjects compose through the same display-value port as #names, so
      # one person reads the same whether they authored the work or are its
      # subject.
      def personal_name_subjects = name_subjects("personal")
      def corporate_name_subjects = name_subjects("corporate")

      # The last unprojected member of a closed set: every other subject child
      # already has a field, so leaving this one out made "what a subject can
      # carry" arbitrary rather than complete.
      def occupation_subjects = texts_at("/mods:mods/mods:subject/mods:occupation")

      def genre_subjects = texts_at("/mods:mods/mods:subject/mods:genre")

      # A MARC GAC code. Projected as the record wrote it: turning it into a
      # place name needs a lookup table, which is the same call the gem already
      # made for MARC relators -- the label vocabulary belongs to the consumer.
      def geographic_code_subjects = texts_at("/mods:mods/mods:subject/mods:geographicCode")

      # A subject that is a work has a nonSort, a subTitle and part numbers like
      # any other titleInfo, so it composes through the same port as the main
      # title rather than taking titleInfo/title alone.
      def title_subjects
        doc.xpath("/mods:mods/mods:subject/mods:titleInfo", NAMESPACE).filter_map { |node| composed_title_of(node) }
      end

      # Kept structured for the reason #map_data is. Flattening country / state
      # / city into "United States -- New York (State) -- Parksville" would make
      # a consumer that wants the city alone unpick a sentence.
      #
      # This is the axis bdr_43888.mods.xml uses INSTEAD of subject/geographic,
      # so that record projected no place at all -- a live ingest path, not a
      # hypothetical.
      def hierarchical_geographic_subjects
        doc.xpath("/mods:mods/mods:subject/mods:hierarchicalGeographic", NAMESPACE).filter_map do |node|
          entry = HIERARCHICAL_GEOGRAPHIC_LEVELS.to_h { |level| [level, child_text(node, "mods:#{camelize(level)}")] }
          entry if entry.values.any?
        end
      end

      # --- Names ---------------------------------------------------------------

      # One name as the access copy wants it. `affiliation` is how a reader
      # tells one J. Doe from another, and it is the field an institutional
      # repository most wants: it repeats in the schema, so it is an array.
      #
      # Added to the entry rather than as a parallel field, so a name and its
      # affiliation cannot be zipped together wrongly by a consumer.
      def name_entry(node)
        {
          name: name_display_value_w_date(node),
          roles: name_roles(node),
          affiliation: texts_under(node, "mods:affiliation"),
          # @usage is fixed="primary" in the schema and exists to nominate the
          # principal name. A record that sets it has said which name leads,
          # and without it a consumer grouping role-less names can only guess.
          usage: attr_value(node, "usage"),
          alternative_names: alternative_names(node),
          # The vocabulary this name was taken from, read off the <name> alone.
          # A marcrelator <roleTerm> inside it says what the person DID, not
          # which list the name came from -- see #authority_of.
          **authority_of(node),
          **qualifiers_of(node)
        }
      end

      # mods:alternativeName, new in MODS 3.7: a second form of the same name,
      # not a second name. Composed with the ENCLOSING name's @type, because
      # alternativeName carries @altType rather than @type and an alternative
      # for a personal name is still a personal name -- read from its own
      # attributes it would compose "Doe Jane" where the name above it
      # composes "Doe, Jane".
      def alternative_names(node)
        node.xpath("mods:alternativeName", NAMESPACE).filter_map do |alt|
          name_display_value_w_date(alt, attr_value(node, "type"))
        end
      end

      # All top-level names as { name:, roles: }. `name` reproduces the `mods` gem's
      # display_value_w_date (including its quirks -- faithfully, so existing Solr/
      # display output is preserved). MODS repeats `role` on one name, and a
      # cataloguer who records that a person both wrote and edited a work means
      # both. Each term prefers the type="text" roleTerm, falling back to the raw
      # code (NOT MARC-relator-translated -- see README).
      #
      # A name with no name text drops out. A mods:name carrying only a role
      # projected { name: nil, roles: ["edt"] }, which a display renders as a
      # labelled empty row and which every consumer had to guard against with
      # its own compact_blank. #preserved_names deliberately keeps it: that list
      # tells a curator what the XML holds, so an element they need to fix has
      # to stay visible there.
      def names
        doc.xpath("/mods:mods/mods:name", NAMESPACE).filter_map do |node|
          entry = name_entry(node)
          entry if entry[:name]
        end
      end

      # Editable (depositor-managed) creators: the plain names (no authority
      # markers) with a Creator role, as STRUCTURED parts for form pre-fill --
      # distinct from #names, which composes display strings for the access copy.
      def editable_personal_creators
        editable_creator_nodes("personal").map do |node|
          { given: clean_part(joined_parts(node, "given")), family: clean_part(joined_parts(node, "family")) }
        end
      end

      def editable_corporate_creators
        editable_creator_nodes("corporate").map { |node| { name: clean_part(non_date_parts_joined(node)) } }
      end

      # Names the editable form does NOT manage (authority-bearing or non-Creator)
      # -- for read-only display ("these exist; edit via the XML tab"). Composed
      # display string + roles, like #names but filtered to the preserved set.
      def preserved_names
        doc.xpath("/mods:mods/mods:name", NAMESPACE)
           .reject { |node| editable_creator_name?(node) }
           .map { |node| name_entry(node) }
      end

      # --- Scalars / simple arrays --------------------------------------------

      # { term:, object_part:, script: } per language element. Prefer the
      # type="text" term, and translate a code-only one through the ISO 639
      # registry. A record saying `eng` projects "English", so the display and
      # the Solr language facet read the same value rather than the facet
      # showing codes. An unrecognised code survives as itself.
      #
      # An entry rather than a bare string because @objectPart changes what the
      # record is claiming. `<language objectPart="subtitles">spa` says the
      # subtitles are Spanish, and projected flat it said the resource was --
      # which is the case a captioned video hits every time. The script rides
      # along for the same reason a name's role does: a consumer cannot
      # recover it from the term.
      def languages
        doc.xpath("/mods:mods/mods:language", NAMESPACE).filter_map do |lang|
          node = language_term_node(lang)
          term = language_term_of(node)
          next unless term

          # The authority comes off the <languageTerm> the term was read from,
          # never off the <language> around it: MODS carries @authority on the
          # term, and a code-only record declares `iso639-2b` there.
          { term: term, object_part: attr_value(lang, "objectPart"), script: script_term(lang),
            **authority_of(node), **qualifiers_of(lang) }
        end
      end

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

      # subject/cartographics, kept structured. Composing "scale ; projection
      # coordinates" into one string is display policy, and this gem does not own
      # that -- a consumer that wants only the coordinates should not have to
      # unpick a sentence to get them.
      def map_data
        doc.xpath("/mods:mods/mods:subject/mods:cartographics", NAMESPACE).filter_map do |node|
          entry = {
            scale: child_text(node, "mods:scale"),
            projection: child_text(node, "mods:projection"),
            coordinates: child_text(node, "mods:coordinates")
          }
          # cartographics carries neither attribute; the enclosing subject does.
          entry.merge(qualifiers_of(node.parent)) if entry.values.any?
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

      # The eleven children the XSD allows under hierarchicalGeographic, in the
      # order MODS lists them -- broadest first, which is also the order a
      # consumer composing a place string wants to reverse.
      HIERARCHICAL_GEOGRAPHIC_LEVELS = %i[
        continent country province region state territory county city
        city_section island area
      ].freeze

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

      # The corporate axis also takes a subject name with NO @type (see
      # TYPELESS_NAME_SUBJECT_TYPE), so a name the heading composes reaches a
      # browse instead of displaying and projecting nowhere.
      def name_subjects(type)
        predicate = "@type='#{type}'"
        predicate = "#{predicate} or not(@type)" if type == TYPELESS_NAME_SUBJECT_TYPE
        doc.xpath("/mods:mods/mods:subject/mods:name[#{predicate}]", NAMESPACE)
           .filter_map { |node| name_display_value_w_date(node) }
      end

      # The child a heading's axis and authority come from: the first one
      # carrying heading text. A heading with none projects nothing, so its
      # axis is never asked for.
      def heading_axis_node(node)
        node.xpath("mods:*", NAMESPACE).find { |child| subject_heading_part(child).compact.any? }
      end

      # The axis of one heading child, as the MODS element that holds it. A
      # <name> splits by @type, because a person and an organisation are
      # separate browses and MODS says which on the element rather than in the
      # element name.
      def heading_axis(child)
        return "#{attr_value(child, "type") || TYPELESS_NAME_SUBJECT_TYPE}_name" if child.name == "name"

        snake_case(child.name)
      end

      def subject_heading_parts(node)
        node.xpath("mods:*", NAMESPACE).flat_map { |child| subject_heading_part(child) }.compact
      end

      def subject_heading_part(child)
        return [] if HEADING_OMITTED_CHILDREN.include?(child.name)

        case child.name
        when "name" then [name_display_value_w_date(child)]
        when "titleInfo" then [composed_title_of(child)]
        # Each level is its own part, so a hierarchical place reads as the steps
        # of the heading rather than as one run-together string.
        when "hierarchicalGeographic" then child.xpath("mods:*", NAMESPACE).map { |level| clean(level.text) }
        else split_heading_text(clean(child.text))
        end
      end

      # A cataloguer who typed a whole heading into one element as "A--B--C"
      # made the same statement as one who structured it into siblings, so both
      # arrive here as the same parts.
      def split_heading_text(text)
        return [] if text.nil?
        return [text] unless text.include?("--")

        text.split("--").filter_map { |part| clean(part) }
      end

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

      # Which <languageTerm> the language of one element is read from, text
      # form preferred. The node is located separately from its text because
      # the authority governing the term sits on that element: the value and
      # its vocabulary have to come from one node rather than from two
      # independent lookups.
      def language_term_node(lang)
        lang.at_xpath("mods:languageTerm[@type='text']", NAMESPACE) ||
          lang.at_xpath("mods:languageTerm", NAMESPACE)
      end

      # A text term as the record wrote it; a code through the ISO 639
      # registry, so a record saying `eng` projects "English".
      def language_term_of(node)
        return nil unless node

        return clean(node.text) if attr_value(node, "type") == "text"

        code = clean(node.text)
        code && LanguageCodes.term(code)
      end

      # A scriptTerm, text form preferred. No registry expands a code here: the
      # ISO 15924 list is not vendored, and inventing a half-translation would
      # be worse than handing the consumer what the record wrote.
      def script_term(lang)
        text = lang.at_xpath("mods:scriptTerm[@type='text']", NAMESPACE)
        return clean(text.text) if text

        clean(lang.at_xpath("mods:scriptTerm", NAMESPACE)&.text)
      end
    end
  end
end
