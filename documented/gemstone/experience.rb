require "ostruct"

# Namespace for the Lich 5 Ruby scripting engine.
module Lich
  # Namespace for GemStone IV and DragonRealms game APIs.
  module Gemstone
    # Namespace for character experience, field experience, and related bonuses tracked by the game server.
    module Experience
      # Returns the character's current fame value.
      #
      # @return [Integer, nil] the fame value, or nil if not yet received from the server
      # @example
      #   Lich::Gemstone::Experience.fame #=> 42
      def self.fame
        Infomon.get("experience.fame")
      end

      # Returns the character's current field experience (FXP).
      #
      # @return [Integer] the current field experience points
      def self.fxp_current
        XMLData.field_exp
      end

      # Returns the character's maximum field experience (FXP) for the current field rank.
      #
      # @return [Integer] the maximum field experience points
      def self.fxp_max
        XMLData.max_field_exp
      end

      # Returns the character's current total experience (EXP), excluding ascension experience.
      #
      # @return [Integer] the total experience points
      def self.exp
        XMLData.exp
      end

      # Returns the character's current ascension experience (AXP).
      #
      # @return [Integer] the ascension experience points
      def self.axp
        XMLData.ascension_exp
      end

      # Returns the sum of the character's total experience and ascension experience.
      #
      # @return [Integer] the combined experience points
      # @see .exp
      # @see .axp
      def self.txp
        XMLData.exp + XMLData.ascension_exp
      end

      # Returns the total experience needed to reach the next experience level.
      #
      # @return [Integer] the experience points needed
      def self.until_next
        XMLData.until_next
      end

      # Ascension experience remaining until the next ascension training point.
      # One ATP is earned per 50,000 ascension experience, so at an exact
      # multiple this reports a full 50,000 interval to the next point.
      def self.next_atp
        50_000 - (axp % 50_000)
      end

      # Returns the character's field experience as a percentage of the maximum for the current rank.
      #
      # @return [Float] the percentage between 0.0 and 100.0
      def self.percent_fxp
        (fxp_current.to_f / fxp_max.to_f) * 100
      end

      # Returns the character's ascension experience as a percentage of total experience.
      #
      # @return [Float] the percentage between 0.0 and 100.0
      def self.percent_axp
        (axp.to_f / txp.to_f) * 100
      end

      # Returns the character's experience as a percentage of total experience.
      #
      # @return [Float] the percentage between 0.0 and 100.0
      def self.percent_exp
        (exp.to_f / txp.to_f) * 100
      end

      # Returns the character's long-term experience (LTE) bonus value.
      #
      # @return [Integer, nil] the long-term experience value, or nil if not yet received from the server
      def self.lte
        Infomon.get("experience.long_term_experience")
      end

      # Returns the character's completed deeds value.
      #
      # @return [Integer, nil] the deeds count, or nil if not yet received from the server
      def self.deeds
        Infomon.get("experience.deeds")
      end

      # Returns the character's deaths sting value, representing a temporary experience penalty.
      #
      # @return [Integer, nil] the deaths sting value, or nil if not yet received from the server
      def self.deaths_sting
        Infomon.get("experience.deaths_sting")
      end

      # Returns whether the Rank Point Adjustment (RPA) bonus is active.
      #
      # @return [Boolean] true if RPA is active, false otherwise
      def self.rpa?
        !XMLData.rpa.nil?
      end

      # Returns the character's current Rank Point Adjustment (RPA) value.
      #
      # @return [Integer, nil] the RPA value, or nil if the bonus has not been redeemed
      def self.rpa
        XMLData.rpa
      end

      # Returns whether the Lumnis bonus is active.
      #
      # @return [Boolean] true if Lumnis is active, false otherwise
      def self.lumnis?
        !XMLData.lumnis.nil?
      end

      # Returns the character's current Lumnis bonus value.
      #
      # @return [Integer, nil] the Lumnis value, or nil if the bonus has not been redeemed
      def self.lumnis
        XMLData.lumnis
      end

      # fashlonae has three states on the mindState bar: absent (no orb redeemed),
      # 1 (redeemed but not active), and 2 (redeemed and active). fashlonae?
      # reports whether the bonus is active; fashlonae_redeemed? reports whether an
      # orb has been redeemed at all.
      def self.fashlonae?
        XMLData.fashlonae.eql?(2)
      end

      # Returns whether a Fashlonae orb has been redeemed, regardless of whether it is currently active.
      #
      # @return [Boolean] true if an orb has been redeemed, false otherwise
      # @see .fashlonae?
      def self.fashlonae_redeemed?
        !XMLData.fashlonae.nil?
      end

      # Returns the timestamp when experience data was last updated by the server.
      #
      # @return [Time, nil] the last update time, or nil if experience data has not been received
      def self.updated_at
        timestamp = Infomon.get_updated_at("experience.total_experience")
        timestamp ? Time.at(timestamp) : nil
      end

      # Returns whether the experience data is older than the given threshold.
      #
      # @param threshold [ActiveSupport::Duration] the age threshold; defaults to 24 hours
      # @return [Boolean] true if data is stale or has never been received, false otherwise
      # @example
      #   Lich::Gemstone::Experience.stale?(threshold: 1.hour) #=> false
      def self.stale?(threshold: 24.hours)
        return true unless updated_at
        updated_at < threshold.ago
      end

      # Returns whether the experience data was updated within the given threshold.
      #
      # @param threshold [ActiveSupport::Duration] the recency threshold; defaults to 5 minutes
      # @return [Boolean] true if data was recently updated, false if data is stale or has never been received
      # @example
      #   Lich::Gemstone::Experience.recently_updated?(threshold: 30.seconds) #=> true
      def self.recently_updated?(threshold: 5.minutes)
        return false unless updated_at
        updated_at >= threshold.ago
      end
    end
  end
end
