# frozen_string_literal: true

module NEU
  module MODS
    # Lightweight whitespace canonicalization used by the *no-op guard* -- does an
    # edit actually change anything, or only insignificant whitespace? (Cerberus's
    # MODSMerge uses this to avoid minting an unchanged OCFL MODS version.) This is
    # deliberately distinct from TextNormalizer (text_normalizer.rb): this one only folds
    # whitespace; TextNormalizer cleans curator freetext for the access copy.
    module Canonicalize
      module_function

      NBSP = [0xA0].pack("U") # U+00A0 non-breaking space, built from codepoint

      # \s doesn't match U+00A0 (NBSP) in Ruby's default mode, so fold NBSP to a
      # plain space first, then collapse any whitespace run to one space + strip.
      def canonical_ws(str)
        str.to_s.tr(NBSP, " ").gsub(/\s+/, " ").strip
      end

      # canonical_ws per line, keeping the line breaks. For a field where a
      # newline is structure rather than formatting -- tableOfContents, where
      # the break separates one entry from the next. Blank lines drop, so a
      # double-spaced list does not project empty entries.
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
