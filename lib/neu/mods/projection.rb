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
      def topical_subjects
        doc.xpath("/mods:mods/mods:subject/mods:topic", NAMESPACE).map { |t| clean(t.text) }
      end

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

      # --- Names ---------------------------------------------------------------

      # All top-level names as { name:, role: }. `name` reproduces the `mods` gem's
      # display_value_w_date (including its quirks -- faithfully, so existing Solr/
      # display output is preserved). `role` prefers the type="text" roleTerm,
      # falling back to the raw code (NOT MARC-relator-translated -- see README).
      def names
        doc.xpath("/mods:mods/mods:name", NAMESPACE).map do |node|
          { name: name_display_value_w_date(node), role: name_role(node) }
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
      # display string + role, like #names but filtered to the preserved set.
      def preserved_names
        doc.xpath("/mods:mods/mods:name", NAMESPACE)
           .reject { |node| editable_creator_name?(node) }
           .map { |node| { name: name_display_value_w_date(node), role: name_role(node) } }
      end

      # --- Scalars / simple arrays --------------------------------------------

      def languages
        doc.xpath("/mods:mods/mods:language", NAMESPACE).map do |lang|
          term = lang.at_xpath("mods:languageTerm[@type='text']", NAMESPACE) ||
                 lang.at_xpath("mods:languageTerm", NAMESPACE)
          clean(term&.text)
        end.compact
      end

      # MODS repeats typeOfResource, and repeats physicalDescription (and form and
      # extent within one), so all four are :many. A record that is both text and
      # a still image used to project as text alone.
      def resource_type = texts_at("/mods:mods/mods:typeOfResource")
      def format = texts_at("/mods:mods/mods:physicalDescription/mods:form")
      def extent = texts_at("/mods:mods/mods:physicalDescription/mods:extent")
      def digital_origin = texts_at("/mods:mods/mods:physicalDescription/mods:digitalOrigin")

      def genres
        doc.xpath("/mods:mods/mods:genre", NAMESPACE).map { |g| clean(g.text) }
      end

      # originInfo repeats, and so do publisher and edition within one. Cerberus's
      # IPTC ingest writes the publisher from the IPTC Source field on every batch,
      # so this element was being written into the preservation XML and then read
      # back by nothing.
      def publication_information = texts_at("/mods:mods/mods:originInfo/mods:publisher")
      def edition = texts_at("/mods:mods/mods:originInfo/mods:edition")

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
      def location
        doc.xpath("/mods:mods/mods:location", NAMESPACE).filter_map do |node|
          entry = {
            physical_location: child_text(node, "mods:physicalLocation"),
            shelf_location: child_text(node, "mods:shelfLocation"),
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
      def host_collections = related_item_titles("host")

      def identifiers
        doc.xpath("/mods:mods/mods:identifier", NAMESPACE).map { |i| clean(i.text) }
      end

      def permanent_url
        node = doc.at_xpath("/mods:mods/mods:identifier[@type='hdl']", NAMESPACE)
        node && clean(node.text)
      end

      # The three w3cdtf date shapes a dateCreated may stop at: year, year-month,
      # or a full date. Matching the shape explicitly, rather than widening
      # DateTime.parse, is what lets the declared precision fall out of the parse
      # instead of being guessed after it.
      W3CDTF_DATE = /\A(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?\z/

      # The three originInfo dates, each paired with the granularity the record
      # declared, as [value, precision]. value is nil if the element is absent,
      # or "" if present but unparseable (mirrors Atlas's safe_date_parse
      # rescue). precision is "year", "month" or "day", and nil whenever value
      # is not a DateTime.
      #
      # The precision has to be captured here, at the only point where the shape
      # is still visible: a year-only date parses to January 1st, and no consumer
      # downstream can tell that month and day from a record that claimed them.
      # A preservation repository must not project a precision it was not given.
      #
      # These stay :one where the sibling originInfo elements are :many. MODS
      # repeats them, but a date carries a precision alongside it, and an array
      # of values paired with an array of precisions is a shape no consumer
      # wants. A record that ranges its dates uses point="start"/"end", which is
      # its own projection question rather than a cardinality one.
      def date_created_with_precision = date_with_precision("dateCreated")
      def date_issued_with_precision = date_with_precision("dateIssued")
      def copyright_date_with_precision = date_with_precision("copyrightDate")

      def date_created = date_created_with_precision.first
      def date_created_precision = date_created_with_precision.last
      def date_issued = date_issued_with_precision.first
      def date_issued_precision = date_issued_with_precision.last
      def copyright_date = copyright_date_with_precision.first
      def copyright_date_precision = copyright_date_with_precision.last

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
        edition: :many,
        date_created: :one,
        date_created_precision: :one,
        date_issued: :one,
        date_issued_precision: :one,
        copyright_date: :one,
        copyright_date_precision: :one,

        # physical description
        resource_type: :many,
        genres: :many,
        format: :many,
        extent: :many,
        digital_origin: :many,
        notes: :many,

        # subjects
        topical_subjects: :many,
        geographic_subjects: :many,
        temporal_subjects: :many,
        personal_name_subjects: :many,
        corporate_name_subjects: :many,
        map_data: :many,

        # related items
        related_series: :many,
        host_collections: :many,

        # identifiers and location
        identifiers: :many,
        permanent_url: :one,
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

      def date_with_precision(element)
        node = doc.at_xpath("/mods:mods/mods:originInfo/mods:#{element}", NAMESPACE)
        return [nil, nil] unless node

        str = NEU::MODS.canonical_ws(node.text)
        return [nil, nil] if str.empty?

        parse_w3cdtf(str)
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

      def text_at(xpath)
        node = doc.at_xpath(xpath, NAMESPACE)
        node ? NEU::MODS.canonical_ws(node.text) : ""
      end

      # The :many counterpart of #text_at. Blank members drop out rather than
      # arriving as nil, so a consumer mapping over the array cannot trip on one.
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
