# frozen_string_literal: true

# Namespace for Lich 5, a Ruby scripting engine for GemStone IV and DragonRealms.
module Lich
  # Namespace for shared utilities and parsers used across Lich 5.
  module Common
    # Decodes the five standard XML entities. The SAX parsers run Ox with
    # convert_special: false (so Ox never turns a numeric entity into UTF-8 that
    # would then be mis-encoded), which means Ox leaves the standard entities
    # literal -- this restores them. Shared by Lich::Common::XMLParser and
    # Lich::DragonRealms::DRParser.
    module XmlEntities
      # &amp; is decoded last so an already-encoded entity such as &amp;gt;
      # round-trips to the literal &gt; rather than being double-decoded to >.
      def self.decode(str)
        return str unless str.include?('&')

        str.gsub('&lt;', '<').gsub('&gt;', '>').gsub('&quot;', '"').gsub('&apos;', "'").gsub('&amp;', '&')
      end

      # Encodes the three markup-significant characters so a raw value can be
      # safely embedded in an XML-like payload sent to a frontend. &amp; is
      # encoded first so the ampersands introduced by encoding < and > are not
      # themselves double-encoded.
      def self.encode(str)
        str.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
      end
    end
  end
end
