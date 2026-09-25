# frozen_string_literal: true

require_relative "../namespaces"
require_relative "../selectors"
require_relative "support"
require_relative "name_display"

module NEU
  module MODS
    module Projection
      # Top-level names: the composed entries for the access copy and the
      # editable and preserved sets the edit form reads.
      module Names
        include Support
        include NameDisplay
        include Selectors

        # One name as the access copy wants it. `affiliation` is how a reader
        # tells one J. Doe from another, and it is the field an institutional
        # repository most wants: it repeats in the schema, so it is an array.
        #
        # Added to the entry rather than as a parallel field, so a name and its
        # affiliation cannot be zipped together wrongly by a consumer.
        def name_entry(node)
          {
            name: name_display_value_w_date(node),
            roles: name_roles(node),
            affiliation: texts_under(node, "mods:affiliation"),
            # @usage is fixed="primary" in the schema and exists to nominate the
            # principal name. A record that sets it has said which name leads,
            # and without it a consumer grouping role-less names can only guess.
            usage: attr_value(node, "usage"),
            alternative_names: alternative_names(node),
            # The vocabulary this name was taken from, read off the <name> alone.
            # A marcrelator <roleTerm> inside it says what the person DID, not
            # which list the name came from -- see #authority_of.
            **authority_of(node),
            **qualifiers_of(node)
          }
        end

        # mods:alternativeName, new in MODS 3.7: a second form of the same name,
        # not a second name. Composed with the ENCLOSING name's @type, because
        # alternativeName carries @altType rather than @type and an alternative
        # for a personal name is still a personal name -- read from its own
        # attributes it would compose "Doe Jane" where the name above it
        # composes "Doe, Jane".
        def alternative_names(node)
          node.xpath("mods:alternativeName", NAMESPACE).filter_map do |alt|
            name_display_value_w_date(alt, attr_value(node, "type"))
          end
        end

        # All top-level names as { name:, roles: }. `name` reproduces the `mods` gem's
        # display_value_w_date (including its quirks -- faithfully, so existing Solr/
        # display output is preserved). MODS repeats `role` on one name, and a
        # cataloguer who records that a person both wrote and edited a work means
        # both. Each term prefers the type="text" roleTerm, falling back to the raw
        # code (NOT MARC-relator-translated -- see README).
        #
        # A name with no name text drops out. A mods:name carrying only a role
        # projected { name: nil, roles: ["edt"] }, which a display renders as a
        # labelled empty row and which every consumer had to guard against with
        # its own compact_blank. #preserved_names deliberately keeps it: that list
        # tells a curator what the XML holds, so an element they need to fix has
        # to stay visible there.
        def names
          doc.xpath("/mods:mods/mods:name", NAMESPACE).filter_map do |node|
            entry = name_entry(node)
            entry if entry[:name]
          end
        end

        # Editable (depositor-managed) creators: the plain names (no authority
        # markers) with a Creator role, as STRUCTURED parts for form pre-fill --
        # distinct from #names, which composes display strings for the access copy.
        def editable_personal_creators
          editable_creator_nodes("personal").map do |node|
            { given: clean_part(joined_parts(node, "given")), family: clean_part(joined_parts(node, "family")) }
          end
        end

        def editable_corporate_creators
          editable_creator_nodes("corporate").map { |node| { name: clean_part(non_date_parts_joined(node)) } }
        end

        # Names the editable form does NOT manage (authority-bearing or non-Creator)
        # -- for read-only display ("these exist; edit via the XML tab"). Composed
        # display string + roles, like #names but filtered to the preserved set.
        def preserved_names
          doc.xpath("/mods:mods/mods:name", NAMESPACE)
             .reject { |node| editable_creator_name?(node) }
             .map { |node| name_entry(node) }
        end
      end
    end
  end
end
