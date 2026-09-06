# frozen_string_literal: true

require "date"

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
      # --- Title ---------------------------------------------------------------

      # Structured primary-title parts, byte-faithful to the document. nil for an
      # absent part (the Cerberus form treats nil as "not present"); to_h coerces
      # to "" for the Atlas main_title.
      #
      # Faithful on purpose: this is what Cerberus pre-fills its edit forms from
      # (MODSFields for the Metadata tab, load_advanced! for the Advanced tab),
      # and MODSMerge writes back whatever the form posts. Normalising here would
      # rewrite the curator's characters in the preservation XML on the next save.
      # #access_title_parts is the normalised surface.
      def title_parts
        title_parts_of(primary_title_info)
      end

      # The variant titles, each composed and normalised like the main title.
      # MODS repeats titleInfo, so a record may carry more than one of a type.
      # These are what keeps the primary-title fallback's refusal to promote a
      # variant from hiding anything: the variant still reaches a reader, under
      # a label that says which kind of title it is.
      def alternative_title = variant_titles("alternative")
      def uniform_title = variant_titles("uniform")
      def translated_title = variant_titles("translated")
      def abbreviated_title = variant_titles("abbreviated")

      # Composed display title (the former Atlas MODSDecoration#plain_title), driven
      # off the scoped primary title.
      def plain_title
        Projection.compose_title(title_parts)
      end

      # Pure title composition over a parts hash, factored out of #plain_title so
      # callers that already hold the parts -- e.g. Atlas's access-copy model --
      # can compose the display title WITHOUT re-parsing XML on the read path
      # (reaching for Nokogiri in a decorator is the smell this avoids). Keys:
      # :non_sort :title :subtitle :part_name :part_number (nil or "" for absent).
      # Returns "" when there is no title. Exposed as NEU::MODS.compose_title.
      def self.compose_title(parts)
        return "" if parts[:title].to_s.strip.empty?

        optional = { ": " => parts[:subtitle], " - " => parts[:part_name], ", " => parts[:part_number] }
        suffix = optional.filter_map { |sep, val| "#{sep}#{val}" unless val.to_s.strip.empty? }.join
        "#{join_non_sort(parts[:non_sort], parts[:title])}#{suffix}"
      end

      # Characters that bind a nonSort to the word after it. An elided article
      # takes no space -- "L'Etranger", not "L' Etranger" -- and the same holds
      # for a hyphenated prefix. U+2019 is the curly apostrophe, escaped rather
      # than literal to keep lib/ pure ASCII (see the source-purity spec).
      NON_SORT_BINDING = ["'", "\u2019", "-"].freeze

      # MODS says a nonSort carries whatever separator it needs, so the historical
      # composition simply concatenated. That only holds while the authored
      # trailing space survives, and it does not: #child_text canonicalizes
      # whitespace on read, so `<nonSort>The </nonSort>` arrives here as "The" and
      # the title came out as "TheHobbit". Composing the separator instead makes
      # the output right whether or not the source kept one -- which matters,
      # because an invisible trailing space is not something a curator, a
      # hand-edit or a third-party producer can be relied on to preserve.
      #
      # Callers that DO pass the space (Atlas's access-copy model) are unaffected:
      # a nonSort already ending in whitespace is joined as-is.
      def self.join_non_sort(non_sort, title)
        prefix = non_sort.to_s
        return title.to_s if prefix.empty?
        return "#{prefix}#{title}" if prefix.end_with?(" ") || prefix.end_with?(*NON_SORT_BINDING)

        "#{prefix} #{title}"
      end

      # --- Abstract / access ---------------------------------------------------

      def abstract
        join_paragraphs(abstract_nodes)
      end

      # Every top-level accessCondition joined, regardless of @type. Retained
      # because it is the only projection that carries an untyped or
      # unrecognised accessCondition, which the two typed fields below cannot
      # see -- a consumer that renders only those needs this as its fallback.
      def access_condition
        join_paragraphs(doc.xpath("/mods:mods/mods:accessCondition", NAMESPACE))
      end

      # The two @type values MODS defines, projected apart. Collapsing them into
      # one value presented an access *restriction* to a reader as a *licence*,
      # which is the one defect in this area that misinforms someone about their
      # rights rather than merely hiding a field.
      def use_and_reproduction = access_conditions_of_type("use and reproduction")
      def restriction_on_access = access_conditions_of_type("restriction on access")

      # --- Subjects ------------------------------------------------------------

      # The editable free-text keyword set (Cerberus simple form): topics under the
      # attribute-free keyword subjects only.
      def keywords
        keyword_subjects.flat_map { |s| s.xpath("mods:topic", NAMESPACE).map { |t| t.text.strip } }
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
        doc.xpath("/mods:mods/mods:subject/mods:titleInfo", NAMESPACE).filter_map do |node|
          parts = title_parts_of(node).transform_values { |value| NEU::MODS.normalize(value.to_s) }
          clean(Projection.compose_title(parts))
        end
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
          role: name_role(node),
          affiliation: texts_under(node, "mods:affiliation")
        }
      end

      # All top-level names as { name:, role: }. `name` reproduces the `mods` gem's
      # display_value_w_date (including its quirks -- faithfully, so existing Solr/
      # display output is preserved). `role` prefers the type="text" roleTerm,
      # falling back to the raw code (NOT MARC-relator-translated -- see README).
      def names
        doc.xpath("/mods:mods/mods:name", NAMESPACE).map { |node| name_entry(node) }
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
      # display string + role, like #names but filtered to the preserved set.
      def preserved_names
        doc.xpath("/mods:mods/mods:name", NAMESPACE)
           .reject { |node| editable_creator_name?(node) }
           .map { |node| name_entry(node) }
      end

      # --- Scalars / simple arrays --------------------------------------------

      # Prefer the type="text" term, and translate a code-only one through the
      # ISO 639 registry. A record saying `eng` projects "English", so the
      # display and the Solr language facet read the same value rather than the
      # facet showing codes. An unrecognised code survives as itself.
      def languages
        doc.xpath("/mods:mods/mods:language", NAMESPACE).filter_map do |lang|
          text = lang.at_xpath("mods:languageTerm[@type='text']", NAMESPACE)
          next clean(text.text) if text

          code = clean(lang.at_xpath("mods:languageTerm", NAMESPACE)&.text)
          code && LanguageCodes.term(code)
        end
      end

      # MODS repeats typeOfResource, and repeats physicalDescription (and form and
      # extent within one), so all four are :many. A record that is both text and
      # a still image used to project as text alone.
      def resource_type = texts_at("/mods:mods/mods:typeOfResource")
      def format = texts_at("/mods:mods/mods:physicalDescription/mods:form")
      def extent = texts_at("/mods:mods/mods:physicalDescription/mods:extent")
      def digital_origin = texts_at("/mods:mods/mods:physicalDescription/mods:digitalOrigin")

      def genres = texts_at("/mods:mods/mods:genre")

      # originInfo repeats, and so do publisher and edition within one. Cerberus's
      # IPTC ingest writes the publisher from the IPTC Source field on every batch,
      # so this element was being written into the preservation XML and then read
      # back by nothing.
      def publication_information = texts_at("/mods:mods/mods:originInfo/mods:publisher")
      def edition = texts_at("/mods:mods/mods:originInfo/mods:edition")
      def place_of_publication = texts_at("/mods:mods/mods:originInfo/mods:place/mods:placeTerm")
      def issuance = texts_at("/mods:mods/mods:originInfo/mods:issuance")

      # Serials. The @authority a record puts on a frequency is not projected:
      # authority handling is a question the gem defers everywhere else -- for
      # genre, subject and name -- and answering it for one field would be
      # inconsistent.
      def frequency = texts_at("/mods:mods/mods:originInfo/mods:frequency")

      def table_of_contents = texts_at("/mods:mods/mods:tableOfContents")
      def reformatting_quality = texts_at("/mods:mods/mods:physicalDescription/mods:reformattingQuality")

      # An LCC or DDC call number. Note this is NOT the same concept as Atlas's
      # classification_ssim, which carries a FileSet content-type vocabulary --
      # the name collision is accidental and the consumer has to pick a free
      # Solr field.
      def classification = texts_at("/mods:mods/mods:classification")

      # Every top-level note, keeping its @type. The type carries meaning -- a
      # "statement of responsibility" is not a "funding" note -- so flattening
      # them into bare strings would repeat the accessCondition mistake.
      def notes
        doc.xpath("/mods:mods/mods:note", NAMESPACE).filter_map do |node|
          value = clean(node.text)
          { type: clean(node["type"]), value: value } if value
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
          entry if entry.values.any?
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
          entry if entry.values.any?
        end
      end

      def related_series = related_item_titles("series")

      # The host's title plus THIS work's position within it. The host's own
      # name, originInfo and identifier stay out: they belong to the other
      # record, and a transcribed copy goes stale the moment that record is
      # edited. A part is the exception, because a volume, issue and page range
      # describe this article and no other record holds that fact.
      def host_collections
        doc.xpath("/mods:mods/mods:relatedItem[@type='host']", NAMESPACE).filter_map do |node|
          title = child_text(node, "mods:titleInfo/mods:title")
          { title: title, **host_part(node) } if title
        end
      end

      # relatedItem @type values that already have a field of their own, so the
      # catch-all below does not repeat them.
      NAMED_RELATED_ITEM_TYPES = %w[series host].freeze

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
          { type: type, title: title } if title
        end
      end

      # { type:, value: }, because a DOI, an accession number and a collection
      # id are not the same kind of thing and no consumer can tell them apart
      # from the digits alone -- a reader shown a bare 10.1234/x cannot see it
      # is a DOI, and a display cannot decide to linkify it. The same argument
      # #notes already makes for its @type, and #permanent_url already proves
      # the attribute is load-bearing by special-casing @type='hdl'.
      def identifiers
        doc.xpath("/mods:mods/mods:identifier", NAMESPACE).filter_map do |node|
          value = clean(node.text)
          { type: clean(node["type"]), value: value } if value
        end
      end

      def permanent_url
        node = doc.at_xpath("/mods:mods/mods:identifier[@type='hdl']", NAMESPACE)
        node && clean(node.text)
      end

      # The three w3cdtf date shapes a dateCreated may stop at: year, year-month,
      # or a full date. Matching the shape explicitly, rather than widening
      # DateTime.parse, is what lets the declared precision fall out of the parse
      # instead of being guessed after it.
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

      W3CDTF_DATE = /\A(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?\z/

      # What #date_parts returns when the element is absent entirely, so an
      # absent date is distinguishable from one present and unparseable.
      EMPTY_DATE = { value: nil, precision: nil, end_value: nil,
                     end_precision: nil, qualifier: nil, key_date: nil }.freeze

      # Everything a record declared about one originInfo date, as
      # { value:, precision:, end_value:, end_precision:, qualifier:, key_date: }.
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
      # object -- a Solr sort key, a citation year and an OAI date.
      def date_created_parts = date_parts("dateCreated")
      def date_issued_parts = date_parts("dateIssued")
      def copyright_date_parts = date_parts("copyrightDate")

      def date_created = date_created_parts[:value]
      def date_created_precision = date_created_parts[:precision]
      def date_created_end = date_created_parts[:end_value]
      def date_created_end_precision = date_created_parts[:end_precision]
      def date_created_qualifier = date_created_parts[:qualifier]
      def date_created_key_date = date_created_parts[:key_date]

      def date_issued = date_issued_parts[:value]
      def date_issued_precision = date_issued_parts[:precision]
      def date_issued_end = date_issued_parts[:end_value]
      def date_issued_end_precision = date_issued_parts[:end_precision]
      def date_issued_qualifier = date_issued_parts[:qualifier]
      def date_issued_key_date = date_issued_parts[:key_date]

      def copyright_date = copyright_date_parts[:value]
      def copyright_date_precision = copyright_date_parts[:precision]
      def copyright_date_end = copyright_date_parts[:end_value]
      def copyright_date_end_precision = copyright_date_parts[:end_precision]
      def copyright_date_qualifier = copyright_date_parts[:qualifier]
      def copyright_date_key_date = copyright_date_parts[:key_date]

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
        alternative_title: :many,
        uniform_title: :many,
        translated_title: :many,
        abbreviated_title: :many,

        names: :many,
        languages: :many,
        abstract: :one,

        # origin
        publication_information: :many,
        place_of_publication: :many,
        edition: :many,
        issuance: :many,
        frequency: :many,
        # Six rows per originInfo date. Flat rather than one nested value,
        # because the value half has consumers that need a real date object.
        date_created: :one,
        date_created_precision: :one,
        date_created_end: :one,
        date_created_end_precision: :one,
        date_created_qualifier: :one,
        date_created_key_date: :one,
        date_issued: :one,
        date_issued_precision: :one,
        date_issued_end: :one,
        date_issued_end_precision: :one,
        date_issued_qualifier: :one,
        date_issued_key_date: :one,
        copyright_date: :one,
        copyright_date_precision: :one,
        copyright_date_end: :one,
        copyright_date_end_precision: :one,
        copyright_date_qualifier: :one,
        copyright_date_key_date: :one,

        # physical description
        resource_type: :many,
        genres: :many,
        format: :many,
        extent: :many,
        digital_origin: :many,
        reformatting_quality: :many,
        notes: :many,
        table_of_contents: :many,

        # subjects
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
        record_info: :one,
        location: :many,

        # access
        access_condition: :one,
        use_and_reproduction: :one,
        restriction_on_access: :one
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

      # The title parts as the access copy wants them: normalised like the
      # abstract, so a curly quote, an invisible format mark or a Windows-1252
      # control cannot reach Solr or a display template. Titles and prose share
      # one vocabulary -- the asymmetry where only prose was cleaned was the bug.
      def access_title_parts
        title_parts.transform_values { |value| NEU::MODS.normalize(value.to_s) }
      end

      # Atlas names this field main_title; the registry requires a method per
      # field name, and #access_title_parts is the descriptive name for what it
      # returns. Kept as an alias rather than a rename so both read well.
      def main_title = access_title_parts

      private

      # --- helpers -------------------------------------------------------------

      # A shape-matched but impossible date (2026-13, 2026-02-30) reaches DateTime
      # and raises; it falls to the "" sentinel like any other unparseable value.
      # Anything outside the three shapes keeps the old permissive parse, so a
      # timestamp still projects as a full date.
      def parse_w3cdtf(str)
        m = W3CDTF_DATE.match(str)
        return [DateTime.parse(str), "day"] unless m

        precision = if m[3]
                      "day"
                    elsif m[2]
                      "month"
                    else
                      "year"
                    end
        [DateTime.new(m[1].to_i, (m[2] || 1).to_i, (m[3] || 1).to_i), precision]
      rescue Date::Error
        ["", nil]
      end

      # One originInfo date element, read by its attributes rather than by
      # position. A record is free to write point="end" first, and taking the
      # first node would then invert the range.
      def date_parts(element)
        nodes = doc.xpath("/mods:mods/mods:originInfo/mods:#{element}", NAMESPACE)
        return EMPTY_DATE if nodes.empty?

        start = nodes.find { |n| attr_value(n, "point") == "start" } ||
                nodes.find { |n| attr_value(n, "point") != "end" }
        finish = nodes.find { |n| attr_value(n, "point") == "end" }
        date_entry(start, finish, nodes)
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
        value, precision = node_date(start)
        end_value, end_precision = node_date(finish)
        {
          value: value,
          precision: precision,
          end_value: end_value,
          end_precision: end_precision,
          qualifier: attr_value(start, "qualifier") || attr_value(finish, "qualifier"),
          key_date: nodes.any? { |n| attr_value(n, "keyDate") == "yes" }
        }
      end

      def node_date(node)
        return [nil, nil] unless node

        str = NEU::MODS.canonical_ws(node.text)
        return [nil, nil] if str.empty?

        parse_w3cdtf(str)
      end

      def attr_value(node, name)
        return nil unless node

        value = NEU::MODS.canonical_ws(node[name].to_s)
        value.empty? ? nil : value
      end

      # Byte-faithful title parts off any titleInfo node, shared by #title_parts
      # (which Cerberus pre-fills its edit forms from) and the variant titles.
      def title_parts_of(node)
        {
          non_sort: child_text(node, "mods:nonSort"),
          subtitle: child_text(node, "mods:subTitle"),
          title: child_text(node, "mods:title"),
          part_name: child_text(node, "mods:partName"),
          part_number: child_text(node, "mods:partNumber")
        }
      end

      # A variant title composed the way the access copy wants it: normalised
      # first, like #access_title_parts, so a curly quote or an invisible format
      # mark cannot reach Solr or a display template through this route either.
      def variant_titles(type)
        doc.xpath("/mods:mods/mods:titleInfo[@type='#{type}']", NAMESPACE).filter_map do |node|
          parts = title_parts_of(node).transform_values { |value| NEU::MODS.normalize(value.to_s) }
          clean(Projection.compose_title(parts))
        end
      end

      def name_subjects(type)
        doc.xpath("/mods:mods/mods:subject/mods:name[@type='#{type}']", NAMESPACE)
           .filter_map { |node| name_display_value_w_date(node) }
      end

      def related_item_titles(type)
        texts_at("/mods:mods/mods:relatedItem[@type='#{type}']/mods:titleInfo/mods:title")
      end

      # Kept in parts rather than composed into "24(3), pp. 210-218". The
      # punctuation of a citation is display policy, the same call #map_data
      # makes for cartographics. MODS leaves @unit optional, so a page extent
      # without one is read rather than dropped.
      def host_part(node)
        part = node.at_xpath("mods:part", NAMESPACE)
        return {} if part.nil?

        pages = "mods:extent[@unit='page' or not(@unit)]"
        {
          volume: child_text(part, "mods:detail[@type='volume']/mods:number"),
          issue: child_text(part, "mods:detail[@type='issue']/mods:number"),
          start_page: child_text(part, "#{pages}/mods:start"),
          end_page: child_text(part, "#{pages}/mods:end")
        }.compact
      end

      def text_at(xpath)
        node = doc.at_xpath(xpath, NAMESPACE)
        node ? NEU::MODS.canonical_ws(node.text) : ""
      end

      # The :many counterpart of #text_at, and the one way this file builds a
      # string array. Blank members drop out rather than arriving as nil: a
      # record template that seeds an empty <topic> for an edit form to fill --
      # which is exactly what Atlas's MODSBuilder writes -- otherwise projects
      # [nil], and every consumer of that array has to guard for it.
      # #texts_at scoped to a node rather than the document, for a repeatable
      # child of one element.
      # :city_section -> "citySection". The level names are snake_case in the
      # projection and camelCase in the schema.
      def camelize(level)
        head, *rest = level.to_s.split("_")
        [head, *rest.map(&:capitalize)].join
      end

      def texts_under(node, xpath)
        node.xpath(xpath, NAMESPACE).filter_map { |child| clean(child.text) }
      end

      def texts_at(xpath)
        doc.xpath(xpath, NAMESPACE).filter_map { |node| clean(node.text) }
      end

      def child_text(parent, xpath)
        return nil unless parent

        node = parent.at_xpath(xpath, NAMESPACE)
        return nil unless node

        v = NEU::MODS.canonical_ws(node.text)
        v.empty? ? nil : v
      end

      # canonical_ws, but nil for blank (used where an absent member must drop out).
      def clean(str)
        return nil if str.nil?

        v = NEU::MODS.canonical_ws(str)
        v.empty? ? nil : v
      end

      # canonical_ws keeping "" for blank -- for structured form-field values
      # (an empty given/family/org renders as an empty input, not a dropped key).
      def clean_part(str)
        NEU::MODS.canonical_ws(str)
      end

      # The schema leaves accessCondition/@type an open string, so match on the
      # canonicalised, case-folded value rather than in the XPath: real records
      # carry "Use and Reproduction" as readily as the MODS-recommended casing.
      def access_conditions_of_type(type)
        nodes = doc.xpath("/mods:mods/mods:accessCondition", NAMESPACE)
                   .select { |node| NEU::MODS.canonical_ws(node["type"].to_s).downcase == type }
        join_paragraphs(nodes)
      end

      def join_paragraphs(nodes)
        nodes.map { |n| NEU::MODS.normalize_paragraphs(n.text) }.reject(&:empty?).join("\n\n")
      end

      # --- name display (faithful port of mods gem display_value_w_date) -------

      def name_display_value_w_date(node)
        dv = name_display_value(node)
        node.xpath("mods:namePart[@type='date']", NAMESPACE).each do |np|
          d = np.text
          dv += ", #{d}" unless d.empty? || dv.end_with?(d)
        end
        dv = dv.sub(/\A, /, "")
        dv.strip.empty? ? nil : dv.strip
      end

      def name_display_value(node)
        display_form = node.at_xpath("mods:displayForm", NAMESPACE)
        return display_form.text if display_form && !display_form.text.empty?

        if node["type"] == "personal"
          personal_display_value(node)
        else
          non_date_parts_joined(node)
        end
      end

      def personal_display_value(node)
        family = joined_parts(node, "family")
        given  = joined_parts(node, "given")
        dv =
          if family.empty?
            given
          else
            given.empty? ? family : "#{family}, #{given}"
          end

        return non_date_parts_joined(node) if dv.empty?

        append_terms_of_address(node, dv)
      end

      def append_terms_of_address(node, dv)
        first = true
        node.xpath("mods:namePart[@type='termsOfAddress']", NAMESPACE).each do |np|
          next if np.text.empty?

          dv += first ? " #{np.text}" : ", #{np.text}"
          first = false
        end
        dv
      end

      # NodeSet-style concatenation: the `mods` gem joins same-typed nameParts via
      # NodeSet#text (no separator) -- e.g. two `given` parts become "A.(B)". We
      # reproduce that (quirk included) to stay behavior-preserving.
      def joined_parts(node, type)
        node.xpath("mods:namePart[@type='#{type}']", NAMESPACE).map(&:text).join
      end

      def non_date_parts_joined(node)
        node.xpath("mods:namePart", NAMESPACE)
            .reject { |np| np["type"] == "date" || np.text.empty? }
            .map(&:text).join(" ")
      end

      def name_role(node)
        node.xpath("mods:role", NAMESPACE).each do |role|
          val = role_term_value(role)
          return val if val
        end
        nil
      end

      # Prefer the type="text" roleTerm; fall back to the raw type="code" term
      # (NOT MARC-relator-translated -- see README). nil if neither is present.
      def role_term_value(role)
        %w[text code].each do |type|
          term = role.at_xpath("mods:roleTerm[@type='#{type}']", NAMESPACE)
          text = term&.text.to_s.strip
          return text unless text.empty?
        end
        nil
      end
    end
  end
end
