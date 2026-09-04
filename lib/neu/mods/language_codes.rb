# frozen_string_literal: true

module NEU
  module MODS
    # ISO 639 code -> English language name, for projecting a code-only
    # languageTerm as something a reader (and a Solr facet) can use.
    #
    # This is the one place a code is translated, on purpose. The alternative --
    # mapping in each consumer's display layer -- leaves Solr indexing "eng"
    # while the page shows "English", so the language facet reads in codes. One
    # table, read once, keeps the projection, the display and the index agreed.
    #
    # Roles are deliberately NOT translated here; a MARC relator is a display
    # label, and the label vocabulary belongs to the consumer (see README).
    module LanguageCodes
      # The Library of Congress ISO 639-2 registry, vendored byte-for-byte from
      # https://www.loc.gov/standards/iso639-2/ISO-639-2_utf-8.txt so its
      # provenance is a diff rather than a claim. Pipe-delimited:
      # alpha3-bibliographic | alpha3-terminologic | alpha2 | English | French.
      # It lives outside lib/*.rb because the English names carry non-ASCII and
      # the source-purity spec holds the Ruby files to ASCII.
      REGISTRY_PATH = File.expand_path("data/iso639-2.txt", __dir__)

      # Every alpha-3 bibliographic, alpha-3 terminologic and alpha-2 code that
      # the registry defines, each pointing at its English name. MODS records
      # declare authority="iso639-2b" most often, but iso639-1 and the
      # terminologic codes are equally valid, and a lookup table costs the same
      # whether it holds one form or all three.
      TERMS = File.readlines(REGISTRY_PATH, encoding: "bom|utf-8").each_with_object({}) do |line, terms|
        bibliographic, terminologic, alpha2, english = line.chomp.split("|")
        next if english.to_s.empty?

        # The registry lists synonyms in preference order, so "Spanish;
        # Castilian" becomes "Spanish". Rendering every synonym would make a
        # facet value nobody would click.
        name = english.split(";").first.strip
        [bibliographic, terminologic, alpha2].each do |code|
          terms[code] = name unless code.to_s.empty?
        end
      end.freeze

      # The English name for a code, or the code itself when the registry does
      # not define it. Never returns nil for a present value: an unrecognised
      # code is still what the record says, and dropping it would lose data.
      def self.term(code)
        key = code.to_s.strip
        return key if key.empty?

        TERMS.fetch(key.downcase, key)
      end
    end
  end
end
