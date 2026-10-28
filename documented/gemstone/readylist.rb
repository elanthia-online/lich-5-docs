# Namespace for Lich 5, a Ruby scripting engine for GemStone IV and DragonRealms.
module Lich
  # Namespace for game mechanics and state management for GemStone IV.
  module Gemstone
    # Tracks equipped items and storage locations from the "ready list" command in GemStone IV.
    #
    # Maintains two parallel lists: a ready list of currently equipped items (shields, weapons, wands, etc.)
    # and a store list of items staged for retrieval from storage. Use {.check} to sync state from the
    # game server, then read individual entries via accessor methods like {.weapon} or {.store_weapon}.
    #
    # @note Entries are stored as GameObj instances; {.valid?} confirms all stored items remain in
    #       inventory, containers, or hands.
    class ReadyList
      @checked = false

      # Standard game-provided ready list entry types.
      #
      # Represents the default equipment slots GemStone IV tracks: shields, primary/secondary weapons,
      # ranged weapons, ammo bundles, sheaths, and wands.
      #
      # @see ORIGINAL_STORE_LIST
      ORIGINAL_READY_LIST = [:shield, :weapon, :secondary_weapon, :ranged_weapon, :ammo_bundle, :ammo2_bundle, :sheath, :secondary_sheath, :wand]
      # Standard game-provided store list entry types.
      #
      # Subset of ORIGINAL_READY_LIST used for tracking items awaiting retrieval from storage.
      # Excludes ammo2_bundle, sheath, and secondary_sheath.
      #
      # @see ORIGINAL_READY_LIST
      ORIGINAL_STORE_LIST = [:shield, :weapon, :secondary_weapon, :ranged_weapon, :ammo_bundle, :wand]

      @ready_list = {
        shield: nil,
        weapon: nil,
        secondary_weapon: nil,
        ranged_weapon: nil,
        ammo_bundle: nil,
        ammo2_bundle: nil,
        sheath: nil,
        secondary_sheath: nil,
        wand: nil,
      }
      @store_list = {
        shield: nil,
        weapon: nil,
        secondary_weapon: nil,
        ranged_weapon: nil,
        ammo_bundle: nil,
        wand: nil,
      }

      # Define class-level accessors for ready list entries
      @ready_list.each_key do |type|
        define_singleton_method("#{type}") { @ready_list[type] }
        define_singleton_method("#{type}=") { |value| @ready_list[type] = value }
      end

      # Define class-level accessors for store list entries
      @store_list.each_key do |type|
        define_singleton_method("store_#{type}") { @store_list[type] }
        define_singleton_method("store_#{type}=") { |value| @store_list[type] = value }
      end

      class << self
        # Returns the internal hash mapping equipment slot names to GameObj instances.
        #
        # @return [Hash{Symbol => GameObj, nil}] keys are :shield, :weapon, :secondary_weapon,
        #         :ranged_weapon, :ammo_bundle, :ammo2_bundle, :sheath, :secondary_sheath, :wand;
        #         values are GameObj or nil if unset
        # @example
        #   Lich::Gemstone::ReadyList.ready_list
        #   #=> {:shield=>nil, :weapon=>#<GameObj id=12345>, ...}
        def ready_list
          @ready_list
        end

        # Returns the internal hash mapping storage slot names to GameObj instances.
        #
        # @return [Hash{Symbol => GameObj, nil}] keys are :shield, :weapon, :secondary_weapon,
        #         :ranged_weapon, :ammo_bundle, :wand; values are GameObj or nil if unset
        # @example
        #   Lich::Gemstone::ReadyList.store_list
        #   #=> {:shield=>nil, :weapon=>#<GameObj id=67890>, ...}
        def store_list
          @store_list
        end

        # Returns true if {.check} has successfully synced state from the game server.
        #
        # @return [Boolean] true if the ready list has been checked; false initially or after {.reset}
        # @see .check
        def checked?
          @checked
        end

        # Sets the checked state flag.
        #
        # @param value [Boolean] whether the ready list is considered in sync with the server
        # @return [Boolean] the assigned value
        # @api private
        def checked=(value)
          @checked = value
        end

        # Verifies that all stored equipment items still exist in inventory, containers, or hands.
        #
        # Confirms {.checked?} is true, then iterates the ready list verifying each non-wand entry
        # either has a nil value or the GameObj (by id) still appears in GameObj.inv, GameObj.containers,
        # GameObj.right_hand, or GameObj.left_hand. Wand entries are excluded from validation.
        # Sets {.checked=} to false if any item is missing.
        #
        # @param all [Boolean] if true, validate all ready_list entries; if false (default), validate
        #            only entries in ORIGINAL_READY_LIST
        # @return [Boolean] true if checked and all relevant items are valid; false if not checked or
        #         an item is missing
        # @example
        #   Lich::Gemstone::ReadyList.check
        #   Lich::Gemstone::ReadyList.valid? #=> true
        # @see .checked?
        def valid?(all: false)
          # check if existing ready items are valid or not
          return false unless checked?
          @ready_list.each do |key, value|
            next unless all || ORIGINAL_READY_LIST.include?(key)
            unless key.eql?(:wand) || value.nil? || GameObj.inv.map(&:id).include?(value.id) || GameObj.containers.values.flatten.map(&:id).include?(value.id) || GameObj.right_hand.id.eql?(value.id) || GameObj.left_hand.id.eql?(value.id)
              @checked = false
              return false
            end
          end
          return true
        end

        # Clears all stored entries and sets checked state to false.
        #
        # Sets {.checked=} to false, then nilifies entries in ready_list and store_list.
        #
        # @param all [Boolean] if true, reset all entries; if false (default), reset only entries
        #            in ORIGINAL_READY_LIST and ORIGINAL_STORE_LIST
        # @return [void]
        # @example
        #   Lich::Gemstone::ReadyList.reset
        # @see .checked=
        def reset(all: false)
          @checked = false
          @ready_list.each do |key, _value|
            next unless all || ORIGINAL_READY_LIST.include?(key)
            @ready_list[key] = nil
          end
          @store_list.each do |key, _value|
            next unless all || ORIGINAL_STORE_LIST.include?(key)
            @store_list[key] = nil
          end
        end

        # Syncs ready list state from the game server by parsing "ready list" command output.
        #
        # Waits for roundtime, issues the "ready list" command, and reads equipment assignments from
        # the server response. Parses the response to extract item IDs and slot types, populating
        # {.ready_list} and {.store_list}. Sets {.checked?} to true only if the response contains
        # "Your current settings are:", indicating a valid ready list from the server.
        #
        # @param silent [Boolean] if true, suppress command echoing to the script window (default: false)
        # @param quiet [Boolean] if true, use compact XML output format instead of human-readable
        #              (default: false); affects the start_pattern used to parse server response
        # @return [void]
        # @example
        #   Lich::Gemstone::ReadyList.check
        # @see .checked? .ready_list
        def check(silent: false, quiet: false)
          if quiet
            start_pattern = /<output class="mono"\/>|^You are a ghost!/
          else
            start_pattern = /Your current settings are:|^You are a ghost!/
          end
          waitrt?
          results = Lich::Util.issue_command("ready list", start_pattern, silent: silent, quiet: quiet)
          @checked = results.any? { |line| line.match?(/Your current settings are:/) }
        end
      end
    end
  end
end
