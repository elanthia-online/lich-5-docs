# frozen_string_literal: true

# Namespace for Lich 5, the Ruby scripting engine for GemStone IV and DragonRealms.
module Lich
  # Namespace for DragonRealms-specific scripting features.
  module DragonRealms
    # DragonRealms Common Travel: utilities for navigation, merchant interactions, and room finding.
    #
    # Provides methods for walking between rooms, buying/selling/asking merchants, disposing items,
    # and locating empty rooms suitable for spellcasting or hunting.
    module DRCT
      module_function

      # Direction reversal mapping for path reversal
      # Note: With frozen_string_literal: true, string literals are already frozen
      DIRECTION_REVERSE = {
        'northeast' => 'southwest',
        'southwest' => 'northeast',
        'northwest' => 'southeast',
        'southeast' => 'northwest',
        'north'     => 'south',
        'south'     => 'north',
        'east'      => 'west',
        'west'      => 'east',
        'up'        => 'down',
        'down'      => 'up'
      }.freeze unless defined?(DIRECTION_REVERSE)

      # Patterns indicating successful sale at a merchant
      SELL_SUCCESS_PATTERNS = [
        /hands? you \d+ (?:kronars|lirums|dokoras)/i
      ].freeze unless defined?(SELL_SUCCESS_PATTERNS)

      # Patterns indicating failed sale attempt
      SELL_FAILURE_PATTERNS = [
        /I need to examine the merchandise first/,
        /That's not worth anything/,
        /I only deal in pelts/,
        /There's folk around here that'd slit a throat for this/
      ].freeze unless defined?(SELL_FAILURE_PATTERNS)

      # Patterns matching merchant price quotes in response to a BUY request.
      #
      # Extracted named capture group 'amount' contains the numeric price in kronars, lirums, or dokoras.
      # Each pattern accounts for merchant personality variation across GemStone and DragonRealms towns.
      #
      # @see #buy_item
      # @example Merchant quote matching
      #   "prepared to offer it to you for 500 kronars" #=> captures amount: "500"
      #   "Cost you just 250 lirums?, okie dokie?" #=> captures amount: "250"
      BUY_PRICE_PATTERNS = [
        /prepared to offer it to you for (?<amount>.*) (?:kronar|lirum|dokora)s?/,
        /Let me but ask the humble sum of (?<amount>.*) coins/,
        /it would be just (?<amount>\d*) (?:kronar|lirum|dokora)s?/,
        /for a (?:mere )?(?<amount>\d*) (?:kronar|lirum|dokora)s?/,
        /I can let that go for\.\.\.(?<amount>.*) (?:kronar|lirum|dokora)s?/,
        /cost you (?:just )?(?<amount>.*) (?:kronar|lirum|dokora)s?/,
        /it may be yours for just (?<amount>.*) (?:kronar|lirum|dokora)s?/,
        /I'll give that to you for (?<amount>.*) (?:kronar|lirum|dokora)s?/,
        /I'll let you have it for (?<amount>.*) (?:kronar|lirum|dokora)s?/i,
        /I ask that you give (?<amount>.*) copper (?:kronar|lirum|dokora)s?/,
        /it'll be (?<amount>.*) (?:kronar|lirum|dokora)s?/,
        /the price of (?<amount>.*) coins? is all I ask/,
        /tis only (?<amount>.*) (?:kronar|lirum|dokora)s?/,
        /That will be (?<amount>.*) copper (?:kronar|lirum|dokora)s? please/,
        /That'll be (?<amount>.*) copper (?:kronar|lirum|dokora)s?/,
        /to you for (?<amount>.*) (?:kronar|lirum|dokora)s?/,
        /I ask (?<amount>.*) copper (?:kronar|lirum|dokora)s or if you would prefer/,
        /Cost you just (?<amount>.*) (?:kronar|lirum|dokora)s?, okie dokie\?/i,
        /It will cost just (?<amount>.*) (?:kronar|lirum|dokora)s?/i,
        /I would suggest (?<amount>.*) (?:kronar|lirum|dokora)s?/i,
        /to you for (?<amount>.*) (?:kronar|lirum|dokora)s?/i,
        /asking (?<amount>.*) (?:kronar|lirum|dokora)s?/i
      ].freeze unless defined?(BUY_PRICE_PATTERNS)

      # Patterns indicating buy action without price info
      BUY_NON_PRICE_PATTERNS = [
        'You decide to purchase',
        'Buy what'
      ].freeze unless defined?(BUY_NON_PRICE_PATTERNS)

      # Patterns indicating successful ASK request
      ASK_SUCCESS_PATTERNS = [
        /hands you/
      ].freeze unless defined?(ASK_SUCCESS_PATTERNS)

      # Patterns indicating failed ASK request
      ASK_FAILURE_PATTERNS = [
        /does not seem to know anything about that/,
        /All I know about/,
        /To whom are you speaking/,
        /Usage: ASK/
      ].freeze unless defined?(ASK_FAILURE_PATTERNS)

      # Visit a merchant and sell an item.
      # Usually to sell junk at pawn shops.
      def sell_item(room, item)
        return false unless DRCI.in_hands?(item)

        walk_to(room)

        case DRC.bput("sell my #{item}", *SELL_SUCCESS_PATTERNS, *SELL_FAILURE_PATTERNS)
        when *SELL_SUCCESS_PATTERNS
          true
        when *SELL_FAILURE_PATTERNS
          false
        end
      end

      # Visit a merchant and buy an item by offering their asking price.
      # Usually for restocking ammunition or other misc items.
      def buy_item(room, item)
        walk_to(room)

        all_patterns = BUY_PRICE_PATTERNS + BUY_NON_PRICE_PATTERNS
        result = DRC.bput("buy #{item}", *all_patterns)

        match_data = BUY_PRICE_PATTERNS.lazy.filter_map { |p| p.match(result) }.first
        amount = match_data[:amount] if match_data

        fput("offer #{amount}") if amount
      end

      # Visit a merchant and ask for an item.
      # Usually this is for bundling ropes or gem pouches.
      def ask_for_item?(room, name, item)
        walk_to(room)

        case DRC.bput("ask #{name} for #{item}", *ASK_SUCCESS_PATTERNS, *ASK_FAILURE_PATTERNS)
        when *ASK_SUCCESS_PATTERNS
          true
        else
          false
        end
      end

      # Visit a merchant and order from a menu.
      def order_item(room, item_number)
        walk_to(room)

        return if DRC.bput("order #{item_number}", 'Just order it again', 'you don\'t have enough coins') == 'you don\'t have enough coins'

        DRC.bput("order #{item_number}", 'takes some coins from you')
      end

      # Discards an item by walking to a trash room and disposing of it in a trashcan.
      #
      # If no trash room is provided, disposes in the current room. If a worn trashcan
      # (e.g., a backpack or sack) is specified, deposits the item there instead.
      #
      # @param item [String] the item name or pronoun (e.g. "my lockpick", "junk")
      # @param trash_room [Integer, nil] room id to walk to before disposing; if nil, disposes in place
      # @param worn_trashcan [String, nil] worn container to put item into (e.g. "my backpack")
      # @param worn_trashcan_verb [String, nil] preposition for inserting into the container (e.g. "on", "in")
      # @return [void]
      # @example
      #   DRCT.dispose("my junk", 4711)
      #   DRCT.dispose("my lockpick", 5000, "my lockpick container", "on")
      def dispose(item, trash_room = nil, worn_trashcan = nil, worn_trashcan_verb = nil)
        return unless item

        DRCT.walk_to(trash_room) unless trash_room.nil?
        DRCI.dispose_trash(item, worn_trashcan, worn_trashcan_verb)
      end

      # Buys lockpicks from the locksmith in a hometown and stores them in a container.
      #
      # Walks to the locksmith location (looked up from town data), buys the specified number
      # of lockpicks of a given type, and places each into a worn container. Stops early if
      # a put-away fails (e.g., due to container type mismatch). Fixes standing and exits
      # the locksmith room afterward to be polite to thieves.
      #
      # Returns silently if count < 1 or if no locksmith location is found for the hometown.
      #
      # @param lockpick_type [String] lockpick type (e.g. "iron", "silver")
      # @param hometown [String] the character's hometown (used to look up locksmith location)
      # @param container [String] worn container name for storage (e.g. "my lockpick container")
      # @param count [Integer] number of lockpicks to buy; skipped if < 1
      # @return [void]
      # @note Logs messages if locksmith location is not found or if put-away fails.
      # @example
      #   DRCT.refill_lockpick_container("iron", "Wehnimer's Landing", "my lockpick container", 10)
      def refill_lockpick_container(lockpick_type, hometown, container, count)
        return if count < 1

        room = get_data('town')[hometown]['locksmithing']['id']

        if room.nil?
          Lich::Messaging.msg('bold', 'DRCT: No locksmith location found for current hometown. Skipping refilling.')
          return
        end

        walk_to(room)
        if Room.current.id != room
          Lich::Messaging.msg('bold', 'DRCT: Could not reach locksmith location. Skipping refilling.')
          return
        end

        count.times do
          buy_item(room, "#{lockpick_type} lockpick")
          unless DRCI.put_away_item_unsafe?('my lockpick', "my #{container}", 'on')
            Lich::Messaging.msg('bold', "DRCT: Failed to put lockpick on #{container}. Check your lockpick settings - mixing types in a container is not allowed.")
            break
          end
        end

        # Be polite to Thieves, who need the room to be empty
        DRC.fix_standing
        move('out') if XMLData.room_exits.include?('out')
      end

      # Maximum number of times walk_to will retry navigation before giving up.
      # Prevents unbounded recursion (and eventual SystemStackError) when the
      # game server connection is lost or go2 repeatedly fails.
      MAX_WALK_TO_RETRIES = 3

      # Navigate to +target_room+ using the go2 script.
      #
      # @param target_room [Integer, String] room id or map tag (e.g. 'bank')
      # @param restart_on_fail [Boolean] retry navigation on failure
      # @param retry_depth [Integer] internal counter -- callers should not set this
      # @return [Boolean] true if the character is now in the target room
      def walk_to(target_room, restart_on_fail = true, retry_depth: 0)
        target_room = tag_to_id(target_room) if target_room.is_a?(String) && target_room.count("a-zA-Z") > 0

        return false if target_room.nil?

        room_num = target_room.to_i
        # Room.current is nil when the room could not be resolved. Under Lich's
        # NilClass patch nil.id yielded nil, so the comparison simply failed.
        return true if room_num == Room.current&.id

        DRC.fix_standing

        if Room.current&.id.nil?
          Lich::Messaging.msg('plain', "DRCT: In an unknown room, manually attempting to navigate to #{room_num}")
          rooms = Map.list.compact.select { |room| room.description.include?(XMLData.room_description.strip) && room.title.include?(XMLData.room_title) }
          if rooms.empty? || rooms.length > 1
            Lich::Messaging.msg('bold', 'DRCT: Failed to find a matching room from unknown location.')
            return false
          end
          room = rooms.first
          return true if room_num == room.id

          if room.wayto[room_num.to_s]
            move room.wayto[room_num.to_s]
            return room_num == room.id
          end
          path = Map.findpath(room, Map[room_num])
          way = room.wayto[path.first.to_s]
          if way.is_a?(StringProc)
            way.call
          else
            move way
          end
          if retry_depth >= MAX_WALK_TO_RETRIES
            Lich::Messaging.msg('bold', "DRCT: Failed to navigate from unknown room after #{MAX_WALK_TO_RETRIES} retries, giving up.")
            return false
          end
          return walk_to(room_num, true, retry_depth: retry_depth + 1)
        end

        script_handle = start_script('go2', [room_num.to_s], force: true)

        timer = Time.now
        prev_room = XMLData.room_description + XMLData.room_title

        Flags.add('travel-closed-shop', 'The door is locked up tightly for the night', 'You smash your nose', '^A servant (blocks|stops)')
        Flags.add('travel-engaged', 'You are engaged')

        begin
          while Script.running.include?(script_handle)
            if Flags['travel-closed-shop']
              Flags.reset('travel-closed-shop')
              kill_script(script_handle)
              if /You open/ !~ DRC.bput('open door', 'It is locked', 'You .+', 'What were')
                restart_on_fail = false
                break
              end
              timer = Time.now
              script_handle = start_script('go2', [room_num.to_s])
            end
            if Flags['travel-engaged']
              Flags.reset('travel-engaged')
              kill_script(script_handle)
              DRC.retreat
              timer = Time.now
              script_handle = start_script('go2', [room_num.to_s])
            end
            if (Time.now - timer) > 90
              kill_script(script_handle)
              pause 0.5 while Script.running.include?(script_handle)
              break unless restart_on_fail

              timer = Time.now
              script_handle = start_script('go2', [room_num.to_s])
            end
            if Script.running?('escort') || Script.running?('bescort') || (XMLData.room_description + XMLData.room_title) != prev_room || XMLData.room_description =~ /The terrain constantly changes as you travel along on your journey/
              timer = Time.now
            end
            prev_room = XMLData.room_description + XMLData.room_title
            pause 0.5
          end
        ensure
          Flags.delete('travel-closed-shop')
          Flags.delete('travel-engaged')
        end

        if room_num != Room.current.id && restart_on_fail
          if retry_depth >= MAX_WALK_TO_RETRIES
            Lich::Messaging.msg('bold', "DRCT: Failed to navigate to room #{room_num} after #{MAX_WALK_TO_RETRIES} retries, giving up.")
            return false
          end
          Lich::Messaging.msg('bold', "DRCT: Failed to navigate to room #{room_num}, attempting again (#{retry_depth + 1}/#{MAX_WALK_TO_RETRIES}).")
          return walk_to(room_num, true, retry_depth: retry_depth + 1)
        end
        room_num == Room.current.id
      end

      # Converts a map tag (e.g. "bank", "healer") to the room id of the closest reachable room with that tag.
      #
      # Uses Dijkstra pathfinding to find the shortest path from the current room to any room
      # tagged with the target. If already in a room with the target tag, returns the current room.
      # Returns nil if no rooms match, no path exists, or pathfinding fails.
      #
      # @param target [String] a map tag such as "bank", "healer", "council"
      # @return [Integer, nil] the room id of the closest tagged room, or nil if not found
      # @note Messages are logged (at 'bold' level) on failure.
      # @example
      #   DRCT.tag_to_id("bank") #=> 5000
      def tag_to_id(target)
        start_room = Room.current.id
        target_list = Map.rooms_by_tag(target)

        if target_list.empty?
          Lich::Messaging.msg('bold', "DRCT: No go2 targets matching '#{target}' found.")
          return nil
        end

        if target_list.include?(start_room)
          Lich::Messaging.msg('plain', "DRCT: You're already here.")
          return start_room
        end
        _previous, shortest_distances = Room.current.dijkstra(target_list)
        if shortest_distances.nil?
          Lich::Messaging.msg('bold', "DRCT: Pathfinding failed while looking for a '#{target}' tag.")
          return nil
        end

        target_list.delete_if { |room_id| shortest_distances[room_id].nil? }
        if target_list.empty?
          Lich::Messaging.msg('bold', "DRCT: Couldn't find a path from here to any room with a '#{target}' tag.")
          return nil
        end

        target_id = target_list.sort { |a, b| shortest_distances[a] <=> shortest_distances[b] }.first
        unless target_id && (destination = Map[target_id])
          Lich::Messaging.msg('bold', "DRCT: Something went wrong! Debug failed with target_id=#{target_id}, destination=#{destination}, tag='#{target}'.")
          return nil
        end
        target_id
      end

      # Retreats from combat if there are non-ignored NPCs in the room.
      #
      # Checks if the room contains any NPCs other than those in ignored_npcs.
      # If so, calls DRC.retreat. Otherwise does nothing.
      #
      # @param ignored_npcs [Array] NPC names to exclude from retreat logic
      # @return [void]
      # @example
      #   DRCT.retreat(["Grukk"])
      def retreat(ignored_npcs = [])
        return if (DRRoom.npcs - ignored_npcs).empty?

        DRC.retreat(ignored_npcs)
      end

      # Searches for a suitable room (empty or matching a condition) across multiple locations.
      #
      # Walks through search_rooms and applies a suitability check. On each attempt, evaluates
      # each room using a predicate (or the default: room is empty and contains no non-grouped PCs).
      # If min_mana > 0 and not a Moon Mage or Trader, also checks mana percentage.
      #
      # If no suitable room is found on an attempt, walks to idle_room (or a random one if it's
      # an Array), pauses 20-40 seconds, and retries up to max_search_attempts times.
      #
      # With prioritize_buddies=true, prefers rooms containing friends (UserVars.friends) over
      # empty rooms on the first pass.
      #
      # Returns true immediately when a suitable room is found. Returns false if all attempts exhaust.
      #
      # @param search_rooms [Array<Integer>] room ids to check in order
      # @param idle_room [Integer, Array<Integer>, nil] room(s) to idle in between attempts; no idle if nil
      # @param predicate [Proc, nil] custom suitability check: receives search_attempt (1-indexed) and returns Boolean
      # @param min_mana [Integer] minimum mana percentage required if mana checking is enabled (0 disables)
      # @param strict_mana [Boolean] if false, allows empty rooms without mana after first pass
      # @param max_search_attempts [Integer] maximum search attempts before giving up
      # @param prioritize_buddies [Boolean] on first pass, prefer rooms with friends over empty rooms
      # @return [Boolean] true if a suitable room was found, false otherwise
      # @note Messages are logged to indicate search attempts and outcomes.
      # @example
      #   DRCT.find_empty_room([5000, 5001, 5002], 5010, nil, 50, true, 5)
      def find_empty_room(search_rooms, idle_room, predicate = nil, min_mana = 0, strict_mana = false, max_search_attempts = Float::INFINITY, prioritize_buddies = false)
        search_attempt = 0
        check_mana = min_mana > 0
        rooms_searched = 0
        loop do
          search_attempt += 1
          Lich::Messaging.msg('plain', "DRCT: Search attempt #{search_attempt} of #{max_search_attempts} to find a suitable room.")
          found_empty = false
          search_rooms.each do |room_id|
            walk_to(room_id)
            pause 0.1 until room_id == Room.current.id

            rooms_searched += 1

            if prioritize_buddies && (rooms_searched <= search_rooms.size)
              suitable_room = ((DRRoom.pcs & UserVars.friends).any? && (DRRoom.pcs & UserVars.hunting_nemesis).none?)
              if rooms_searched == search_rooms.size && (DRRoom.pcs & UserVars.friends).empty? && (DRRoom.pcs & UserVars.hunting_nemesis).empty?
                Lich::Messaging.msg('plain', 'DRCT: Reached last room in list, and found no buddies. Retrying for empty room.')
                return find_empty_room(search_rooms, idle_room, predicate, min_mana, strict_mana, max_search_attempts, false)
              end
            else
              suitable_room = predicate ? predicate.call(search_attempt) : (DRRoom.pcs - DRRoom.group_members).empty?
            end
            if suitable_room && check_mana && !(DRStats.moon_mage? || DRStats.trader?)
              found_empty = true
              suitable_room = (DRCA.perc_mana >= min_mana)
            end
            return true if suitable_room
          end

          if found_empty && check_mana && !strict_mana
            check_mana = false
            Lich::Messaging.msg('plain', 'DRCT: Empty rooms found, but not with the right mana. Going to use those anyway.')
            next
          end

          check_mana = min_mana > 0

          if idle_room && search_attempt < max_search_attempts
            idle_room = idle_room.sample if idle_room.is_a?(Array)
            walk_to(idle_room)
            wait_time = rand(20..40)
            Lich::Messaging.msg('plain', "DRCT: Failed to find an empty room, pausing #{wait_time} seconds.")
            pause wait_time
          else
            Lich::Messaging.msg('plain', 'DRCT: Failed to find an empty room, stopping the search.')
            return false
          end
        end
      end

      # Sorts a list of destination room ids by shortest path distance from the current room.
      #
      # Uses Dijkstra pathfinding to compute shortest distances from the current room to all
      # destinations. Unreachable rooms are filtered out. Returns the sorted list in ascending
      # order of distance.
      #
      # If pathfinding fails or a room is unreachable, it is removed (except the current room itself,
      # which is preserved even without a distance).
      #
      # @param target_list [Array<Integer, String>] room ids to sort (converted to Integer)
      # @return [Array<Integer>] target_list sorted by distance from current room (nearest first)
      # @example
      #   DRCT.sort_destinations([5000, 5001, 4999]) #=> [4999, 5000, 5001] (assuming those distances)
      def sort_destinations(target_list)
        target_list = target_list.collect(&:to_i)
        _previous, shortest_distances = Map.dijkstra(Room.current.id)
        # Pathfinding failed; hand back what was asked for rather than nothing.
        return target_list if shortest_distances.nil?

        target_list.delete_if { |room_num| shortest_distances[room_num].nil? && room_num != Room.current.id }
        # The current room is kept above even without a distance, so sort on a
        # fallback rather than handing nil to the comparator. dijkstra seeds the
        # source at 0, so this is defensive rather than a live case.
        target_list.sort_by { |room_num| shortest_distances[room_num] || Float::INFINITY }
      end

      # Finds an empty room by searching destinations sorted by shortest path distance.
      #
      # Sorts search_rooms by distance from the current room using #sort_destinations,
      # then searches them in that order using #find_empty_room with default parameters.
      #
      # @param search_rooms [Array<Integer>] room ids to search
      # @param idle_room [Integer, Array<Integer>, nil] room(s) to idle in between search attempts
      # @param predicate [Proc, nil] optional custom suitability check
      # @return [Boolean] true if an empty room was found, false otherwise
      # @example
      #   DRCT.find_sorted_empty_room([5000, 5001, 5002], 5010)
      def find_sorted_empty_room(search_rooms, idle_room, predicate = nil)
        sorted_rooms = sort_destinations(search_rooms)
        find_empty_room(sorted_rooms, idle_room, predicate)
      end

      # Computes the shortest number of moves required to travel between two rooms.
      #
      # Uses Dijkstra pathfinding from origin to destination. Returns the distance (number of moves),
      # or nil if no path exists or pathfinding fails.
      #
      # @param origin [Integer] starting room id
      # @param destination [Integer] target room id
      # @return [Integer, nil] minimum number of moves to reach destination, or nil if unreachable
      # @example
      #   DRCT.time_to_room(5000, 5001) #=> 2
      def time_to_room(origin, destination)
        # Results are keyed by Integer room id, and dijkstra only terminates
        # early when the destination compares as an Integer.
        destination = destination.to_i
        _previous, shortest_paths = Map.dijkstra(origin, destination)
        return nil if shortest_paths.nil?

        shortest_paths[destination]
      end

      # Reverses a path of compass directions into the opposite sequence.
      #
      # Takes an array of full direction names (e.g. ["north", "east", "northeast"])
      # and returns an array of reversed directions in reverse order (e.g. ["southwest", "west", "south"]).
      # Unknown directions cause a message to be logged and nil to be returned.
      #
      # @param path [Array<String>] array of full direction names (e.g. "northeast", "up", "south")
      # @return [Array<String>, nil] reversed path, or nil if an unknown direction is encountered
      # @note Direction names must be spelled out in full (e.g. "northeast" not "ne").
      # @example
      #   DRCT.reverse_path(["north", "east"]) #=> ["west", "south"]
      #   DRCT.reverse_path(["up"]) #=> ["down"]
      def reverse_path(path)
        path.reverse.map do |dir|
          reversed = DIRECTION_REVERSE[dir]
          unless reversed
            Lich::Messaging.msg('bold', "DRCT: No reverse direction found for '#{dir}'. Use full direction names (e.g., 'northeast' not 'ne'). Path must be an array.")
            return nil
          end
          reversed
        end
      end

      # Retrieves the room id of a target location (e.g. "bank", "healer") in a specific hometown.
      #
      # Looks up the target in town data for the hometown. If not found on first attempt,
      # pauses 2 seconds and retries. Logs debug messages (if $common_travel_debug is true)
      # on first failure, second success, and final result.
      #
      # @param hometown [String] the hometown key in town data (e.g. "Wehnimer's Landing", "River's Rest")
      # @param target [String] the location key (e.g. "bank", "healer", "council")
      # @return [Integer, nil] the room id, or nil if not found after two attempts
      # @note Debug logging is controlled by the global $common_travel_debug flag.
      # @example
      #   DRCT.get_hometown_target_id("Wehnimer's Landing", "bank") #=> 5000
      def get_hometown_target_id(hometown, target)
        hometown_data = get_data('town')[hometown]
        target_id = hometown_data[target] && hometown_data[target]['id']
        unless target_id
          Lich::Messaging.msg('plain', "DRCT: get_hometown_target_id failed first attempt for #{target} in #{hometown}. Trying again.") if $common_travel_debug
          pause 2
          hometown_data = get_data('town')[hometown]
          target_id = hometown_data[target] && hometown_data[target]['id']
          unless target_id
            Lich::Messaging.msg('plain', "DRCT: get_hometown_target_id failed second attempt for #{target} in #{hometown}. Likely target doesn't exist.") if $common_travel_debug
            target_id = nil
          else
            Lich::Messaging.msg('plain', "DRCT: get_hometown_target_id succeeded second attempt for #{target} in #{hometown}.") if $common_travel_debug
          end
        end
        Lich::Messaging.msg('plain', "DRCT: target_id = #{target_id}") if $common_travel_debug
        target_id
      end
    end
  end
end
