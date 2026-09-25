# frozen_string_literal: true

require_relative "../namespaces"
require_relative "support"

module NEU
  module MODS
    module Projection
      # Faithful port of the mods gem's display_value_w_date, plus the role
      # readers that decide whether the edit form owns a name.
      module NameDisplay
        include Support

        private

        # Every namePart is read through #part_text, so the separators this method
        # composes are the only whitespace in the result. Read raw, an indented
        # `<namePart>\n  Doe\n</namePart>` -- what a pretty-printer writes and what
        # a curator pasting from a form leaves behind -- composed as "Doe ,  John",
        # and the outer strip could not reach the spaces around the comma.
        def name_display_value_w_date(node, type = attr_value(node, "type"))
          dv = name_display_value(node, type)
          node.xpath("mods:namePart[@type='date']", NAMESPACE).each do |np|
            d = part_text(np)
            dv += ", #{d}" unless d.empty? || dv.end_with?(d)
          end
          dv = dv.sub(/\A, /, "")
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

        # NodeSet-style concatenation: the `mods` gem joins same-typed nameParts via
        # NodeSet#text (no separator) -- e.g. two `given` parts become "A.(B)". We
        # reproduce that (quirk included) to stay behavior-preserving.
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

        # One name element's text, whitespace-canonicalized, "" when absent. The
        # name composition joins its parts with separators of its own, so a part
        # has to arrive without the insignificant whitespace an XML document is
        # free to carry around element content.
        def part_text(node)
          clean_part(node&.text)
        end

        def name_roles(node)
          node.xpath("mods:role", NAMESPACE).filter_map { |role| role_term_value(role) }
        end

        # The first declared role, which is what decides whether the simple edit
        # form owns a name. Deliberately not #name_roles.include?("Creator"):
        # widening it would hand the form a name whose other roles it cannot
        # represent, and saving would drop them from the preservation XML.
        def name_role(node) = name_roles(node).first

        # Prefer the type="text" roleTerm; fall back to the raw type="code" term
        # (NOT MARC-relator-translated -- see README). nil if neither is present.
        def role_term_value(role)
          %w[text code].each do |type|
            term = part_text(role.at_xpath("mods:roleTerm[@type='#{type}']", NAMESPACE))
            return term unless term.empty?
          end
          nil
        end

        # A name is "editable" (depositor-managed) when it carries no authority
        # markers and resolves to a Creator role. Shared by editable_creator_nodes
        # (write/select) and the editable_*_creators projections (read). The
        # markers are read the way #authority_of reads them, so a blank attribute
        # counts as absent in both and a name the projection calls uncontrolled
        # is one the form can edit.
        def editable_creator_name?(node)
          AUTHORITY_ATTRIBUTES.values.none? { |attr| attr_value(node, attr) } &&
            name_role(node) == "Creator"
        end
      end
    end
  end
end
