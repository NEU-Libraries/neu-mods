# frozen_string_literal: true

require "nokogiri"

module NEU
  module MODS
    # The gem's main entry point: a thin facade over a parsed MODS document.
    #
    #   doc = NEU::MODS::Document.parse(xml)
    #   doc.plain_title            # => composed display title
    #   doc.to_h                   # => full read projection
    #   doc.primary_title_info     # => a live Nokogiri node (for editing)
    #
    # Selectors return live nodes (shared by read and write); projection methods
    # return plain data. Parsing uses `&:noblanks` to match Atlas's read and to
    # avoid spurious whitespace-only text nodes.
    class Document
      include Selectors
      include Projection

      attr_reader :doc

      def self.parse(xml)
        new(Nokogiri::XML(xml.to_s, &:noblanks))
      end

      # Wrap an already-parsed Nokogiri document (used by writers that own the doc
      # they're mutating, so selectors and serialization share one instance).
      def initialize(nokogiri_doc)
        @doc = nokogiri_doc
      end

      def to_xml(...)
        doc.to_xml(...)
      end
    end
  end
end
