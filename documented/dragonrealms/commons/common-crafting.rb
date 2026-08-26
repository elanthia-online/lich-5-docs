# frozen_string_literal: true

# Namespace for the Lich scripting engine.
module Lich
  # Namespace for DragonRealms game-specific functionality.
  module DragonRealms
    # Common crafting utilities for blacksmithing, tailoring, artificing, remedies, and shaping in DragonRealms.
    # Provides pattern matching constants for bput responses and high-level crafting workflows.
    module DRCC
      module_function

      # Pattern constants for bput responses
      LOOK_CRUCIBLE_NOT_FOUND = '^I could not find'
      LOOK_CRUCIBLE_EMPTY = '^There is nothing in there'
      # Pattern matching crucible contents from a look command.
      # Captures the items list in the named group `:items`.
      #
      # @example
      #   "In the brass crucible you see some molten bronze." =~ LOOK_CRUCIBLE_SEE_PATTERN
      #   #=> 0; match[:items] => "some molten bronze"
      # @see LOOK_CRUCIBLE_NOT_FOUND, LOOK_CRUCIBLE_EMPTY
      LOOK_CRUCIBLE_SEE_PATTERN = /^In the .* crucible you see (?<items>.*)\./.freeze
      LOOK_CRUCIBLE_MOLTEN = 'crucible you see some molten'

      LOOK_ANVIL_NOT_FOUND = '^I could not find'
      LOOK_ANVIL_CLEAN = 'surface looks clean and ready'
      # Pattern matching anvil contents from a look command.
      # Captures the items list in the named group `:items`.
      #
      # @example
      #   "You look on the anvil you see an ingot." =~ LOOK_ANVIL_SEE_PATTERN
      #   #=> match[:items] => "an ingot"
      # @see LOOK_ANVIL_CLEAN, LOOK_ANVIL_NOT_FOUND
      LOOK_ANVIL_SEE_PATTERN = /anvil you see (?<items>.*)\./.freeze

      CLEAN_ANVIL_DRAG = 'You drag the'
      CLEAN_ANVIL_REMOVE = 'remove them yourself'
      GET_ANVIL_SUCCESS = 'You get'
      GET_ANVIL_NOT_YOURS = 'is not yours'
      PUT_BUCKET_SUCCESS = 'You drop'

      BOOK_CHAPTER_TURN_SUCCESS = 'You turn'
      # Pattern matched when the player cannot turn a book due to being engaged in combat.
      #
      # @example
      #   "You are too distracted to be doing that right now" =~ BOOK_CHAPTER_DISTRACTED
      #   #=> 0
      # @see BOOK_CHAPTER_TURN_SUCCESS, BOOK_CHAPTER_ALREADY
      BOOK_CHAPTER_DISTRACTED = 'You are too distracted to be doing that right now'
      BOOK_CHAPTER_ALREADY = 'The .* is already turned'
      # Pattern matched when a book chapter turn succeeds, with capture of the book name.
      #
      # @example
      #   "You turn your crafting book to chapter 5." =~ BOOK_CHAPTER2_SUCCESS
      #   #=> 0
      # @see BOOK_CHAPTER2_ALREADY
      BOOK_CHAPTER2_SUCCESS = /^You turn your .* to chapter/
      # Pattern matched when the book is already at the requested chapter.
      #
      # @example
      #   "The crafting book is already turned to chapter 5." =~ BOOK_CHAPTER2_ALREADY
      #   #=> 0
      # @see BOOK_CHAPTER2_SUCCESS
      BOOK_CHAPTER2_ALREADY = /^The .* is already turned to chapter/
      # Pattern matched when a book page turn succeeds.
      #
      # @example
      #   "You turn your crafting book to page 10." =~ BOOK_PAGE_SUCCESS
      #   #=> 0
      # @see BOOK_PAGE_ALREADY
      BOOK_PAGE_SUCCESS = /^You turn your .* to page/
      # Pattern matched when the book is already at the requested page.
      #
      # @example
      #   "You are already on page 10." =~ BOOK_PAGE_ALREADY
      #   #=> 0
      # @see BOOK_PAGE_SUCCESS
      BOOK_PAGE_ALREADY = /^You are already on page/
      # Pattern matched when turning a book to a discipline section succeeds.
      #
      # @example
      #   "You turn the crafting book to the section on engineering." =~ BOOK_DISCIPLINE_SUCCESS
      #   #=> 0
      # @see BOOK_CHAPTER2_SUCCESS
      BOOK_DISCIPLINE_SUCCESS = /^You turn the .* to the section on/
      # Pattern matched when studying a book completes and the roundtime message appears.
      #
      # @example
      #   "Roundtime: 5 seconds" =~ BOOK_STUDY_SUCCESS
      #   #=> 0
      BOOK_STUDY_SUCCESS = /^Roundtime/

      # Pattern matched when successfully untying or removing an item from a belt.
      #
      # @example
      #   "You untie a pliers from your crafting belt." =~ BELT_UNTIE_SUCCESS
      #   #=> 0
      # @see BELT_UNTIE_ALREADY, BELT_UNTIE_NOT_FOUND, BELT_UNTIE_WOUNDED
      BELT_UNTIE_SUCCESS = /^You (remove|untie)/
      # Pattern matched when the item is already removed from the belt.
      #
      # @example
      #   "You are already holding a pliers." =~ BELT_UNTIE_ALREADY
      #   #=> 0
      # @see BELT_UNTIE_SUCCESS
      BELT_UNTIE_ALREADY = /^You are already/
      # Pattern matched when the item to untie cannot be found on the belt.
      #
      # @example
      #   "Untie what?" =~ BELT_UNTIE_NOT_FOUND
      #   #=> 0
      # @see BELT_UNTIE_SUCCESS
      BELT_UNTIE_NOT_FOUND = /^Untie what/
      # Pattern matched when wounds prevent untying from the belt.
      #
      # @example
      #   "Your wounds hinder your ability to do that." =~ BELT_UNTIE_WOUNDED
      #   #=> 0
      # @see BELT_UNTIE_SUCCESS
      BELT_UNTIE_WOUNDED = /^Your wounds hinder your ability to do that/

      # Pattern matched when successfully picking up a crafting item.
      #
      # @example
      #   "You get a pliers from your backpack." =~ GET_CRAFTING_SUCCESS
      #   #=> 0
      # @see GET_CRAFTING_ALREADY, GET_CRAFTING_PICKUP, GET_CRAFTING_HEAVY, GET_CRAFTING_TIED
      GET_CRAFTING_SUCCESS = /^You get/
      # Pattern matched when the crafting item is already in hand.
      #
      # @example
      #   "You are already holding a pliers." =~ GET_CRAFTING_ALREADY
      #   #=> 0
      # @see GET_CRAFTING_SUCCESS
      GET_CRAFTING_ALREADY = /^You are already/
      # Pattern matched when the item is not found in the specified location.
      #
      # @example
      #   "What do you want to get?" =~ GET_CRAFTING_NOT_FOUND_WHAT
      #   #=> 0
      # @see GET_CRAFTING_NOT_FOUND_WERE
      GET_CRAFTING_NOT_FOUND_WHAT = /^What do you/
      # Pattern matched when the item cannot be found (alternate form).
      #
      # @example
      #   "What were you referring to?" =~ GET_CRAFTING_NOT_FOUND_WERE
      #   #=> 0
      # @see GET_CRAFTING_NOT_FOUND_WHAT
      GET_CRAFTING_NOT_FOUND_WERE = /^What were you/
      # Pattern matched when picking up a crafting item from the ground.
      #
      # @example
      #   "You pick up a pliers." =~ GET_CRAFTING_PICKUP
      #   #=> 0
      # @see GET_CRAFTING_SUCCESS
      GET_CRAFTING_PICKUP = /^You pick up/
      # Pattern matched when an item is too heavy to lift.
      #
      # @example
      #   "You can't quite lift it." =~ GET_CRAFTING_HEAVY
      #   #=> 0
      # @see GET_CRAFTING_SUCCESS
      GET_CRAFTING_HEAVY = /can't quite lift it/
      # Pattern matched when an item must be untied before being retrieved.
      #
      # @example
      #   "You should untie this from your belt first." =~ GET_CRAFTING_TIED
      #   #=> 0
      # @see UNTIE_SUCCESS
      GET_CRAFTING_TIED = /^You should untie/

      # Pattern matched when successfully untying an item.
      #
      # @example
      #   "You untie a pliers." =~ UNTIE_SUCCESS
      #   #=> 0
      # @see UNTIE_NOT_FOUND, UNTIE_WOUNDED
      UNTIE_SUCCESS = /^You (remove|untie)/
      # Pattern matched when the item to untie cannot be found.
      #
      # @example
      #   "Untie what?" =~ UNTIE_NOT_FOUND
      #   #=> 0
      # @see UNTIE_SUCCESS
      UNTIE_NOT_FOUND = /^Untie what/
      # Pattern matched when wounds prevent untying an item.
      #
      # @example
      #   "Your wounds hinder your ability to do that." =~ UNTIE_WOUNDED
      #   #=> 0
      # @see UNTIE_SUCCESS
      UNTIE_WOUNDED = /^Your wounds hinder your ability to do that/

      TIE_BELT_SUCCESS = 'you attach'
      TIE_BELT_WOUNDED = 'Your wounds hinder'

      PUT_BAG_TUCK = 'You tuck'
      PUT_BAG_PUT = 'You put your'
      PUT_BAG_NOT_FOUND = 'What were you referring to'
      # Pattern matched when an item is too large to fit in a container.
      #
      # @example
      #   "The pliers is too large to fit in your backpack." =~ PUT_BAG_TOO_BIG
      #   #=> match at "too large to fit"
      # @see PUT_BAG_WEIRD, PUT_BAG_NO_ROOM
      PUT_BAG_TOO_BIG = /is too \w+ to fit/
      PUT_BAG_WEIRD = "Weirdly, you can't manage"
      PUT_BAG_NO_ROOM = "There's no room"
      PUT_BAG_CANT_THERE = "You can't put that there"
      PUT_BAG_COMBINE = 'You combine'

      # Parts that cannot be purchased from crafting shops
      PARTS_CANNOT_PURCHASE = %w[
        sufil blue\ flower muljin belradi dioica hulnik aloe eghmok
        lujeakave yelith cebi blocil hulij nuloe hisan gem pebble
        ring gwethdesuan brazier burin any ingot mechanism
      ].freeze

      REPAIR_SUCCESS = 'Roundtime'
      REPAIR_NOT_NEEDED = 'not damaged enough'
      REPAIR_ENGAGED = 'You cannot do that while engaged!'
      REPAIR_CONFUSED = 'cannot figure out how'
      REPAIR_POUR_WHAT = 'Pour what'

      CONSUMABLE_GET_SUCCESS = 'You get'
      CONSUMABLE_GET_NOT_FOUND = 'What were'
      # Pattern that extracts a numeric count (uses, yards, etc.) from a message.
      # Captures the number in group 1.
      #
      # @example
      #   "The oil has 25 uses remaining".match(COUNT_USES_PATTERN)[1] #=> "25"
      # @see COUNT_USES_MESSAGES, #check_consumables
      COUNT_USES_PATTERN = /(\d+)/.freeze
      # Array of regex patterns used to extract the remaining uses from consumable items.
      # Each pattern should contain a capture group for the numeric count.
      #
      # @example
      #   COUNT_USES_MESSAGES.any? { |msg| "The oil has 5 uses remaining" =~ msg }
      #   #=> true
      # @see COUNT_USES_PATTERN, #check_consumables
      COUNT_USES_MESSAGES = [
        'The .* has (\d+) uses remaining',
        'You count out (\d+) yards of material there'
      ].freeze

      ADJUST_TONGS_SHOVEL = 'You lock the tongs'
      ADJUST_TONGS_TONGS = 'With a yank you fold the shovel'
      ADJUST_TONGS_CANNOT = 'You cannot adjust'
      ADJUST_TONGS_UNKNOWN = 'You have no idea how'

      BUNDLE_SUCCESS = 'You notate the'
      BUNDLE_EXPIRED = 'This work order has expired'
      # Pattern matched when bundling fails because the item quality is too low for the work order.
      #
      # @example
      #   "The work order requires items of a higher quality" =~ BUNDLE_QUALITY
      #   #=> 0
      # @see BUNDLE_WRONG_TYPE, BUNDLE_EXPIRED
      BUNDLE_QUALITY = 'The work order requires items of a higher quality'
      # Pattern matched when bundling fails because the item type does not match the work order.
      #
      # @example
      #   "That isn't the correct type of item for this work order." =~ BUNDLE_WRONG_TYPE
      #   #=> 0
      # @see BUNDLE_QUALITY, BUNDLE_EXPIRED
      BUNDLE_WRONG_TYPE = "That isn't the correct type of item for this work order."
      BUNDLE_NOT_HOLDING = 'You need to be holding'

      # Pattern matched when tapping a fount that is located inside a bag.
      #
      # @example
      #   "You tap the fount inside your backpack." =~ FOUNT_TAP_IN_BAG
      #   #=> 0
      # @see FOUNT_TAP_ON_BAG, FOUNT_TAP_NOT_FOUND
      FOUNT_TAP_IN_BAG = /You tap .* inside your .*/
      # Pattern matched when tapping a fount that is on the player's person (but not in a bag).
      #
      # @example
      #   "You tap the fount on your belt." =~ FOUNT_TAP_ON_BAG
      #   #=> 0
      # @see FOUNT_TAP_IN_BAG, FOUNT_TAP_NOT_FOUND
      FOUNT_TAP_ON_BAG = /You tap .*your .*/
      FOUNT_TAP_NOT_FOUND = /I could not find what you were referring to./
      FOUNT_TAP_ON_BRAZIER = /You tap .* atop a .*brazier./
      # Pattern that extracts remaining uses from analyzing a fount or other crafting tool.
      # Captures the numeric uses in the named group `:uses`.
      #
      # @example
      #   "This appears to be a crafting tool and it has approximately 42 uses remaining".match(FOUNT_ANALYZE_PATTERN)[:uses]
      #   #=> "42"
      # @see #fount, #order_enchant
      FOUNT_ANALYZE_PATTERN = /This appears to be a crafting tool and it has approximately (?<uses>\d+) uses remaining/.freeze

      BRAZIER_NOTHING = 'There is nothing on there'
      # Pattern matching brazier contents from a look command.
      # Captures the items list in the named group `:items`.
      #
      # @example
      #   "On the brass brazier you see some molten silver and a quill.".match(BRAZIER_SEE_PATTERN)[:items]
      #   #=> "some molten silver and a quill"
      # @see BRAZIER_NOTHING, #clean_brazier?
      BRAZIER_SEE_PATTERN = /On the (?:.*)brazier you see (?<items>.*)\./.freeze
      BRAZIER_CLEAN_PREPARE = 'You prepare to clean off the brazier'
      BRAZIER_CLEAN_NOTHING = 'There is nothing'
      BRAZIER_CLEAN_NOT_LIT = 'The brazier is not currently lit'
      # Pattern matched when cleaning a lit brazier causes a flame hazard.
      #
      # @example
      #   "a massive ball of flame jets forward and singes everything nearby" =~ BRAZIER_CLEAN_FLAME
      #   #=> 0
      # @see BRAZIER_CLEAN_PREPARE, BRAZIER_CLEAN_NOT_LIT
      BRAZIER_CLEAN_FLAME = 'a massive ball of flame jets forward and singes everything nearby'
      BRAZIER_GET_SUCCESS = 'You get'

      # Pattern matched when rummaging for materials yields no results.
      #
      # @example
      #   "Looking for crafting materials but there is nothing in there like that." =~ RUMMAGE_NOTHING
      #   #=> 0
      # @see RUMMAGE_SUCCESS_PATTERN, #count_raw_metal
      RUMMAGE_NOTHING = /crafting materials but there is nothing in there like that\.$/
      # Pattern matched when attempting to rummage in a closed container.
      #
      # @example
      #   "While it's closed you can't rummage through that." =~ RUMMAGE_CLOSED
      #   #=> 0
      # @see RUMMAGE_SUCCESS_PATTERN, #count_raw_metal
      RUMMAGE_CLOSED = /While it\'s closed/
      # Pattern matched when the container cannot be found.
      #
      # @example
      #   "I don't know what you are referring to." =~ RUMMAGE_NOT_FOUND
      #   #=> 0
      # @see RUMMAGE_SUCCESS_PATTERN, #count_raw_metal
      RUMMAGE_NOT_FOUND = /I don\'t know what you are referring to/
      # Pattern matched when attempting to rummage while invisible.
      #
      # @example
      #   "You feel about blindly, unable to see what you're looking for." =~ RUMMAGE_INVISIBLE
      #   #=> 0
      # @see RUMMAGE_SUCCESS_PATTERN, #count_raw_metal
      RUMMAGE_INVISIBLE = /You feel about/
      # Pattern matched when rummaging would have no effect (e.g., container is empty or already sorted).
      #
      # @example
      #   "That would accomplish nothing." =~ RUMMAGE_NOTHING_ACCOMPLISH
      #   #=> 0
      # @see RUMMAGE_SUCCESS_PATTERN
      RUMMAGE_NOTHING_ACCOMPLISH = /That would accomplish nothing/
      # Pattern that extracts the materials list from a successful rummage.
      # Captures the materials in the named group `:materials`.
      #
      # @example
      #   "You are looking for crafting materials and see 3 pieces of bronze ingot, 2 pieces of iron ingot.".match(RUMMAGE_SUCCESS_PATTERN)[:materials]
      #   #=> "3 pieces of bronze ingot, 2 pieces of iron ingot"
      # @see #count_raw_metal
      RUMMAGE_SUCCESS_PATTERN = /looking for crafting materials and see (?<materials>.*)\.$/

      TAP_CRUCIBLE_NOT_FOUND = 'I could not'
      # Pattern matched when successfully tapping a crucible.
      #
      # @example
      #   "You tap the brass crucible." =~ TAP_CRUCIBLE_SUCCESS
      #   #=> 0
      # @see TAP_CRUCIBLE_NOT_FOUND, #find_empty_crucible
      TAP_CRUCIBLE_SUCCESS = /You tap.*crucible/
      TAP_ANVIL_NOT_FOUND = 'I could not'
      # Pattern matched when successfully tapping an anvil.
      #
      # @example
      #   "You tap the sturdy anvil." =~ TAP_ANVIL_SUCCESS
      #   #=> 0
      # @see TAP_ANVIL_NOT_FOUND, #find_anvil
      TAP_ANVIL_SUCCESS = /You tap.*anvil/
      TAP_GRINDSTONE_NOT_FOUND = 'I could not'
      TAP_GRINDSTONE_SUCCESS = 'You tap.*grindstone'
      TAP_GRINDER_NOT_FOUND = 'I could not'
      TAP_GRINDER_SUCCESS = 'You tap.*grinder'

      SIGIL_COUNT_NOTHING = 'but there is nothing in there like that'

      # Determines if the current crucible is empty, and clears any remaining contents if needed.
      # If the crucible contains molten materials, tilts it; if it contains items, retrieves and discards them.
      # Returns true only if the crucible ends in an empty state.
      #
      # @return [Boolean] true if the crucible is empty or has been emptied, false if the crucible cannot be found
      # @example
      #   DRCC.empty_crucible? #=> true
      # @see #find_empty_crucible
      def empty_crucible?
        case result = DRC.bput('look in cruc',
                               LOOK_CRUCIBLE_NOT_FOUND,
                               LOOK_CRUCIBLE_EMPTY,
                               LOOK_CRUCIBLE_SEE_PATTERN)
        when /There is nothing in there/i
          true
        when /I could not find/
          false
        when LOOK_CRUCIBLE_MOLTEN
          fput('tilt crucible')
          fput('tilt crucible')
          return DRCC.empty_crucible?
        when /crucible you see/
          match = result.match(LOOK_CRUCIBLE_SEE_PATTERN)
          return false unless match

          clutter = match[:items]
                    .split(/(?:,|and) (?:some|an|a)/)
                    .map(&:strip)
          clutter.each do |junk|
            junk = DRC.get_noun(junk)
            DRCI.get_item_unsafe(junk, 'crucible')
            DRCI.dispose_trash(junk)
          end
          return DRCC.empty_crucible?
        else
          false
        end
      end

      # Locates an empty crucible in the blacksmithing area for the given hometown.
      # First checks if the current crucible is empty and free of other players.
      # If not, searches through available crucibles and cleans the anvil when found.
      #
      # @param hometown [String] the town name, e.g. "Crossing"
      # @return [void]
      # @example
      #   DRCC.find_empty_crucible("Crossing")
      # @see #empty_crucible?, #clean_anvil?
      def find_empty_crucible(hometown)
        return if DRC.bput('tap crucible', TAP_CRUCIBLE_NOT_FOUND, TAP_CRUCIBLE_SUCCESS) =~ TAP_CRUCIBLE_SUCCESS && (DRRoom.pcs - DRRoom.group_members).empty? && empty_crucible?

        crucibles = get_data('crafting')['blacksmithing'][hometown]['crucibles']
        idle_room = get_data('crafting')['blacksmithing'][hometown]['idle-room']
        DRCT.find_sorted_empty_room(crucibles, idle_room, proc { (DRRoom.pcs - DRRoom.group_members).empty? && empty_crucible? })
        DRCC.clean_anvil?
      end

      # Determines if the current anvil is clean, and removes any clutter if needed.
      # If the anvil is uncluttered and ready, returns true.
      # If items are present, attempts to clean them via drag or individual retrieval.
      #
      # @return [Boolean] true if the anvil is clean or has been cleaned, false if the anvil cannot be found or cleaning fails
      # @example
      #   DRCC.clean_anvil? #=> true
      # @see #find_anvil, LOOK_ANVIL_CLEAN
      def clean_anvil?
        case result = DRC.bput('look on anvil', LOOK_ANVIL_NOT_FOUND, LOOK_ANVIL_CLEAN, LOOK_ANVIL_SEE_PATTERN)
        when /surface looks clean and ready/i
          true
        when /I could not find/
          false
        when /anvil you see/
          match = result.match(LOOK_ANVIL_SEE_PATTERN)
          return false unless match

          clutter = match[:items].split.last
          case DRC.bput('clean anvil', CLEAN_ANVIL_DRAG, CLEAN_ANVIL_REMOVE)
          when /drag/
            fput('clean anvil')
            pause
            waitrt?
          else
            case DRC.bput("get #{clutter} from anvil", GET_ANVIL_SUCCESS, GET_ANVIL_NOT_YOURS)
            when GET_ANVIL_NOT_YOURS
              fput('clean anvil')
              fput('clean anvil')
            when GET_ANVIL_SUCCESS
              DRC.bput("put #{clutter} in bucket", PUT_BUCKET_SUCCESS)
            else
              return false
            end
          end
          true
        else
          false
        end
      end

      # Locates an available spinning wheel for tailoring in the given hometown.
      #
      # @param hometown [String] the town name, e.g. "Crossing"
      # @return [void]
      # @example
      #   DRCC.find_wheel("Crossing")
      # @api private
      def find_wheel(hometown)
        wheels = get_data('crafting')['tailoring'][hometown]['spinning-rooms']
        idle_room = get_data('crafting')['tailoring'][hometown]['idle-room']
        DRCT.find_sorted_empty_room(wheels, idle_room)
      end

      # Locates a clean anvil in the blacksmithing area for the given hometown.
      # First checks if the current anvil is clean and free of other players.
      # If not, searches through available anvils and checks the crucible when found.
      #
      # @param hometown [String] the town name, e.g. "Crossing"
      # @return [void]
      # @example
      #   DRCC.find_anvil("Crossing")
      # @see #clean_anvil?, #find_empty_crucible
      def find_anvil(hometown)
        return if DRC.bput('tap anvil', TAP_ANVIL_NOT_FOUND, TAP_ANVIL_SUCCESS) =~ TAP_ANVIL_SUCCESS && (DRRoom.pcs - DRRoom.group_members).empty? && clean_anvil?

        anvils = get_data('crafting')['blacksmithing'][hometown]['anvils']
        idle_room = get_data('crafting')['blacksmithing'][hometown]['idle-room']
        DRCT.find_sorted_empty_room(anvils, idle_room, proc { (DRRoom.pcs - DRRoom.group_members).empty? && clean_anvil? })
        DRCC.empty_crucible?
      end

      # Locates an available grindstone in the blacksmithing area for the given hometown.
      # Returns unless a grindstone is not found in the current location.
      #
      # @param hometown [String] the town name, e.g. "Crossing"
      # @return [void]
      # @example
      #   DRCC.find_grindstone("Crossing")
      # @api private
      def find_grindstone(hometown)
        return unless DRC.bput('tap grindstone', TAP_GRINDSTONE_NOT_FOUND, TAP_GRINDSTONE_SUCCESS) == TAP_GRINDSTONE_NOT_FOUND

        grindstones = get_data('crafting')['blacksmithing'][hometown]['grindstones']
        idle_room = get_data('crafting')['blacksmithing'][hometown]['idle-room']
        DRCT.find_sorted_empty_room(grindstones, idle_room)
      end

      # Locates a sewing room for tailoring in the given hometown, or walks to an override location if provided.
      #
      # @param hometown [String] the town name, e.g. "Crossing"
      # @param override [String, nil] an optional room ID to walk to directly, bypassing the search
      # @return [void]
      # @example
      #   DRCC.find_sewing_room("Crossing")
      #   DRCC.find_sewing_room("Crossing", "12345")
      # @api private
      def find_sewing_room(hometown, override = nil)
        if override
          DRCT.walk_to(override)
        else
          sewingrooms = get_data('crafting')['tailoring'][hometown]['sewing-rooms']
          idle_room = get_data('crafting')['tailoring'][hometown]['idle-room']
          DRCT.find_sorted_empty_room(sewingrooms, idle_room)
        end
      end

      # Locates a loom room for tailoring in the given hometown, or walks to an override location if provided.
      #
      # @param hometown [String] the town name, e.g. "Crossing"
      # @param override [String, nil] an optional room ID to walk to directly, bypassing the search
      # @return [void]
      # @example
      #   DRCC.find_loom_room("Crossing")
      #   DRCC.find_loom_room("Crossing", "12345")
      # @api private
      def find_loom_room(hometown, override = nil)
        if override
          DRCT.walk_to(override)
        else
          loom_rooms = get_data('crafting')['tailoring'][hometown]['loom-rooms']
          idle_room = get_data('crafting')['tailoring'][hometown]['idle-room']
          DRCT.find_sorted_empty_room(loom_rooms, idle_room)
        end
      end

      # Locates a shaping room for shaping in the given hometown, or walks to an override location if provided.
      #
      # @param hometown [String] the town name, e.g. "Crossing"
      # @param override [String, nil] an optional room ID to walk to directly, bypassing the search
      # @return [void]
      # @example
      #   DRCC.find_shaping_room("Crossing")
      #   DRCC.find_shaping_room("Crossing", "12345")
      # @api private
      def find_shaping_room(hometown, override = nil)
        if override
          DRCT.walk_to(override)
        else
          shapingrooms = get_data('crafting')['shaping'][hometown]['shaping-rooms']
          idle_room = get_data('crafting')['shaping'][hometown]['idle-room']
          DRCT.find_sorted_empty_room(shapingrooms, idle_room)
        end
      end

      # Locates a press/grinder room for remedies in the given hometown.
      # Returns unless a grinder is not found in the current location.
      #
      # @param hometown [String] the town name, e.g. "Crossing"
      # @return [void]
      # @example
      #   DRCC.find_press_grinder_room("Crossing")
      # @api private
      def find_press_grinder_room(hometown)
        return unless DRC.bput('tap grinder', TAP_GRINDER_NOT_FOUND, TAP_GRINDER_SUCCESS) == TAP_GRINDER_NOT_FOUND

        pressgrinderrooms = get_data('crafting')['remedies'][hometown]['press-grinder-rooms']
        DRCT.walk_to(pressgrinderrooms[0])
      end

      # Locates a brazier room for artificing in the given hometown, or walks to an override location if provided.
      # Searches for a clean brazier and an empty crafting area.
      #
      # @param hometown [String] the town name, e.g. "Crossing"
      # @param override [String, nil] an optional room ID to walk to directly, bypassing the search
      # @return [void]
      # @example
      #   DRCC.find_enchanting_room("Crossing")
      #   DRCC.find_enchanting_room("Crossing", "12345")
      # @see #clean_brazier?
      def find_enchanting_room(hometown, override = nil)
        if override
          DRCT.walk_to(override)
        else
          enchanting_rooms = get_data('crafting')['artificing'][hometown]['brazier-rooms']
          idle_room = get_data('crafting')['artificing'][hometown]['idle-room']
          DRCT.find_sorted_empty_room(enchanting_rooms, idle_room, proc { (DRRoom.pcs - DRRoom.group_members).empty? && clean_brazier? })
        end
      end

      # Looks up a recipe by partial or exact name from a list of recipes.
      # If multiple matches are found, prompts the user to select the desired recipe.
      # Exact matches take precedence over partial matches.
      #
      # @param recipes [Array<Hash>] array of recipe hashes, each with a 'name' key
      # @param item_name [String] the partial or full name of the recipe to find
      # @return [Hash, nil] the matching recipe hash, or nil if no recipes match
      # @example
      #   recipes = [{"name" => "a metal ring cap", "noun" => "cap"}]
      #   DRCC.recipe_lookup(recipes, "metal ring") #=> {"name" => "a metal ring cap", "noun" => "cap"}
      # @api private
      def recipe_lookup(recipes, item_name)
        match_names = recipes.map { |x| x['name'] }.select { |x| x =~ /#{item_name}/i }
        case match_names.length
        when 0
          Lich::Messaging.msg('bold', "DRCC: No recipe in base-recipes.yaml matches #{item_name}")
          nil
        when 1
          recipes.find { |x| x['name'] =~ /#{item_name}/i }
        else
          exact_matches = recipes.map { |x| x['name'] }.select { |x| x == item_name }

          if exact_matches.length == 1
            return recipes.find { |x| x['name'] == item_name }
          end

          Lich::Messaging.msg('bold', "DRCC: Using the full name of the item you wish to craft will avoid this in the future (e.g. 'a metal pike' vs 'metal pike')")
          Lich::Messaging.msg('plain', "DRCC: Please select desired recipe #{$clean_lich_char}send #")
          match_names.each_with_index { |x, i| respond "    #{i + 1}: #{x}" }
          line = get until line.strip =~ /^(\d+)$/
          match = line.strip.match(/^(?<num>\d+)$/)
          item_name = match_names[match[:num].to_i - 1]
          recipes.find { |x| x['name'] =~ /#{item_name}/i }
        end
      end

      # Finds the page number of a recipe in a crafting book by chapter and item name.
      # Turns the book to the specified chapter and searches the page content.
      # Returns the first matching page number, or nil if not found.
      #
      # @param chapter [Integer, String] the chapter number to turn to
      # @param match_string [String] the recipe name or keyword to search for
      # @param book [String] the book name, defaults to 'book'
      # @return [String, nil] the page number of the matching recipe, or nil if not found
      # @example
      #   DRCC.find_recipe(5, "metal pike") #=> "23"
      # @api private
      def find_recipe(chapter, match_string, book = 'book')
        case DRC.bput("turn my #{book} to chapter #{chapter}", BOOK_CHAPTER_TURN_SUCCESS, BOOK_CHAPTER_DISTRACTED, BOOK_CHAPTER_ALREADY)
        when BOOK_CHAPTER_DISTRACTED
          Lich::Messaging.msg('bold', 'DRCC: Cannot turn book, assuming engaged in combat.')
          fput('look')
          fput('exit')
        end

        recipe = DRC.bput("read my #{book}", "Page \\d+:\\s(?:some|a|an)?\\s*#{match_string}").split('Page').find { |x| x =~ /#{match_string}/i }
        match = recipe&.match(/(?<page>\d+):/)
        match&.[](:page)
      end

      # Finds and studies a recipe in a crafting book by chapter and item name, with optional discipline.
      # Turns the book to the specified chapter (and discipline if provided), searches the page content,
      # and studies the recipe. Does not return a page number.
      #
      # @param chapter [Integer, String] the chapter number to turn to
      # @param match_string [String] the recipe name or keyword to search for
      # @param book [String] the book name, defaults to 'book'
      # @param discipline [String, nil] an optional discipline section to turn to first
      # @return [void]
      # @example
      #   DRCC.find_recipe2(3, "metal pike", "book", "armorsmithing")
      # @api private
      def find_recipe2(chapter, match_string, book = 'book', discipline = nil)
        DRC.bput("turn my #{book} to discipline #{discipline}", BOOK_DISCIPLINE_SUCCESS) unless discipline.nil?
        case DRC.bput("turn my #{book} to chapter #{chapter}", BOOK_CHAPTER2_SUCCESS, BOOK_CHAPTER2_ALREADY, BOOK_CHAPTER_DISTRACTED)
        when BOOK_CHAPTER_DISTRACTED
          Lich::Messaging.msg('bold', 'DRCC: Cannot turn book, assuming engaged in combat.')
          fput('look')
          fput('exit')
        end

        recipe = DRC.bput("read my #{book}", "Page \\d+:\\s(?:some|a|an)?\\s*#{match_string}").split('Page').find { |x| x =~ /#{match_string}/i }
        match = recipe&.match(/(?<page>\d+):/)
        page = match&.[](:page)
        DRC.bput("turn my #{book} to page #{page}", BOOK_PAGE_SUCCESS, BOOK_PAGE_ALREADY)
        DRC.bput("study my #{book}", BOOK_STUDY_SUCCESS)
      end

      # Retrieves a crafting item from a belt, bag, or ground.
      # First checks if the item is on a belt and unties it if present.
      # Then attempts to retrieve the item from the bag or from your hands.
      # If the item is not found and skip_exit is false, stops the script with an error.
      # If the item is too heavy or tied, recursively attempts to address the issue.
      #
      # @param name [String] the name of the item to retrieve, e.g. "pliers"
      # @param bag [String] the name of the primary container, e.g. "backpack"
      # @param bag_items [Array<String>] list of items stored in the bag
      # @param belt [Hash, nil] a belt configuration hash with 'name' and 'items' keys, or nil
      # @param skip_exit [Boolean] if true, returns silently on item not found; defaults to false
      # @return [void]
      # @example
      #   belt_config = {"name" => "crafting belt", "items" => ["pliers"]}
      #   DRCC.get_crafting_item("pliers", "backpack", ["pliers"], belt_config)
      # @see #stow_crafting_item
      def get_crafting_item(name, bag, bag_items, belt, skip_exit = false)
        waitrt?
        if belt && belt['items'].find { |item| /\b#{name}/i =~ item || /\b#{item}/i =~ name }
          case DRC.bput("untie my #{name} from my #{belt['name']}", BELT_UNTIE_SUCCESS, BELT_UNTIE_ALREADY, BELT_UNTIE_NOT_FOUND, BELT_UNTIE_WOUNDED)
          when BELT_UNTIE_SUCCESS, BELT_UNTIE_ALREADY
            return
          when BELT_UNTIE_WOUNDED
            craft_room = Room.current.id
            DRC.wait_for_script_to_complete('safe-room', ['force'])
            DRCT.walk_to(craft_room)
            return get_crafting_item(name, bag, bag_items, belt)
          end
        end
        command = "get my #{name}"
        command += " from my #{bag}" if bag_items && bag_items.include?(name)
        case DRC.bput(command, GET_CRAFTING_SUCCESS, GET_CRAFTING_ALREADY, GET_CRAFTING_NOT_FOUND_WHAT, GET_CRAFTING_NOT_FOUND_WERE, GET_CRAFTING_PICKUP, GET_CRAFTING_HEAVY, GET_CRAFTING_TIED)
        when GET_CRAFTING_NOT_FOUND_WHAT, GET_CRAFTING_NOT_FOUND_WERE
          pause 2
          return if DRCI.in_hands?(name)

          DRC.beep
          Lich::Messaging.msg('bold', "DRCC: You seem to be missing: #{name}")
          return nil if skip_exit

          Lich::Messaging.msg('bold', 'DRCC: Cannot continue crafting without required item. Stopping script.')
          return nil
        when GET_CRAFTING_HEAVY
          get_crafting_item(name, bag, bag_items, belt)
        when GET_CRAFTING_TIED
          case DRC.bput("untie my #{name}", UNTIE_SUCCESS, UNTIE_NOT_FOUND, UNTIE_WOUNDED)
          when UNTIE_SUCCESS
            return
          when UNTIE_WOUNDED
            craft_room = Room.current.id
            DRC.wait_for_script_to_complete('safe-room', ['force'])
            DRCT.walk_to(craft_room)
            return get_crafting_item(name, bag, bag_items, belt)
          end
        end
      end

      # Stows a crafting item into a belt or bag.
      # If a belt is configured and the item matches belt items, attempts to tie the item to the belt.
      # Otherwise, puts the item into the bag. Falls back to stow command if the item is too large.
      # Returns true on success, false on failure to tie to belt or put in bag.
      #
      # @param name [String] the name of the item to stow, or nil
      # @param bag [String] the name of the primary container, e.g. "backpack"
      # @param belt [Hash, nil] a belt configuration hash with 'name' and 'items' keys, or nil
      # @return [Boolean] true if the item was stowed, false if tying to belt failed or put failed
      # @example
      #   belt_config = {"name" => "crafting belt", "items" => ["pliers"]}
      #   DRCC.stow_crafting_item("pliers", "backpack", belt_config) #=> true
      # @see #get_crafting_item
      def stow_crafting_item(name, bag, belt)
        return unless name

        waitrt?
        if belt && belt['items'].find { |item| /\b#{name}/i =~ item || /\b#{item}/i =~ name }
          unless DRCI.tie_item?(name, belt['name'])
            Lich::Messaging.msg('bold', "DRCC: Failed to tie #{name} to #{belt['name']}.")
            craft_room = Room.current.id
            DRC.wait_for_script_to_complete('safe-room', ['force'])
            DRCT.walk_to(craft_room)
            return stow_crafting_item(name, bag, belt)
          end
        else
          case DRC.bput("put my #{name} in my #{bag}", PUT_BAG_TUCK, PUT_BAG_PUT, PUT_BAG_NOT_FOUND, PUT_BAG_TOO_BIG, PUT_BAG_WEIRD, PUT_BAG_NO_ROOM, PUT_BAG_CANT_THERE, PUT_BAG_COMBINE)
          when PUT_BAG_TOO_BIG, PUT_BAG_WEIRD, PUT_BAG_NO_ROOM
            fput("stow my #{name}")
          when PUT_BAG_CANT_THERE
            fput("put my #{name} in my other #{bag}")
            return false
          end
        end
        true
      end

      # Calculates the total crafting cost in the town's local currency.
      # Sums the cost of stock materials (if applicable) and purchasable parts, then adds 1000 for consumables.
      # Converts to the town's currency (kronars, lirums, or dokoras) using appropriate exchange rates.
      #
      # @param recipe [Hash] a recipe hash from base-recipes with at least a 'volume' key
      # @param hometown [String] the town name, e.g. "Crossing"
      # @param parts [Array<String>, nil] array of part names to purchase, or nil
      # @param quantity [Integer] number of items to craft
      # @param material [Hash, nil] a stock material hash from base-crafting with 'stock-value', 'stock-volume', and 'stock-name' keys, or nil
      # @return [Integer] the total crafting cost in the town's currency
      # @example
      #   recipe = {"volume" => 20, "type" => "armorsmithing"}
      #   material = {"stock-value" => 50, "stock-volume" => 5, "stock-name" => "bronze"}
      #   DRCC.crafting_cost(recipe, "Crossing", nil, 1, material) #=> 1200
      # @see #repair_own_tools
      def crafting_cost(recipe, hometown, parts, quantity, material)
        # To use this method, you'll need to pass:
        # recipe => This is a hash drawn directly from base-recipes eg {name: 'a metal ring cap', noun: 'cap', volume: 8, type: 'armorsmithing',etc}
        #     This is fetched via get_data('recipes').crafting_recipes('name')[<name of recipe>]
        # hometown => Just a string eg "Crossing"
        # parts => This is an array containing(if any) a list of parts required. Where base-recipes doesn't do this, you will need to format this.
        # quantity => an integer representing how many of each finished craft you intend to make. You can call this once per item, or once for all items.
        # material => This needs to be a hash drawn directly from base-crafting eg {stock-volume: 5, stock-number: 11, stock-name: 'bronze', stock-value: 562}
        #     This is fetched via get_data('crafting')['stock'][<name of material>]
        #     nil or false if not using stock materials

        currency = DRCM.town_currency(hometown)
        data = get_data('crafting')['stock'] # fetch parts data
        total = 0

        if material && %w[alabaster granite marble].any? { |x| material['stock-name'] == x } # stone isn't stackable, so just calculate stock*quantity
          total += material['stock-value'] * quantity
        elsif material # neither alchemy nor artificing have ONE stock material, they take various materials and combine them, so those are handled by parts below
          stock_to_order = ((recipe['volume'] / material['stock-volume'].to_f) * quantity).ceil
          total += (stock_to_order * material['stock-value'])
        end

        if parts
          parts_to_price = parts.reject { |part| PARTS_CANNOT_PURCHASE.include?(part) } # excludes things you cannot purchase, so won't error if you've got these.
          parts_to_price.each { |part| total += data[part]['stock-value'] * quantity } # adds the cost of each purchasable part to the total
        end

        total += 1000 # added to account for consumables, water, coal, etc

        case currency
        when 'kronars'
          total
        when 'lirums'
          (total * 0.800).ceil
        when 'dokoras'
          (total * 0.7216).ceil
        else
          total
        end
      end

      # Repairs a list of crafting tools using oil and wire brush, tracking immune tools to prevent over-repair.
      # Maintains a UserVars.immune_list hash of tools that have been recently repaired (7000 second cooldown).
      # Retrieves oil and brush for each tool, applies them in sequence, and stows the results.
      # Handles wounds by routing to safe-room and resuming repair.
      #
      # @param info [Hash] tool information hash with keys 'finisher-room', 'finisher-number', 'wire-brush-number'
      # @param tools [String, Array<String>] tool name(s) to repair
      # @param bag [String] the name of the primary container
      # @param bag_items [Array<String>] list of items stored in the bag
      # @param belt [Hash, nil] a belt configuration hash
      # @return [void]
      # @example
      #   info = {"finisher-room" => 123, "finisher-number" => 45, "wire-brush-number" => 10}
      #   DRCC.repair_own_tools(info, "pliers", "backpack", [], nil)
      # @see #get_crafting_item, #stow_crafting_item, #check_consumables
      def repair_own_tools(info, tools, bag, bag_items, belt)
        UserVars.immune_list ||= {} # declaring a hash unless hash already
        tools = tools.to_a # Convert single tool string to array
        UserVars.immune_list.reject! { |_k, v| v < Time.now } # removing anything from the immune list that has an expired timer
        tools.reject! { |x| UserVars.immune_list[x] } # removing tools from the list of eligible repairs if they're still on the immune list
        return unless tools.size > 0 # skips the whole method if no tools are eligible for repairs

        DRCC.check_consumables('oil', info['finisher-room'], info['finisher-number'], bag, bag_items, belt, tools.size) # checks intelligently for enough oil uses to repair the number of tools eligible for repair
        DRCC.check_consumables('wire brush', info['finisher-room'], info['wire-brush-number'] || 10, bag, bag_items, belt, tools.size) # checks intelligently for enough brush uses to repair the number of tools eligible for repair
        repair_tool = ['wire brush', 'oil']
        tools.each do |tool_name| # begins repair cycle for each tool
          DRCC.get_crafting_item(tool_name, bag, bag_items, belt, true) # attempts to fetch the next tool, with the option (true) to continue if fetch fails
          next unless DRC.right_hand # if we don't get the next tool for whatever reason, we move on to the next tool.

          repair_tool.each do |x| # iterates once for each: wire brush, oil
            DRCC.get_crafting_item(x, bag, bag_items, belt)
            command = x == 'wire brush' ? "rub my #{tool_name} with my wire brush" : "pour my oil on my #{tool_name}" # changes the command based on the tool, instead of a second case statement, since it's just one of each

            case DRC.bput(command, REPAIR_SUCCESS, REPAIR_NOT_NEEDED, REPAIR_ENGAGED, REPAIR_CONFUSED, REPAIR_POUR_WHAT)
            when REPAIR_SUCCESS # successful partial repair (one brush or one oil)
              DRCC.stow_crafting_item(x, bag, belt)
              next # move to oil, or move out of loop
            when REPAIR_NOT_NEEDED # doesn't require repair, leaving loop for the next tool
              DRCC.stow_crafting_item(x, bag, belt)
              break # leave brush/oil loop and choose next tool
            when REPAIR_POUR_WHAT
              DRCC.check_consumables('oil', info['finisher-room'], info['finisher-number'], bag, bag_items, belt) # somehow ran out of oil, fetching more
              DRCC.get_crafting_item(x, bag, bag_items, belt)
              DRC.bput("pour my oil on my #{tool_name}", REPAIR_SUCCESS)
              DRCC.stow_crafting_item(x, bag, belt)
              next # oil done, next tool
            when REPAIR_ENGAGED
              Lich::Messaging.msg('bold', 'DRCC: Cannot repair in combat.')
              DRCC.stow_crafting_item(tool_name, bag, belt)
              DRCC.stow_crafting_item(x, bag, belt)
              break
            when REPAIR_CONFUSED
              Lich::Messaging.msg('bold', 'DRCC: Something has gone wrong with repair, exiting repair loop.')
              DRCC.stow_crafting_item(tool_name, bag, belt)
              DRCC.stow_crafting_item(x, bag, belt)
              break
            end
          end
          UserVars.immune_list.store(tool_name, Time.now + 7000) if Flags['proper-repair'] # if our flag picks up a Proper Forging Tool Care successful repair, we add that tool and a time of now plus 7000 seconds (just shy of 2 hours) to the list of immune tools
          Flags.reset('proper-repair')
          DRCC.stow_crafting_item(tool_name, bag, belt)
        end
        nil
      end

      # Checks if a consumable item has sufficient remaining uses, and orders more if needed.
      # Retrieves the item, counts its uses via the count command, and disposes/reorders if uses are below the threshold.
      # Always stows the item and returns to the original room on completion.
      #
      # @param name [String] the consumable item name, e.g. "oil"
      # @param room [Integer, String] the stock room ID to order from
      # @param number [Integer] the stock number to order
      # @param bag [String] the name of the primary container
      # @param bag_items [Array<String>] list of items stored in the bag
      # @param belt [Hash, nil] a belt configuration hash
      # @param count [Integer] minimum number of uses required; defaults to 3
      # @return [void]
      # @example
      #   DRCC.check_consumables("oil", 12345, 67, "backpack", [], nil, 5)
      # @see #repair_own_tools
      def check_consumables(name, room, number, bag, bag_items, belt, count = 3)
        current = Room.current.id
        case DRC.bput("get my #{name} from my #{bag}", CONSUMABLE_GET_SUCCESS, CONSUMABLE_GET_NOT_FOUND)
        when CONSUMABLE_GET_SUCCESS
          count_result = DRC.bput("count my #{name}", *COUNT_USES_MESSAGES)
          match = count_result.match(COUNT_USES_PATTERN)
          if match && match[1].to_i < count
            DRCT.dispose(name)
            DRCC.check_consumables(name, room, number, bag, bag_items, belt, count)
          end
          DRCC.stow_crafting_item(name, bag, belt)
        else
          DRCT.order_item(room, number)
          DRCC.stow_crafting_item(name, bag, belt)
        end
        DRCT.walk_to(current)
      end

      # Retrieves and adjusts tongs to the requested configuration (shovel or tongs), tracking state via @tongs_status.
      # Supports three usage modes: 'shovel', 'tongs', or 'reset shovel'/'reset tongs' to initialize state.
      # Returns true if the tongs are in the requested configuration, false if not adjustable or retrieval fails.
      # Routes to safe-room if wounds prevent adjustment.
      #
      # @param usage [String] the desired tongs configuration: 'shovel', 'tongs', 'reset shovel', or 'reset tongs'
      # @param bag [String] the name of the primary container
      # @param bag_items [Array<String>] list of items stored in the bag
      # @param belt [Hash, nil] a belt configuration hash
      # @param adjustable_tongs [Boolean] whether the tongs can be adjusted; defaults to false
      # @return [Boolean] true if tongs are in the requested configuration, false otherwise
      # @example
      #   DRCC.get_adjust_tongs?("reset shovel", "backpack", [], nil)
      #   #=> true (if tongs are adjustable)
      # @see #get_crafting_item, #stow_crafting_item
      def get_adjust_tongs?(usage, bag, bag_items, belt, adjustable_tongs = false)
        case usage
        when 'shovel' # looking for a shovel
          if @tongs_status == 'shovel' # tongs already a shovel
            DRCC.get_crafting_item('tongs', bag, bag_items, belt) unless DRCI.in_hands?('tongs') # get unless already holding
            return true # tongs previously set to shovel, in hands, adjusted to shovel.
          elsif !adjustable_tongs # determines state of tongs, works either nil or tongs
            return false # non-adjustable
          else
            DRCC.get_crafting_item('tongs', bag, bag_items, belt) unless DRCI.in_hands?('tongs') # get unless already holding

            case DRC.bput('adjust my tongs', ADJUST_TONGS_SHOVEL, ADJUST_TONGS_TONGS, ADJUST_TONGS_CANNOT, ADJUST_TONGS_UNKNOWN)
            when ADJUST_TONGS_CANNOT, ADJUST_TONGS_UNKNOWN # holding tongs, not adjustable, settings are wrong.
              Lich::Messaging.msg('bold', 'DRCC: Tongs are not adjustable. Please change yaml to reflect adjustable_tongs: false')
              DRCC.stow_crafting_item('tongs', bag, belt) # stows to make room for shovel
              return false
            when ADJUST_TONGS_TONGS # now tongs, adjust success but in wrong configuration
              DRC.bput('adjust my tongs', ADJUST_TONGS_SHOVEL) # now shovel, ready to work
              @tongs_status = 'shovel' # correcting instance variable
              return true # tongs as shovel
            when ADJUST_TONGS_SHOVEL # now shovel, adjust success
              @tongs_status = 'shovel' # setting instance variable
              return true # tongs as shovel
            end
          end

          # at this point, we either have tongs-in-shovel and a return of true, or tongs stowed(if in left hand) and a return of false

        when 'tongs' # looking for tongs
          DRCC.get_crafting_item('tongs', bag, bag_items, belt) unless DRCI.in_hands?('tongs') # get unless already holding. Here we are always getting tongs, never stowing tongs.
          if @tongs_status == 'tongs' # tongs as tongs already
            return true # tongs previously set to tongs, in hands, adjusted to tongs. this will not catch unscripted adjustments to tongs.
          elsif !adjustable_tongs # determines state of tongs, works either nil or shovel
            return false # have tongs, as tongs, but not adjustable.
          else

            case DRC.bput('adjust my tongs', ADJUST_TONGS_SHOVEL, ADJUST_TONGS_TONGS, ADJUST_TONGS_CANNOT, ADJUST_TONGS_UNKNOWN)
            when ADJUST_TONGS_CANNOT, ADJUST_TONGS_UNKNOWN # holding tongs, not adjustable, settings are wrong.
              Lich::Messaging.msg('bold', 'DRCC: Tongs are not adjustable. Please change yaml to reflect adjustable_tongs: false')
              return false # here we have tongs in hand, as tongs, but they're not adjustable, so this returns false.
            when ADJUST_TONGS_SHOVEL # now in shovel, adjust success but in wrong configuration
              DRC.bput('adjust my tongs', ADJUST_TONGS_TONGS) # now tongs, ready to work
              @tongs_status = 'tongs'
              return true # tongs as tongs AND adjustable
            when ADJUST_TONGS_TONGS # now tongs
              @tongs_status = 'tongs'
              return true # tongs as tongs AND adjustable
            end
          end

        when 'reset shovel', 'reset tongs' # Used at the top of a script, to determine state of tongs.
          @tongs_status = nil
          adjustable_tongs = true
          if usage == 'reset shovel'
            return DRCC.get_adjust_tongs?('shovel', bag, bag_items, belt, adjustable_tongs)
          elsif usage == 'reset tongs'
            return DRCC.get_adjust_tongs?('tongs', bag, bag_items, belt, adjustable_tongs)
          end
        end
      end

      # Bundles a crafted item with a logbook work order and discards rejected items.
      # Attempts to retrieve the logbook, bundle the item, and handle various failure modes.
      # Disposes of items that fail quality, type, or expiration checks.
      # Stows the logbook when complete.
      #
      # @param logbook [String] the logbook type, e.g. "engineering"
      # @param noun [String] the crafted item noun to bundle
      # @param container [String] the container to retrieve items from
      # @return [void]
      # @example
      #   DRCC.logbook_item("engineering", "mechanism", "backpack")
      # @see #get_crafting_item, #stow_crafting_item
      def logbook_item(logbook, noun, container)
        DRCI.get_item?("#{logbook} logbook")
        bundle_result = DRC.bput("bundle my #{noun} with my logbook",
                                 BUNDLE_SUCCESS,
                                 BUNDLE_EXPIRED,
                                 BUNDLE_QUALITY,
                                 BUNDLE_WRONG_TYPE,
                                 BUNDLE_NOT_HOLDING)
        case bundle_result
        when BUNDLE_EXPIRED, BUNDLE_QUALITY, BUNDLE_WRONG_TYPE
          DRCI.dispose_trash(noun)
        when BUNDLE_NOT_HOLDING
          if DRCI.get_item?(noun, container)
            case DRC.bput("bundle my #{noun} with my logbook",
                          BUNDLE_SUCCESS,
                          BUNDLE_EXPIRED,
                          BUNDLE_QUALITY,
                          BUNDLE_WRONG_TYPE)
            when BUNDLE_EXPIRED, BUNDLE_QUALITY, BUNDLE_WRONG_TYPE
              DRCI.dispose_trash(noun)
            end
          end
        end
        DRCI.put_away_item?("#{logbook} logbook", container) || DRCI.put_away_item?("#{logbook} logbook")
      end

      # Orders multiple enchanting stock items from a stock room and stows them.
      # Iterates for the specified count, ordering each item and stowing both hands on completion.
      #
      # @param stock_room [Integer, String] the stock room ID to order from
      # @param stock_needed [Integer] the number of items to order
      # @param stock_number [Integer] the stock number to order
      # @param bag [String] the name of the primary container
      # @param belt [Hash, nil] a belt configuration hash
      # @return [void]
      # @example
      #   DRCC.order_enchant(12345, 3, 67, "backpack", nil)
      # @see #fount
      def order_enchant(stock_room, stock_needed, stock_number, bag, belt)
        stock_needed.times do
          DRCT.order_item(stock_room, stock_number)
          stow_crafting_item(DRC.left_hand, bag, belt)
          stow_crafting_item(DRC.right_hand, bag, belt)
          next unless DRC.left_hand && DRC.right_hand
        end
      end

      # Checks if a fount has sufficient uses for the requested crafting quantity, and orders more if needed.
      # Taps the fount (in bag, on person, or on brazier), analyzes it, and reorders if uses are insufficient.
      # Clears hands and orders stock via #order_enchant as needed.
      #
      # @param stock_room [Integer, String] the stock room ID to order from
      # @param stock_needed [Integer] the number of new founts to order if insufficient
      # @param stock_number [Integer] the stock number to order
      # @param quantity [Integer] the number of crafting operations to be performed
      # @param bag [String] the name of the primary container
      # @param bag_items [Array<String>] list of items stored in the bag
      # @param belt [Hash, nil] a belt configuration hash
      # @return [void]
      # @example
      #   DRCC.fount(12345, 2, 67, 5, "backpack", ["fount"], nil)
      # @see #order_enchant, #check_consumables
      def fount(stock_room, stock_needed, stock_number, quantity, bag, bag_items, belt)
        case DRC.bput('tap my fount', FOUNT_TAP_IN_BAG, FOUNT_TAP_ON_BAG, FOUNT_TAP_NOT_FOUND)
        when FOUNT_TAP_IN_BAG, FOUNT_TAP_ON_BAG
          analyze_result = DRC.bput('analyze my fount', FOUNT_ANALYZE_PATTERN)
          match = analyze_result.match(FOUNT_ANALYZE_PATTERN)
          if match && match[:uses].to_i < (quantity + 1)
            get_crafting_item('fount', bag, bag_items, belt)
            DRCT.dispose('fount')
            DRCI.stow_hands
            order_enchant(stock_room, stock_needed, stock_number, bag, belt)
          end
        when FOUNT_TAP_NOT_FOUND
          case DRC.bput('tap my fount on my brazier', FOUNT_TAP_ON_BRAZIER, FOUNT_TAP_NOT_FOUND)
          when FOUNT_TAP_ON_BRAZIER
            analyze_result = DRC.bput('analyze my fount on my brazier', FOUNT_ANALYZE_PATTERN)
            match = analyze_result.match(FOUNT_ANALYZE_PATTERN)
            if match && match[:uses].to_i < quantity
              DRCI.stow_hands
              order_enchant(stock_room, stock_needed, stock_number, bag, belt)
            end
          when FOUNT_TAP_NOT_FOUND
            order_enchant(stock_room, stock_needed, stock_number, bag, belt)
          end
        end
      end

      # Determines if the current brazier is clean, and removes any items on it if needed.
      # If the brazier is empty, returns true. If items are present, attempts to clean the brazier
      # and empties any remaining contents.
      #
      # @return [Boolean] true if the brazier is clean or has been cleaned, false if check cannot be determined
      # @example
      #   DRCC.clean_brazier? #=> true
      # @see #empty_brazier, #find_enchanting_room
      def clean_brazier?
        case DRC.bput('look on brazier', BRAZIER_NOTHING, BRAZIER_SEE_PATTERN)
        when /There is nothing on there/i
          true
        when /On the .* you see/
          case DRC.bput('clean brazier', BRAZIER_CLEAN_PREPARE, BRAZIER_CLEAN_NOTHING, BRAZIER_CLEAN_NOT_LIT)
          when BRAZIER_CLEAN_PREPARE
            DRC.bput('clean brazier', BRAZIER_CLEAN_FLAME)
          end
          empty_brazier
          true
        end
      end

      # Removes all items from the current brazier and discards them.
      # Uses a look command to retrieve items, then gets and disposes of each one.
      #
      # @return [void]
      # @example
      #   DRCC.empty_brazier
      # @see #clean_brazier?
      def empty_brazier
        result = DRC.bput('look on brazier', BRAZIER_SEE_PATTERN, BRAZIER_CLEAN_NOTHING)
        match = result.match(BRAZIER_SEE_PATTERN)
        return unless match

        items = match[:items]
        items = items.split(' and ')
        items.each do |item|
          item = item.split.last
          DRC.bput("get #{item} from brazier", BRAZIER_GET_SUCCESS)
          DRCT.dispose(item)
        end
      end

      # Checks if sufficient sigil-scrolls are in inventory, and orders more if needed.
      # Counts existing sigil-scrolls in the bag, compares against the quantity needed, and orders the difference.
      # Returns true if the quantity is met (via inventory or order), false if the sigil type is not available for purchase.
      #
      # @param sigil [String] the sigil type, e.g. "primary" or "secondary"
      # @param stock_number [Integer] the stock number to order
      # @param quantity [Integer] the number of sigil-scrolls required
      # @param bag [String] the name of the primary container
      # @param belt [Hash, nil] a belt configuration hash
      # @param info [Hash] stock information with 'stock-room' key
      # @return [Boolean] true if sigil quantity is satisfied, false if unavailable for purchase
      # @example
      #   info = {"stock-room" => 12345}
      #   DRCC.check_for_existing_sigil?("primary", 67, 3, "backpack", nil, info) #=> true
      # @see #order_enchant
      def check_for_existing_sigil?(sigil, stock_number, quantity, bag, belt, info)
        merged = Regexp.union($PRIMARY_SIGILS_PATTERN, $SECONDARY_SIGILS_PATTERN)

        more = 0
        tmp_count = DRCI.count_items_in_container("#{sigil} sigil-scroll", bag).to_i

        if tmp_count >= quantity
          return true
        else
          if merged.match?("#{sigil} sigil")
            more = quantity - tmp_count
            # Found a weird challenge that made the temp_part_count equal 1 even though no "sigil" was in container
            # Check if there's really nothing in there - use bput to check for the nothing message
            nothing_result = DRC.bput("look in my #{bag}", SIGIL_COUNT_NOTHING, /.*/)
            more += 1 if nothing_result&.include?(SIGIL_COUNT_NOTHING)
            DRCC.order_enchant(info['stock-room'], more, stock_number, bag, belt)
            return true
          else
            Lich::Messaging.msg('bold', "DRCC: Not enough #{sigil} sigil-scroll(s). You can purchase or harvest #{more} more. We recommend using our sigilhunter script. Run #{$clean_lich_char}sigilhunter help for more information.")
            return false
          end
        end
      end

      # Counts and displays raw metals in a container via rummage.
      # Parses the rummage output to extract volume and piece counts for each metal type.
      # Handles various error conditions (closed container, not found, invisible).
      # Returns a hash of metal => [total_volume, piece_count], or a specific metal's data if type is provided.
      #
      # @param container [String] the container noun to rummage, e.g. "workbench"
      # @param type [String, nil] an optional metal type to return (e.g., "bronze"); if nil, returns all metals
      # @return [Hash, Array, nil] a hash of metals with volumes and counts, or an array [volume, count] for a specific type, or nil on error
      # @example
      #   DRCC.count_raw_metal("workbench") #=> {"bronze" => [150, 3], "iron" => [100, 2]}
      #   DRCC.count_raw_metal("workbench", "bronze") #=> [150, 3]
      # @see #RUMMAGE_SUCCESS_PATTERN
      def count_raw_metal(container, type = nil)
        result = DRC.bput("rummage /M #{container}", RUMMAGE_NOTHING, RUMMAGE_CLOSED, RUMMAGE_NOT_FOUND, RUMMAGE_INVISIBLE, RUMMAGE_NOTHING_ACCOMPLISH, RUMMAGE_SUCCESS_PATTERN)

        if result&.match?(RUMMAGE_NOTHING)
          Lich::Messaging.msg('bold', 'DRCC: No materials found.')
          return nil
        elsif result&.match?(RUMMAGE_CLOSED)
          return nil unless DRCI.open_container?(container)

          return count_raw_metal(container, type)
        elsif result&.match?(RUMMAGE_NOT_FOUND)
          Lich::Messaging.msg('bold', 'DRCC: Container not found.')
          return nil
        elsif result&.match?(RUMMAGE_INVISIBLE)
          Lich::Messaging.msg('bold', "DRCC: Try again when you're not invisible.")
          return nil
        end

        match = result&.match(RUMMAGE_SUCCESS_PATTERN)
        unless match
          Lich::Messaging.msg('bold', 'DRCC: Please report this error to the dev team on discord. Include a log snippet if possible.')
          return nil
        end

        h = {}
        list = match[:materials].sub(' and ', ', ').split(', ')
        list.each do |e|
          metal = e.split[2]
          volume = $VOL_MAP[e.split[1]]
          if h.key?(metal)
            h[metal][0] += volume
            h[metal][1] += 1
          else
            h[metal] = [volume, 1]
          end
        end
        h.each do |k, v|
          Lich::Messaging.msg('plain', "DRCC: #{k} - #{v[0]} volume - #{v[1]} pieces")
        end

        type.nil? ? h : h[type]
      end

      # Creates a specified number of mechanisms using a press in the shaping room.
      # Sets the press speed, then for each mechanism: retrieves ingot, pushes fuel with shovel,
      # pushes ingot into press, pulls mechanism from press, and stows the result.
      # Combines mechanisms if both hands are full.
      #
      # @param settings [OpenStruct] crafting settings with keys: hometown, crafting_container, crafting_items_in_container, forging_belt
      # @param material [String] the material type, e.g. "bronze"
      # @param number [Integer] the number of mechanisms to create
      # @param speed [Integer] the press speed (1-12); defaults to 6
      # @return [void]
      # @example
      #   settings = OpenStruct.new(hometown: "Crossing", crafting_container: "backpack", crafting_items_in_container: [], forging_belt: nil)
      #   DRCC.create_mechanisms(settings, "bronze", 3, 8)
      # @see #find_shaping_room, #get_crafting_item, #stow_crafting_item
      def create_mechanisms(settings, material, number, speed = 6)
        DRCC.find_shaping_room(settings.hometown)
        case DRC.bput("turn press to #{speed}", /You dial the device to \d+ and ready it for pressing/, /The press cannot be turned to a speed greater than 12/, /The press cannot be turned to a volume less than 1/)
        when /The press cannot be turned to a speed greater than 12/, /The press cannot be turned to a volume less than 1/
          DRC.message("Invalid press speed specified.  Valid values are from 1-12.")
          return
        end
        number.times do
          DRCC.get_crafting_item("#{material} ingot", settings.crafting_container, settings.crafting_items_in_container, settings.forging_belt)
          break unless DRCI.in_hands?("#{material} ingot")
          DRCC.get_crafting_item('shovel', settings.crafting_container, settings.crafting_items_in_container, settings.forging_belt) unless DRCI.in_hands?('shovel')
          DRC.bput("push fuel with my shovel", /^Roundtime/)
          DRCC.stow_crafting_item('shovel', settings.crafting_container, settings.forging_belt)
          DRCC.get_crafting_item('pliers', settings.crafting_container, settings.crafting_items_in_container, settings.forging_belt)
          DRC.bput('push my ingot with press', /Roundtime/)
          DRC.bput('pull my mech with press', /Roundtime/)
          DRCC.stow_crafting_item('pliers', settings.crafting_container, settings.forging_belt)
          DRCC.get_crafting_item('mechanisms', settings.crafting_container, settings.crafting_items_in_container, nil, true)
          fput('combine') if DRC.right_hand && DRC.left_hand
          DRCC.stow_crafting_item('mechanisms', settings.crafting_container, nil)
        end
        DRCC.get_crafting_item("#{material} ingot", nil, nil, nil, true)
        DRCC.stow_crafting_item("#{material} ingot", settings.crafting_container, nil) if DRC.right_hand
      end
    end
  end
end
