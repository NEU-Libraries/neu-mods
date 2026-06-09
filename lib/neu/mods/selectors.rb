# frozen_string_literal: true

module NEU
  module MODS
    # Node LOCATION over a parsed MODS document. These return live Nokogiri nodes,
    # so they serve BOTH the read path (projection reads their text) AND the write
    # path (Cerberus's MODSMerge mutates the returned nodes in place). That shared
    # definition is the point: the node an editor changes is provably the node the
    # projection reads. Mixed into Document; operates on `doc`.
    module Selectors
      # Top-level primary titleInfo, falling back to the first top-level titleInfo.
      # Scoped to direct children of <mods:mods> so a relatedItem's nested
      # titleInfo (e.g. a series title) is never matched.
      def primary_title_info
        doc.at_xpath("/mods:mods/mods:titleInfo[@usage='primary']", NAMESPACE) ||
          doc.at_xpath("/mods:mods/mods:titleInfo", NAMESPACE)
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

      private

      def keyword_subject?(subject)
        return false if subject.attributes.any?

        topics = subject.element_children
        topics.any? && topics.all? { |c| c.name == "topic" }
      end
    end
  end
end
