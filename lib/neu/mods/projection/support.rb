# frozen_string_literal: true

require_relative "../namespaces"
require_relative "../canonicalize"
require_relative "../text_normalizer"

module NEU
  module MODS
    module Projection
      # The attribute, text and qualifier readers every projection area shares.
      # The qualifier and authority rules are in docs/qualifiers-and-authority.md.
      module Support
        # The three attributes MODS uses to declare where a value came from, and
        # the projected key each reports under.
        AUTHORITY_ATTRIBUTES = { authority: "authority", authority_uri: "authorityURI",
                                 value_uri: "valueURI" }.freeze

        private

        def attr_value(node, name)
          return nil unless node

          clean(node[name])
        end

        # The header and the link a display reads off an element, as one pair.
        def qualifiers_of(node)
          { display_label: attr_value(node, "displayLabel"), href: xlink_href(node) }
        end

        # The vocabulary a VALUE came from: the element's own attributes, then an
        # enclosing <subject>'s. Never widen this to the subtree: the deposit form
        # writes a marcrelator <roleTerm> on every creator, which would make every
        # depositor-entered name controlled.
        def authority_of(node)
          heading = enclosing_subject(node)
          AUTHORITY_ATTRIBUTES.transform_values do |attribute|
            attr_value(node, attribute) || attr_value(heading, attribute)
          end
        end

        # Matched by namespace URI, not prefix: a document binds MODS to any prefix.
        def enclosing_subject(node)
          node&.ancestors&.find do |ancestor|
            ancestor.name == "subject" && ancestor.namespace&.href == NAMESPACE["mods"]
          end
        end

        # By namespace, not by prefix: node["xlink:href"] matches the literal
        # prefix alone, and a document may bind XLink to any prefix.
        def xlink_href(node)
          return nil unless node

          attribute = node.attribute_with_ns("href", XLINK_NAMESPACE)
          attribute && clean(attribute.value)
        end

        # A displayed value plus the qualifiers of the element its header comes
        # from, which is not always the element holding the text.
        def labeled(value, label_node, authority_node: nil)
          entry = { value: value, **qualifiers_of(label_node) }
          authority_node ? entry.merge(authority_of(authority_node)) : entry
        end

        # #texts_at, with each value carrying the qualifiers of its element.
        # `from:` is an XPath, relative to the text-bearing node, naming the
        # ancestor the header comes from instead. `authority:` adds the value's
        # vocabulary, which always resolves off the text-bearing node.
        def labeled_texts_at(xpath, from: nil, authority: false)
          doc.xpath(xpath, NAMESPACE).filter_map do |node|
            value = clean(node.text)
            next unless value

            labeled(value, from ? node.at_xpath(from, NAMESPACE) : node,
                    authority_node: authority ? node : nil)
          end
        end

        # The first of a node set to state the attribute, for the companion
        # scalars of a field that joins several elements into one value.
        def first_attr(nodes, name)
          nodes.filter_map { |node| attr_value(node, name) }.first
        end

        def first_href(nodes)
          nodes.filter_map { |node| xlink_href(node) }.first
        end

        # :city_section -> "citySection". The level names are snake_case in the
        # projection and camelCase in the schema.
        def camelize(level)
          head, *rest = level.to_s.split("_")
          [head, *rest.map(&:capitalize)].join
        end

        # #camelize's inverse: "hierarchicalGeographic" -> "hierarchical_geographic".
        # Hand-rolled because the gem has no Rails dependency.
        def snake_case(name)
          name.to_s.gsub(/([a-z])([A-Z])/) { "#{Regexp.last_match(1)}_#{Regexp.last_match(2).downcase}" }
        end

        # #texts_at scoped to a node rather than the document, for a repeatable
        # child of one element.
        def texts_under(node, xpath)
          node.xpath(xpath, NAMESPACE).filter_map { |child| clean(child.text) }
        end

        # The one way the projection builds a string array. Blank members drop
        # out rather than arriving as nil, because Atlas's MODSBuilder seeds empty
        # elements for an edit form to fill.
        def texts_at(xpath)
          doc.xpath(xpath, NAMESPACE).filter_map { |node| clean(node.text) }
        end

        def child_text(parent, xpath)
          clean(parent&.at_xpath(xpath, NAMESPACE)&.text)
        end

        # canonical_ws, but nil for blank (used where an absent member must drop out).
        def clean(str)
          return nil if str.nil?

          v = Canonicalize.canonical_ws(str)
          v.empty? ? nil : v
        end

        # canonical_ws keeping "" for blank -- for structured form-field values
        # (an empty given/family/org renders as an empty input, not a dropped key).
        def clean_part(str)
          Canonicalize.canonical_ws(str)
        end

        def join_paragraphs(nodes)
          nodes.map { |n| TextNormalizer.normalize_paragraphs(n.text) }.reject(&:empty?).join("\n\n")
        end
      end
    end
  end
end
