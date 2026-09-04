# frozen_string_literal: true

module NEU
  module MODS
    # Node LOCATION over a parsed MODS document. These return live Nokogiri nodes,
    # so they serve BOTH the read path (projection reads their text) AND the write
    # path (Cerberus's MODSMerge mutates the returned nodes in place). That shared
    # definition is the point: the node an editor changes is provably the node the
    # projection reads. Mixed into Document; operates on `doc`.
    module Selectors
      # Top-level primary titleInfo, falling back to the first top-level titleInfo
      # that is NOT a variant. Scoped to direct children of <mods:mods> so a
      # relatedItem's nested titleInfo (e.g. a series title) is never matched.
      #
      # MODS does not require usage="primary", so the fallback fires often, and
      # an unfiltered one let document order decide the record's title. It also
      # decided which node an edit form wrote to: MODSMerge overwrites the node
      # this returns, so an alternative title reached here was destroyed on the
      # next title edit, leaving the record with no primary title at all. nil is
      # the right answer instead -- MODSMerge creates a proper primary titleInfo
      # from nil, and each variant is projected under its own field.
      def primary_title_info
        doc.at_xpath("/mods:mods/mods:titleInfo[@usage='primary']", NAMESPACE) ||
          doc.xpath("/mods:mods/mods:titleInfo", NAMESPACE).reject { |ti| variant_title?(ti) }.first
      end

      # MODS enumerates titleInfo/@type as exactly abbreviated, translated,
      # alternative and uniform -- every one of them a variant. So the presence
      # of any @type marks a variant, which also keeps an unrecognised or
      # misspelled value out of the write path rather than guessing at it.
      def variant_title?(node)
        !NEU::MODS.canonical_ws(node["type"].to_s).empty?
      end

      # All top-level <abstract> elements (MODS permits several).
      def abstract_nodes
        doc.xpath("/mods:mods/mods:abstract", NAMESPACE)
      end

      # The "keyword" subjects the simple form manages: attribute-free <subject>
      # elements whose element children are all <topic>. Anything with an
      # authority/valueURI (or a non-topic child, e.g. a <name> subject) is curated
      # and left untouched. (Distinct from the projection's #topical_subjects,
      # which harvests *every* <topic> for the access copy.)
      def keyword_subjects
        doc.xpath("/mods:mods/mods:subject", NAMESPACE).select { |s| keyword_subject?(s) }
      end

      # Build a namespaced MODS element reusing the document's existing `mods:`
      # namespace declaration (so new nodes never re-declare xmlns).
      def build_node(name, text = nil)
        node = Nokogiri::XML::Node.new(name, doc)
        node.namespace = doc.root.namespace_definitions.find { |d| d.prefix == "mods" }
        node.content = text unless text.nil?
        node
      end

      # The "editable creator" <name> nodes of a given @type ("personal" /
      # "corporate") that the Advanced form manages: plain names (no authority
      # markers) with a Creator role. The write-path counterpart to the
      # editable_*_creators projections; everything else (authority-bearing or
      # non-Creator) is curated and left untouched. Mirrors keyword_subjects.
      def editable_creator_nodes(type)
        doc.xpath("/mods:mods/mods:name[@type='#{type}']", NAMESPACE)
           .select { |n| editable_creator_name?(n) }
      end

      # Build a plain personal-creator <name> node: namePart[@type=given]/[family]
      # + a text roleTerm. No authority/valueURI (the editable set). `role` is
      # parameterised (default "Creator") so a later role-selectable form is a
      # non-breaking change.
      def build_personal_name(given:, family:, role: "Creator")
        name = build_node("name")
        name["type"] = "personal"
        name.add_child(name_part(given, "given")) unless given.to_s.strip.empty?
        name.add_child(name_part(family, "family")) unless family.to_s.strip.empty?
        name.add_child(role_node(role))
        name
      end

      # Build a plain corporate-creator <name> node: a single namePart + a text
      # roleTerm. No authority/valueURI.
      def build_corporate_name(name:, role: "Creator")
        node = build_node("name")
        node["type"] = "corporate"
        node.add_child(name_part(name)) unless name.to_s.strip.empty?
        node.add_child(role_node(role))
        node
      end

      private

      def keyword_subject?(subject)
        return false if subject.attributes.any?

        topics = subject.element_children
        topics.any? && topics.all? { |c| c.name == "topic" }
      end

      # A name is "editable" (depositor-managed) when it carries no authority
      # markers and resolves to a Creator role. Shared by editable_creator_nodes
      # (write/select) and the editable_*_creators projections (read).
      def editable_creator_name?(node)
        %w[authority authorityURI valueURI].none? { |attr| node[attr] } &&
          name_role(node) == "Creator"
      end

      def name_part(text, type = nil)
        np = build_node("namePart", text.to_s.strip)
        np["type"] = type if type
        np
      end

      def role_node(role)
        role_el = build_node("role")
        term = build_node("roleTerm", role)
        term["type"] = "text"
        role_el.add_child(term)
        role_el
      end
    end
  end
end
