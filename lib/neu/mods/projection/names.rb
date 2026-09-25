# frozen_string_literal: true

require_relative "../namespaces"
require_relative "../selectors"
require_relative "support"
require_relative "name_display"

module NEU
  module MODS
    module Projection
      # Top-level names: the composed entries for the access copy and the
      # editable and preserved sets the edit form reads. See docs/names.md.
      module Names
        include Support
        include NameDisplay
        include Selectors

        # One name as the access copy wants it.
        def name_entry(node)
          {
            name: name_display_value_w_date(node),
            roles: name_roles(node),
            affiliation: texts_under(node, "mods:affiliation"),
            usage: attr_value(node, "usage"),
            alternative_names: alternative_names(node),
            # Off the <name> alone: a marcrelator <roleTerm> says what the person
            # did, not which list the name came from.
            **authority_of(node),
            **qualifiers_of(node)
          }
        end

        # Composed with the ENCLOSING name's @type: alternativeName carries
        # @altType, and an alternative for a personal name is still personal.
        def alternative_names(node)
          node.xpath("mods:alternativeName", NAMESPACE).filter_map do |alt|
            name_display_value_w_date(alt, attr_value(node, "type"))
          end
        end

        # Every top-level name with name text. #preserved_names keeps a name with
        # none, so a curator can still see the element to fix it.
        def names
          doc.xpath("/mods:mods/mods:name", NAMESPACE).filter_map do |node|
            entry = name_entry(node)
            entry if entry[:name]
          end
        end

        # The plain Creator names the edit form manages, as structured parts
        # for pre-fill rather than composed display strings.
        def editable_personal_creators
          editable_creator_nodes("personal").map do |node|
            { given: clean_part(joined_parts(node, "given")), family: clean_part(joined_parts(node, "family")) }
          end
        end

        def editable_corporate_creators
          editable_creator_nodes("corporate").map { |node| { name: clean_part(non_date_parts_joined(node)) } }
        end

        # The names the edit form does not manage, for read-only display.
        def preserved_names
          doc.xpath("/mods:mods/mods:name", NAMESPACE)
             .reject { |node| editable_creator_name?(node) }
             .map { |node| name_entry(node) }
        end
      end
    end
  end
end
