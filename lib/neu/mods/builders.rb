# frozen_string_literal: true

require "nokogiri"

require_relative "namespaces"

module NEU
  module MODS
    # Node CREATION for the write path, beside Selectors' node location.
    # Cerberus's MODSMerge builds every title, abstract, subject and creator it
    # adds through these, so their names and signatures are part of the
    # contract. Mixed into Document; operates on `doc`.
    module Builders
      # Build a namespaced MODS element reusing the document's existing MODS
      # namespace declaration (so new nodes never re-declare xmlns). Matched by
      # URI rather than prefix: a document binds MODS to whatever prefix it
      # likes, and an element built outside the namespace is invisible to every
      # XPath here. A document declaring no MODS namespace raises instead.
      def build_node(name, text = nil)
        node = Nokogiri::XML::Node.new(name, doc)
        node.namespace = mods_namespace_definition
        node.content = text unless text.nil?
        node
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

      def mods_namespace_definition
        doc.root.namespace_definitions.find { |d| d.href == NAMESPACE["mods"] } ||
          raise(ArgumentError, "document declares no MODS namespace on its root element")
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
