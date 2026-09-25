# frozen_string_literal: true

require_relative "../namespaces"
require_relative "../selectors"
require_relative "support"
require_relative "name_display"
require_relative "titles"

module NEU
  module MODS
    module Projection
      # Every top-level subject, as assembled headings and as one list per axis.
      # See docs/subjects.md.
      module Subjects
        include Support
        include NameDisplay
        include Selectors
        include Titles

        # The free-text set Cerberus's simple form edits.
        def keywords
          keyword_subjects.flat_map { |s| texts_under(s, "mods:topic") }
        end

        # A coordinate and a MARC code: neither is heading text.
        HEADING_OMITTED_CHILDREN = %w[cartographics geographicCode].freeze

        # Joined here so a display and a browse index hold the same string. Atlas
        # reads it as Projection::HEADING_SEPARATOR.
        HEADING_SEPARATOR = " -- "

        # The axis a <subject><name> with no @type reaches.
        TYPELESS_NAME_SUBJECT_TYPE = "corporate"

        # Every top-level <subject> as ONE heading: its parts, the joined string,
        # and the axis of its main term.
        def subject_headings
          doc.xpath("/mods:mods/mods:subject", NAMESPACE).filter_map do |node|
            axis_node = heading_axis_node(node)
            parts = subject_heading_parts(node)
            next if axis_node.nil? || parts.empty?

            { parts: parts, heading: parts.join(HEADING_SEPARATOR), axis: heading_axis(axis_node),
              **authority_of(axis_node), **qualifiers_of(node) }
          end
        end

        # Every <topic> under any top-level <subject>, for the access copy.
        def topical_subjects = texts_at("/mods:mods/mods:subject/mods:topic")

        def geographic_subjects = texts_at("/mods:mods/mods:subject/mods:geographic")
        def temporal_subjects = texts_at("/mods:mods/mods:subject/mods:temporal")

        # Composed like #names, so one person reads the same as author and subject.
        def personal_name_subjects = name_subjects("personal")
        def corporate_name_subjects = name_subjects("corporate")

        def occupation_subjects = texts_at("/mods:mods/mods:subject/mods:occupation")

        def genre_subjects = texts_at("/mods:mods/mods:subject/mods:genre")

        # A MARC GAC code, as written. The label vocabulary is the consumer's.
        def geographic_code_subjects = texts_at("/mods:mods/mods:subject/mods:geographicCode")

        # Composed like the main title, since a subject work has every titleInfo part.
        def title_subjects
          doc.xpath("/mods:mods/mods:subject/mods:titleInfo", NAMESPACE).filter_map { |node| composed_title_of(node) }
        end

        # One key per level, kept structured so a consumer can take one level.
        def hierarchical_geographic_subjects
          doc.xpath("/mods:mods/mods:subject/mods:hierarchicalGeographic", NAMESPACE).filter_map do |node|
            entry = HIERARCHICAL_GEOGRAPHIC_LEVELS.to_h { |level| [level, child_text(node, "mods:#{camelize(level)}")] }
            entry if entry.values.any?
          end
        end

        # subject/cartographics, kept structured: composing it is display policy.
        def map_data
          doc.xpath("/mods:mods/mods:subject/mods:cartographics", NAMESPACE).filter_map do |node|
            entry = {
              scale: child_text(node, "mods:scale"),
              projection: child_text(node, "mods:projection"),
              coordinates: child_text(node, "mods:coordinates")
            }
            # cartographics carries neither attribute; the enclosing subject does.
            entry.merge(qualifiers_of(node.parent)) if entry.values.any?
          end
        end

        # The eleven hierarchicalGeographic children, in schema order, broadest first.
        HIERARCHICAL_GEOGRAPHIC_LEVELS = %i[
          continent country province region state territory county city
          city_section island area
        ].freeze

        private

        # The corporate axis also takes a name with no @type.
        def name_subjects(type)
          predicate = "@type='#{type}'"
          predicate = "#{predicate} or not(@type)" if type == TYPELESS_NAME_SUBJECT_TYPE
          doc.xpath("/mods:mods/mods:subject/mods:name[#{predicate}]", NAMESPACE)
             .filter_map { |node| name_display_value_w_date(node) }
        end

        # The child a heading's axis and authority come from: the first one
        # carrying heading text.
        def heading_axis_node(node)
          node.xpath("mods:*", NAMESPACE).find { |child| subject_heading_part(child).compact.any? }
        end

        # The element name, except that a <name> splits by @type: a person and an
        # organisation are separate browses.
        def heading_axis(child)
          return "#{attr_value(child, "type") || TYPELESS_NAME_SUBJECT_TYPE}_name" if child.name == "name"

          snake_case(child.name)
        end

        def subject_heading_parts(node)
          node.xpath("mods:*", NAMESPACE).flat_map { |child| subject_heading_part(child) }.compact
        end

        def subject_heading_part(child)
          return [] if HEADING_OMITTED_CHILDREN.include?(child.name)

          case child.name
          when "name" then [name_display_value_w_date(child)]
          when "titleInfo" then [composed_title_of(child)]
          # Each level is its own part, so a hierarchical place reads as the steps
          # of the heading rather than as one run-together string.
          when "hierarchicalGeographic" then child.xpath("mods:*", NAMESPACE).map { |level| clean(level.text) }
          else split_heading_text(clean(child.text))
          end
        end

        # "A--B--C" in one element gives the same parts as three siblings.
        def split_heading_text(text)
          return [] if text.nil?
          return [text] unless text.include?("--")

          text.split("--").filter_map { |part| clean(part) }
        end
      end
    end
  end
end
