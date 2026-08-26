require "ostruct"

# Namespace for the Lich 5 scripting engine.
module Lich
  # Namespace for GemStone IV and DragonRealms scripting APIs.
  module Gemstone
    # API for querying character statistics: abilities, attributes, experience, and level.
    module Stats
      # Returns the character's race.
      #
      # @return [String, nil] the race name, or nil if not yet cached from the server
      # @example
      #   Lich::Gemstone::Stats.race #=> "Human"
      def self.race
        Infomon.get("stat.race")
      end

      # Returns the character's profession.
      #
      # @return [String, nil] the profession name, or nil if not yet cached from the server
      # @example
      #   Lich::Gemstone::Stats.profession #=> "Warrior"
      def self.profession
        Infomon.get("stat.profession")
      end

      # Alias for `.profession`.
      #
      # @return [String, nil] the profession name, or nil if not yet cached from the server
      def self.prof
        self.profession
      end

      # Returns the character's gender.
      #
      # @return [String, nil] the gender, or nil if not yet cached from the server
      # @example
      #   Lich::Gemstone::Stats.gender #=> "Male"
      def self.gender
        Infomon.get("stat.gender")
      end

      # Returns the character's age in years.
      #
      # @return [Integer, nil] the age, or nil if not yet cached from the server
      # @example
      #   Lich::Gemstone::Stats.age #=> 25
      def self.age
        Infomon.get("stat.age")
      end

      # Returns the character's level.
      #
      # @return [Integer, nil] the level, or nil if not yet cached from the server
      # @example
      #   Lich::Gemstone::Stats.level #=> 50
      def self.level
        XMLData.level
      end

      @@stats = %i(strength constitution dexterity agility discipline aura logic intuition wisdom influence)
      @@stats.each do |stat|
        self.define_singleton_method(stat) do
          # Base stats (from 'info full') - nil if user hasn't run 'info full'
          base = OpenStruct.new(
            value: Lich::Gemstone::Infomon.get("stat.%s.base" % stat),
            bonus: Lich::Gemstone::Infomon.get("stat.%s.base_bonus" % stat)
          )

          enhanced = OpenStruct.new(
            value: Lich::Gemstone::Infomon.get("stat.%s.enhanced" % stat),
            bonus: Lich::Gemstone::Infomon.get("stat.%s.enhanced_bonus" % stat)
          )

          return OpenStruct.new(
            value: Lich::Gemstone::Infomon.get("stat.%s" % stat),
            bonus: Lich::Gemstone::Infomon.get("stat.%s_bonus" % stat),
            base: base,
            enhanced: enhanced
          )
        end
      end
      # these are here for backwards compat
      %i[str con dex agi dis aur log int wis inf].each do |shorthand|
        # find the long-hand method we want to use as a source for this data
        long_hand = @@stats.find { |method| method.to_s.start_with?(shorthand.to_s) }
        self.define_singleton_method(shorthand) do
          stat = Lich::Gemstone::Stats.send(long_hand)
          [stat.value, stat.bonus]
        end
        # polyfill `base_<shorthand>` for base stats (from 'info full')
        self.define_singleton_method("base_%s" % shorthand) do
          stat = Lich::Gemstone::Stats.send(long_hand)
          [stat.base.value, stat.base.bonus]
        end
        # polyfill `enhanced_<shorthand>` for backwards compat
        self.define_singleton_method("enhanced_%s" % shorthand) do
          stat = Lich::Gemstone::Stats.send(long_hand)
          [stat.enhanced.value, stat.enhanced.bonus]
        end
      end

      # Returns the character's current experience.
      #
      # @return [Integer, nil] the experience value, or nil if not yet cached from the server
      # @example
      #   Lich::Gemstone::Stats.exp #=> 1234567
      def self.exp
        XMLData.exp
      end

      # Returns an array of all character statistics in a fixed order for serialization.
      #
      # Includes race, profession, gender, age, experience, level, all base and shorthand
      # attributes (str, con, dex, agi, dis, aur, log, int, wis, inf), their enhanced
      # variants, and base variants.
      #
      # @return [Array] an ordered array of character stats; elements may be nil if not yet cached
      # @example
      #   Lich::Gemstone::Stats.serialize #=> ["Human", "Warrior", "Male", 25, 1234567, 50, ...]
      def self.serialize
        [self.race, self.prof, self.gender,
         self.age, self.exp, self.level,
         self.str, self.con, self.dex,
         self.agi, self.dis, self.aur,
         self.log, self.int, self.wis, self.inf,
         self.enhanced_str, self.enhanced_con, self.enhanced_dex,
         self.enhanced_agi, self.enhanced_dis, self.enhanced_aur,
         self.enhanced_log, self.enhanced_int, self.enhanced_wis,
         self.enhanced_inf,
         self.base_str, self.base_con, self.base_dex,
         self.base_agi, self.base_dis, self.base_aur,
         self.base_log, self.base_int, self.base_wis,
         self.base_inf]
      end
    end
  end
end
