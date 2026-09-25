# frozen_string_literal: true

require "nokogiri"

require_relative "namespaces"
require_relative "projection/support"
require_relative "projection/name_display"

module NEU
  module MODS
    # Node LOCATION over a parsed MODS document. These return live Nokogiri nodes,
    # so they serve BOTH the read path (projection reads their text) AND the write
    # path (Cerberus's MODSMerge mutates the returned nodes in place). That shared
    # definition is the point: the node an editor changes is provably the node the
    # projection reads. Mixed into Document; operates on `doc`.
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

      # The "keyword" subjects the simple form manages: attribute-free <subject>
      # elements whose element children are all <topic>. Anything with an
      # authority/valueURI (or a non-topic child, e.g. a <name> subject) is curated
      # and left untouched. (Distinct from the projection's #topical_subjects,
      # which harvests *every* <topic> for the access copy.)
      def keyword_subjects
        doc.xpath("/mods:mods/mods:subject", NAMESPACE).select { |s| keyword_subject?(s) }
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

      private

      def keyword_subject?(subject)
        return false if subject.attributes.any?

        topics = subject.element_children
        topics.any? && topics.all? { |c| c.name == "topic" }
      end
    end
  end
end
