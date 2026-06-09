# frozen_string_literal: true

module NEU
  module MODS
    # Lightweight whitespace canonicalization used by the *no-op guard* -- does an
    # edit actually change anything, or only insignificant whitespace? (Cerberus's
    # MODSMerge uses this to avoid minting an unchanged OCFL MODS version.) This is
    # deliberately distinct from TextNormalizer below: this one only folds
    # whitespace; TextNormalizer cleans curator freetext for the access copy.
    module Canonicalize
      module_function

      NBSP = [0xA0].pack("U") # U+00A0 non-breaking space, built from codepoint

      # \s doesn't match U+00A0 (NBSP) in Ruby's default mode, so fold NBSP to a
      # plain space first, then collapse any whitespace run to one space + strip.
      def canonical_ws(str)
        str.to_s.tr(NBSP, " ").gsub(/\s+/, " ").strip
      end

      # Treat values differing only by insignificant whitespace (NBSP vs space,
      # collapsible runs, leading/trailing) as equal.
      def whitespace_equivalent?(current, incoming)
        canonical_ws(current) == canonical_ws(incoming)
      end
    end

    # Normalises curator-authored freetext on the way into the JSON access copy
    # (and Solr); the XML preservation copy stays untouched. Ported from Atlas's
    # TextNormalizer (which carries DRS v1 prior art) so the gem reproduces Atlas's
    # projection byte-for-byte.
    #
    # IMPORTANT: every character-class regex is built *programmatically* from
    # codepoint lists via `format('\\u%04X', cp)`, so this source file stays pure
    # ASCII -- no literal smart-quotes, dashes, or (critically) raw control bytes
    # land on disk. Keep it that way.
    #
    # Pipeline: force UTF-8 + scrub invalid bytes; NFC; map Unicode dashes to '-'
    # (swung-dash to '~'); transliterate the General Punctuation block (smart
    # quotes, ellipsis, etc.) to ASCII; strip C0/C1 controls (keeping tab/newline);
    # collapse horizontal-whitespace runs to one space; for paragraph fields,
    # collapse 2+ newlines to exactly two; strip.
    #
    #   .normalize(str)            -- single-line fields (newlines -> spaces)
    #   .normalize_paragraphs(str) -- fields that may carry paragraph breaks
    #                                 (abstract, accessCondition)
    module TextNormalizer
      module_function

      # Build a character-class Regexp from an array of integer codepoints, as
      # \uXXXX escapes (keeps this source ASCII).
      def self.char_class(codepoints, prefix: "")
        Regexp.new("[#{prefix}#{codepoints.map { |cp| format('\\u%04X', cp) }.join}]")
      end

      # NOTE: U+2053 (swung dash) is intentionally excluded from dashes -- it is
      # named "dash" but conventionally maps to ASCII '~', not '-' (V1 prior art).
      DASH_CODEPOINTS = [
        0x002D, 0x00AD, 0x058A, 0x05BE, 0x1400, 0x1806,
        0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015,
        0x2043, 0x207B, 0x208B, 0x2212,
        0x2E17, 0x2E1A, 0x2E3A, 0x2E3B, 0x2E40,
        0x301C, 0x3030, 0x30A0, 0xFE31, 0xFE32, 0xFE58,
        0xFE63, 0xFF0D
      ].freeze
      DASH_RE = char_class(DASH_CODEPOINTS).freeze

      SWUNG_DASH_RE = Regexp.new(format('\\u%04X', 0x2053)).freeze

      # C0 (U+0000..U+0008, U+000B..U+001F) and C1 (U+007F..U+009F). U+0009 (tab)
      # and U+000A (newline) are preserved.
      CONTROL_CODEPOINTS = ((0x0000..0x0008).to_a + (0x000B..0x001F).to_a + (0x007F..0x009F).to_a).freeze
      CONTROL_RE = char_class(CONTROL_CODEPOINTS).freeze

      HORIZONTAL_WS_CODEPOINTS = [
        0x0009, 0x00A0, 0x1680,
        0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006,
        0x2007, 0x2008, 0x2009, 0x200A, 0x202F, 0x205F, 0x3000
      ].freeze
      # Leading literal space included in the class (the " " prefix); `+` so a run
      # of horizontal whitespace collapses to a single space.
      HORIZONTAL_WS_RE = Regexp.new("#{char_class(HORIZONTAL_WS_CODEPOINTS, prefix: " ").source}+").freeze

      PARAGRAPH_RUN_RE = /\n{2,}/

      # General Punctuation block (U+2000..U+206F). Codepoints not listed pass
      # through unchanged. Empty-string values deliberately drop invisible/bidi/
      # format marks so they cannot leak into the access copy.
      GENERAL_PUNCTUATION = {
        0x2000 => " ", 0x2001 => " ", 0x2002 => " ", 0x2003 => " ",
        0x2004 => " ", 0x2005 => " ", 0x2006 => " ", 0x2007 => " ",
        0x2008 => " ", 0x2009 => " ", 0x200A => " ",
        0x200B => "",  0x200C => "",  0x200D => "",
        0x200E => "",  0x200F => "",
        0x2018 => "'", 0x2019 => "'", 0x201A => ",", 0x201B => "'",
        0x201C => '"', 0x201D => '"', 0x201E => '"', 0x201F => '"',
        0x2020 => "+", 0x2021 => "+",
        0x2022 => "*", 0x2023 => "*", 0x2024 => ".", 0x2025 => "..",
        0x2026 => "...",
        0x2028 => "\n", 0x2029 => "\n\n",
        0x202A => "",  0x202B => "", 0x202C => "", 0x202D => "",
        0x202E => "",  0x202F => " ",
        0x2030 => "%", 0x2032 => "'", 0x2033 => '"', 0x2035 => "'",
        0x2036 => '"',
        0x2039 => "<", 0x203A => ">", 0x203C => "!!", 0x203D => "?",
        0x2044 => "/", 0x2052 => "%",
        0x205F => " ", 0x2060 => "", 0x2061 => "", 0x2062 => "",
        0x2063 => "",  0x2064 => "",
        0x206A => "",  0x206B => "", 0x206C => "", 0x206D => "",
        0x206E => "",  0x206F => ""
      }.transform_keys { |cp| [cp].pack("U") }.freeze
      GENERAL_PUNCTUATION_RE = Regexp.new("[#{format('\\u%04X-\\u%04X', 0x2000, 0x206F)}]").freeze

      def normalize(str)
        return "" if str.nil?

        s = base_normalize(str.to_s)
        s = s.tr("\n", " ")
        s.gsub(HORIZONTAL_WS_RE, " ").strip
      end

      def normalize_paragraphs(str)
        return "" if str.nil?

        s = base_normalize(str.to_s)
        s = s.gsub(HORIZONTAL_WS_RE, " ")
        s = s.gsub(/ *\n */, "\n")
        s.split(PARAGRAPH_RUN_RE).map { |p| p.tr("\n", " ").strip }
                                 .reject(&:empty?).join("\n\n")
      end

      def base_normalize(str)
        s = str.dup.force_encoding("UTF-8")
        s = s.scrub("")
        s = s.unicode_normalize(:nfc)
        s = s.gsub(DASH_RE, "-")
        s = s.gsub(SWUNG_DASH_RE, "~")
        s = s.gsub(GENERAL_PUNCTUATION_RE) { |c| GENERAL_PUNCTUATION.fetch(c, c) }
        s.gsub(CONTROL_RE, "")
      end
    end
  end
end
