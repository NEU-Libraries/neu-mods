# frozen_string_literal: true

require_relative "../namespaces"
require_relative "../canonicalize"
require_relative "../text_normalizer"

module NEU
  module MODS
    module Projection
      # The attribute, text and qualifier readers every projection area shares.
      module Support
        # The three attributes MODS uses to declare where a value came from, and
        # the projected key each reports under. Read by #authority_of below.
        AUTHORITY_ATTRIBUTES = { authority: "authority", authority_uri: "authorityURI",
                                 value_uri: "valueURI" }.freeze

        private

        def attr_value(node, name)
          return nil unless node

          clean(node[name])
        end

        # The two attributes a display reads off an element rather than out of its
        # text: the header the record asked for, and the link the record attached.
        # They travel together as one pair rather than as two parallel
        # projections a consumer has to zip.
        #
        # The two sets overlap rather than match. MODS 3.8 puts @displayLabel on
        # 26 elements and xlink:href on 14 -- titleInfo, name, alternativeName,
        # agent, subject, abstract, tableOfContents, note, relatedItem,
        # accessCondition, physicalLocation and three more. Reading both off
        # every element costs nothing: an element the schema does not let carry
        # one simply projects nil for it, and a consumer asking the pair of any
        # entry does not have to hold the two lists.
        #
        # An href with no text displays nothing. Every caller drops a value-less
        # element already, which is also what the librarians asked for: a link
        # needs something to hang on.
        def qualifiers_of(node)
          { display_label: attr_value(node, "displayLabel"), href: xlink_href(node) }
        end

        # The attributes naming the vocabulary a VALUE was taken from, which is
        # what tells a controlled term apart from one a depositor typed. A
        # consumer gating a browse link on "is this term controlled?" asks for
        # any of the three: MODS lets a record declare its vocabulary by URI
        # alone, so requiring @authority would call an authorityURI-bearing name
        # uncontrolled.
        #
        # NOT part of #qualifiers_of, and the difference is the resolution rule
        # rather than taste. That pair answers "where does the HEADER come
        # from", which is often a PARENT -- six projections pass `from:` for
        # exactly that reason, because MODS puts @displayLabel on originInfo and
        # physicalDescription rather than on the publisher or extent inside
        # them. An authority is the opposite: `<form authority="marcform">`
        # carries it on the element holding the text, so reading it off the
        # label's element would find nothing there and attribute a parent's
        # vocabulary to a child elsewhere.
        #
        # Each attribute resolves on the element, then on an enclosing
        # <subject>: a pre-coordinated heading declares its vocabulary once, on
        # the heading, and every part of it belongs to that vocabulary.
        #
        # A <role>/<roleTerm> authority is never consulted, which falls out of
        # only ever reading the element and its <subject> ancestor. That matters
        # because the deposit form writes a marcrelator roleTerm on every
        # creator it collects, so an "any authority in the subtree" check would
        # call every depositor-entered name controlled.
        def authority_of(node)
          heading = enclosing_subject(node)
          AUTHORITY_ATTRIBUTES.transform_values do |attribute|
            attr_value(node, attribute) || attr_value(heading, attribute)
          end
        end

        # The <subject> a node sits inside, matched by namespace rather than by
        # prefix for the reason #xlink_href is: a document binds the MODS
        # namespace to whatever prefix it likes.
        def enclosing_subject(node)
          node&.ancestors&.find do |ancestor|
            ancestor.name == "subject" && ancestor.namespace&.href == NAMESPACE["mods"]
          end
        end

        # xlink:href by namespace rather than by prefix. A document is free to
        # bind the XLink namespace to any prefix, or to none, and node["xlink:href"]
        # matches the literal prefix alone.
        def xlink_href(node)
          return nil unless node

          attribute = node.attribute_with_ns("href", XLINK_NAMESPACE)
          attribute && clean(attribute.value)
        end

        # A displayed value plus the qualifiers of the element a display takes its
        # header from. That is not always the element holding the text: MODS puts
        # @displayLabel on originInfo and physicalDescription, never on the
        # publisher, place, extent or digitalOrigin inside them.
        def labeled(value, label_node, authority_node: nil)
          entry = { value: value, **qualifiers_of(label_node) }
          authority_node ? entry.merge(authority_of(authority_node)) : entry
        end

        # #texts_at, with each value carrying the qualifiers of its element.
        # `from:` is an XPath relative to the text-bearing node, naming the
        # ancestor the header comes from instead.
        # `authority:` adds the vocabulary of the VALUE, which resolves off the
        # text-bearing node even where `from:` points the header at an ancestor
        # -- `<form authority="marcform">` is exactly that shape.
        def labeled_texts_at(xpath, from: nil, authority: false)
          doc.xpath(xpath, NAMESPACE).filter_map do |node|
            value = clean(node.text)
            next unless value

            labeled(value, from ? node.at_xpath(from, NAMESPACE) : node,
                    authority_node: authority ? node : nil)
          end
        end

        # The first of a node set to state the attribute. A field joining several
        # elements into one value has one header, and a record that labels only
        # its second abstract still meant the label.
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

        # #camelize's inverse, for reporting a schema element name as a projected
        # one: "hierarchicalGeographic" -> "hierarchical_geographic". Hand-rolled
        # for the reason the gem has no Rails dependency at all.
        def snake_case(name)
          name.to_s.gsub(/([a-z])([A-Z])/) { "#{Regexp.last_match(1)}_#{Regexp.last_match(2).downcase}" }
        end

        # #texts_at scoped to a node rather than the document, for a repeatable
        # child of one element.
        def texts_under(node, xpath)
          node.xpath(xpath, NAMESPACE).filter_map { |child| clean(child.text) }
        end

        # The one way this file builds a string array. Blank members drop out
        # rather than arriving as nil: a record template that seeds an empty
        # <topic> for an edit form to fill -- which is exactly what Atlas's
        # MODSBuilder writes -- otherwise projects [nil], and every consumer of
        # that array has to guard for it.
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
