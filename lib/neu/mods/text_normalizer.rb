# frozen_string_literal: true

module NEU
  module MODS
    # Cleans curator text for the JSON access copy and Solr, byte for byte as
    # Atlas's TextNormalizer does; the XML preservation copy is never touched.
    # See docs/text-normalization.md for the pipeline.
    #
    # Keep this file pure ASCII: build every character class from codepoints
    # through char_class, never from a literal character.
    module TextNormalizer
      module_function

      # Build a character-class Regexp from an array of integer codepoints, as
      # \uXXXX escapes (keeps this source ASCII).
      def self.char_class(codepoints, prefix: "")
        Regexp.new("[#{prefix}#{codepoints.map { |cp| format('\\u%04X', cp) }.join}]")
      end

      # U+2053 (swung dash) is not listed: it maps to "~", as in v1.
      DASH_CODEPOINTS = [
        0x002D, 0x058A, 0x05BE, 0x1400, 0x1806,
        0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015,
        0x2043, 0x207B, 0x208B, 0x2212,
        0x2E17, 0x2E1A, 0x2E3A, 0x2E3B, 0x2E40,
        0x301C, 0x3030, 0x30A0, 0xFE31, 0xFE32, 0xFE58,
        0xFE63, 0xFF0D
      ].freeze
      DASH_RE = char_class(DASH_CODEPOINTS).freeze

      SWUNG_DASH_RE = char_class([0x2053]).freeze

      # Dropped, not made a hyphen: a hyphen would split one word into two Solr
      # tokens.
      SOFT_HYPHEN_RE = char_class([0x00AD]).freeze

      # Word's manual line break and page break. They become a newline, because
      # deleting one runs the words on either side together.
      SEPARATOR_CONTROL_CODEPOINTS = [0x000B, 0x000C].freeze
      SEPARATOR_CONTROL_RE = char_class(SEPARATOR_CONTROL_CODEPOINTS).freeze

      # The rest of C0 and C1, keeping tab and newline. Dropping U+000D reduces
      # CRLF to one newline.
      CONTROL_CODEPOINTS = ((0x0000..0x0008).to_a + (0x000D..0x001F).to_a + (0x007F..0x009F).to_a).freeze
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

      # U+2000..U+206F. Unlisted codepoints pass through; "" drops an invisible
      # or format mark.
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
        s.split(PARAGRAPH_RUN_RE).map { |p| p.tr("\n", " ").strip }.reject(&:empty?).join("\n\n")
      end

      # One stage of the pipeline rather than an entry point, so it stays off the
      # module's public surface.
      def base_normalize(str)
        s = str.dup.force_encoding("UTF-8")
        s = s.scrub("")
        s = s.unicode_normalize(:nfc)
        s = s.gsub(DASH_RE, "-")
        s = s.gsub(SWUNG_DASH_RE, "~")
        s = s.gsub(GENERAL_PUNCTUATION_RE) { |c| GENERAL_PUNCTUATION.fetch(c, c) }
        s = s.gsub(SEPARATOR_CONTROL_RE, "\n")
        s = s.gsub(SOFT_HYPHEN_RE, "")
        s.gsub(CONTROL_RE, "")
      end
      private_class_method :base_normalize
    end
  end
end
