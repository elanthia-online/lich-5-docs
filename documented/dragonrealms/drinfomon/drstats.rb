# frozen_string_literal: true

# Namespace for the Lich scripting engine.
module Lich
  # Namespace for DragonRealms-specific APIs.
  module DragonRealms
    # Access and manage character stats and attributes in DragonRealms.
    #
    # This module provides thread-safe read/write access to character statistics
    # gathered from the game's XML data feed, including abilities (strength, agility,
    # etc.), dynamic states (health, mana, balance), and character metadata (guild,
    # gender, age). Stats are cached in module-level variables and persist across
    # script reloads when serialized and restored.
    #
    # @example Check character guild
    #   if DRStats.paladin?
    #     DRStats.circle  # => 40
    #   end
    # @example Query trained stats
    #   DRStats.agility  # => 18
    # @example Check native mana type
    #   DRStats.native_mana  # => "holy" for Paladin
    module DRStats
      @@race = nil
      @@guild = nil
      @@gender = nil
      @@age ||= 0
      @@circle ||= 0
      @@strength ||= 0
      @@stamina ||= 0
      @@reflex ||= 0
      @@agility ||= 0
      @@intelligence ||= 0
      @@wisdom ||= 0
      @@discipline ||= 0
      @@charisma ||= 0
      @@favors ||= 0
      @@tdps ||= 0
      @@encumbrance = nil
      @@balance ||= 8
      @@position ||= 0
      @@luck ||= 0

      # Returns the character's race.
      #
      # @return [String, nil] the race name, or nil if not yet loaded
      def self.race
        @@race
      end

      # Sets the character's race.
      #
      # @param val [String, nil] the race name
      # @return [String, nil]
      def self.race=(val)
        @@race = val
      end

      # Returns the character's guild.
      #
      # @return [String, nil] the guild name (e.g. "Paladin", "Moon Mage"), or nil if not yet loaded
      def self.guild
        @@guild
      end

      # Sets the character's guild.
      #
      # @param val [String, nil] the guild name
      # @return [String, nil]
      def self.guild=(val)
        @@guild = val
      end

      # Returns the character's gender.
      #
      # @return [String, nil] the gender, or nil if not yet loaded
      def self.gender
        @@gender
      end

      # Sets the character's gender.
      #
      # @param val [String, nil] the gender
      # @return [String, nil]
      def self.gender=(val)
        @@gender = val
      end

      # Returns the character's age in years.
      #
      # @return [Integer] the age, or 0 if not yet loaded
      def self.age
        @@age
      end

      # Sets the character's age.
      #
      # @param val [Integer] the age in years
      # @return [Integer]
      def self.age=(val)
        @@age = val
      end

      # Returns the character's guild circle (experience tier).
      #
      # @return [Integer] the circle, or 0 if not yet loaded
      def self.circle
        @@circle
      end

      # Sets the character's guild circle.
      #
      # @param val [Integer] the circle
      # @return [Integer]
      def self.circle=(val)
        @@circle = val
      end

      # Returns the character's trained Strength ability.
      #
      # @return [Integer] the trained rank, or 0 if not yet loaded
      def self.strength
        @@strength
      end

      # Sets the character's trained Strength ability.
      #
      # @param val [Integer] the trained rank
      # @return [Integer]
      def self.strength=(val)
        @@strength = val
      end

      # Returns the character's trained Stamina ability.
      #
      # @return [Integer] the trained rank, or 0 if not yet loaded
      def self.stamina
        @@stamina
      end

      # Sets the character's trained Stamina ability.
      #
      # @param val [Integer] the trained rank
      # @return [Integer]
      def self.stamina=(val)
        @@stamina = val
      end

      # Returns the character's trained Reflex ability.
      #
      # @return [Integer] the trained rank, or 0 if not yet loaded
      def self.reflex
        @@reflex
      end

      # Sets the character's trained Reflex ability.
      #
      # @param val [Integer] the trained rank
      # @return [Integer]
      def self.reflex=(val)
        @@reflex = val
      end

      # Returns the character's trained Agility ability.
      #
      # @return [Integer] the trained rank, or 0 if not yet loaded
      def self.agility
        @@agility
      end

      # Sets the character's trained Agility ability.
      #
      # @param val [Integer] the trained rank
      # @return [Integer]
      def self.agility=(val)
        @@agility = val
      end

      # Returns the character's trained Intelligence ability.
      #
      # @return [Integer] the trained rank, or 0 if not yet loaded
      def self.intelligence
        @@intelligence
      end

      # Sets the character's trained Intelligence ability.
      #
      # @param val [Integer] the trained rank
      # @return [Integer]
      def self.intelligence=(val)
        @@intelligence = val
      end

      # Returns the character's trained Wisdom ability.
      #
      # @return [Integer] the trained rank, or 0 if not yet loaded
      def self.wisdom
        @@wisdom
      end

      # Sets the character's trained Wisdom ability.
      #
      # @param val [Integer] the trained rank
      # @return [Integer]
      def self.wisdom=(val)
        @@wisdom = val
      end

      # Returns the character's trained Discipline ability.
      #
      # @return [Integer] the trained rank, or 0 if not yet loaded
      def self.discipline
        @@discipline
      end

      # Sets the character's trained Discipline ability.
      #
      # @param val [Integer] the trained rank
      # @return [Integer]
      def self.discipline=(val)
        @@discipline = val
      end

      # Returns the character's trained Charisma ability.
      #
      # @return [Integer] the trained rank, or 0 if not yet loaded
      def self.charisma
        @@charisma
      end

      # Sets the character's trained Charisma ability.
      #
      # @param val [Integer] the trained rank
      # @return [Integer]
      def self.charisma=(val)
        @@charisma = val
      end

      # Returns the character's favor count.
      #
      # @return [Integer] the favor count, or 0 if not yet loaded
      def self.favors
        @@favors
      end

      # Sets the character's favor count.
      #
      # @param val [Integer] the favor count
      # @return [Integer]
      def self.favors=(val)
        @@favors = val
      end

      # Returns the character's total drained points (from experience loss).
      #
      # @return [Integer] the drained points, or 0 if not yet loaded
      def self.tdps
        @@tdps
      end

      # Sets the character's total drained points.
      #
      # @param val [Integer] the drained points
      # @return [Integer]
      def self.tdps=(val)
        @@tdps = val
      end

      # Returns the character's luck rating.
      #
      # @return [Integer] the luck rating, or 0 if not yet loaded
      def self.luck
        @@luck
      end

      # Sets the character's luck rating.
      #
      # @param val [Integer] the luck rating
      # @return [Integer]
      def self.luck=(val)
        @@luck = val
      end

      # Returns the character's current balance, a measure of how soon the character can perform an action.
      #
      # @return [Integer] the balance value, defaults to 8
      def self.balance
        @@balance
      end

      # Sets the character's current balance.
      #
      # @param val [Integer] the balance value
      # @return [Integer]
      def self.balance=(val)
        @@balance = val
      end

      # Combat positioning relative to your opponent. Signed magnitude where
      # positive means you hold the advantage, negative means your opponent
      # does, and 0 is an even contest. See DR_POSITION_VALUES.
      def self.position
        @@position
      end

      # Sets the character's combat positioning relative to the opponent.
      #
      # Positive values indicate an advantage, negative values indicate a disadvantage,
      # and 0 is an even contest.
      #
      # @param val [Integer] the signed position value
      # @return [Integer]
      def self.position=(val)
        @@position = val
      end

      # Returns the character's encumbrance level.
      #
      # @return [String, nil] the encumbrance state, or nil if not yet loaded
      def self.encumbrance
        @@encumbrance
      end

      # Sets the character's encumbrance level.
      #
      # @param val [String, nil] the encumbrance state
      # @return [String, nil]
      def self.encumbrance=(val)
        @@encumbrance = val
      end

      # Returns the character's name from the XML data feed.
      #
      # @return [String] the character name
      def self.name
        XMLData.name
      end

      # Returns the character's current health from the XML data feed.
      #
      # @return [Integer] the current health
      def self.health
        XMLData.health
      end

      # Returns the character's current mana from the XML data feed.
      #
      # @return [Integer] the current mana
      def self.mana
        XMLData.mana
      end

      # Returns the character's current fatigue (stamina pool) from the XML data feed.
      #
      # @return [Integer] the current fatigue
      def self.fatigue
        XMLData.stamina
      end

      # Returns the character's current spirit from the XML data feed.
      #
      # @return [Integer] the current spirit
      def self.spirit
        XMLData.spirit
      end

      # Returns the character's current concentration from the XML data feed.
      #
      # @return [Integer] the current concentration
      def self.concentration
        XMLData.concentration
      end

      # Guilds and their native mana types, frozen for immutability.
      GUILD_MANA_TYPES = {
        'Necromancer'  => 'arcane',
        'Barbarian'    => nil,
        'Thief'        => nil,
        'Moon Mage'    => 'lunar',
        'Trader'       => 'lunar',
        'Warrior Mage' => 'elemental',
        'Bard'         => 'elemental',
        'Cleric'       => 'holy',
        'Paladin'      => 'holy',
        'Empath'       => 'life',
        'Ranger'       => 'life'
      }.freeze

      # Returns the mana type native to the character's guild.
      #
      # @return [String, nil] the mana type ("arcane", "lunar", "elemental", "holy", "life"), or nil for guilds without native mana (Barbarian, Thief, Commoner)
      # @example
      #   DRStats.native_mana  # => "holy" for Paladin
      #   DRStats.native_mana  # => nil for Barbarian
      def self.native_mana
        GUILD_MANA_TYPES[@@guild]
      end

      # Serialization order (17 elements, indices 0-16):
      # 0: race, 1: guild, 2: gender, 3: age, 4: circle,
      # 5: strength, 6: stamina, 7: reflex, 8: agility,
      # 9: intelligence, 10: wisdom, 11: discipline, 12: charisma,
      # 13: favors, 14: tdps, 15: luck, 16: encumbrance
      def self.serialize
        [@@race, @@guild, @@gender, @@age, @@circle, @@strength, @@stamina, @@reflex, @@agility, @@intelligence, @@wisdom, @@discipline, @@charisma, @@favors, @@tdps, @@luck, @@encumbrance]
      end

      # BUG FIX: Original code used array[5..12] which only provides 8 elements
      # but tried to assign to 13 variables (circle + 12 stats), causing data loss.
      # The correct slice is array[4..16] for the remaining 13 variables.
      def self.load_serialized=(array)
        return if array.nil? || array.empty?

        @@race, @@guild, @@gender, @@age = array[0..3]
        @@circle, @@strength, @@stamina, @@reflex, @@agility, @@intelligence, @@wisdom, @@discipline, @@charisma, @@favors, @@tdps, @@luck, @@encumbrance = array[4..16]
      end

      # Returns whether the character is a Barbarian.
      #
      # @return [Boolean]
      def self.barbarian?
        @@guild == 'Barbarian'
      end

      # Returns whether the character is a Bard.
      #
      # @return [Boolean]
      def self.bard?
        @@guild == 'Bard'
      end

      # Returns whether the character is a Cleric.
      #
      # @return [Boolean]
      def self.cleric?
        @@guild == 'Cleric'
      end

      # Returns whether the character is a Commoner.
      #
      # @return [Boolean]
      def self.commoner?
        @@guild == 'Commoner'
      end

      # Returns whether the character is an Empath.
      #
      # @return [Boolean]
      def self.empath?
        @@guild == 'Empath'
      end

      # Returns whether the character is a Moon Mage.
      #
      # @return [Boolean]
      def self.moon_mage?
        @@guild == 'Moon Mage'
      end

      # Returns whether the character is a Necromancer.
      #
      # @return [Boolean]
      def self.necromancer?
        @@guild == 'Necromancer'
      end

      # Returns whether the character is a Paladin.
      #
      # @return [Boolean]
      def self.paladin?
        @@guild == 'Paladin'
      end

      # Returns whether the character is a Ranger.
      #
      # @return [Boolean]
      def self.ranger?
        @@guild == 'Ranger'
      end

      # Returns whether the character is a Thief.
      #
      # @return [Boolean]
      def self.thief?
        @@guild == 'Thief'
      end

      # Returns whether the character is a Trader.
      #
      # @return [Boolean]
      def self.trader?
        @@guild == 'Trader'
      end

      # Returns whether the character is a Warrior Mage.
      #
      # @return [Boolean]
      def self.warrior_mage?
        @@guild == 'Warrior Mage'
      end
    end
  end
end
