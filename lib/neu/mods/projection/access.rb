# frozen_string_literal: true

require_relative "../namespaces"
require_relative "../canonicalize"
require_relative "../selectors"
require_relative "support"

module NEU
  module MODS
    module Projection
      # The abstract and the access conditions, each joined into one value with
      # its header and link as companion scalars. See docs/other-fields.md.
      module Access
        include Support
        include Selectors

        def abstract
          join_paragraphs(abstract_nodes)
        end

        # Companion scalars, because #abstract joins every element into one string.
        def abstract_display_label = first_attr(abstract_nodes, "displayLabel")
        def abstract_href = first_href(abstract_nodes)

        # Every accessCondition, whatever its type. The only field that carries an
        # untyped or unrecognised one.
        def access_condition
          join_paragraphs(doc.xpath("/mods:mods/mods:accessCondition", NAMESPACE))
        end

        # Kept apart so a restriction is never shown to a reader as a licence.
        def use_and_reproduction = access_conditions_of_type("use and reproduction")
        def restriction_on_access = access_conditions_of_type("restriction on access")

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

        # Letters and digits only, lower-cased: records write @type in any casing.
        def self.fold_type(str)
          Canonicalize.canonical_ws(str).downcase.gsub(/[^a-z0-9]/, "")
        end

        private

        # Shared by the text and its companions, so a header always comes from
        # the elements the value does.
        def access_condition_nodes(type = nil)
          nodes = doc.xpath("/mods:mods/mods:accessCondition", NAMESPACE)
          return nodes if type.nil?

          wanted = Access.fold_type(type)
          nodes.select { |node| Access.fold_type(node["type"]) == wanted }
        end

        # Matched on the folded @type, not in the XPath, because @type is open.
        def access_conditions_of_type(type)
          join_paragraphs(access_condition_nodes(type))
        end
      end
    end
  end
end
