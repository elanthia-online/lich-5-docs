# Namespace for the Lich scripting engine.
module Lich
  # Namespace for GemStone IV game integration.
  module Gemstone
    # Access character currency holdings including silver, notes, and specialty scrips.
    #
    # All accessor methods query Infomon's cached wealth data; use the +refresh:+ parameter
    # or explicit refresh methods to send WEALTH commands to the game server.
    module Currency
      # Silver carried, as Infomon last saw it. Infomon updates it whenever a
      # WEALTH or INFO response goes by, so the value is only as fresh as the
      # last of those; pass +refresh: true+ to send WEALTH QUIET first.
      #
      # @param refresh [Boolean]
      # @return [Integer, nil]
      def self.silver(refresh: false)
        self.refresh if refresh
        Lich::Gemstone::Infomon.get('currency.silver')
      end

      # Send WEALTH so Infomon re-reads the silver carried (WEALTH is quiet by
      # default; LOUD is the option that echoes to the room). The response is
      # parsed on the game thread before hooks run, so hiding it from the front
      # end does not hide it from Infomon.
      #
      # @param all [Boolean] WEALTH ALL, which also refreshes gigas fragments,
      #   redsteel marks and gemstone dust
      # @return [Integer, nil] the refreshed silver
      def self.refresh(all: false)
        Lich::Util.issue_command(all ? 'wealth all' : 'wealth', Lich::Gemstone::Infomon::Parser::Pattern::WealthSilver, silent: true, quiet: true)
        Lich::Gemstone::Infomon.get('currency.silver')
      end

      # Silver stored in worn containers, as WEALTH last reported it.
      #
      # @return [Integer, nil]
      def self.silver_container
        Lich::Gemstone::Infomon.get('currency.silver_container')
      end

      # Carried plus container silver, the "carrying a total of" line.
      #
      # @param refresh [Boolean]
      # @return [Integer, nil]
      def self.silver_total(refresh: false)
        self.refresh if refresh
        Lich::Gemstone::Infomon.get('currency.silver_total')
      end

      # Total value of accessible bank notes, from WEALTH NOTES.
      #
      # @param refresh [Boolean]
      # @return [Integer, nil]
      def self.notes(refresh: false)
        refresh_notes if refresh
        Lich::Gemstone::Infomon.get('currency.notes')
      end

      # Send WEALTH NOTES so Infomon re-reads the note total.
      #
      # @return [Integer, nil]
      def self.refresh_notes
        Lich::Util.issue_command('wealth notes', /^Listing accessible bank notes/, /^Total note value:/, silent: true, quiet: true)
        Lich::Gemstone::Infomon.get('currency.notes')
      end

      # Returns the character's redsteel mark balance, as WEALTH RICH last reported it.
      #
      # @return [Integer, nil]
      def self.redsteel_marks
        Lich::Gemstone::Infomon.get('currency.redsteel_marks')
      end

      # Returns the character's ticket balance, as WEALTH last reported it.
      #
      # @return [Integer, nil]
      def self.tickets
        Lich::Gemstone::Infomon.get('currency.tickets')
      end

      # Returns the character's blackscrip balance, as WEALTH last reported it.
      #
      # @return [Integer, nil]
      def self.blackscrip
        Lich::Gemstone::Infomon.get('currency.blackscrip')
      end

      # Returns the character's bloodscrip balance, as WEALTH last reported it.
      #
      # @return [Integer, nil]
      def self.bloodscrip
        Lich::Gemstone::Infomon.get('currency.bloodscrip')
      end

      # Returns the character's ethereal scrip balance, as WEALTH last reported it.
      #
      # @return [Integer, nil]
      def self.ethereal_scrip
        Lich::Gemstone::Infomon.get('currency.ethereal_scrip')
      end

      # Returns the character's raikhen balance, as WEALTH last reported it.
      #
      # @return [Integer, nil]
      def self.raikhen
        Lich::Gemstone::Infomon.get('currency.raikhen')
      end

      # Returns the character's elan balance, as WEALTH last reported it.
      #
      # @return [Integer, nil]
      def self.elans
        Lich::Gemstone::Infomon.get('currency.elans')
      end

      # Returns the character's soul shard balance, as WEALTH last reported it.
      #
      # @return [Integer, nil]
      def self.soul_shards
        Lich::Gemstone::Infomon.get('currency.soul_shards')
      end

      # Returns the character's aevit balance, as WEALTH last reported it.
      #
      # @return [Integer, nil]
      def self.aevit
        Lich::Gemstone::Infomon.get('currency.aevit')
      end

      # Returns the character's gold balance, as WEALTH last reported it.
      #
      # @return [Integer, nil]
      def self.gold
        Lich::Gemstone::Infomon.get('currency.gold')
      end

      # Returns the character's gigas artifact fragment balance, as WEALTH ALL last reported it.
      #
      # @return [Integer, nil]
      # @see .refresh Use +refresh(all: true)+ to update this value from the game server.
      def self.gigas_artifact_fragments
        Lich::Gemstone::Infomon.get('currency.gigas_artifact_fragments')
      end

      # Returns the character's gemstone dust balance, as WEALTH ALL last reported it.
      #
      # @return [Integer, nil]
      # @see .refresh Use +refresh(all: true)+ to update this value from the game server.
      def self.gemstone_dust
        Lich::Gemstone::Infomon.get('currency.gemstone_dust')
      end
    end
  end
end
