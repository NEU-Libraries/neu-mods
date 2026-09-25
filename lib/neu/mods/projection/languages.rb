# frozen_string_literal: true

require_relative "../namespaces"
require_relative "../language_codes"
require_relative "support"

module NEU
  module MODS
    module Projection
      # Top-level language elements, a code-only term read through the ISO 639
      # registry.
      module Languages
        include Support

        # { term:, object_part:, script: } per language element. Prefer the
        # type="text" term, and translate a code-only one through the ISO 639
        # registry. A record saying `eng` projects "English", so the display and
        # the Solr language facet read the same value rather than the facet
        # showing codes. An unrecognised code survives as itself.
        #
        # An entry rather than a bare string because @objectPart changes what the
        # record is claiming. `<language objectPart="subtitles">spa` says the
        # subtitles are Spanish, and projected flat it said the resource was --
        # which is the case a captioned video hits every time. The script rides
        # along for the same reason a name's role does: a consumer cannot
        # recover it from the term.
        def languages
          doc.xpath("/mods:mods/mods:language", NAMESPACE).filter_map do |lang|
            node = language_term_node(lang)
            term = language_term_of(node)
            next unless term

            # The authority comes off the <languageTerm> the term was read from,
            # never off the <language> around it: MODS carries @authority on the
            # term, and a code-only record declares `iso639-2b` there.
            { term: term, object_part: attr_value(lang, "objectPart"), script: script_term(lang),
              **authority_of(node), **qualifiers_of(lang) }
          end
        end

        private

        # Which <languageTerm> the language of one element is read from, text
        # form preferred. The node is located separately from its text because
        # the authority governing the term sits on that element: the value and
        # its vocabulary have to come from one node rather than from two
        # independent lookups.
        def language_term_node(lang)
          lang.at_xpath("mods:languageTerm[@type='text']", NAMESPACE) ||
            lang.at_xpath("mods:languageTerm", NAMESPACE)
        end

        # A text term as the record wrote it; a code through the ISO 639
        # registry, so a record saying `eng` projects "English".
        def language_term_of(node)
          return nil unless node

          return clean(node.text) if attr_value(node, "type") == "text"

          code = clean(node.text)
          code && LanguageCodes.term(code)
        end

        # A scriptTerm, text form preferred. No registry expands a code here: the
        # ISO 15924 list is not vendored, and inventing a half-translation would
        # be worse than handing the consumer what the record wrote.
        def script_term(lang)
          text = lang.at_xpath("mods:scriptTerm[@type='text']", NAMESPACE)
          return clean(text.text) if text

          clean(lang.at_xpath("mods:scriptTerm", NAMESPACE)&.text)
        end
      end
    end
  end
end
