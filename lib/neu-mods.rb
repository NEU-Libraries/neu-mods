# frozen_string_literal: true

require_relative "neu/mods/version"
require_relative "neu/mods/canonicalize"
require_relative "neu/mods/selectors"
require_relative "neu/mods/projection"
require_relative "neu/mods/document"

# Northeastern-flavored MODS v3 projection + selection for the DRS.
#
# A Nokogiri-native, dependency-light *reading/projection contract* over MODS
# documents, shared by Cerberus (front end) and Atlas (API backend). Pure
# functions over a document -- no Rails, no persistence, no HTTP. It answers two
# questions and nothing else:
#
#   * "Where is X?"            -> Selectors (live nodes; serve read AND write)
#   * "What does this project to?" -> Projection (plain data; for index/display)
#
# Top-level conveniences delegate to the canonicalization helpers so callers can
# write `NEU::MODS.whitespace_equivalent?(a, b)` etc. without reaching into the
# submodules.
module NEU
  module MODS
    # The MODS v3 namespace, as a Nokogiri xpath namespace hash.
    NAMESPACE = { "mods" => "http://www.loc.gov/mods/v3" }.freeze

    # The projected field set and its cardinality (see Projection::FIELDS),
    # surfaced here so a consumer deriving its own schema from it -- Atlas's
    # Metadata::MODS attr_json set -- reads the shared contract off the top-level
    # module instead of reaching into a mixin.
    FIELDS = Projection::FIELDS

    module_function

    # Whitespace no-op guard (see Canonicalize).
    def canonical_ws(str) = Canonicalize.canonical_ws(str)
    def whitespace_equivalent?(current, incoming) = Canonicalize.whitespace_equivalent?(current, incoming)

    # Curator-freetext normalization for the access copy (see TextNormalizer).
    def normalize(str) = TextNormalizer.normalize(str)
    def normalize_paragraphs(str) = TextNormalizer.normalize_paragraphs(str)

    # Pure display-title composition over a primary-title parts hash (see
    # Projection.compose_title). Lets a caller that already holds the parts --
    # e.g. Atlas's access-copy model -- compose the title without parsing XML.
    def compose_title(parts) = Projection.compose_title(parts)
  end
end
