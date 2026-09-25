# frozen_string_literal: true

require "nokogiri"

require_relative "namespaces"

module NEU
  module MODS
    # Node CREATION for the write path. Cerberus's MODSMerge builds every
    # element it adds through these, so their names and signatures are part of
    # the contract. See docs/editing.md.
    module Builders
      # A MODS element reusing the root's namespace declaration, matched by URI:
      # built outside MODS, an element is invisible to every XPath here.
      def build_node(name, text = nil)
        node = Nokogiri::XML::Node.new(name, doc)
        node.namespace = mods_namespace_definition
        node.content = text unless text.nil?
        node
      end

      # A plain personal creator: given and family parts and a text roleTerm.
      def build_personal_name(given:, family:, role: "Creator")
        name = build_node("name")
        name["type"] = "personal"
        name.add_child(name_part(given, "given")) unless given.to_s.strip.empty?
        name.add_child(name_part(family, "family")) unless family.to_s.strip.empty?
        name.add_child(role_node(role))
        name
      end

      # A plain corporate creator: one name part and a text roleTerm.
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
