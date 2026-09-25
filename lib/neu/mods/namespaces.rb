# frozen_string_literal: true

module NEU
  module MODS
    # The MODS v3 namespace, as a Nokogiri xpath namespace hash.
    NAMESPACE = { "mods" => "http://www.loc.gov/mods/v3" }.freeze

    # XLink, which MODS uses for the @xlink:href a display hyperlinks an element
    # to. Held as a bare URI rather than a prefix map because the attribute is
    # read by namespace: a document may bind XLink to any prefix it likes.
    XLINK_NAMESPACE = "http://www.w3.org/1999/xlink"
  end
end
