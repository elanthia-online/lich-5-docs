# frozen_string_literal: true

# Namespace for the Lich 5 scripting engine for GemStone IV and DragonRealms.
module Lich
  # Namespace for DragonRealms-specific scripting utilities.
  module DragonRealms
    # DragonRealms Common Crafting module: shared patterns, methods, and helpers for all crafting scripts.
    #
    # This module contains response pattern constants matched by bput, recipe finding and lookup
    # utilities, crafting item management (getting/stowing with support for belts and bags),
    # cost calculations, consumable tracking, and helpers for specific crafts like forging,
    # artificing, blacksmithing, shaping, and remedies.
    module DRCC
      module_function

      # Pattern constants for bput responses
      LOOK_CRUCIBLE_NOT_FOUND = '^I could not find'
      LOOK_CRUCIBLE_EMPTY = '^There is nothing in there'
      # Matches a crucible look result with items present.
      #
      # Captures the full items list in the named group 'items'; splitting by
      # LOOK_CRUCIBLE_ITEM_SEPARATOR then separates individual entries.
      #
      # @return [Regexp]
      # @example
      #   "In the iron crucible you see molten gold and some ash." =~ LOOK_CRUCIBLE_SEE_PATTERN
      #   => 0
      # @see LOOK_CRUCIBLE_ITEM_SEPARATOR
      # @see LOOK_CRUCIBLE_MOLTEN
      LOOK_CRUCIBLE_SEE_PATTERN = /^In the .* crucible you see (?<items>.*)\./.freeze
      # Splits the LOOK_CRUCIBLE_SEE_PATTERN items list into entries at ", ",
      # ", and " or " and " followed by an article or a bare "molten ", keeping
      # that word. The " and " must be a whole word, so "a gold wand and ..."
      # is not cut.
      LOOK_CRUCIBLE_ITEM_SEPARATOR = /(?:,\s+(?:and\s+)?|\s+and\s+)(?=(?:some|an?|molten)\s)/.freeze
      # Matches one entry of the LOOK_CRUCIBLE_SEE_PATTERN items list.
      LOOK_CRUCIBLE_MOLTEN = /\A(?:(?:some|an?)\s+)?molten\s/.freeze
      EMPTY_CRUCIBLE_MAX_PASSES = 3

      LOOK_ANVIL_NOT_FOUND = '^I could not find'
      LOOK_ANVIL_CLEAN = 'surface looks clean and ready'
      # Matches an anvil look result with items present.
      #
      # Captures the items list in the named group 'items'.
      #
      # @return [Regexp]
      # @example
      #   "On the workstation anvil you see a bronze bar." =~ LOOK_ANVIL_SEE_PATTERN
      #   => 5
      LOOK_ANVIL_SEE_PATTERN = /anvil you see (?<items>.*)\./.freeze

      CLEAN_ANVIL_DRAG = 'You drag the'
      CLEAN_ANVIL_REMOVE = 'remove them yourself'
      GET_ANVIL_SUCCESS = 'You get'
      GET_ANVIL_NOT_YOURS = 'is not yours'
      PUT_BUCKET_SUCCESS = 'You drop'

      BOOK_CHAPTER_TURN_SUCCESS = 'You turn'
      # Matches the reply when too distracted (e.g., engaged in combat) to turn a book chapter.
      #
      # @return [String]
      BOOK_CHAPTER_DISTRACTED = 'You are too distracted to be doing that right now'
      BOOK_CHAPTER_ALREADY = 'The .* is already turned'
      # Matches successful chapter turn on a book or reference (newer books).
      #
      # @return [Regexp]
      # @example
      #   "You turn your tinkering manual to chapter 3."
      BOOK_CHAPTER2_SUCCESS = /^You turn your .* to chapter/
      # Matches the reply when a book/reference is already at the target chapter.
      #
      # @return [Regexp]
      # @example
      #   "The tinkering manual is already turned to chapter 3."
      BOOK_CHAPTER2_ALREADY = /^The .* is already turned to chapter/
      # Matches successful page turn on a book.
      #
      # @return [Regexp]
      # @example
      #   "You turn your book to page 42."
      BOOK_PAGE_SUCCESS = /^You turn your .* to page/
      # Matches the reply when already on the target page of a book.
      #
      # @return [Regexp]
      # @example
      #   "You are already on page 42."
      BOOK_PAGE_ALREADY = /^You are already on page/
      # Matches successful discipline selection on a reference manual.
      #
      # @return [Regexp]
      # @example
      #   "You turn the remedies manual to the section on herbalism."
      BOOK_DISCIPLINE_SUCCESS = /^You turn the .* to the section on/
      # Matches successful study action (indicates roundtime).
      #
      # @return [Regexp]
      BOOK_STUDY_SUCCESS = /^Roundtime/

      # Matches successful untie/removal of a crafting item from the belt.
      #
      # @return [Regexp]
      # @example
      #   "You untie your tongs from your forging belt."
      BELT_UNTIE_SUCCESS = /^You (remove|untie)/
      # Matches the reply when the item is already untied or not worn on belt.
      #
      # @return [Regexp]
      # @example
      #   "You are already holding a tongs in your right hand."
      BELT_UNTIE_ALREADY = /^You are already/
      # Matches the reply when the item is not found on the belt.
      #
      # @return [Regexp]
      # @example
      #   "Untie what?"
      BELT_UNTIE_NOT_FOUND = /^Untie what/
      # Matches the reply when wounds prevent untying from the belt.
      #
      # @return [Regexp]
      # @example
      #   "Your wounds hinder your ability to do that."
      BELT_UNTIE_WOUNDED = /^Your wounds hinder your ability to do that/

      # Matches successful acquisition of a crafting item.
      #
      # @return [Regexp]
      # @example
      #   "You get a tongs from inside your bag."
      GET_CRAFTING_SUCCESS = /^You get/
      # Matches the reply when the item is already in hand.
      #
      # @return [Regexp]
      # @example
      #   "You are already holding a tongs."
      GET_CRAFTING_ALREADY = /^You are already/
      # Matches the query when the item is not found and noun is ambiguous.
      #
      # @return [Regexp]
      # @example
      #   "What do you want to get?"
      GET_CRAFTING_NOT_FOUND_WHAT = /^What do you/
      # Matches the query when the item is not found (you were referring to).
      #
      # @return [Regexp]
      # @example
      #   "What were you referring to?"
      GET_CRAFTING_NOT_FOUND_WERE = /^What were you/
      # Matches successful pickup of a crafting item (alternative to 'You get').
      #
      # @return [Regexp]
      # @example
      #   "You pick up a tongs."
      GET_CRAFTING_PICKUP = /^You pick up/
      # Matches the reply when an item is too heavy to carry.
      #
      # @return [Regexp]
      # @example
      #   "You can't quite lift it."
      GET_CRAFTING_HEAVY = /can't quite lift it/
      # Matches the reply when the item must be untied before getting it.
      #
      # @return [Regexp]
      # @example
      #   "You should untie that from your belt first."
      GET_CRAFTING_TIED = /^You should untie/

      # Matches successful untie/removal of a general item.
      #
      # @return [Regexp]
      # @example
      #   "You untie the rope."
      UNTIE_SUCCESS = /^You (remove|untie)/
      # Matches the reply when the item to untie is not found.
      #
      # @return [Regexp]
      # @example
      #   "Untie what?"
      UNTIE_NOT_FOUND = /^Untie what/
      # Matches the reply when wounds prevent untying.
      #
      # @return [Regexp]
      # @example
      #   "Your wounds hinder your ability to do that."
      UNTIE_WOUNDED = /^Your wounds hinder your ability to do that/

      # Matches the reply when wounds prevent tying to belt; aliased from UNTIE_WOUNDED.
      #
      # @return [Regexp]
      # @see UNTIE_WOUNDED
      TIE_BELT_WOUNDED = UNTIE_WOUNDED

      PUT_BAG_TUCK = 'You tuck'
      PUT_BAG_PUT = 'You put your'
      PUT_BAG_NOT_FOUND = 'What were you referring to'
      # Matches the reply when an item is too large to fit in a bag.
      #
      # @return [Regexp]
      # @example
      #   "That item is too large to fit in your bag."
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
      # Extracts a numeric count from consumable-usage messages.
      #
      # Captures a number from any string; used with COUNT_USES_MESSAGES patterns
      # to extract remaining uses from tools or yards of material.
      #
      # @return [Regexp]
      # @see COUNT_USES_MESSAGES
      COUNT_USES_PATTERN = /(\d+)/.freeze
      # Array of patterns for extracting consumable uses or material quantities.
      #
      # Each pattern captures the numeric value in group 1, paired with COUNT_USES_PATTERN.
      # Supports both tools with remaining uses and materials measured in yards.
      #
      # @return [Array<String>]
      # @see COUNT_USES_PATTERN
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
      # Matches the reply when bundled items fail quality requirements.
      #
      # @return [String]
      BUNDLE_QUALITY = 'The work order requires items of a higher quality'
      # Matches the reply when a bundled item does not match the work order type.
      #
      # @return [String]
      BUNDLE_WRONG_TYPE = "That isn't the correct type of item for this work order."
      BUNDLE_NOT_HOLDING = 'You need to be holding'

      # Matches successful tap of a fount tool while inside a bag.
      #
      # @return [Regexp]
      # @example
      #   "You tap the enchanting fount inside your bag."
      FOUNT_TAP_IN_BAG = /You tap .* inside your .*/
      # Matches successful tap of a fount tool on a bag.
      #
      # @return [Regexp]
      # @example
      #   "You tap the enchanting fount on your bag."
      FOUNT_TAP_ON_BAG = /You tap .*your .*/
      # Matches the reply when a fount is not found.
      #
      # @return [Regexp]
      # @example
      #   "I could not find what you were referring to."
      FOUNT_TAP_NOT_FOUND = /I could not find what you were referring to./
      # Matches successful tap of a fount tool on a brazier.
      #
      # @return [Regexp]
      # @example
      #   "You tap the enchanting fount atop a small bronze brazier."
      FOUNT_TAP_ON_BRAZIER = /You tap .* atop a .*brazier./
      # Matches fount analysis result and extracts remaining uses.
      #
      # Captures the numeric uses count in the named group 'uses'.
      #
      # @return [Regexp]
      # @example
      #   "This appears to be a crafting tool and it has approximately 42 uses remaining."
      FOUNT_ANALYZE_PATTERN = /This appears to be a crafting tool and it has approximately (?<uses>\d+) uses remaining/.freeze

      BRAZIER_NOTHING = 'There is nothing on there'
      # Matches a brazier look result with items present.
      #
      # Captures the items list in the named group 'items'; entries are split on ' and '.
      #
      # @return [Regexp]
      # @example
      #   "On the small bronze brazier you see a glowing sigil and some ash."
      BRAZIER_SEE_PATTERN = /On the (?:.*)brazier you see (?<items>.*)\./.freeze
      BRAZIER_CLEAN_PREPARE = 'You prepare to clean off the brazier'
      BRAZIER_CLEAN_NOTHING = 'There is nothing'
      BRAZIER_CLEAN_NOT_LIT = 'The brazier is not currently lit'
      # Matches the reply when cleaning a lit brazier triggers a flame burst.
      #
      # @return [String]
      BRAZIER_CLEAN_FLAME = 'a massive ball of flame jets forward and singes everything nearby'
      BRAZIER_GET_SUCCESS = 'You get'

      # Matches the reply when rummaging for crafting materials finds none.
      #
      # @return [Regexp]
      # @example
      #   "You look through the materials container looking for crafting materials but there is nothing in there like that."
      RUMMAGE_NOTHING = /crafting materials but there is nothing in there like that\.$/
      # Matches the reply when rummaging in a closed container.
      #
      # @return [Regexp]
      # @example
      #   "While it's closed, you can't rummage through it."
      RUMMAGE_CLOSED = /While it\'s closed/
      # Matches the reply when the container is not found.
      #
      # @return [Regexp]
      # @example
      #   "I don't know what you are referring to."
      RUMMAGE_NOT_FOUND = /I don\'t know what you are referring to/
      # Matches the reply when invisible and unable to rummage.
      #
      # @return [Regexp]
      # @example
      #   "You feel about blindly for items."
      RUMMAGE_INVISIBLE = /You feel about/
      # Matches the reply when rummaging would accomplish nothing (no such item type).
      #
      # @return [Regexp]
      # @example
      #   "That would accomplish nothing."
      RUMMAGE_NOTHING_ACCOMPLISH = /That would accomplish nothing/
      # Matches successful rummage with material list captured.
      #
      # Captures the raw materials list in the named group 'materials'; entries are
      # separated by ' and ' and use format like 'X <size> <metal>'.
      #
      # @return [Regexp]
      # @example
      #   "You look through the container looking for crafting materials and see 3 large bronze, 2 small iron and 1 medium steel."
      RUMMAGE_SUCCESS_PATTERN = /looking for crafting materials and see (?<materials>.*)\.$/

      TAP_CRUCIBLE_NOT_FOUND = 'I could not'
      # Matches successful tap of a crucible (indicates it exists nearby).
      #
      # @return [Regexp]
      # @example
      #   "You tap the iron crucible and listen intently."
      TAP_CRUCIBLE_SUCCESS = /You tap.*crucible/
      TAP_ANVIL_NOT_FOUND = 'I could not'
      # Matches successful tap of an anvil (indicates it exists nearby).
      #
      # @return [Regexp]
      # @example
      #   "You tap the workstation anvil and listen intently."
      TAP_ANVIL_SUCCESS = /You tap.*anvil/
      TAP_GRINDSTONE_NOT_FOUND = 'I could not'
      TAP_GRINDSTONE_SUCCESS = 'You tap.*grindstone'
      TAP_GRINDER_NOT_FOUND = 'I could not'
      TAP_GRINDER_SUCCESS = 'You tap.*grinder'

      SIGIL_COUNT_NOTHING = 'but there is nothing in there like that'

      # Tilts out molten metal and clears clutter, then looks again, up to
      # EMPTY_CRUCIBLE_MAX_PASSES times. Returns false if it is still not empty.
      # Molten metal is found wherever it appears in the list. Clutter is only
      # disposed of when it was actually picked up from the crucible, and
      # clutter whose noun matches something already in hand (DRCI.in_hands?
      # matches any held word starting with the noun) is left alone, so a held
      # item cannot stand in for clutter that was not picked up. Each held
      # noun is reported once per call, not once per entry or per pass.
      # pass: and warned: are internal recursion state -- callers should not
      # set them.
      def empty_crucible?(pass: 0, warned: [])
        case result = DRC.bput('look in cruc',
                               LOOK_CRUCIBLE_NOT_FOUND,
                               LOOK_CRUCIBLE_EMPTY,
                               LOOK_CRUCIBLE_SEE_PATTERN)
        when /There is nothing in there/i
          true
        when /I could not find/
          false
        when /crucible you see/
          if pass >= EMPTY_CRUCIBLE_MAX_PASSES
            Lich::Messaging.msg('bold', "DRCC: The crucible is still not empty after #{pass} attempts to tilt or clear it.")
            return false
          end

          match = result.match(LOOK_CRUCIBLE_SEE_PATTERN)
          return false unless match

          contents = match[:items]
                     .split(LOOK_CRUCIBLE_ITEM_SEPARATOR)
                     .map(&:strip)
          if contents.any? { |entry| entry.match?(LOOK_CRUCIBLE_MOLTEN) }
            fput('tilt crucible')
            fput('tilt crucible')
          else
            attempted = false
            contents.each do |junk|
              junk = DRC.get_noun(junk)
              next unless junk

              # get_item_unsafe and dispose_trash only check that the noun is in
              # hand, so a held matching item would be the one thrown away.
              if DRCI.in_hands?(junk)
                unless warned.include?(junk)
                  Lich::Messaging.msg('bold', "DRCC: Not clearing the #{junk} from the crucible while you are holding something that matches it.")
                  warned += [junk]
                end
                next
              end

              attempted = true
              # A failed GET leaves nothing in hand, and dispose_trash would
              # then fetch a same-noun item from the player's own containers.
              DRCI.dispose_trash(junk) if DRCI.get_item_unsafe(junk, 'crucible')
            end
            return false unless attempted
          end
          DRCC.empty_crucible?(pass: pass + 1, warned: warned)
        else
          false
        end
      end

      # Finds and navigates to an empty crucible in the specified hometown.
      #
      # Taps a crucible in the current room first; if found, empty, and unoccupied,
      # stays put. Otherwise, consults the crafting data and uses DRCT.find_sorted_empty_room
      # to locate an available crucible, then cleans the anvil when done.
      #
      # @param hometown [String] the crafting hometown (e.g., "Crossing")
      # @return [void]
      # @see #empty_crucible?
      # @see #clean_anvil?
      def find_empty_crucible(hometown)
        return if DRC.bput('tap crucible', TAP_CRUCIBLE_NOT_FOUND, TAP_CRUCIBLE_SUCCESS) =~ TAP_CRUCIBLE_SUCCESS && (DRRoom.pcs - DRRoom.group_members).empty? && empty_crucible?

        crucibles = get_data('crafting')['blacksmithing'][hometown]['crucibles']
        idle_room = get_data('crafting')['blacksmithing'][hometown]['idle-room']
        DRCT.find_sorted_empty_room(crucibles, idle_room, proc { (DRRoom.pcs - DRRoom.group_members).empty? && empty_crucible? })
        DRCC.clean_anvil?
      end

      # Checks if an anvil is clean and ready for use, or cleans it if cluttered.
      #
      # Looks at the anvil; if clean, returns true. If cluttered with one item,
      # attempts to clean it (dragging or manually removing items). Returns true
      # on success, false if the anvil is not found or the cleanup fails.
      #
      # @return [Boolean] true if the anvil is clean (or now clean), false otherwise
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

      # Navigates to an available spinning wheel for tailoring.
      #
      # Uses DRCT.find_sorted_empty_room to find an idle spinning-room from the
      # crafting data and walks there.
      #
      # @param hometown [String] the crafting hometown (e.g., "Crossing")
      # @return [void]
      def find_wheel(hometown)
        wheels = get_data('crafting')['tailoring'][hometown]['spinning-rooms']
        idle_room = get_data('crafting')['tailoring'][hometown]['idle-room']
        DRCT.find_sorted_empty_room(wheels, idle_room)
      end

      # Finds and navigates to an empty anvil in the specified hometown.
      #
      # Taps an anvil in the current room first; if found, empty, and unoccupied,
      # stays put. Otherwise, consults crafting data and uses DRCT.find_sorted_empty_room
      # to locate an available anvil, then checks if the crucible is empty when done.
      #
      # @param hometown [String] the crafting hometown (e.g., "Crossing")
      # @return [void]
      # @see #clean_anvil?
      # @see #empty_crucible?
      def find_anvil(hometown)
        return if DRC.bput('tap anvil', TAP_ANVIL_NOT_FOUND, TAP_ANVIL_SUCCESS) =~ TAP_ANVIL_SUCCESS && (DRRoom.pcs - DRRoom.group_members).empty? && clean_anvil?

        anvils = get_data('crafting')['blacksmithing'][hometown]['anvils']
        idle_room = get_data('crafting')['blacksmithing'][hometown]['idle-room']
        DRCT.find_sorted_empty_room(anvils, idle_room, proc { (DRRoom.pcs - DRRoom.group_members).empty? && clean_anvil? })
        DRCC.empty_crucible?
      end

      # Navigates to an available grindstone for blacksmithing.
      #
      # Taps to verify a grindstone is available in the current room; if not found,
      # uses crafting data to locate and walk to an idle grindstone.
      #
      # @param hometown [String] the crafting hometown (e.g., "Crossing")
      # @return [void]
      def find_grindstone(hometown)
        return unless DRC.bput('tap grindstone', TAP_GRINDSTONE_NOT_FOUND, TAP_GRINDSTONE_SUCCESS) == TAP_GRINDSTONE_NOT_FOUND

        grindstones = get_data('crafting')['blacksmithing'][hometown]['grindstones']
        idle_room = get_data('crafting')['blacksmithing'][hometown]['idle-room']
        DRCT.find_sorted_empty_room(grindstones, idle_room)
      end

      # Navigates to a sewing room, or to an override location if specified.
      #
      # When override is provided, walks directly there. Otherwise, uses crafting data
      # to find an idle sewing-room and navigates via DRCT.find_sorted_empty_room.
      #
      # @param hometown [String] the crafting hometown (e.g., "Crossing")
      # @param override [Integer, nil] optional room id to walk to instead
      # @return [void]
      def find_sewing_room(hometown, override = nil)
        if override
          DRCT.walk_to(override)
        else
          sewingrooms = get_data('crafting')['tailoring'][hometown]['sewing-rooms']
          idle_room = get_data('crafting')['tailoring'][hometown]['idle-room']
          DRCT.find_sorted_empty_room(sewingrooms, idle_room)
        end
      end

      # Navigates to a loom room, or to an override location if specified.
      #
      # When override is provided, walks directly there. Otherwise, uses crafting data
      # to find an idle loom-room and navigates via DRCT.find_sorted_empty_room.
      #
      # @param hometown [String] the crafting hometown (e.g., "Crossing")
      # @param override [Integer, nil] optional room id to walk to instead
      # @return [void]
      def find_loom_room(hometown, override = nil)
        if override
          DRCT.walk_to(override)
        else
          loom_rooms = get_data('crafting')['tailoring'][hometown]['loom-rooms']
          idle_room = get_data('crafting')['tailoring'][hometown]['idle-room']
          DRCT.find_sorted_empty_room(loom_rooms, idle_room)
        end
      end

      # Navigates to a shaping room, or to an override location if specified.
      #
      # When override is provided, walks directly there. Otherwise, uses crafting data
      # to find an idle shaping-room and navigates via DRCT.find_sorted_empty_room.
      #
      # @param hometown [String] the crafting hometown (e.g., "Crossing")
      # @param override [Integer, nil] optional room id to walk to instead
      # @return [void]
      def find_shaping_room(hometown, override = nil)
        if override
          DRCT.walk_to(override)
        else
          shapingrooms = get_data('crafting')['shaping'][hometown]['shaping-rooms']
          idle_room = get_data('crafting')['shaping'][hometown]['idle-room']
          DRCT.find_sorted_empty_room(shapingrooms, idle_room)
        end
      end

      # Navigates to a press-grinder room for remedy crafting.
      #
      # Taps to verify a grinder is available in the current room; if not found,
      # walks to the first press-grinder-room in the remedies crafting data.
      #
      # @param hometown [String] the crafting hometown (e.g., "Crossing")
      # @return [void]
      def find_press_grinder_room(hometown)
        return unless DRC.bput('tap grinder', TAP_GRINDER_NOT_FOUND, TAP_GRINDER_SUCCESS) == TAP_GRINDER_NOT_FOUND

        pressgrinderrooms = get_data('crafting')['remedies'][hometown]['press-grinder-rooms']
        DRCT.walk_to(pressgrinderrooms[0])
      end

      # Navigates to a brazier room for artificing, or to an override location if specified.
      #
      # When override is provided, walks directly there. Otherwise, uses crafting data
      # to find an idle brazier-room where the brazier is clean and unoccupied,
      # via DRCT.find_sorted_empty_room.
      #
      # @param hometown [String] the crafting hometown (e.g., "Crossing")
      # @param override [Integer, nil] optional room id to walk to instead
      # @return [void]
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

      # Finds the recipe whose name matches item_name (a case-insensitive
      # regex). A single match, or a single exact-name match, is returned
      # directly. Otherwise the matches are listed as a numbered menu and the
      # user picks one with ;send #. Lines that are not a bare number are
      # ignored (they may be game output); a number outside the menu
      # re-prompts. The chosen recipe is returned by its menu position, so a
      # pick never resolves to a different recipe with a similar or
      # duplicate name.
      #
      # @param recipes [Array<Hash>] recipe entries with at least 'name'
      # @param item_name [String] full or partial recipe name
      # @return [Hash, nil] the chosen recipe, or nil when nothing matches
      def recipe_lookup(recipes, item_name)
        matches = recipes.select { |x| x['name'] =~ /#{item_name}/i }
        case matches.length
        when 0
          Lich::Messaging.msg('bold', "DRCC: No recipe in base-recipes.yaml matches #{item_name}")
          nil
        when 1
          matches.first
        else
          exact_matches = matches.select { |x| x['name'] == item_name }
          return exact_matches.first if exact_matches.length == 1

          # The full-name hint only helps when the full name was not typed and
          # at least one listed name is unique; a name shared by several
          # recipes shows this menu however it is typed.
          if exact_matches.empty? && matches.map { |x| x['name'] }.tally.value?(1)
            Lich::Messaging.msg('bold', "DRCC: Using the full name of the item you wish to craft will avoid this in the future (e.g. 'a metal pike' vs 'metal pike')")
          end
          Lich::Messaging.msg('plain', "DRCC: Please select desired recipe #{$clean_lich_char}send #")
          recipe_menu_labels(matches).each_with_index { |label, i| respond "    #{i + 1}: #{label}" }
          matches[recipe_menu_choice(matches.length) - 1]
        end
      end

      # Menu labels for recipe_lookup. A name that appears more than once is
      # suffixed with its type and chapter so the entries can be told apart,
      # and with its volume too when the type and chapter are also shared.
      # Entries that are still identical after that (a duplicate in the data)
      # are numbered "entry k of n" so every menu line is distinct.
      def recipe_menu_labels(matches)
        name_counts = matches.map { |x| x['name'] }.tally
        place_counts = matches.map { |x| x.values_at('name', 'type', 'chapter') }.tally
        labels = matches.map do |x|
          next x['name'] if name_counts[x['name']] == 1

          details = [x['type'], "chapter #{x['chapter']}"]
          details << "volume #{x['volume']}" if x['volume'] && place_counts[x.values_at('name', 'type', 'chapter')] > 1
          "#{x['name']} (#{details.join(', ')})"
        end
        label_counts = labels.tally
        seen = Hash.new(0)
        labels.map do |label|
          next label if label_counts[label] == 1

          "#{label.delete_suffix(')')}, entry #{seen[label] += 1} of #{label_counts[label]})"
        end
      end

      # Reads lines until one is a bare number from 1 to count and returns it.
      def recipe_menu_choice(count)
        loop do
          line = get.to_s.strip
          next unless line =~ /\A\d+\z/

          choice = line.to_i
          return choice if choice.between?(1, count)

          Lich::Messaging.msg('bold', "DRCC: #{choice} is not on the list. Enter a number from 1 to #{count} with #{$clean_lich_char}send #")
        end
      end

      private_class_method :recipe_menu_labels, :recipe_menu_choice

      # Locates a recipe page by chapter and item name pattern in a crafting book.
      #
      # Turns to the specified chapter, reads the book for matching item names,
      # and returns the page number of the first match. Stops the script if
      # distracted (e.g., in combat).
      #
      # @param chapter [Integer] the chapter number to turn to
      # @param match_string [String] case-insensitive regex pattern for item name
      # @param book [String] the book item noun (default 'book')
      # @return [String, nil] the page number as a string, or nil if no match found
      # @see #find_recipe2 for newer book format support
      def find_recipe(chapter, match_string, book = 'book')
        case DRC.bput("turn my #{book} to chapter #{chapter}", BOOK_CHAPTER_TURN_SUCCESS, BOOK_CHAPTER_DISTRACTED, BOOK_CHAPTER_ALREADY)
        when BOOK_CHAPTER_DISTRACTED
          Lich::Messaging.msg('bold', 'DRCC: Cannot turn book, assuming engaged in combat.')
          fput('look')
          exit
        end

        recipe = DRC.bput("read my #{book}", "Page \\d+:\\s(?:some|a|an)?\\s*#{match_string}").split('Page').find { |x| x =~ /#{match_string}/i }
        match = recipe&.match(/(?<page>\d+):/)
        match&.[](:page)
      end

      # Locates a recipe page and studies it for newer-format crafting books.
      #
      # Turns to the specified discipline (if provided) and chapter, reads the book
      # for matching item names, turns to that page, and studies it. Stops the script
      # if distracted (e.g., in combat).
      #
      # @param chapter [Integer] the chapter number to turn to
      # @param match_string [String] case-insensitive regex pattern for item name
      # @param book [String] the book item noun (default 'book')
      # @param discipline [String, nil] optional discipline to turn to first
      # @return [void]
      # @see #find_recipe for older book format
      def find_recipe2(chapter, match_string, book = 'book', discipline = nil)
        DRC.bput("turn my #{book} to discipline #{discipline}", BOOK_DISCIPLINE_SUCCESS) unless discipline.nil?
        case DRC.bput("turn my #{book} to chapter #{chapter}", BOOK_CHAPTER2_SUCCESS, BOOK_CHAPTER2_ALREADY, BOOK_CHAPTER_DISTRACTED)
        when BOOK_CHAPTER_DISTRACTED
          Lich::Messaging.msg('bold', 'DRCC: Cannot turn book, assuming engaged in combat.')
          fput('look')
          exit
        end

        recipe = DRC.bput("read my #{book}", "Page \\d+:\\s(?:some|a|an)?\\s*#{match_string}").split('Page').find { |x| x =~ /#{match_string}/i }
        match = recipe&.match(/(?<page>\d+):/)
        page = match&.[](:page)
        DRC.bput("turn my #{book} to page #{page}", BOOK_PAGE_SUCCESS, BOOK_PAGE_ALREADY)
        DRC.bput("study my #{book}", BOOK_STUDY_SUCCESS)
      end

      # Puts a crafting tool or material in hand. A tool listed on the
      # crafting belt is untied from it; anything else is fetched with
      # `get my <name>`, from +bag+ when +bag_items+ lists it.
      #
      # When wounds hinder an untie, visits safe-room once and sends that
      # untie once more. The belt untie and the plain untie each get their
      # own visit, so a call that falls from the belt to a GET that says to
      # untie the item can visit safe-room twice, never more. Four failures
      # are final, and no retry follows them:
      # - the item can't be found and isn't already in hand;
      # - the game says it "can't quite lift it";
      # - the GET says to untie the item, the untie finds nothing, and the
      #   item isn't in hand;
      # - wounds still hinder the untie after the safe-room trip, and the
      #   item isn't in hand.
      # Each one beeps and prints a bold line. The method then returns false
      # when +skip_exit+ is set; otherwise it stops the script. A reply that
      # matches nothing (a bput timeout) is not final. A timed-out GET, or a
      # timed-out untie after "You should untie", returns whether the item is
      # in hand, as a late reply may still deliver it; a timed-out belt untie
      # falls back to the GET.
      #
      # @param name [String] item to put in hand
      # @param bag [String] container that holds +bag_items+
      # @param bag_items [Array<String>, nil] items kept in +bag+
      # @param belt [Hash, nil] crafting belt settings ('name', 'items')
      # @param skip_exit [Boolean] return false on a final failure instead of
      #   stopping the script
      # @return [Boolean] true when the item is in hand (the untie or get
      #   succeeded, or it was already held); false after a final failure
      #   with +skip_exit+, or when a timed-out reply leaves it out of hand
      def get_crafting_item(name, bag, bag_items, belt, skip_exit = false)
        waitrt?
        if belt && belt['items'].find { |item| /\b#{name}/i =~ item || /\b#{item}/i =~ name }
          case untie_crafting_item(name, "untie my #{name} from my #{belt['name']}", BELT_UNTIE_WOUNDED, BELT_UNTIE_SUCCESS, BELT_UNTIE_ALREADY, BELT_UNTIE_NOT_FOUND)
          when BELT_UNTIE_SUCCESS, BELT_UNTIE_ALREADY
            return true
          when BELT_UNTIE_WOUNDED
            return true if DRCI.in_hands?(name)

            return crafting_item_failed("DRCC: Your wounds still hinder untying: #{name}", skip_exit)
          end
        end
        command = "get my #{name}"
        command += " from my #{bag}" if bag_items && bag_items.include?(name)
        case DRC.bput(command, GET_CRAFTING_SUCCESS, GET_CRAFTING_ALREADY, GET_CRAFTING_NOT_FOUND_WHAT, GET_CRAFTING_NOT_FOUND_WERE, GET_CRAFTING_PICKUP, GET_CRAFTING_HEAVY, GET_CRAFTING_TIED)
        when GET_CRAFTING_SUCCESS, GET_CRAFTING_ALREADY, GET_CRAFTING_PICKUP
          true
        when GET_CRAFTING_NOT_FOUND_WHAT, GET_CRAFTING_NOT_FOUND_WERE
          pause 2
          return true if DRCI.in_hands?(name)

          crafting_item_failed("DRCC: You seem to be missing: #{name}", skip_exit)
        when GET_CRAFTING_HEAVY
          # Final: GETting it again won't make it liftable.
          crafting_item_failed("DRCC: You can't quite lift: #{name}", skip_exit)
        when GET_CRAFTING_TIED
          case untie_crafting_item(name, "untie my #{name}", UNTIE_WOUNDED, UNTIE_SUCCESS, UNTIE_NOT_FOUND)
          when UNTIE_SUCCESS
            true
          when UNTIE_WOUNDED
            return true if DRCI.in_hands?(name)

            crafting_item_failed("DRCC: Your wounds still hinder untying: #{name}", skip_exit)
          when UNTIE_NOT_FOUND
            return true if DRCI.in_hands?(name)

            crafting_item_failed("DRCC: Told to untie it, but found nothing to untie: #{name}", skip_exit)
          else
            DRCI.in_hands?(name)
          end
        else
          DRCI.in_hands?(name)
        end
      end

      # Sends an untie for get_crafting_item. When wounds hinder it, visits
      # safe-room once, walks back and sends the untie once more.
      #
      # @param name [String] item being untied
      # @param command [String] the untie command
      # @param wounded [Regexp] the reply meaning wounds hinder the untie
      # @param patterns [Array<Regexp>] the other replies to wait for
      # @return [String] the matched reply ('' on a timeout)
      def untie_crafting_item(name, command, wounded, *patterns)
        result = DRC.bput(command, *patterns, wounded)
        return result unless result.match?(wounded)

        Lich::Messaging.msg('bold', "DRCC: Wounds hinder untying #{name}. Visiting safe-room, then trying once more.")
        craft_room = Room.current.id
        DRC.wait_for_script_to_complete('safe-room', ['force'])
        DRCT.walk_to(craft_room)
        DRC.bput(command, *patterns, wounded)
      end

      # Reports a final get_crafting_item failure: beeps and prints +message+.
      #
      # @param message [String] bold line naming the failure
      # @param skip_exit [Boolean] return instead of stopping the script
      # @return [false] when +skip_exit+; otherwise stops the script
      def crafting_item_failed(message, skip_exit)
        DRC.beep
        Lich::Messaging.msg('bold', message)
        return false if skip_exit

        Lich::Messaging.msg('bold', 'DRCC: Cannot continue crafting without required item. Stopping script.')
        exit
      end

      # Internal to get_crafting_item; kept off the public DRCC API.
      private_class_method :untie_crafting_item, :crafting_item_failed

      # Stows a crafting item in a bag or (if on belt) ties it back to the belt.
      #
      # Attempts to tie the item to the belt if it matches belt items; if that fails
      # or the item is not a belt item, puts it in the bag. When the bag is full,
      # falls back to general stow. Returns true on success, false only when the
      # alternate bag fallback is used.
      #
      # @param name [String] item noun to stow
      # @param bag [String] container noun to stow in (e.g., 'bag')
      # @param belt [Hash, nil] crafting belt settings with 'name' and 'items' keys
      # @return [Boolean] true unless the alternate bag fallback was used
      # @see #get_crafting_item
      # @see #tie_to_crafting_belt?
      def stow_crafting_item(name, bag, belt)
        return unless name

        waitrt?
        if belt && belt['items'].find { |item| /\b#{name}/i =~ item || /\b#{item}/i =~ name }
          return true if tie_to_crafting_belt?(name, belt)

          # Not tied: wounds outlasted the safe-room trip, or the reply was a
          # refusal that retrying won't clear. Put the tool in the bag instead;
          # get_crafting_item's `get my <name>` finds it there.
          Lich::Messaging.msg('bold', "DRCC: Failed to tie #{name} to #{belt['name']}. Stowing it off the belt instead.")
        end

        case DRC.bput("put my #{name} in my #{bag}", PUT_BAG_TUCK, PUT_BAG_PUT, PUT_BAG_NOT_FOUND, PUT_BAG_TOO_BIG, PUT_BAG_WEIRD, PUT_BAG_NO_ROOM, PUT_BAG_CANT_THERE, PUT_BAG_COMBINE)
        when PUT_BAG_TOO_BIG, PUT_BAG_WEIRD, PUT_BAG_NO_ROOM
          fput("stow my #{name}")
        when PUT_BAG_CANT_THERE
          fput("put my #{name} in my other #{bag}")
          return false
        end
        true
      end

      # Ties a crafting tool to the belt. When wounds hinder the tie, visits
      # safe-room once and tries once more; any other reply is final.
      #
      # @param name [String] tool noun, as passed to stow_crafting_item
      # @param belt [Hash] crafting belt settings ('name' is tied to)
      # @return [Boolean] true if the tool is tied (or was already tied off)
      def tie_to_crafting_belt?(name, belt)
        command = "tie my #{name} to my #{belt['name']}"
        patterns = [DRCI::TIE_ITEM_SUCCESS_PATTERNS, DRCI::TIE_ITEM_EMPTY_PATTERN, DRCI::TIE_ITEM_FAILURE_PATTERNS]
        result = DRC.bput(command, *patterns)
        if result.match?(TIE_BELT_WOUNDED)
          Lich::Messaging.msg('bold', "DRCC: Wounds hinder tying #{name} to #{belt['name']}. Visiting safe-room, then trying once more.")
          craft_room = Room.current.id
          DRC.wait_for_script_to_complete('safe-room', ['force'])
          DRCT.walk_to(craft_room)
          result = DRC.bput(command, *patterns)
        end
        DRCI::TIE_ITEM_SUCCESS_PATTERNS.any? { |pattern| result.match?(pattern) }
      end
      private_class_method :tie_to_crafting_belt?

      # Calculates the total copper cost to craft items in the specified hometown.
      #
      # Accounts for stock materials (stackable or single), non-purchasable parts,
      # purchasable parts, a fixed 1000-copper overhead for consumables and utilities,
      # and converts the total based on the town's currency.
      #
      # @param recipe [Hash] recipe entry with 'volume' key
      # @param hometown [String] the crafting hometown for currency conversion
      # @param parts [Array<String>, nil] list of part nouns required (nil skips parts cost)
      # @param quantity [Integer] number of finished items to craft
      # @param material [Hash, nil] stock material entry with 'stock-volume' and 'stock-value' keys; nil skips stock cost
      # @return [Integer] total copper cost, converted to hometown currency
      # @example
      #   recipe = {"name" => "a metal ring cap", "volume" => 8}
      #   material = {"stock-volume" => 5, "stock-value" => 562}
      #   DRCC.crafting_cost(recipe, "Crossing", ["gold"], 10, material) #=> 45000
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

      # Repairs each tool with a wire brush and oil, stowing every item it takes out.
      # Stops at the first engaged reply and leaves the remaining tools for later.
      #
      # @return [Symbol, nil] :engaged when repairs stopped because the character is engaged; nil otherwise
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

          stop_repairs = false # set when engaged: no further tool can be repaired right now
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
              retry_result = DRC.bput("pour my oil on my #{tool_name}", REPAIR_SUCCESS, REPAIR_ENGAGED)
              DRCC.stow_crafting_item(x, bag, belt)
              if retry_result == REPAIR_ENGAGED # engaged while fetching more oil: stop like the first reply would
                Lich::Messaging.msg('bold', 'DRCC: Cannot repair in combat.')
                stop_repairs = true
                break
              end
              next # oil done, next tool
            when REPAIR_ENGAGED
              Lich::Messaging.msg('bold', 'DRCC: Cannot repair in combat.')
              DRCC.stow_crafting_item(x, bag, belt) # the tool itself is stowed once, below
              stop_repairs = true
              break
            when REPAIR_CONFUSED # this tool can't be repaired this way; the others may still be
              Lich::Messaging.msg('bold', "DRCC: Cannot repair #{tool_name}, skipping it.")
              DRCC.stow_crafting_item(x, bag, belt) # the tool itself is stowed once, below
              break
            end
          end
          UserVars.immune_list.store(tool_name, Time.now + 7000) if Flags['proper-repair'] # if our flag picks up a Proper Forging Tool Care successful repair, we add that tool and a time of now plus 7000 seconds (just shy of 2 hours) to the list of immune tools
          Flags.reset('proper-repair')
          DRCC.stow_crafting_item(tool_name, bag, belt)
          return :engaged if stop_repairs # skip the remaining tools
        end
        nil
      end

      # Verifies consumable tool has sufficient uses; orders more if needed.
      #
      # Gets the consumable from the bag, counts uses, and if below the threshold,
      # disposes of it and recursively checks for a fresh copy. Returns to the
      # starting room when done. Handles order_item via DRCT.
      #
      # @param name [String] consumable item noun (e.g., 'oil', 'wire brush')
      # @param room [Integer] room id where the consumable vendor is located
      # @param number [Integer] vendor order number for the item
      # @param bag [String] container noun where the consumable is kept
      # @param bag_items [Array<String>] list of items normally in the bag
      # @param belt [Hash, nil] crafting belt settings
      # @param count [Integer] minimum required uses (default 3)
      # @return [void]
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

      # Gets and adjusts tongs or shovel form, or resets tongs state at script start.
      #
      # Manages three states: 'shovel', 'tongs', or 'reset shovel'/'reset tongs'.
      # Fetches the item, adjusts it to the target configuration if needed, and
      # tracks the configuration in @tongs_status. When given an adjustable_tongs
      # parameter, retries adjustment on mismatch; non-adjustable tongs fail safely.
      #
      # @param usage [String] one of: 'shovel', 'tongs', 'reset shovel', 'reset tongs'
      # @param bag [String] container noun where tongs are kept
      # @param bag_items [Array<String>] list of items normally in the bag
      # @param belt [Hash, nil] crafting belt settings
      # @param adjustable_tongs [Boolean] whether the tongs can switch forms (default false)
      # @return [Boolean] true if the target configuration is in hand and correct, false otherwise
      # @see #get_crafting_item
      # @see #stow_crafting_item
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

      # Bundles a crafted item with a logbook, disposing of it if the bundle fails.
      #
      # Gets the logbook, attempts to bundle the item. On quality/type failures or
      # expiration, disposes of the item. On missing item, fetches it from the
      # container and retries. Stows the logbook when done.
      #
      # @param logbook [String] the logbook type (e.g., 'armorsmithing', 'tailoring')
      # @param noun [String] the crafted item noun to bundle
      # @param container [String] container noun where the item is kept
      # @return [void]
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

      # Orders stock_needed items from a vendor and stows all hands.
      #
      # Iterates stock_needed times: orders one item from the vendor at stock_number
      # in stock_room, then stows left and right hand items. Stops early if both
      # hands fill up (next order would fail).
      #
      # @param stock_room [Integer] room id where the vendor is located
      # @param stock_needed [Integer] number of items to order
      # @param stock_number [Integer] vendor order number
      # @param bag [String] container noun for stowing
      # @param belt [Hash, nil] crafting belt settings
      # @return [void]
      # @api private
      def order_enchant(stock_room, stock_needed, stock_number, bag, belt)
        stock_needed.times do
          DRCT.order_item(stock_room, stock_number)
          stow_crafting_item(DRC.left_hand, bag, belt)
          stow_crafting_item(DRC.right_hand, bag, belt)
          next unless DRC.left_hand && DRC.right_hand
        end
      end

      # Checks fount uses and orders enchanting stock if needed.
      #
      # Taps the fount (in bag or on brazier) and analyzes it. If uses fall below
      # the quantity threshold, disposes of the fount and orders new enchanting stock.
      # Attempts bag first, then brazier location.
      #
      # @param stock_room [Integer] room id where the enchanting vendor is located
      # @param stock_needed [Integer] number of stock items to order
      # @param stock_number [Integer] vendor order number for stock
      # @param quantity [Integer] required uses threshold
      # @param bag [String] container noun where fount/stock are kept
      # @param bag_items [Array<String>] list of items normally in the bag
      # @param belt [Hash, nil] crafting belt settings
      # @return [void]
      # @see #order_enchant
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

      # Checks if a brazier is clean and empty, or cleans it if cluttered.
      #
      # Looks at the brazier; if nothing is on it, returns true. If items are present,
      # attempts to clean it (handling potential flame bursts), then empties any
      # remaining items. Returns true on success or if already empty.
      #
      # @return [Boolean] true if the brazier is clean (or now clean), false if an error occurred
      # @see #empty_brazier
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

      # Removes all items from a brazier and disposes of them.
      #
      # Looks at the brazier, parses the items list (split by ' and '), gets each
      # item by its noun, and disposes of it. Returns early if no items are found.
      #
      # @return [void]
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

      # Checks for existing sigil-scrolls and orders more if the supply is insufficient.
      #
      # Counts sigil-scrolls in the bag. If the count meets or exceeds quantity, returns
      # true. Otherwise, if the sigil type is in the global sigil patterns, orders
      # the shortage via order_enchant and returns true. Returns false when the sigil
      # type is unavailable and purchase is impossible.
      #
      # @param sigil [String] sigil type (e.g., 'holy', 'unholy')
      # @param stock_number [Integer] vendor order number for sigils
      # @param quantity [Integer] required sigil-scroll count
      # @param bag [String] container noun where sigil-scrolls are kept
      # @param belt [Hash, nil] crafting belt settings
      # @param info [Hash] vendor info with 'stock-room' key
      # @return [Boolean] true if sigil-scrolls are available or have been ordered, false otherwise
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

      # Counts and reports raw metal in a materials container, optionally filtered by type.
      #
      # Rummages the container for crafting materials, parses entries as
      # '<count> <size> <metal>', aggregates by metal noun, and prints a summary.
      # Returns a hash of {metal => [total_volume, piece_count]} or nil on failure.
      # When type is given, returns the entry for that metal type only.
      #
      # @param container [String] container noun to rummage
      # @param type [String, nil] optional metal type to return (e.g., 'bronze')
      # @return [Hash, Integer, nil] hash of metal => [volume, pieces] if no type;
      #   an entry value if type is set; nil on error (not found, closed, or invisible)
      # @example
      #   DRCC.count_raw_metal('materials') #=> {"bronze"=>[21, 3], "iron"=>[10, 2]}
      #   DRCC.count_raw_metal('materials', 'bronze') #=> [21, 3]
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

      # Creates finished mechanisms by pressing metal ingots on a shaping press.
      #
      # Finds a shaping room, dials the press to the target speed, then iterates
      # to create mechanisms: gets ingot and shovel, pushes fuel, gets pliers,
      # pushes ingot into press, pulls mechanism, stows items, and combines hands
      # when both are full. Leaves excess ingots stowed after completion.
      #
      # @param settings [OpenStruct] crafting settings with hometown, crafting_container,
      #   crafting_items_in_container, forging_belt keys
      # @param material [String] metal type (e.g., 'bronze') for ingot acquisition
      # @param number [Integer] quantity of mechanisms to create
      # @param speed [Integer] press speed dial setting 1-12 (default 6)
      # @return [void]
      # @note Prints error message and returns if press speed is invalid (>12 or <1)
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
      # Patterns matching entry rejection to a private forge (insufficient funds, blocked, etc.).
      #
      # @return [Array<String>]
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
