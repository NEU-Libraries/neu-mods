# frozen_string_literal: true

module NEU
  module MODS
    # Whitespace canonicalization for the no-op guard: did an edit change
    # anything, or only insignificant whitespace? Distinct from TextNormalizer,
    # which cleans text for the access copy. See docs/text-normalization.md.
    module Canonicalize
      module_function

      NBSP = [0xA0].pack("U") # U+00A0 non-breaking space, built from codepoint

      # Fold NBSP first: Ruby's \s does not match U+00A0.
      def canonical_ws(str)
        str.to_s.tr(NBSP, " ").gsub(/\s+/, " ").strip
      end

      # canonical_ws per line, keeping the breaks and dropping blank lines.
      def canonical_lines(str)
        str.to_s.split("\n").map { |line| canonical_ws(line) }.reject(&:empty?).join("\n")
      end

      # Treat values differing only by insignificant whitespace (NBSP vs space,
      # collapsible runs, leading/trailing) as equal.
      def whitespace_equivalent?(current, incoming)
        canonical_ws(current) == canonical_ws(incoming)
      end
    end
  end
end
