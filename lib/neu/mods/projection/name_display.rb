# frozen_string_literal: true

require_relative "../namespaces"
require_relative "support"

module NEU
  module MODS
    module Projection
      # Faithful port of the mods gem's display_value_w_date, quirks included,
      # plus the role readers that decide whether the edit form owns a name.
      # See docs/names.md.
      module NameDisplay
        include Support

        private

        # Read every namePart through #part_text, so the separators composed here
        # are the only whitespace in the result.
        def name_display_value_w_date(node, type = attr_value(node, "type"))
          dv = name_display_value(node, type)
          node.xpath("mods:namePart[@type='date']", NAMESPACE).each do |np|
            d = part_text(np)
            dv += ", #{d}" unless d.empty? || dv.end_with?(d)
          end
          dv = dv.delete_prefix(", ")
          dv.strip.empty? ? nil : dv.strip
        end

        def name_display_value(node, type)
          display_form = part_text(node.at_xpath("mods:displayForm", NAMESPACE))
          return display_form unless display_form.empty?

          type == "personal" ? personal_display_value(node) : non_date_parts_joined(node)
        end

        def personal_display_value(node)
          family = joined_parts(node, "family")
          given  = joined_parts(node, "given")
          dv =
            if family.empty?
              given
            else
              given.empty? ? family : "#{family}, #{given}"
            end

          return non_date_parts_joined(node) if dv.empty?

          append_terms_of_address(node, dv)
        end

        def append_terms_of_address(node, dv)
          first = true
          node.xpath("mods:namePart[@type='termsOfAddress']", NAMESPACE).each do |np|
            term = part_text(np)
            next if term.empty?

            dv += first ? " #{term}" : ", #{term}"
            first = false
          end
          dv
        end

        # No separator, as the mods gem's NodeSet#text had: two `given` parts
        # become "A.(B)". The conformance spec pins this quirk.
        def joined_parts(node, type)
          node.xpath("mods:namePart[@type='#{type}']", NAMESPACE).map { |np| part_text(np) }.join
        end

        def non_date_parts_joined(node)
          node.xpath("mods:namePart", NAMESPACE)
              .reject { |np| np["type"] == "date" }
              .map { |np| part_text(np) }
              .reject(&:empty?)
              .join(" ")
        end

        # One name element's text, whitespace-canonicalized, "" when absent.
        def part_text(node)
          clean_part(node&.text)
        end

        def name_roles(node)
          node.xpath("mods:role", NAMESPACE).filter_map { |role| role_term_value(role) }
        end

        # The first declared role. Do not widen this to "any role is Creator":
        # the form would then own a name whose other roles it cannot represent,
        # and saving would drop them from the preservation XML.
        def name_role(node) = name_roles(node).first

        # The text roleTerm, else the raw code, untranslated. nil if neither.
        def role_term_value(role)
          %w[text code].each do |type|
            term = part_text(role.at_xpath("mods:roleTerm[@type='#{type}']", NAMESPACE))
            return term unless term.empty?
          end
          nil
        end

        # No authority attribute and a Creator role. Shared by the write path's
        # node selection and the read path's pre-fill, and reads the attributes
        # the way #authority_of does, so the two never disagree.
        def editable_creator_name?(node)
          AUTHORITY_ATTRIBUTES.values.none? { |attr| attr_value(node, attr) } &&
            name_role(node) == "Creator"
        end
      end
    end
  end
end
