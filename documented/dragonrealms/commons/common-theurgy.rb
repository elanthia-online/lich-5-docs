# frozen_string_literal: true

# Namespace for the Lich scripting engine and its supporting libraries.
module Lich
  # Namespace for DragonRealms-specific scripting utilities.
  module DragonRealms
    # Theurgy helper methods for clerics performing rituals and commune sense.
    #
    # Theurgy is the cleric holy magic system in DragonRealms. This module provides
    # inventory management for ritual supplies (holy water, oil, incense, etc.),
    # sprinkle/apply operations, and parsing of COMMUNE SENSE output to determine
    # active/recent communes and readiness for the next commune.
    module DRCTH
      module_function

      # Items used by clerics for theurgy rituals
      # Note: With frozen_string_literal: true, string literals are already frozen
      CLERIC_ITEMS = [
        'holy water', 'holy oil', 'wine', 'incense', 'flint', 'chamomile', 'sage', 'jalbreth balm'
      ].freeze unless defined?(CLERIC_ITEMS)

      # Error messages when attempting commune rituals
      COMMUNE_ERRORS = [
        'As you commune you sense that the ground is already consecrated.',
        'You stop as you realize that you have attempted a commune',
        'completed this commune too recently'
      ].freeze unless defined?(COMMUNE_ERRORS)

      # Devotion level messages from commune sense, ordered from lowest to highest
      DEVOTION_LEVELS = [
        'You sense nothing special from your communing',
        'You feel unclean and unworthy',
        'You close your eyes and start to concentrate',
        'You call out to your god, but there is no answer',
        'After a moment, you sense that your god is barely aware of you',
        'After a moment, you sense that your efforts have not gone unnoticed',
        'After a moment, you sense a distinct link between you and your god',
        'After a moment, you sense that your god is aware of your devotion',
        'After a moment, you sense that your god knows your name',
        'After a moment, you sense that your god is pleased with your devotion',
        'After a moment, you see a vision of your god, though the visage is cloudy',
        'After a moment, you sense a slight pressure on your shoulder',
        'After a moment, you see a silent vision of your god',
        'After a moment, you see a vision of your god who calls to you by name, "Come here, my child',
        'After a moment, you see a vision of your god who calls to you by name, "My child, though you may',
        'After a moment, you see a crystal-clear vision of your god who speaks slowly and deliberately',
        'After a moment, you feel a clear presence like a warm blanket covering you'
      ].freeze unless defined?(DEVOTION_LEVELS)

      # Start pattern for commune sense output. Matches the first line of output
      # which varies depending on active commune state.
      # Verified in-game 2026-02-07.
      COMMUNE_SENSE_START = /benevolent eyes|miracle of Tamsine|auspices of Kertigen|influence is woven|not a vessel|will not be able|eager to better/.freeze unless defined?(COMMUNE_SENSE_START)

      # Data class for commune_sense results. Replaces raw hash return.
      # Supports [] for backward compat with callers using result['key'].
      #
      # +captured+ is false when the COMMUNE SENSE reply was not captured in
      # full: no reply arrived (a timeout), or the reply was cut off before its
      # Roundtime line. commune_ready is then false so the result never reads as
      # ready; treat it as "unknown". After a timeout the lists are empty; after
      # a cut-off reply they hold what arrived, which may not be everything.
      # +captured+ true means a complete reply was read; it does not prove the
      # reply was sent in answer to this call (the tail of a reply that arrives
      # after an earlier call timed out can still be read by the next call,
      # since COMMUNE_SENSE_START also matches lines from the middle of a reply).
      class CommuneSenseResult
        attr_reader :active_communes, :recent_communes, :commune_ready, :captured

        # Initializes a CommuneSenseResult with commune status data.
        #
        # @param active_communes [Array<String>] god names from currently active communes (e.g., ["Tamsine", "Kertigen"])
        # @param recent_communes [Array<String>] god names from recently completed communes
        # @param commune_ready [Boolean] true if the character may open another divine conduit now
        # @param captured [Boolean] true if the full COMMUNE SENSE reply was captured; false if timeout or cut off
        def initialize(active_communes: [], recent_communes: [], commune_ready: true, captured: true)
          @active_communes = active_communes.freeze
          @recent_communes = recent_communes.freeze
          @commune_ready = commune_ready
          @captured = captured
        end

        # Returns true if the character is ready to open another divine conduit.
        #
        # @return [Boolean] false when COMMUNE SENSE output indicates a cooldown is active; true otherwise
        def commune_ready?
          @commune_ready
        end

        # @return [Boolean] true when the COMMUNE SENSE reply was captured
        def captured?
          @captured
        end

        # Hash-style accessor for backward compatibility with older calling code.
        #
        # Allows code that expects a Hash to call result["active_communes"] or result["commune_ready"].
        #
        # @param key [String, Symbol] the attribute name (e.g., "active_communes", :commune_ready)
        # @return [Array<String>, Boolean] the value of the requested attribute
        # @example
        #   result = commune_sense
        #   result["active_communes"] #=> ["Tamsine"]
        def [](key)
          send(key.to_sym)
        end
      end

      # Checks for holy water in a container without leaving the container open.
      #
      # Retrieves the water_holder (e.g., a waterskin) from theurgy_supply_container,
      # verifies it contains holy water, then puts it back. This is safer than a simple
      # inventory check.
      #
      # @param theurgy_supply_container [String] the container noun where supplies are stored
      # @param water_holder [String] the water_holder item noun (e.g., "waterskin", "vial")
      # @return [Boolean] true if holy water was found in the water_holder
      # @example
      #   DRCTH.has_holy_water?("portal", "waterskin") #=> true
      def has_holy_water?(theurgy_supply_container, water_holder)
        return false unless DRCI.get_item?(water_holder, theurgy_supply_container)

        has_water = DRCI.inside?('holy water', water_holder)
        DRCI.put_away_item?(water_holder, theurgy_supply_container)
        has_water
      end

      # Checks for flint in the supply container.
      #
      # @param theurgy_supply_container [String] the container noun where supplies are stored
      # @return [Boolean] true if flint is present in the container
      def has_flint?(theurgy_supply_container)
        DRCI.have_item_by_look?('flint', theurgy_supply_container)
      end

      # Checks for holy oil in the supply container.
      #
      # @param theurgy_supply_container [String] the container noun where supplies are stored
      # @return [Boolean] true if holy oil is present in the container
      def has_holy_oil?(theurgy_supply_container)
        DRCI.have_item_by_look?('holy oil', theurgy_supply_container)
      end

      # Checks for incense in the supply container.
      #
      # @param theurgy_supply_container [String] the container noun where supplies are stored
      # @return [Boolean] true if incense is present in the container
      def has_incense?(theurgy_supply_container)
        DRCI.have_item_by_look?('incense', theurgy_supply_container)
      end

      # Checks for jalbreth balm in the supply container.
      #
      # @param theurgy_supply_container [String] the container noun where supplies are stored
      # @return [Boolean] true if jalbreth balm is present in the container
      def has_jalbreth_balm?(theurgy_supply_container)
        DRCI.have_item_by_look?('jalbreth balm', theurgy_supply_container)
      end

      # Queries theurgy data to determine if an item must be blessed when purchased.
      #
      # Consults the game data (lich/theurgy.yaml) for the given town and item.
      # Returns nil if town data or item shop data does not exist.
      #
      # @param town [String] the town key used in theurgy.yaml (e.g., "River's Rest")
      # @param item_name [String] the item name (e.g., "holy water", "incense")
      # @return [Boolean, nil] true if the item requires blessing after purchase; false if not; nil if town or item not found
      # @example
      #   DRCTH.buying_cleric_item_requires_bless?("River's Rest", "holy water") #=> true
      def buying_cleric_item_requires_bless?(town, item_name)
        town_theurgy_data = get_data('theurgy')[town]
        return if town_theurgy_data.nil?

        item_shop_data = town_theurgy_data["#{item_name}_shop"]
        return if item_shop_data.nil?

        item_shop_data['needs_bless']
      end

      # Purchases cleric ritual supplies and returns them to storage.
      #
      # Walks to the shop location, buys the requested quantity of items, optionally
      # combines stackable items, and stores them in the supply container. Each item
      # is blessed after purchase if needed and the player knows the Bless spell.
      # Prints a bold message and returns false if town or item data is missing.
      #
      # @param town [String] the town key used in theurgy.yaml
      # @param item_name [String] the supply item name
      # @param stackable [Boolean] true to combine identical items after each purchase
      # @param num_to_buy [Integer] the number of items to purchase
      # @param theurgy_supply_container [String] the container noun for storage
      # @return [Boolean] true on successful purchase of all items; false if data lookup failed
      # @example
      #   DRCTH.buy_cleric_item?("River's Rest", "incense", false, 2, "portal") #=> true
      def buy_cleric_item?(town, item_name, stackable, num_to_buy, theurgy_supply_container)
        town_theurgy_data = get_data('theurgy')[town]
        if town_theurgy_data.nil?
          Lich::Messaging.msg("bold", "DRCTH: No theurgy data found for town '#{town}'.")
          return false
        end

        item_shop_data = town_theurgy_data["#{item_name}_shop"]
        if item_shop_data.nil?
          Lich::Messaging.msg("bold", "DRCTH: No shop data found for '#{item_name}' in '#{town}'.")
          return false
        end

        DRCT.walk_to(item_shop_data['id'])
        if stackable
          num_to_buy.times do
            buy_single_supply(item_name, item_shop_data)
            if DRCI.get_item?(item_name, theurgy_supply_container)
              DRC.bput("combine #{item_name} with #{item_name}", 'You combine', 'You can\'t combine', 'You must be holding')
            end
            # Put this back in the container each cycle so it doesn't interfere
            # with bless of next purchase.
            DRCI.put_away_item?(item_name, theurgy_supply_container)
          end
        else
          num_to_buy.times do
            buy_single_supply(item_name, item_shop_data)
            DRCI.put_away_item?(item_name, theurgy_supply_container)
          end
        end

        true
      end

      # Purchases a single cleric supply item and optionally blesses it.
      #
      # If shop_data contains a 'method' key, calls that method to perform purchase
      # (allowing custom handling). Otherwise uses the standard DRCT.buy_item call.
      # If the item requires blessing and the player knows Bless, casts it immediately.
      #
      # @param item_name [String] the supply item name
      # @param shop_data [Hash] shop configuration including 'id' (shop location), optional 'method' (custom purchase), and 'needs_bless' (Boolean)
      # @return [void]
      # @api private
      def buy_single_supply(item_name, shop_data)
        if shop_data['method']
          send(shop_data['method'])
        else
          DRCT.buy_item(shop_data['id'], item_name)
        end

        return unless shop_data['needs_bless'] && DRSpells.known_spells.include?('Bless')

        quick_bless_item(item_name)
      end

      # Casts Bless on a held item using minimal mana and prep time.
      #
      # Constructs a dummy settings object and invokes DRCA.cast_spell with fixed
      # parameters suitable for quick blessing during supply purchase.
      #
      # @param item_name [String] the item noun to bless
      # @return [void]
      # @api private
      def quick_bless_item(item_name)
        # use dummy settings object since this isn't complex enough for camb, etc.
        DRCA.cast_spell(
          { 'abbrev' => 'bless', 'mana' => 1, 'prep_time' => 2, 'cast' => "cast my #{item_name}" },
          {}
        )
      end

      # Puts away or drops all items held by the cleric.
      #
      # Calls empty_cleric_right_hand and empty_cleric_left_hand to handle both hands.
      # Issues an explicit glance command first to refresh hand state (because item
      # snuffing and other operations can leave hands in unexpected states).
      #
      # @param theurgy_supply_container [String] the container noun for ritual supplies
      # @return [void]
      # @see #empty_cleric_right_hand
      # @see #empty_cleric_left_hand
      def empty_cleric_hands(theurgy_supply_container)
        # Adding an explicit glance to ensure we know what's in hands, as
        # items can change
        # [combat-trainer]>snuff my incense
        # You snuff out the fragrant incense.
        # [combat-trainer]>put my fragrant incense in my portal
        # What were you referring to?
        # >glance
        # You glance down to see a steel light spear in your right hand and some burnt incense in your left hand.
        #
        # Which this explicit glance fixes.
        DRC.bput('glance', 'You glance')
        empty_cleric_right_hand(theurgy_supply_container)
        empty_cleric_left_hand(theurgy_supply_container)
      end

      # Puts away the right hand item if it is a cleric ritual supply.
      #
      # Checks the right hand against CLERIC_ITEMS patterns. If matched, stores in
      # theurgy_supply_container; otherwise drops it or uses default put-away. Does
      # nothing if the right hand is empty.
      #
      # @param theurgy_supply_container [String] the container noun for ritual supplies
      # @return [void]
      # @api private
      def empty_cleric_right_hand(theurgy_supply_container)
        return if DRC.right_hand.nil?

        container = CLERIC_ITEMS.any? { |item| DRC.right_hand =~ /#{item}/i } ? theurgy_supply_container : nil
        DRCI.put_away_item?(DRC.right_hand, container)
      end

      # Puts away the left hand item if it is a cleric ritual supply.
      #
      # Checks the left hand against CLERIC_ITEMS patterns. If matched, stores in
      # theurgy_supply_container; otherwise drops it or uses default put-away. Does
      # nothing if the left hand is empty.
      #
      # @param theurgy_supply_container [String] the container noun for ritual supplies
      # @return [void]
      # @api private
      def empty_cleric_left_hand(theurgy_supply_container)
        return if DRC.left_hand.nil?

        container = CLERIC_ITEMS.any? { |item| DRC.left_hand =~ /#{item}/i } ? theurgy_supply_container : nil
        DRCI.put_away_item?(DRC.left_hand, container)
      end

      # Sprinkles holy water on a target from a water container, with error handling.
      #
      # Retrieves the water_holder from storage, attempts the sprinkle action, and
      # returns it to storage. Prints a bold message and returns false if retrieval
      # fails or the sprinkle action does not succeed.
      #
      # @param theurgy_supply_container [String] the container noun for storage
      # @param water_holder [String] the water-holding item noun
      # @param target [String] the target name or pronoun (e.g., "knight", "corpse")
      # @return [Boolean] true if the sprinkle succeeded; false if retrieval or action failed
      # @example
      #   DRCTH.sprinkle_holy_water?("portal", "waterskin", "knight") #=> true
      def sprinkle_holy_water?(theurgy_supply_container, water_holder, target)
        unless DRCI.get_item?(water_holder, theurgy_supply_container)
          Lich::Messaging.msg("bold", "DRCTH: Can't get #{water_holder} to sprinkle.")
          return false
        end
        unless sprinkle?(water_holder, target)
          DRCI.put_away_item?(water_holder, theurgy_supply_container)
          Lich::Messaging.msg("bold", "DRCTH: Couldn't sprinkle holy water.")
          return false
        end
        DRCI.put_away_item?(water_holder, theurgy_supply_container)
        true
      end

      # Sprinkles holy oil on a target, with error handling.
      #
      # Retrieves holy oil from storage, attempts the sprinkle action, and empties
      # both cleric hands afterward. Prints a bold message and returns false if
      # retrieval or the sprinkle action fails.
      #
      # @param theurgy_supply_container [String] the container noun for storage
      # @param target [String] the target name or pronoun
      # @return [Boolean] true if the sprinkle succeeded; false if retrieval or action failed
      # @example
      #   DRCTH.sprinkle_holy_oil?("portal", "corpse") #=> true
      def sprinkle_holy_oil?(theurgy_supply_container, target)
        unless DRCI.get_item?("holy oil", theurgy_supply_container)
          Lich::Messaging.msg("bold", "DRCTH: Can't get holy oil to sprinkle.")
          return false
        end
        unless sprinkle?("oil", target)
          empty_cleric_hands(theurgy_supply_container)
          Lich::Messaging.msg("bold", "DRCTH: Couldn't sprinkle holy oil.")
          return false
        end
        empty_cleric_hands(theurgy_supply_container)
        true
      end

      # Sprinkles holy water on a target without explicit error handling.
      #
      # Retrieves the water_holder, executes the sprinkle, and returns it to storage.
      # No return value or error messages; suitable for scripted sequences where
      # preconditions are already verified.
      #
      # @param theurgy_supply_container [String] the container noun for storage
      # @param water_holder [String] the water-holding item noun
      # @param target [String] the target name or pronoun
      # @return [void]
      # @see #sprinkle_holy_water?
      # @api private
      def sprinkle_holy_water(theurgy_supply_container, water_holder, target)
        DRCI.get_item?(water_holder, theurgy_supply_container)
        sprinkle?(water_holder, target)
        DRCI.put_away_item?(water_holder, theurgy_supply_container)
      end

      # Sprinkles holy oil on a target without explicit error handling.
      #
      # Retrieves holy oil, executes the sprinkle, and returns it to storage only if
      # still held. No return value or error messages; suitable for scripted sequences
      # where preconditions are already verified.
      #
      # @param theurgy_supply_container [String] the container noun for storage
      # @param target [String] the target name or pronoun
      # @return [void]
      # @see #sprinkle_holy_oil?
      # @api private
      def sprinkle_holy_oil(theurgy_supply_container, target)
        DRCI.get_item?('holy oil', theurgy_supply_container)
        sprinkle?('oil', target)
        DRCI.put_away_item?('holy oil', theurgy_supply_container) if DRCI.in_hands?('oil')
      end

      # Attempts to sprinkle an item on a target and reports success.
      #
      # Issues the sprinkle command and returns true only if the output contains
      # "You sprinkle"; returns false for any other response (invalid target, etc.).
      #
      # @param item [String] the item noun to sprinkle (e.g., "holy water", "oil")
      # @param target [String] the target name or pronoun
      # @return [Boolean] true if the "You sprinkle" message was received; false otherwise
      # @api private
      def sprinkle?(item, target)
        result = DRC.bput("sprinkle #{item} on #{target}", 'You sprinkle', 'Sprinkle (what|that)', 'What were you referring to')
        result == 'You sprinkle'
      end

      # Applies jalbreth balm to a target and returns it to storage.
      #
      # Retrieves jalbreth balm from the supply container, applies it to the target,
      # and returns it to storage if still held. Accepts any server response (.*)
      # without checking success.
      #
      # @param theurgy_supply_container [String] the container noun for storage
      # @param target [String] the target name or pronoun
      # @return [void]
      # @api private
      def apply_jalbreth_balm(theurgy_supply_container, target)
        DRCI.get_item?('jalbreth balm', theurgy_supply_container)
        DRC.bput("apply balm to #{target}", '.*')
        DRCI.put_away_item?('jalbreth balm', theurgy_supply_container) if DRCI.in_hands?('balm')
      end

      # Lights incense with flint and waves it at a target, with full error handling.
      #
      # Clears both hands first, verifies presence of flint and incense in storage,
      # retrieves the flint lighter, gets incense, attempts to light (retrying up to 5
      # times on "nothing happens"), waves at target, snuffs if still held, and returns
      # both items to storage. Prints bold messages and returns false at each failure
      # point.
      #
      # @param theurgy_supply_container [String] the container noun for storage
      # @param flint_lighter [String] the lighter item noun (e.g., "flint", "steel")
      # @param target [String] the target name or pronoun
      # @return [Boolean] true if incense was lit and waved successfully; false if any step failed
      # @example
      #   DRCTH.wave_incense?("portal", "flint", "knight") #=> true
      def wave_incense?(theurgy_supply_container, flint_lighter, target)
        empty_cleric_hands(theurgy_supply_container)

        unless has_flint?(theurgy_supply_container)
          Lich::Messaging.msg("bold", "DRCTH: Can't find flint to light")
          return false
        end

        unless has_incense?(theurgy_supply_container)
          Lich::Messaging.msg("bold", "DRCTH: Can't find incense to light")
          return false
        end

        unless DRCI.get_item?(flint_lighter)
          Lich::Messaging.msg("bold", "DRCTH: Can't get #{flint_lighter} to light incense")
          return false
        end

        unless DRCI.get_item?('incense', theurgy_supply_container)
          Lich::Messaging.msg("bold", "DRCTH: Can't get incense to light")
          empty_cleric_hands(theurgy_supply_container)
          return false
        end

        lighting_attempts = 0
        while DRC.bput('light my incense with my flint', 'nothing happens', 'bursts into flames', 'much too dark in here to do that', 'What were you referring to?') == 'nothing happens'
          waitrt?

          lighting_attempts += 1
          if lighting_attempts >= 5
            Lich::Messaging.msg("bold", "DRCTH: Can't light your incense for some reason. Tried 5 times, giving up.")
            empty_cleric_hands(theurgy_supply_container)
            return false
          end
        end
        DRC.bput("wave my incense at #{target}", 'You wave')
        DRC.bput('snuff my incense', 'You snuff out') if DRCI.in_hands?('incense')

        DRCI.put_away_item?(flint_lighter)
        empty_cleric_hands(theurgy_supply_container)
        true
      end

      # Issues 'commune sense' and parses the output to determine active/recent communes
      # and whether the character is ready to commune again.
      # Returns a CommuneSenseResult (backward-compatible with hash access via []).
      #
      # A reply that is not captured in full never gives a "ready" reading:
      # - no reply in time: prints a bold message and returns a result with
      #   captured false, commune_ready false and empty lists.
      # - a reply cut off before its Roundtime line: prints a bold message and
      #   returns the communes that did arrive, with captured false and
      #   commune_ready false.
      def commune_sense
        lines, complete = DRC.capture_reply(
          'commune sense',
          COMMUNE_SENSE_START,
          /Roundtime/,
          usexml: false
        )
        if lines.empty?
          Lich::Messaging.msg("bold", "DRCTH: Failed to capture COMMUNE SENSE output (timeout).")
          return CommuneSenseResult.new(commune_ready: false, captured: false)
        end

        result = parse_commune_sense_lines(lines.map(&:strip).reject(&:empty?))
        return result if complete

        Lich::Messaging.msg("bold", "DRCTH: COMMUNE SENSE output was cut off (timeout); the result is incomplete.")
        CommuneSenseResult.new(
          active_communes: result.active_communes,
          recent_communes: result.recent_communes,
          commune_ready: false,
          captured: false
        )
      end

      # Pure parsing method for commune sense output lines.
      # Takes an array of plain text strings and returns a CommuneSenseResult.
      def parse_commune_sense_lines(lines)
        commune_ready = true
        active_communes = []
        recent_communes = []

        lines.each do |line|
          case line
          when /You will not be able to open another divine conduit yet/
            commune_ready = false
          when /Tamsine's benevolent eyes are upon you/, /The miracle of Tamsine has manifested about you/
            active_communes << 'Tamsine'
          when /You are under the auspices of Kertigen/
            active_communes << 'Kertigen'
          when /Meraud's influence is woven into the area/
            active_communes << 'Meraud'
          when /The waters of Eluned are still in your thoughts/
            recent_communes << 'Eluned'
          when /You have been recently enlightened by Tamsine/
            recent_communes << 'Tamsine'
          when /The sounds of Kertigen's forge still ring in your ears/
            recent_communes << 'Kertigen'
          when /You are still captivated by Truffenyi's favor/
            recent_communes << 'Truffenyi'
          end
        end

        CommuneSenseResult.new(
          active_communes: active_communes,
          recent_communes: recent_communes,
          commune_ready: commune_ready
        )
      end
    end
  end
end
