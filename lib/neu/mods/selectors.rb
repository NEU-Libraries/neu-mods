# frozen_string_literal: true

require "nokogiri"

require_relative "namespaces"
require_relative "projection/support"
require_relative "projection/name_display"

module NEU
  module MODS
    # Node LOCATION, returning live nodes that serve both the read path and
    # Cerberus's MODSMerge edits. A selector must never return a node the
    # projection would not read from. See docs/editing.md.
    module Selectors
      include Projection::Support
      include Projection::NameDisplay

      # Top-level primary titleInfo, falling back to the first top-level one that
      # is not a variant; nil if every titleInfo is a variant. Never fall back to
      # a variant: MODSMerge overwrites the node this returns. See docs/titles.md.
      def primary_title_info
        doc.at_xpath("/mods:mods/mods:titleInfo[@usage='primary']", NAMESPACE) ||
          doc.xpath("/mods:mods/mods:titleInfo", NAMESPACE).reject { |ti| variant_title?(ti) }.first
      end

      # Any @type marks a variant: MODS enumerates four types, all variants.
      def variant_title?(node)
        !attr_value(node, "type").nil?
      end

      # All top-level <abstract> elements (MODS permits several).
      def abstract_nodes
        doc.xpath("/mods:mods/mods:abstract", NAMESPACE)
      end

      # The attribute-free, topic-only subjects the simple form manages.
      def keyword_subjects
        doc.xpath("/mods:mods/mods:subject", NAMESPACE).select { |s| keyword_subject?(s) }
      end

      # The plain Creator <name> nodes of one @type, for replace-on-save.
      def editable_creator_nodes(type)
        doc.xpath("/mods:mods/mods:name[@type='#{type}']", NAMESPACE)
           .select { |n| editable_creator_name?(n) }
      end

      private

      def keyword_subject?(subject)
        return false if subject.attributes.any?

        topics = subject.element_children
        topics.any? && topics.all? { |c| c.name == "topic" }
      end
    end
  end
end
