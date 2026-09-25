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
      module Subjects
        include Support
        include NameDisplay
        include Selectors
        include Titles

        # The editable free-text keyword set (Cerberus simple form): topics under the
        # attribute-free keyword subjects only.
        def keywords
          keyword_subjects.flat_map { |s| texts_under(s, "mods:topic") }
        end

        # Neither child carries heading text: cartographics is a structured
        # coordinate a reader reaches through #map_data, and geographicCode is a
        # MARC code rather than a place name.
        HEADING_OMITTED_CHILDREN = %w[cartographics geographicCode].freeze

        # What a cataloguer puts between the steps of a pre-coordinated heading.
        # Here rather than with the consumer because the composed heading is a
        # projected value now: a display and an index that both read it cannot
        # separate it differently. Spaces included, which is the separator DRS
        # has displayed for years.
        HEADING_SEPARATOR = " -- "

        # A <subject><name> with no @type reaches the corporate axis. The display
        # already composes such a name, because #subject_heading_part never
        # consulted @type, so the alternative is a heading a reader sees and no
        # browse holds. Corporate rather than personal: MODS expects
        # @type="personal" on a person, and the untyped subject names DRS holds
        # are institutional.
        TYPELESS_NAME_SUBJECT_TYPE = "corporate"

        # Every top-level <subject> as ONE heading, its parts in document order.
        # A pre-coordinated heading like "Salt marshes--Massachusetts--20th
        # century" is a single statement, and the per-axis fields below cannot say
        # which parts belonged together: they pool every topic on the record into
        # one list, so a fragment of a heading and a whole heading read alike.
        #
        # The parts stay, because the Advanced edit form and a consumer wanting
        # one step of a heading both ask for them. `heading:` is the same parts
        # joined, and it is here rather than left to each caller because the
        # composed heading is now BOTH the string a display renders and the
        # string a browse index holds. Two callers joining independently is how
        # a displayed value and an indexed value drift apart, and this join
        # makes them the same string rather than two that happen to match.
        #
        # `axis:` names the MODS element the heading's MAIN term came from, which
        # is the first child that carries heading text. A consumer cannot derive
        # it from the parts -- they are bare strings -- and it is the fact that
        # says which browse a heading belongs to: "Salt marshes -- Massachusetts"
        # is a topic heading with a place subdivision, not a place. Reported as
        # the element name, so the browse vocabulary stays with the consumer.
        def subject_headings
          doc.xpath("/mods:mods/mods:subject", NAMESPACE).filter_map do |node|
            axis_node = heading_axis_node(node)
            parts = subject_heading_parts(node)
            next if axis_node.nil? || parts.empty?

            { parts: parts, heading: parts.join(HEADING_SEPARATOR), axis: heading_axis(axis_node),
              **authority_of(axis_node), **qualifiers_of(node) }
          end
        end

        # Every <topic> under any top-level <subject> (the access-copy projection,
        # equivalent to Atlas's extract_topical_subjects).
        def topical_subjects = texts_at("/mods:mods/mods:subject/mods:topic")

        # The other subject axes. Cerberus's IPTC ingest writes subject/geographic
        # from the IPTC City and State fields, so this one was also being written
        # on every batch and read back by nothing.
        def geographic_subjects = texts_at("/mods:mods/mods:subject/mods:geographic")

        def temporal_subjects = texts_at("/mods:mods/mods:subject/mods:temporal")

        # Name subjects compose through the same display-value port as #names, so
        # one person reads the same whether they authored the work or are its
        # subject.
        def personal_name_subjects = name_subjects("personal")

        def corporate_name_subjects = name_subjects("corporate")

        # The last unprojected member of a closed set: every other subject child
        # already has a field, so leaving this one out made "what a subject can
        # carry" arbitrary rather than complete.
        def occupation_subjects = texts_at("/mods:mods/mods:subject/mods:occupation")

        def genre_subjects = texts_at("/mods:mods/mods:subject/mods:genre")

        # A MARC GAC code. Projected as the record wrote it: turning it into a
        # place name needs a lookup table, which is the same call the gem already
        # made for MARC relators -- the label vocabulary belongs to the consumer.
        def geographic_code_subjects = texts_at("/mods:mods/mods:subject/mods:geographicCode")

        # A subject that is a work has a nonSort, a subTitle and part numbers like
        # any other titleInfo, so it composes through the same port as the main
        # title rather than taking titleInfo/title alone.
        def title_subjects
          doc.xpath("/mods:mods/mods:subject/mods:titleInfo", NAMESPACE).filter_map { |node| composed_title_of(node) }
        end

        # Kept structured for the reason #map_data is. Flattening country / state
        # / city into "United States -- New York (State) -- Parksville" would make
        # a consumer that wants the city alone unpick a sentence.
        #
        # This is the axis bdr_43888.mods.xml uses INSTEAD of subject/geographic,
        # so that record projected no place at all -- a live ingest path, not a
        # hypothetical.
        def hierarchical_geographic_subjects
          doc.xpath("/mods:mods/mods:subject/mods:hierarchicalGeographic", NAMESPACE).filter_map do |node|
            entry = HIERARCHICAL_GEOGRAPHIC_LEVELS.to_h { |level| [level, child_text(node, "mods:#{camelize(level)}")] }
            entry if entry.values.any?
          end
        end

        # subject/cartographics, kept structured. Composing "scale ; projection
        # coordinates" into one string is display policy, and this gem does not own
        # that -- a consumer that wants only the coordinates should not have to
        # unpick a sentence to get them.
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

        # The eleven children the XSD allows under hierarchicalGeographic, in the
        # order MODS lists them -- broadest first, which is also the order a
        # consumer composing a place string wants to reverse.
        HIERARCHICAL_GEOGRAPHIC_LEVELS = %i[
          continent country province region state territory county city
          city_section island area
        ].freeze

        private

        # The corporate axis also takes a subject name with NO @type (see
        # TYPELESS_NAME_SUBJECT_TYPE), so a name the heading composes reaches a
        # browse instead of displaying and projecting nowhere.
        def name_subjects(type)
          predicate = "@type='#{type}'"
          predicate = "#{predicate} or not(@type)" if type == TYPELESS_NAME_SUBJECT_TYPE
          doc.xpath("/mods:mods/mods:subject/mods:name[#{predicate}]", NAMESPACE)
             .filter_map { |node| name_display_value_w_date(node) }
        end

        # The child a heading's axis and authority come from: the first one
        # carrying heading text. A heading with none projects nothing, so its
        # axis is never asked for.
        def heading_axis_node(node)
          node.xpath("mods:*", NAMESPACE).find { |child| subject_heading_part(child).compact.any? }
        end

        # The axis of one heading child, as the MODS element that holds it. A
        # <name> splits by @type, because a person and an organisation are
        # separate browses and MODS says which on the element rather than in the
        # element name.
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

        # A cataloguer who typed a whole heading into one element as "A--B--C"
        # made the same statement as one who structured it into siblings, so both
        # arrive here as the same parts.
        def split_heading_text(text)
          return [] if text.nil?
          return [text] unless text.include?("--")

          text.split("--").filter_map { |part| clean(part) }
        end
      end
    end
  end
end
