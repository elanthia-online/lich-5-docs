# Top-level namespace for Lich 5, a Ruby scripting engine for GemStone IV and
# DragonRealms.
module Lich
  # Namespace for GemStone IV scripting APIs.
  module Gemstone
    # Access to the player\'s current currency and scrip balances.
    #
    # All methods query the live character data maintained by the Lich engine.
    # Returns are [Integer] or [nil] if the data is not yet available.
    module Currency
      # Returns the player\'s current silver balance.
      #
      # @return [Integer, nil] silver amount, or nil if not yet available
      # @example
      #   Lich::Gemstone::Currency.silver #=> 5000
      def self.silver
        Lich::Gemstone::Infomon.get('currency.silver')
      end

      # Returns the item noun of the container holding the player\'s silver.
      #
      # @return [String, nil] container noun (e.g. "pouch", "sack"), or nil if not yet available
      def self.silver_container
        Lich::Gemstone::Infomon.get('currency.silver_container')
      end

      # Returns the player\'s current Redsteel Marks balance.
      #
      # @return [Integer, nil] Redsteel Marks amount, or nil if not yet available
      # @example
      #   Lich::Gemstone::Currency.redsteel_marks #=> 42
      def self.redsteel_marks
        Lich::Gemstone::Infomon.get('currency.redsteel_marks')
      end

      # Returns the player\'s current Tickets balance.
      #
      # @return [Integer, nil] Tickets amount, or nil if not yet available
      def self.tickets
        Lich::Gemstone::Infomon.get('currency.tickets')
      end

      # Returns the player\'s current Blackscrip balance.
      #
      # @return [Integer, nil] Blackscrip amount, or nil if not yet available
      def self.blackscrip
        Lich::Gemstone::Infomon.get('currency.blackscrip')
      end

      # Returns the player\'s current Bloodscrip balance.
      #
      # @return [Integer, nil] Bloodscrip amount, or nil if not yet available
      def self.bloodscrip
        Lich::Gemstone::Infomon.get('currency.bloodscrip')
      end

      # Returns the player\'s current Ethereal Scrip balance.
      #
      # @return [Integer, nil] Ethereal Scrip amount, or nil if not yet available
      def self.ethereal_scrip
        Lich::Gemstone::Infomon.get('currency.ethereal_scrip')
      end

      # Returns the player\'s current Raikhen balance.
      #
      # @return [Integer, nil] Raikhen amount, or nil if not yet available
      def self.raikhen
        Lich::Gemstone::Infomon.get('currency.raikhen')
      end

      # Returns the player\'s current Elans balance.
      #
      # @return [Integer, nil] Elans amount, or nil if not yet available
      def self.elans
        Lich::Gemstone::Infomon.get('currency.elans')
      end

      # Returns the player\'s current Soul Shards balance.
      #
      # @return [Integer, nil] Soul Shards amount, or nil if not yet available
      def self.soul_shards
        Lich::Gemstone::Infomon.get('currency.soul_shards')
      end

      # Returns the player\'s current Aevit balance.
      #
      # @return [Integer, nil] Aevit amount, or nil if not yet available
      def self.aevit
        Lich::Gemstone::Infomon.get('currency.aevit')
      end

      # Returns the player\'s current gold balance.
      #
      # @return [Integer, nil] gold amount, or nil if not yet available
      # @example
      #   Lich::Gemstone::Currency.gold #=> 15000
      def self.gold
        Lich::Gemstone::Infomon.get('currency.gold')
      end

      # Returns the player\'s current Gigas Artifact Fragments balance.
      #
      # @return [Integer, nil] Gigas Artifact Fragments amount, or nil if not yet available
      def self.gigas_artifact_fragments
        Lich::Gemstone::Infomon.get('currency.gigas_artifact_fragments')
      end

      # Returns the player\'s current Gemstone Dust balance.
      #
      # @return [Integer, nil] Gemstone Dust amount, or nil if not yet available
      def self.gemstone_dust
        Lich::Gemstone::Infomon.get('currency.gemstone_dust')
      end
    end
  end
end
