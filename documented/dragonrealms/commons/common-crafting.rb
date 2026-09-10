# frozen_string_literal: true

# Namespace for the Lich game scripting engine.
module Lich
  # Namespace for DragonRealms-specific functionality.
  module DragonRealms
    # Common crafting utilities for the DragonRealms scripting engine.
    #
    # Provides pattern constants for game command responses and methods for
    # acquiring/storing crafting materials, managing tools and consumables,
    # finding crafting rooms, and performing crafting operations.
    module DRCC
      module_function

      # Pattern constants for bput responses
      LOOK_CRUCIBLE_NOT_FOUND = '^I could not find'
      LOOK_CRUCIBLE_EMPTY = '^There is nothing in there'
      # Matches the response when looking into a crucible that contains items.
      #
      # Captures the item list in the `items` named group.
      #
      # @return [Regexp]
      # @example
      #   "In the large crucible you see some bronze and an ingot." =~ LOOK_CRUCIBLE_SEE_PATTERN #=> 0
      # @see LOOK_CRUCIBLE_NOT_FOUND
      # @see LOOK_CRUCIBLE_EMPTY
      LOOK_CRUCIBLE_SEE_PATTERN = /^In the .* crucible you see (?<items>.*)\./.freeze
      LOOK_CRUCIBLE_MOLTEN = 'crucible you see some molten'

      LOOK_ANVIL_NOT_FOUND = '^I could not find'
      LOOK_ANVIL_CLEAN = 'surface looks clean and ready'
      # Matches the response when looking on an anvil that contains items.
      #
      # Captures the item list in the `items` named group.
      #
      # @return [Regexp]
      # @example
      #   "On the anvil you see a bar and a tongs." =~ LOOK_ANVIL_SEE_PATTERN #=> 0
      # @see LOOK_ANVIL_NOT_FOUND
      # @see LOOK_ANVIL_CLEAN
      LOOK_ANVIL_SEE_PATTERN = /anvil you see (?<items>.*)\./.freeze

      CLEAN_ANVIL_DRAG = 'You drag the'
      CLEAN_ANVIL_REMOVE = 'remove them yourself'
      GET_ANVIL_SUCCESS = 'You get'
      GET_ANVIL_NOT_YOURS = 'is not yours'
      PUT_BUCKET_SUCCESS = 'You drop'

      BOOK_CHAPTER_TURN_SUCCESS = 'You turn'
      # Matches when the character cannot perform a crafting action because engaged in combat.
      #
      # @return [String]
      # @example
      #   "You are too distracted to be doing that right now"
      BOOK_CHAPTER_DISTRACTED = 'You are too distracted to be doing that right now'
      BOOK_CHAPTER_ALREADY = 'The .* is already turned'
      # Matches a successful turn to a chapter in a crafting reference book (newer format).
      #
      # @return [Regexp]
      # @example
      #   "You turn your book to chapter 3." =~ BOOK_CHAPTER2_SUCCESS #=> 0
      # @see BOOK_CHAPTER2_ALREADY
      # @see find_recipe2
      BOOK_CHAPTER2_SUCCESS = /^You turn your .* to chapter/
      # Matches when the crafting book is already at the requested chapter (newer format).
      #
      # @return [Regexp]
      # @example
      #   "The book is already turned to chapter 3." =~ BOOK_CHAPTER2_ALREADY #=> 0
      # @see BOOK_CHAPTER2_SUCCESS
      BOOK_CHAPTER2_ALREADY = /^The .* is already turned to chapter/
      # Matches a successful turn to a specific page in a crafting reference book.
      #
      # @return [Regexp]
      # @example
      #   "You turn your book to page 42." =~ BOOK_PAGE_SUCCESS #=> 0
      # @see BOOK_PAGE_ALREADY
      BOOK_PAGE_SUCCESS = /^You turn your .* to page/
      # Matches when the crafting book is already at the requested page.
      #
      # @return [Regexp]
      # @example
      #   "You are already on page 42." =~ BOOK_PAGE_ALREADY #=> 0
      # @see BOOK_PAGE_SUCCESS
      BOOK_PAGE_ALREADY = /^You are already on page/
      # Matches a successful turn to a discipline section in a crafting reference book.
      #
      # @return [Regexp]
      # @example
      #   "You turn the book to the section on Armorsmithing." =~ BOOK_DISCIPLINE_SUCCESS #=> 0
      BOOK_DISCIPLINE_SUCCESS = /^You turn the .* to the section on/
      # Matches roundtime that follows a successful crafting book study action.
      #
      # @return [Regexp]
      # @example
      #   "Roundtime: 30 seconds." =~ BOOK_STUDY_SUCCESS #=> 0
      BOOK_STUDY_SUCCESS = /^Roundtime/

      # Matches a successful untie/removal of an item from a belt.
      #
      # @return [Regexp]
      # @example
      #   "You untie a tongs from your crafting belt." =~ BELT_UNTIE_SUCCESS #=> 0
      # @see BELT_UNTIE_ALREADY
      # @see BELT_UNTIE_NOT_FOUND
      # @see BELT_UNTIE_WOUNDED
      BELT_UNTIE_SUCCESS = /^You (remove|untie)/
      # Matches when an item is already untied/removed from a belt.
      #
      # @return [Regexp]
      # @example
      #   "You are already carrying the tongs." =~ BELT_UNTIE_ALREADY #=> 0
      # @see BELT_UNTIE_SUCCESS
      BELT_UNTIE_ALREADY = /^You are already/
      # Matches when the character cannot find an item to untie from a belt.
      #
      # @return [Regexp]
      # @example
      #   "Untie what?" =~ BELT_UNTIE_NOT_FOUND #=> 0
      # @see BELT_UNTIE_SUCCESS
      BELT_UNTIE_NOT_FOUND = /^Untie what/
      # Matches when wounds prevent untying an item from a belt.
      #
      # @return [Regexp]
      # @example
      #   "Your wounds hinder your ability to do that." =~ BELT_UNTIE_WOUNDED #=> 0
      # @see BELT_UNTIE_SUCCESS
      BELT_UNTIE_WOUNDED = /^Your wounds hinder your ability to do that/

      # Matches a successful pickup of a crafting item.
      #
      # @return [Regexp]
      # @example
      #   "You get a tongs from your crafting bag." =~ GET_CRAFTING_SUCCESS #=> 0
      # @see GET_CRAFTING_ALREADY
      # @see GET_CRAFTING_NOT_FOUND_WHAT
      # @see GET_CRAFTING_PICKUP
      GET_CRAFTING_SUCCESS = /^You get/
      # Matches when an item is already in hand.
      #
      # @return [Regexp]
      # @example
      #   "You are already carrying a tongs." =~ GET_CRAFTING_ALREADY #=> 0
      # @see GET_CRAFTING_SUCCESS
      GET_CRAFTING_ALREADY = /^You are already/
      # Matches when the character cannot find a requested crafting item (first variant).
      #
      # @return [Regexp]
      # @example
      #   "What do you mean, a tongs?" =~ GET_CRAFTING_NOT_FOUND_WHAT #=> 0
      # @see GET_CRAFTING_NOT_FOUND_WERE
      GET_CRAFTING_NOT_FOUND_WHAT = /^What do you/
      # Matches when the character cannot find a requested crafting item (second variant).
      #
      # @return [Regexp]
      # @example
      #   "What were you referring to?" =~ GET_CRAFTING_NOT_FOUND_WERE #=> 0
      # @see GET_CRAFTING_NOT_FOUND_WHAT
      GET_CRAFTING_NOT_FOUND_WERE = /^What were you/
      # Matches a pickup of a crafting item (variant of GET_CRAFTING_SUCCESS).
      #
      # @return [Regexp]
      # @example
      #   "You pick up a tongs." =~ GET_CRAFTING_PICKUP #=> 0
      GET_CRAFTING_PICKUP = /^You pick up/
      # Matches when an item is too heavy to pick up in one attempt.
      #
      # @return [Regexp]
      # @example
      #   "You can't quite lift it." =~ GET_CRAFTING_HEAVY #=> 0
      GET_CRAFTING_HEAVY = /can't quite lift it/
      # Matches when an item must be untied before being picked up.
      #
      # @return [Regexp]
      # @example
      #   "You should untie that from your belt first." =~ GET_CRAFTING_TIED #=> 0
      GET_CRAFTING_TIED = /^You should untie/

      # Matches a successful untie of an item.
      #
      # @return [Regexp]
      # @example
      #   "You untie a tongs." =~ UNTIE_SUCCESS #=> 0
      # @see UNTIE_NOT_FOUND
      # @see UNTIE_WOUNDED
      UNTIE_SUCCESS = /^You (remove|untie)/
      # Matches when the character cannot find an item to untie.
      #
      # @return [Regexp]
      # @example
      #   "Untie what?" =~ UNTIE_NOT_FOUND #=> 0
      # @see UNTIE_SUCCESS
      UNTIE_NOT_FOUND = /^Untie what/
      # Matches when wounds prevent untying an item.
      #
      # @return [Regexp]
      # @example
      #   "Your wounds hinder your ability to do that." =~ UNTIE_WOUNDED #=> 0
      # @see UNTIE_SUCCESS
      UNTIE_WOUNDED = /^Your wounds hinder your ability to do that/

      TIE_BELT_SUCCESS = 'you attach'
      TIE_BELT_WOUNDED = 'Your wounds hinder'

      PUT_BAG_TUCK = 'You tuck'
      PUT_BAG_PUT = 'You put your'
      PUT_BAG_NOT_FOUND = 'What were you referring to'
      # Matches when an item is too large to fit in a container.
      #
      # @return [Regexp]
      # @example
      #   "That is too big to fit in your crafting bag." =~ PUT_BAG_TOO_BIG #=> 0
      # @see PUT_BAG_TUCK
      # @see PUT_BAG_NO_ROOM
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
      # Matches and captures a count of uses from a consumable item response.
      #
      # Captures the numeric count in group 1.
      #
      # @return [Regexp]
      # @example
      #   "The oil has 5 uses remaining"[COUNT_USES_PATTERN, 1] #=> "5"
      # @see COUNT_USES_MESSAGES
      COUNT_USES_PATTERN = /(\d+)/.freeze
      # Array of patterns used to match consumable item use-count responses.
      #
      # Patterns capture the numeric count in group 1.
      #
      # @return [Array<String>]
      # @example
      #   COUNT_USES_MESSAGES[0] #=> "The .* has (\\d+) uses remaining"
      # @see COUNT_USES_PATTERN
      # @see check_consumables
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
      # Matches when bundling a crafted item fails due to insufficient quality.
      #
      # @return [String]
      # @example
      #   "The work order requires items of a higher quality."
      BUNDLE_QUALITY = 'The work order requires items of a higher quality'
      # Matches when bundling a crafted item fails due to incorrect item type.
      #
      # @return [String]
      # @example
      #   "That isn't the correct type of item for this work order."
      BUNDLE_WRONG_TYPE = "That isn't the correct type of item for this work order."
      BUNDLE_NOT_HOLDING = 'You need to be holding'

      # Matches a successful tap of a fount inside a container.
      #
      # @return [Regexp]
      # @example
      #   "You tap the water fount inside your crafting bag." =~ FOUNT_TAP_IN_BAG #=> 0
      # @see FOUNT_TAP_ON_BAG
      # @see FOUNT_TAP_NOT_FOUND
      FOUNT_TAP_IN_BAG = /You tap .* inside your .*/
      # Matches a successful tap of a fount on a container.
      #
      # @return [Regexp]
      # @example
      #   "You tap the water fount on your crafting bag." =~ FOUNT_TAP_ON_BAG #=> 0
      # @see FOUNT_TAP_IN_BAG
      # @see FOUNT_TAP_NOT_FOUND
      FOUNT_TAP_ON_BAG = /You tap .*your .*/
      # Matches when the character cannot find the fount to tap.
      #
      # @return [Regexp]
      # @example
      #   "I could not find what you were referring to." =~ FOUNT_TAP_NOT_FOUND #=> 0
      # @see FOUNT_TAP_IN_BAG
      FOUNT_TAP_NOT_FOUND = /I could not find what you were referring to./
      # Matches a successful tap of a fount on a brazier.
      #
      # @return [Regexp]
      # @example
      #   "You tap the water fount atop a large brazier." =~ FOUNT_TAP_ON_BRAZIER #=> 0
      # @see FOUNT_TAP_IN_BAG
      FOUNT_TAP_ON_BRAZIER = /You tap .* atop a .*brazier./
      # Matches the analyze response for a fount, capturing remaining uses.
      #
      # Captures the use count in the `uses` named group.
      #
      # @return [Regexp]
      # @example
      #   "This appears to be a crafting tool and it has approximately 42 uses remaining" =~ FOUNT_ANALYZE_PATTERN #=> 0
      FOUNT_ANALYZE_PATTERN = /This appears to be a crafting tool and it has approximately (?<uses>\d+) uses remaining/.freeze

      BRAZIER_NOTHING = 'There is nothing on there'
      # Matches the response when looking on a brazier that contains items.
      #
      # Captures the item list in the `items` named group.
      #
      # @return [Regexp]
      # @example
      #   "On the large brazier you see some bronze and a brush." =~ BRAZIER_SEE_PATTERN #=> 0
      # @see BRAZIER_NOTHING
      BRAZIER_SEE_PATTERN = /On the (?:.*)brazier you see (?<items>.*)\./.freeze
      BRAZIER_CLEAN_PREPARE = 'You prepare to clean off the brazier'
      BRAZIER_CLEAN_NOTHING = 'There is nothing'
      BRAZIER_CLEAN_NOT_LIT = 'The brazier is not currently lit'
      # Matches when cleaning a lit brazier causes a dangerous flame response.
      #
      # @return [String]
      # @example
      #   "a massive ball of flame jets forward and singes everything nearby"
      BRAZIER_CLEAN_FLAME = 'a massive ball of flame jets forward and singes everything nearby'
      BRAZIER_GET_SUCCESS = 'You get'

      # Matches when rummaging through a container yields no matching materials.
      #
      # @return [Regexp]
      # @example
      #   "You look through the crafting materials but there is nothing in there like that." =~ RUMMAGE_NOTHING #=> 0
      # @see RUMMAGE_CLOSED
      # @see RUMMAGE_NOT_FOUND
      RUMMAGE_NOTHING = /crafting materials but there is nothing in there like that\.$/
      # Matches when the character attempts to rummage through a closed container.
      #
      # @return [Regexp]
      # @example
      #   "While it's closed, you can't rummage through that." =~ RUMMAGE_CLOSED #=> 0
      # @see RUMMAGE_NOTHING
      RUMMAGE_CLOSED = /While it\'s closed/
      # Matches when the container for rummaging cannot be found.
      #
      # @return [Regexp]
      # @example
      #   "I don't know what you are referring to." =~ RUMMAGE_NOT_FOUND #=> 0
      # @see RUMMAGE_CLOSED
      RUMMAGE_NOT_FOUND = /I don\'t know what you are referring to/
      # Matches when the character is invisible and cannot rummage effectively.
      #
      # @return [Regexp]
      # @example
      #   "You feel about blindly since you are invisible." =~ RUMMAGE_INVISIBLE #=> 0
      RUMMAGE_INVISIBLE = /You feel about/
      # Matches when rummaging would serve no purpose.
      #
      # @return [Regexp]
      # @example
      #   "That would accomplish nothing." =~ RUMMAGE_NOTHING_ACCOMPLISH #=> 0
      RUMMAGE_NOTHING_ACCOMPLISH = /That would accomplish nothing/
      # Matches a successful rummage through a container, capturing the materials found.
      #
      # Captures the material list in the `materials` named group.
      #
      # @return [Regexp]
      # @example
      #   "You look through the crafting materials and see 3 pieces of bronze, 2 pieces of iron." =~ RUMMAGE_SUCCESS_PATTERN #=> 0
      # @see count_raw_metal
      RUMMAGE_SUCCESS_PATTERN = /looking for crafting materials and see (?<materials>.*)\.$/

      TAP_CRUCIBLE_NOT_FOUND = 'I could not'
      # Matches a successful tap of a crucible.
      #
      # @return [Regexp]
      # @example
      #   "You tap the crucible." =~ TAP_CRUCIBLE_SUCCESS #=> 0
      # @see empty_crucible?
      TAP_CRUCIBLE_SUCCESS = /You tap.*crucible/
      TAP_ANVIL_NOT_FOUND = 'I could not'
      # Matches a successful tap of an anvil.
      #
      # @return [Regexp]
      # @example
      #   "You tap the anvil." =~ TAP_ANVIL_SUCCESS #=> 0
      # @see clean_anvil?
      TAP_ANVIL_SUCCESS = /You tap.*anvil/
      TAP_GRINDSTONE_NOT_FOUND = 'I could not'
      TAP_GRINDSTONE_SUCCESS = 'You tap.*grindstone'
      TAP_GRINDER_NOT_FOUND = 'I could not'
      TAP_GRINDER_SUCCESS = 'You tap.*grinder'

      SIGIL_COUNT_NOTHING = 'but there is nothing in there like that'

      # Checks whether the current crucible is empty, removing any items found.
      #
      # Attempts to tap the crucible; if that succeeds and no other characters are
      # present, returns true. Otherwise, iterates through the crucible contents,
      # removing and disposing of each item, then recursively checks again. Handles
      # molten material by tilting the crucible.
      #
      # @return [Boolean] true if the crucible is empty or can be emptied, false if
      #   the crucible cannot be found or if it belongs to another player
      # @note May spend roundtime on cleanup actions
      # @see find_empty_crucible
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

      # Locates an empty crucible suitable for blacksmithing in the given town.
      #
      # First attempts to use the current crucible if one can be tapped and it is
      # empty with no other players present. If that fails, searches through the
      # town's configured crucible locations for one that meets the criteria, then
      # verifies the anvil is also clean before returning.
      #
      # @param hometown [String] the town name (e.g., "Crossing", "Theren")
      # @return [void]
      # @note Performs room navigation and cleanup as needed
      # @see empty_crucible?
      # @see clean_anvil?
      def find_empty_crucible(hometown)
        return if DRC.bput('tap crucible', TAP_CRUCIBLE_NOT_FOUND, TAP_CRUCIBLE_SUCCESS) =~ TAP_CRUCIBLE_SUCCESS && (DRRoom.pcs - DRRoom.group_members).empty? && empty_crucible?

        crucibles = get_data('crafting')['blacksmithing'][hometown]['crucibles']
        idle_room = get_data('crafting')['blacksmithing'][hometown]['idle-room']
        DRCT.find_sorted_empty_room(crucibles, idle_room, proc { (DRRoom.pcs - DRRoom.group_members).empty? && empty_crucible? })
        DRCC.clean_anvil?
      end

      # Checks whether the current anvil is clean, removing any items found.
      #
      # Attempts to look on the anvil. If clean, returns true. If items are found,
      # attempts to clean the anvil using the appropriate method (drag or manual
      # removal), and recursively checks until clean.
      #
      # @return [Boolean] true if the anvil is clean or can be cleaned, false if the
      #   anvil cannot be found or items belong to another player
      # @note May spend roundtime on cleaning actions
      # @see find_anvil
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

      # Locates and navigates to an empty spinning wheel for tailoring in the given town.
      #
      # Searches through the town's configured spinning wheel locations for an empty
      # room and navigates there.
      #
      # @param hometown [String] the town name
      # @return [void]
      # @note Performs room navigation
      # @see find_sewing_room
      # @see find_loom_room
      def find_wheel(hometown)
        wheels = get_data('crafting')['tailoring'][hometown]['spinning-rooms']
        idle_room = get_data('crafting')['tailoring'][hometown]['idle-room']
        DRCT.find_sorted_empty_room(wheels, idle_room)
      end

      # Locates an empty anvil suitable for blacksmithing in the given town.
      #
      # First attempts to use the current anvil if one can be tapped, is clean, and
      # no other players are present. If that fails, searches through the town's
      # configured anvil locations for one that meets the criteria, then verifies
      # the crucible is also empty before returning.
      #
      # @param hometown [String] the town name
      # @return [void]
      # @note Performs room navigation and cleanup as needed
      # @see clean_anvil?
      # @see empty_crucible?
      def find_anvil(hometown)
        return if DRC.bput('tap anvil', TAP_ANVIL_NOT_FOUND, TAP_ANVIL_SUCCESS) =~ TAP_ANVIL_SUCCESS && (DRRoom.pcs - DRRoom.group_members).empty? && clean_anvil?

        anvils = get_data('crafting')['blacksmithing'][hometown]['anvils']
        idle_room = get_data('crafting')['blacksmithing'][hometown]['idle-room']
        DRCT.find_sorted_empty_room(anvils, idle_room, proc { (DRRoom.pcs - DRRoom.group_members).empty? && clean_anvil? })
        DRCC.empty_crucible?
      end

      # Locates and navigates to a grindstone for blacksmithing in the given town.
      #
      # If no grindstone can be tapped at the current location, searches through
      # the town's configured grindstone locations and navigates to an empty one.
      #
      # @param hometown [String] the town name
      # @return [void]
      # @note Performs room navigation
      # @see find_press_grinder_room
      def find_grindstone(hometown)
        return unless DRC.bput('tap grindstone', TAP_GRINDSTONE_NOT_FOUND, TAP_GRINDSTONE_SUCCESS) == TAP_GRINDSTONE_NOT_FOUND

        grindstones = get_data('crafting')['blacksmithing'][hometown]['grindstones']
        idle_room = get_data('crafting')['blacksmithing'][hometown]['idle-room']
        DRCT.find_sorted_empty_room(grindstones, idle_room)
      end

      # Locates and navigates to a sewing room for tailoring in the given town.
      #
      # If an override room ID is provided, navigates directly there. Otherwise,
      # searches through the town's configured sewing room locations for an empty
      # room and navigates there.
      #
      # @param hometown [String] the town name
      # @param override [Integer, nil] optional room ID to navigate to instead of searching
      # @return [void]
      # @note Performs room navigation
      # @see find_loom_room
      # @see find_shaping_room
      def find_sewing_room(hometown, override = nil)
        if override
          DRCT.walk_to(override)
        else
          sewingrooms = get_data('crafting')['tailoring'][hometown]['sewing-rooms']
          idle_room = get_data('crafting')['tailoring'][hometown]['idle-room']
          DRCT.find_sorted_empty_room(sewingrooms, idle_room)
        end
      end

      # Locates and navigates to a loom room for tailoring in the given town.
      #
      # If an override room ID is provided, navigates directly there. Otherwise,
      # searches through the town's configured loom room locations for an empty room
      # and navigates there.
      #
      # @param hometown [String] the town name
      # @param override [Integer, nil] optional room ID to navigate to instead of searching
      # @return [void]
      # @note Performs room navigation
      # @see find_sewing_room
      def find_loom_room(hometown, override = nil)
        if override
          DRCT.walk_to(override)
        else
          loom_rooms = get_data('crafting')['tailoring'][hometown]['loom-rooms']
          idle_room = get_data('crafting')['tailoring'][hometown]['idle-room']
          DRCT.find_sorted_empty_room(loom_rooms, idle_room)
        end
      end

      # Locates and navigates to a shaping room for alchemy/shaping in the given town.
      #
      # If an override room ID is provided, navigates directly there. Otherwise,
      # searches through the town's configured shaping room locations for an empty
      # room and navigates there.
      #
      # @param hometown [String] the town name
      # @param override [Integer, nil] optional room ID to navigate to instead of searching
      # @return [void]
      # @note Performs room navigation
      # @see find_press_grinder_room
      def find_shaping_room(hometown, override = nil)
        if override
          DRCT.walk_to(override)
        else
          shapingrooms = get_data('crafting')['shaping'][hometown]['shaping-rooms']
          idle_room = get_data('crafting')['shaping'][hometown]['idle-room']
          DRCT.find_sorted_empty_room(shapingrooms, idle_room)
        end
      end

      # Locates and navigates to a press-grinder room for alchemy remedies in the given town.
      #
      # If no grinder can be tapped at the current location, navigates to the first
      # configured press-grinder room in the town.
      #
      # @param hometown [String] the town name
      # @return [void]
      # @note Performs room navigation
      # @see find_grindstone
      def find_press_grinder_room(hometown)
        return unless DRC.bput('tap grinder', TAP_GRINDER_NOT_FOUND, TAP_GRINDER_SUCCESS) == TAP_GRINDER_NOT_FOUND

        pressgrinderrooms = get_data('crafting')['remedies'][hometown]['press-grinder-rooms']
        DRCT.walk_to(pressgrinderrooms[0])
      end

      # Locates and navigates to an enchanting room for artificing in the given town.
      #
      # If an override room ID is provided, navigates directly there. Otherwise,
      # searches through the town's configured brazier room locations for an empty
      # clean room (no other players present, brazier is clean) and navigates there.
      #
      # @param hometown [String] the town name
      # @param override [Integer, nil] optional room ID to navigate to instead of searching
      # @return [void]
      # @note Performs room navigation and cleanup as needed
      # @see clean_brazier?
      def find_enchanting_room(hometown, override = nil)
        if override
          DRCT.walk_to(override)
        else
          enchanting_rooms = get_data('crafting')['artificing'][hometown]['brazier-rooms']
          idle_room = get_data('crafting')['artificing'][hometown]['idle-room']
          DRCT.find_sorted_empty_room(enchanting_rooms, idle_room, proc { (DRRoom.pcs - DRRoom.group_members).empty? && clean_brazier? })
        end
      end

      # Searches recipes for one matching the given item name.
      #
      # Attempts a case-insensitive regex match first. If exactly one recipe matches,
      # returns it. If zero or multiple matches are found (and no exact match), prompts
      # the user to select from the list. Returns nil if no recipes match.
      #
      # @param recipes [Array<Hash>] array of recipe hashes from base-recipes.yaml
      # @param item_name [String] the item name to search for
      # @return [Hash, nil] the matching recipe hash, or nil if no match or user selection fails
      # @example
      #   recipes = get_data('recipes').crafting_recipes('armorsmithing')
      #   recipe = DRCC.recipe_lookup(recipes, "cap")
      # @note Displays user prompts and beeps on failure
      # @see find_recipe
      # @see find_recipe2
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

      # Finds and reads a recipe in a crafting reference book (older format).
      #
      # Turns the book to the specified chapter, then reads the page contents and
      # searches for the match string. Returns the page number on which the recipe
      # was found, or nil if not found. If the character is engaged in combat, prints
      # a warning and attempts to exit.
      #
      # @param chapter [Integer] the chapter number to turn to
      # @param match_string [String] the recipe name or pattern to search for
      # @param book [String] the book noun (default: "book")
      # @return [String, nil] the page number as a string, or nil if not found
      # @example
      #   page = DRCC.find_recipe(3, "metal cap", "book")
      # @note Handles combat engagement gracefully
      # @see find_recipe2
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

      # Finds and studies a recipe in a crafting reference book (newer format).
      #
      # Optionally turns the book to a discipline section, then turns to the specified
      # chapter and reads to find the recipe. Upon finding the recipe, extracts the
      # page number, turns to that page, and studies the book. Returns nil on completion.
      # If the character is engaged in combat, prints a warning and attempts to exit.
      #
      # @param chapter [Integer] the chapter number to turn to
      # @param match_string [String] the recipe name or pattern to search for
      # @param book [String] the book noun (default: "book")
      # @param discipline [String, nil] optional discipline section name to turn to first
      # @return [void]
      # @example
      #   DRCC.find_recipe2(3, "metal cap", "book", "Armorsmithing")
      # @note Handles combat engagement gracefully and generates roundtime
      # @see find_recipe
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

      # Acquires a crafting item, handling various storage and retrieval scenarios.
      #
      # First attempts to retrieve from a belt if configured and the item is listed
      # there. Falls back to retrieving from a bag or from general inventory. Handles
      # cases where the item is tied, too heavy to pick up easily, or missing. If
      # wounded, invokes the safe-room script before retrying. Returns nil if the item
      # cannot be found and skip_exit is false (default behavior exits the calling script).
      #
      # @param name [String] the item noun
      # @param bag [String, nil] the bag noun, or nil to skip bag retrieval
      # @param bag_items [Array<String>, nil] list of item nouns to check for in the bag
      # @param belt [Hash, nil] belt hash with 'name' and 'items' keys, or nil to skip belt
      # @param skip_exit [Boolean] if true, returns nil silently when item is not found;
      #   if false (default), stops the script
      # @return [void]
      # @note Generates roundtime and may perform room navigation
      # @example
      #   DRCC.get_crafting_item("tongs", "bag", ["tongs", "oil"], {"name" => "belt", "items" => ["tongs"]})
      # @see stow_crafting_item
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
      #
      # First checks whether the item should be attached to the belt. If so, attempts
      # to tie it there. If not (or if belt is nil), puts the item into the specified
      # bag. Falls back to the general stow command if the item is too large for the
      # bag. Returns nil if a belt-tie fails (with an error message), true on success.
      #
      # @param name [String, nil] the item noun, or nil to return early
      # @param bag [String] the bag noun
      # @param belt [Hash, nil] belt hash with 'name' and 'items' keys, or nil to skip belt
      # @return [Boolean, nil] true on success, nil if name is falsy, or false if
      #   put fails in an unexpected way
      # @note Generates roundtime
      # @example
      #   DRCC.stow_crafting_item("tongs", "bag", {"name" => "belt", "items" => ["tongs"]})
      # @see get_crafting_item
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

      # Calculates the total copper cost to craft items based on recipe, materials, and parts.
      #
      # Computes the cost of stock material (if applicable) and any purchasable parts,
      # then converts the total to the local currency. Non-purchasable parts (e.g.,
      # gems, found materials) are excluded. Adds a fixed 1000 copper surcharge for
      # consumables (water, coal, etc.).
      #
      # @param recipe [Hash] recipe hash from base-recipes.yaml, e.g.
      #   {"name" => "a metal cap", "noun" => "cap", "volume" => 8, "type" => "armorsmithing", ...}
      # @param hometown [String] the town name (e.g., "Crossing")
      # @param parts [Array<String>, nil] list of part names required, or nil/false
      # @param quantity [Integer] number of items to craft
      # @param material [Hash, nil] stock material hash from base-crafting, e.g.
      #   {"stock-volume" => 5, "stock-number" => 11, "stock-name" => "bronze", "stock-value" => 562},
      #   or nil/false if using no stock material (e.g., alchemy, artificing)
      # @return [Integer] total copper cost, converted to local town currency
      # @example
      #   recipe = get_data('recipes').crafting_recipes('armorsmithing')["a metal cap"]
      #   material = get_data('crafting')['stock']["bronze"]
      #   cost = DRCC.crafting_cost(recipe, "Crossing", ["sufil", "muljin"], 5, material)
      # @see PARTS_CANNOT_PURCHASE
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

      # Repairs one or more crafting tools using wire brush and oil.
      #
      # Maintains an immune list of tools recently repaired successfully (7000-second
      # cooldown per Proper Forging Tool Care). For each eligible tool, retrieves it,
      # then iterates through wire brush and oil, applying each in sequence until the
      # tool no longer needs repair. Handles cases where tools are too heavy, wounds
      # prevent repair, or combatant engagement. Restocks consumables as needed.
      #
      # @param info [Hash] location info with 'finisher-room', 'finisher-number', and
      #   optional 'wire-brush-number' (default 10)
      # @param tools [String, Array<String>] tool noun(s) to repair
      # @param bag [String] the bag noun for storing items
      # @param bag_items [Array<String>] list of item nouns in the bag
      # @param belt [Hash, nil] belt hash with 'name' and 'items' keys
      # @return [void]
      # @note Uses UserVars.immune_list and Flags['proper-repair'] for state tracking;
      #   generates significant roundtime
      # @example
      #   info = { "finisher-room" => 5678, "finisher-number" => 9, "wire-brush-number" => 10 }
      #   DRCC.repair_own_tools(info, ["tongs", "tongs"], "bag", ["oil", "wire brush"], belt)
      # @see check_consumables
      # @see get_crafting_item
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

      # Checks the remaining uses on a consumable item and restocks if necessary.
      #
      # Attempts to retrieve the consumable from the bag and count its uses. If the
      # use count is below the required threshold, disposes of the current item,
      # navigates to the stock room, orders a replacement, and verifies the restock.
      # Finally, returns to the original room and stows the item.
      #
      # @param name [String] the consumable item noun (e.g., "oil", "wire brush")
      # @param room [Integer] the stock/shop room ID
      # @param number [Integer] the shop NPC number to order from
      # @param bag [String] the bag noun
      # @param bag_items [Array<String>] list of item nouns in the bag
      # @param belt [Hash, nil] belt hash, or nil to skip belt handling
      # @param count [Integer] minimum required uses (default: 3)
      # @return [void]
      # @note Performs room navigation and generates roundtime during ordering
      # @example
      #   DRCC.check_consumables("oil", 5678, 3, "bag", ["oil", "brush"], belt, 5)
      # @see get_crafting_item
      # @see repair_own_tools
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

      # Acquires and adjusts tongs to the requested configuration (tongs or shovel mode).
      #
      # Manages tongs state via @tongs_status instance variable. Supports two primary
      # use cases ('tongs' and 'shovel') plus two reset modes ('reset tongs' and
      # 'reset shovel') to determine initial state. Returns false if the tongs are not
      # adjustable but a different configuration is needed. Returns true when tongs are
      # in the requested state and in hand. If wounds prevent adjustment, calls safe-room
      # and retries. Non-adjustable tongs are always usable in their fixed mode.
      #
      # @param usage [String] the desired configuration: 'tongs', 'shovel', 'reset tongs',
      #   or 'reset shovel'
      # @param bag [String] the bag noun
      # @param bag_items [Array<String>] list of item nouns in the bag
      # @param belt [Hash, nil] belt hash, or nil to skip belt handling
      # @param adjustable_tongs [Boolean] whether the tongs support adjustment
      #   (default: false)
      # @return [Boolean] true if tongs are in the requested state and ready, false if
      #   the request cannot be fulfilled
      # @note Generates roundtime and may perform room navigation on wound handling
      # @example
      #   DRCC.get_adjust_tongs?("shovel", "bag", ["tongs"], belt, true)
      # @see get_crafting_item
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

      # Bundles a crafted item with a work-order logbook and disposes of it on failure.
      #
      # Retrieves the specified logbook, attempts to bundle the item with it. If the
      # bundle succeeds or fails due to expired/low-quality/wrong-type work orders,
      # disposes of the item. If the bundle fails because the item is not held,
      # attempts to retrieve the item from the container and retry. Finally, stows or
      # disposes of the logbook.
      #
      # @param logbook [String] the logbook type noun (e.g., "armorsmith", "weaponsmith")
      # @param noun [String] the crafted item noun
      # @param container [String] the container noun to retrieve items from if needed
      # @return [void]
      # @note Generates roundtime
      # @example
      #   DRCC.logbook_item("armorsmith", "cap", "bag")
      # @see DRCI.get_item?
      # @see DRCI.dispose_trash
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

      # Orders enchanting materials (sigil-scrolls, founts, etc.) from a shop.
      #
      # Iterates the specified number of times, ordering one item per iteration and
      # stowing the result into the bag or belt. Stops if both hands become full.
      #
      # @param stock_room [Integer] the shop room ID
      # @param stock_needed [Integer] the number of items to order
      # @param stock_number [Integer] the shop NPC number
      # @param bag [String] the bag noun
      # @param belt [Hash, nil] belt hash with 'name' and 'items' keys
      # @return [void]
      # @note Performs room navigation and generates roundtime during ordering
      # @example
      #   DRCC.order_enchant(1234, 5, 2, "bag", belt)
      # @see fount
      # @see check_for_existing_sigil?
      def order_enchant(stock_room, stock_needed, stock_number, bag, belt)
        stock_needed.times do
          DRCT.order_item(stock_room, stock_number)
          stow_crafting_item(DRC.left_hand, bag, belt)
          stow_crafting_item(DRC.right_hand, bag, belt)
          next unless DRC.left_hand && DRC.right_hand
        end
      end

      # Acquires and maintains a fount (crafting tool for artificing).
      #
      # Checks the fount's remaining uses. If uses are insufficient for the requested
      # quantity, disposes of the fount and orders replacements. Attempts to tap the
      # fount in the bag or on a brazier and analyzes the uses. Handles both locations
      # (bag and brazier) gracefully.
      #
      # @param stock_room [Integer] the shop room ID
      # @param stock_needed [Integer] the number of replacement founts to order if needed
      # @param stock_number [Integer] the shop NPC number
      # @param quantity [Integer] the number of uses required
      # @param bag [String] the bag noun
      # @param bag_items [Array<String>] list of item nouns in the bag
      # @param belt [Hash, nil] belt hash, or nil to skip belt handling
      # @return [void]
      # @note Performs room navigation and generates roundtime during ordering
      # @example
      #   DRCC.fount(1234, 3, 2, 10, "bag", ["fount"], belt)
      # @see order_enchant
      # @see FOUNT_ANALYZE_PATTERN
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

      # Checks whether the current brazier is clean, removing any items found.
      #
      # Looks on the brazier. If clean, returns true. If items are found, prepares
      # to clean and executes the clean command (handling flame hazards), then empties
      # any remaining items and returns true.
      #
      # @return [Boolean] true if the brazier is clean or has been cleaned, false only
      #   in edge cases
      # @note May generate roundtime and trigger hazardous flame responses
      # @see empty_brazier
      # @see find_enchanting_room
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

      # Removes and disposes of all items currently on a brazier.
      #
      # Looks on the brazier, parses the item list, and removes each item one by one,
      # disposing of each in sequence.
      #
      # @return [void]
      # @note Generates roundtime during item retrieval and disposal
      # @example
      #   DRCC.empty_brazier
      # @see clean_brazier?
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

      # Checks inventory for sigil-scrolls and orders replacements if needed.
      #
      # Counts existing sigil-scrolls in the bag. If the count meets or exceeds the
      # required quantity, returns true immediately. Otherwise, checks whether the
      # sigil is a known type (primary or secondary). If known but insufficient in
      # quantity, calculates the shortfall and orders replacements. If the sigil type
      # is unknown, prints a message about manual harvesting and returns false.
      #
      # @param sigil [String] the sigil type name (e.g., "water", "fire")
      # @param stock_number [Integer] the shop NPC number
      # @param quantity [Integer] the required number of sigil-scrolls
      # @param bag [String] the bag noun
      # @param belt [Hash, nil] belt hash, or nil to skip belt handling
      # @param info [Hash] location info with 'stock-room' key
      # @return [Boolean] true if the required quantity is available or has been
      #   ordered, false if the sigil type is unknown
      # @note Performs room navigation and generates roundtime if ordering is needed
      # @example
      #   have_sigils = DRCC.check_for_existing_sigil?("water", 2, 5, "bag", belt, info)
      # @see order_enchant
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

      # Rummages through a container and counts raw metal inventory by type.
      #
      # Uses the rummage command to search a container for metals. Parses the response
      # and aggregates metals by type, calculating total volume and piece count.
      # Handles container-not-found, closed-container, invisibility, and no-materials
      # cases. Prints a summary message for each metal type found.
      #
      # @param container [String] the container noun
      # @param type [String, nil] optional specific metal type to return; if nil,
      #   returns a hash of all metals
      # @return [Hash, String, nil] if type is nil, returns a hash like
      #   {"bronze" => [15, 3], "iron" => [10, 2]} (volume and piece count per metal);
      #   if type is specified, returns that metal's [volume, count] array or nil;
      #   returns nil on error (closed, not found, invisible, etc.)
      # @note Prints messaging to the character and generates roundtime
      # @example
      #   all_metals = DRCC.count_raw_metal("bin")
      #   bronze_only = DRCC.count_raw_metal("bin", "bronze")
      # @see RUMMAGE_SUCCESS_PATTERN
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

      # Creates multiple mechanisms via the shaping press.
      #
      # Navigates to a shaping room, sets the press to the specified speed, then
      # iterates to create the requested number of mechanisms. For each mechanism,
      # retrieves an ingot, pushes fuel, presses the ingot, pulls the result with
      # the press, and stows the completed mechanism. Combines mechanisms if holding
      # multiple. Returns any remaining ingots to storage.
      #
      # @param settings [OpenStruct] the character settings object with
      #   .hometown, .crafting_container, .crafting_items_in_container, .forging_belt
      # @param material [String] the metal type for ingots (e.g., "bronze", "steel")
      # @param number [Integer] the quantity of mechanisms to create
      # @param speed [Integer] the press speed 1-12 (default: 6)
      # @return [void]
      # @note Performs room navigation and generates significant roundtime
      # @example
      #   DRCC.create_mechanisms(settings, "steel", 10, 8)
      # @see find_shaping_room
      # @see get_crafting_item
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

      # --- Private forge helpers ---------------------------------------------
      # Shared settings resolution and navigation for the blacksmithing private
      # forge, so smith / forge / makesteel behave identically. Callers should
      # prefer these over inlining the logic.

      # Default copper reserved to rent/enter a private forge when the
      # forge_private_forge_cost setting is unset.
      DEFAULT_PRIVATE_FORGE_COST = 50_000

      # Patterns for entering a private forge through its door/sentry.
      PRIVATE_FORGE_ENTRY_SUCCESS = ['You head through', 'You walk', 'You go', 'Obvious exits'].freeze
      PRIVATE_FORGE_ENTRY_BLOCKED = ["You don't have enough", 'The sentry blocks', 'cannot enter', 'You need to pay'].freeze

      # Resolve the town a crafter should work in: the crafting-specific override
      # if set, otherwise their hometown. Mirrors the convention used by every
      # crafting script.
      #
      # @param settings the character settings object
      # @return [String] the town name
      def crafting_hometown(settings)
        settings.force_crafting_town || settings.hometown
      end

      # Whether the character wants to use a private forge. Accepts the legacy
      # forge-only setting name for backward compatibility.
      #
      # @param settings the character settings object
      # @return [Boolean]
      def use_private_forge?(settings)
        settings.use_private_forge || settings.forge_use_private_forge || false
      end

      # Copper to reserve for private forge rental/entry.
      #
      # @param settings the character settings object
      # @return [Integer]
      def private_forge_cost(settings)
        settings.forge_private_forge_cost || DEFAULT_PRIVATE_FORGE_COST
      end

      # The room id of a town's private forge, or nil when it has none.
      #
      # @param hometown [String]
      # @return [Integer, nil]
      def private_forge_room(hometown)
        get_data('crafting')['blacksmithing'][hometown]['private_forge']
      end

      # Blacksmithing towns that define a private forge.
      #
      # @return [Array<String>]
      def towns_with_private_forge
        get_data('crafting')['blacksmithing'].select { |_town, data| data['private_forge'] }.keys
      end

      # Ensure funds and navigate into the town's private forge.
      #
      # @param hometown [String]
      # @param settings the character settings object
      # @return [Boolean] true if we ended up in the private forge, false when the
      #   town has no private forge, funds could not be secured, or entry was blocked.
      def go_to_private_forge(hometown, settings)
        room = private_forge_room(hometown)
        return false unless room
        return false unless DRCM.ensure_copper_on_hand(private_forge_cost(settings), settings, hometown)

        DRCT.walk_to(room)
        return true if Room.current.id == room

        # Not in the room yet -- try to enter through the door/sentry.
        DRC.bput('go door', *PRIVATE_FORGE_ENTRY_SUCCESS, *PRIVATE_FORGE_ENTRY_BLOCKED, 'What were you')
        Room.current.id == room
      end
    end
  end
end
