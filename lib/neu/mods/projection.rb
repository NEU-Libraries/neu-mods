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
    module Projection
      # --- Title ---------------------------------------------------------------

      # Structured primary-title parts. nil for an absent part (the Cerberus form
      # treats nil as "not present"); to_h coerces to "" for the Atlas main_title.
      def title_parts
        ti = primary_title_info
        {
          non_sort: child_text(ti, "mods:nonSort"),
          subtitle: child_text(ti, "mods:subTitle"),
          title: child_text(ti, "mods:title"),
          part_name: child_text(ti, "mods:partName"),
          part_number: child_text(ti, "mods:partNumber")
        }
      end

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
        "#{parts[:non_sort]}#{parts[:title]}#{suffix}"
      end

      # --- Abstract / access ---------------------------------------------------

      def abstract
        join_paragraphs(abstract_nodes)
      end

      def access_condition
        join_paragraphs(doc.xpath("/mods:mods/mods:accessCondition", NAMESPACE))
      end

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

      # --- Scalars / simple arrays --------------------------------------------

      def languages
        doc.xpath("/mods:mods/mods:language", NAMESPACE).map do |lang|
          term = lang.at_xpath("mods:languageTerm[@type='text']", NAMESPACE) ||
                 lang.at_xpath("mods:languageTerm", NAMESPACE)
          clean(term&.text)
        end.compact
      end

      def resource_type = text_at("/mods:mods/mods:typeOfResource")
      def format = text_at("/mods:mods/mods:physicalDescription/mods:form")
      def extent = text_at("/mods:mods/mods:physicalDescription/mods:extent")
      def digital_origin = text_at("/mods:mods/mods:physicalDescription/mods:digitalOrigin")

      def genres
        doc.xpath("/mods:mods/mods:genre", NAMESPACE).map { |g| clean(g.text) }
      end

      def related_series
        doc.xpath("/mods:mods/mods:relatedItem[@type='series']/mods:titleInfo/mods:title", NAMESPACE)
           .map { |t| clean(t.text) }
      end

      def identifiers
        doc.xpath("/mods:mods/mods:identifier", NAMESPACE).map { |i| clean(i.text) }
      end

      def permanent_url
        node = doc.at_xpath("/mods:mods/mods:identifier[@type='hdl']", NAMESPACE)
        node && clean(node.text)
      end

      # Parsed dateCreated, or nil if no originInfo/dateCreated, or "" if present
      # but unparseable (mirrors Atlas's safe_date_parse rescue).
      def date_created
        node = doc.at_xpath("/mods:mods/mods:originInfo/mods:dateCreated", NAMESPACE)
        return nil unless node

        str = NEU::MODS.canonical_ws(node.text)
        return nil if str.empty?

        begin
          DateTime.parse(str)
        rescue Date::Error
          ""
        end
      end

      # --- Full projection -----------------------------------------------------

      # The complete read projection, keyed to Atlas's Metadata::MODS attribute
      # names -- a drop-in source for `convert_xml_to_json`.
      def to_h
        {
          main_title: title_parts.transform_values(&:to_s),
          names: names,
          languages: languages,
          date_created: date_created,
          resource_type: resource_type,
          genres: genres,
          format: format,
          extent: extent,
          digital_origin: digital_origin,
          abstract: abstract,
          related_series: related_series,
          topical_subjects: topical_subjects,
          identifiers: identifiers,
          permanent_url: permanent_url,
          access_condition: access_condition
        }
      end

      private

      # --- helpers -------------------------------------------------------------

      def text_at(xpath)
        node = doc.at_xpath(xpath, NAMESPACE)
        node ? NEU::MODS.canonical_ws(node.text) : ""
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
