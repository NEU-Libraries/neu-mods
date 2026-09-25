# frozen_string_literal: true

require_relative "../namespaces"
require_relative "../language_codes"
require_relative "support"

module NEU
  module MODS
    module Projection
      # Top-level language elements, a code-only term read through the ISO 639
      # registry. See docs/other-fields.md.
      module Languages
        include Support

        # { term:, object_part:, script: } per language element. An entry, because
        # @objectPart changes what the record claims.
        def languages
          doc.xpath("/mods:mods/mods:language", NAMESPACE).filter_map do |lang|
            node = language_term_node(lang)
            term = language_term_of(node)
            next unless term

            # The authority comes off the <languageTerm>, never the <language>:
            # MODS puts @authority on the term.
            { term: term, object_part: attr_value(lang, "objectPart"), script: script_term(lang),
              **authority_of(node), **qualifiers_of(lang) }
          end
        end

        private

        # Located apart from its text, so the term and its authority come from one
        # node.
        def language_term_node(lang)
          lang.at_xpath("mods:languageTerm[@type='text']", NAMESPACE) ||
            lang.at_xpath("mods:languageTerm", NAMESPACE)
        end

        # A text term as written; a code through the ISO 639 registry.
        def language_term_of(node)
          return nil unless node

          return clean(node.text) if attr_value(node, "type") == "text"

          code = clean(node.text)
          code && LanguageCodes.term(code)
        end

        # Text form preferred, never translated: ISO 15924 is not vendored.
        def script_term(lang)
          text = lang.at_xpath("mods:scriptTerm[@type='text']", NAMESPACE)
          return clean(text.text) if text

          clean(lang.at_xpath("mods:scriptTerm", NAMESPACE)&.text)
        end
      end
    end
  end
end
