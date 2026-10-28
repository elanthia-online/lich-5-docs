# frozen_string_literal: true

require_relative 'drdefs' # clean_npc_string, for .unignored_npcs

# Namespace for Lich script engine and game automation.
module Lich
  # Namespace for DragonRealms game integration.
  module DragonRealms
    # Tracks the current room state: NPCs, PCs, exits, objects, and player status.
    #
    # Data is shared across all running scripts and updated by the script engine as
    # room text is received from the game server. Arrays are frozen when appropriate
    # (npcs, dead_npcs) to prevent script-to-script interference; mutable arrays
    # (pcs, room_objs) are live references.
    #
    # @see Lich::DragonRealms::Creature for addressing individual creatures
    class DRRoom
      @@npcs ||= [].freeze
      @@pcs ||= []
      @@group_members ||= []
      @@pcs_prone ||= []
      @@pcs_sitting ||= []
      @@dead_npcs ||= [].freeze
      @@room_objs ||= []
      @@exits ||= []
      # NOTE: @@title and @@description removed - getters delegate to XMLData

      # Living NPC nouns in the room, sorted, duplicates repeated
      # (["goblin", "goblin"]). Read-only: every script shares this array, so it
      # is frozen; take a copy (`DRRoom.npcs.dup`) to edit. Address a particular
      # creature by its Lich::DragonRealms::Creature id, not by position.
      # @return [Array<String>] frozen
      def self.npcs
        @@npcs
      end

      # Stores a frozen copy, leaving the caller's array untouched.
      # @param val [Array<String>]
      def self.npcs=(val)
        @@npcs = val.dup.freeze
      end

      # {.npcs} without the creatures an ignore list names. Same shape as
      # {.npcs} (sorted nouns, duplicates repeated), so it replaces the
      # `DRRoom.npcs - ignored` idiom.
      #
      # An entry always removes every NPC whose noun equals it, as
      # `npcs - ignored` does. When the Creature roster lists exactly the
      # living creatures in {.npcs}, an entry also removes the creatures it
      # names by noun or by full name (CreatureInstance#matches?), so
      # "spectral white leopard" skips that pet but not a wild leopard. While
      # the roster and {.npcs} disagree (a refresh in progress, a creature
      # with no name yet, or a name with no noun), only the noun rule applies.
      #
      # @param ignored [Array<String>, nil] configured entries
      # @return [Array<String>] a new array
      def self.unignored_npcs(ignored)
        ignored = Array(ignored).compact.map(&:to_s)
        by_noun = npcs - ignored
        return by_noun if by_noun.empty?

        pairs = room_creatures_with_nouns
        return by_noun unless pairs

        pairs.reject { |creature, noun| ignored.include?(noun) || ignored.any? { |entry| creature.matches?(entry) } }
             .map(&:last)
             .sort
      end

      # The living roster creatures, each paired with the noun {.npcs} lists it
      # under, or nil unless those nouns are exactly {.npcs}.
      #
      # @return [Array<Array(Object, String)>, nil]
      def self.room_creatures_with_nouns
        return nil unless defined?(Lich::DragonRealms::Creature)

        pairs = []
        Lich::DragonRealms::Creature.in_room(:not_dead).each do |creature|
          return nil if creature.name.nil?

          noun = npc_noun_parser.clean_npc_string([creature.name]).first
          return nil if noun.nil?

          pairs << [creature, noun]
        end
        pairs.map(&:last).sort == npcs ? pairs : nil
      end
      private_class_method :room_creatures_with_nouns

      # The drdefs helpers, which build {.npcs} from room text.
      # @return [Object]
      def self.npc_noun_parser
        @@npc_noun_parser ||= Object.new.extend(Lich::DragonRealms)
      end
      private_class_method :npc_noun_parser

      # Returns the array of player character nouns currently in the room.
      #
      # @return [Array<String>]
      def self.pcs
        @@pcs
      end

      # Sets the array of player character nouns in the room.
      #
      # @param val [Array<String>]
      def self.pcs=(val)
        @@pcs = val
      end

      # Returns the exits available from the current room.
      #
      # Delegates to XMLData for live room data.
      #
      # @return [Array<String>]
      def self.exits
        XMLData.room_exits
      end

      # Returns the title of the current room.
      #
      # Delegates to XMLData for live room data.
      #
      # @return [String]
      def self.title
        XMLData.room_title
      end

      # Returns the full description of the current room.
      #
      # Delegates to XMLData for live room data.
      #
      # @return [String]
      def self.description
        XMLData.room_description
      end

      # Returns the array of group member identifiers in the current room.
      #
      # @return [Array]
      def self.group_members
        @@group_members
      end

      # Sets the array of group member identifiers in the current room.
      #
      # @param val [Array]
      def self.group_members=(val)
        @@group_members = val
      end

      # Returns the array of player character nouns currently lying prone in the room.
      #
      # @return [Array<String>]
      def self.pcs_prone
        @@pcs_prone
      end

      # Sets the array of player character nouns lying prone in the room.
      #
      # @param val [Array<String>]
      def self.pcs_prone=(val)
        @@pcs_prone = val
      end

      # Returns the array of player character nouns currently sitting in the room.
      #
      # @return [Array<String>]
      def self.pcs_sitting
        @@pcs_sitting
      end

      # Sets the array of player character nouns sitting in the room.
      #
      # @param val [Array<String>]
      def self.pcs_sitting=(val)
        @@pcs_sitting = val
      end

      # Dead NPC nouns in the room; same shape and rules as {.npcs}.
      # @return [Array<String>] frozen
      def self.dead_npcs
        @@dead_npcs
      end

      # Stores a frozen copy, leaving the caller's array untouched.
      # @param val [Array<String>]
      def self.dead_npcs=(val)
        @@dead_npcs = val.dup.freeze
      end

      # Returns the array of objects present in the current room.
      #
      # @return [Array]
      def self.room_objs
        @@room_objs
      end

      # Sets the array of objects in the current room.
      #
      # @param val [Array]
      def self.room_objs=(val)
        @@room_objs = val
      end
    end
  end
end
