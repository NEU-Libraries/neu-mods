# frozen_string_literal: true

require_relative "../namespaces"
require_relative "../canonicalize"
require_relative "../selectors"
require_relative "support"

module NEU
  module MODS
    module Projection
      # The abstract and the access conditions, each joined into one value with
      # its header and link as companion scalars.
      module Access
        include Support
        include Selectors

        def abstract
          join_paragraphs(abstract_nodes)
        end

        # The header and the link a record attached to its abstract. Companion
        # scalars rather than an entry, because #abstract joins every abstract
        # element into one value and three consumers -- the OAI dc:description,
        # the citation and description_tsim -- hold that value as a string.
        def abstract_display_label = first_attr(abstract_nodes, "displayLabel")
        def abstract_href = first_href(abstract_nodes)

        # Every top-level accessCondition joined, regardless of @type. Retained
        # because it is the only projection that carries an untyped or
        # unrecognised accessCondition, which the two typed fields below cannot
        # see -- a consumer that renders only those needs this as its fallback.
        def access_condition
          join_paragraphs(doc.xpath("/mods:mods/mods:accessCondition", NAMESPACE))
        end

        # The two @type values MODS defines, projected apart. Collapsing them into
        # one value presented an access *restriction* to a reader as a *licence*,
        # which is the one defect in this area that misinforms someone about their
        # rights rather than merely hiding a field.
        def use_and_reproduction = access_conditions_of_type("use and reproduction")
        def restriction_on_access = access_conditions_of_type("restriction on access")

        # Companion scalars for the same reason the abstract's are: each of the
        # three fields joins several elements into one value, and a licence URI
        # belongs beside the licence text a reader is given.
        def access_condition_display_label = first_attr(access_condition_nodes, "displayLabel")
        def access_condition_href = first_href(access_condition_nodes)

        def use_and_reproduction_display_label
          first_attr(access_condition_nodes("use and reproduction"), "displayLabel")
        end

        def use_and_reproduction_href = first_href(access_condition_nodes("use and reproduction"))

        def restriction_on_access_display_label
          first_attr(access_condition_nodes("restriction on access"), "displayLabel")
        end

        def restriction_on_access_href = first_href(access_condition_nodes("restriction on access"))

        # An open-string @type reduced to its letters and digits, so casing, word
        # separators and camelCasing cannot decide whether a field matches.
        def self.fold_type(str)
          Canonicalize.canonical_ws(str).downcase.gsub(/[^a-z0-9]/, "")
        end

        private

        # Every top-level accessCondition, or those of one folded @type. Shared by
        # the joined text projections and by the qualifier companions, so a header
        # cannot come from a different element than the value it heads.
        def access_condition_nodes(type = nil)
          nodes = doc.xpath("/mods:mods/mods:accessCondition", NAMESPACE)
          return nodes if type.nil?

          wanted = Access.fold_type(type)
          nodes.select { |node| Access.fold_type(node["type"]) == wanted }
        end

        # The schema leaves accessCondition/@type an open string, so match on a
        # folded key rather than in the XPath. Real records carry "Use and
        # Reproduction", "useAndReproduction" and "restriction-on-access" as
        # readily as the MODS-recommended casing, and an unmatched
        # restrictionOnAccess fell through to the generic #access_condition --
        # which is the same defect the two typed fields exist to prevent, reached
        # by a different route: a restriction presented to a reader as a licence.
        #
        # A genuinely unrecognised type still falls through, which is what
        # #access_condition is for.
        def access_conditions_of_type(type)
          join_paragraphs(access_condition_nodes(type))
        end
      end
    end
  end
end
