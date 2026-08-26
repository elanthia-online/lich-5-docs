=begin
stash.rb: Core lich file for extending free_hands, empty_hands functions in
  item / container script indifferent method.  Usage will ensure no regex is
  required to be maintained.
=end

# Namespace for Lich 5 scripting engine functionality.
module Lich
  # Namespace for inventory container and equipment management.
  #
  # Provides methods to locate containers, move items between hands and storage,
  # and manage the queuing of item stashing and equipping actions.
  module Stash
    @weapon_displayer ||= []
    @bandolier_weapon ||= {}
    @worn_items ||= {}

    # Finds a container in inventory by partial name match.
    #
    # Searches the player's inventory for a container whose name matches the given
    # parameter using two regex patterns: literal substring match and flexible
    # space-separated word match. Returns nil if not found and loud_fail is false.
    #
    # @param param [String, GameObj] container name or a GameObj to extract the name from
    # @param loud_fail [Boolean] if true, raises an error when container not found; if false, returns nil
    # @return [GameObj, nil] the found container, or nil if not found and loud_fail is false
    # @raise [RuntimeError] "could not find Container[name: ...]" when container not found and loud_fail is true
    # @example Find a backpack
    #   Lich::Stash.find_container("backpack", loud_fail: false)
    def self.find_container(param, loud_fail: true)
      param = param.name if param.is_a?(GameObj) # (Lich::Gemstone::GameObj)
      found_container = GameObj.inv.find do |container|
        container.name =~ %r[#{param.strip}]i || container.name =~ %r[#{param.sub(' ', ' .*')}]i
      end
      if found_container.nil? && loud_fail
        fail "could not find Container[name: #{param}]"
      else
        return found_container
      end
    end

    # Returns a container after ensuring it is open and its contents are visible.
    #
    # Looks up the container using .find_container, opens it if closed, and updates
    # the internal @weapon_displayer cache to track which containers have had their
    # contents exposed. This is a setup method meant to be called before manipulating
    # container contents.
    #
    # @param param [String, GameObj] container name or GameObj
    # @return [GameObj] the container object
    # @raise [RuntimeError] if the container cannot be found
    def self.container(param)
      container_to_check = find_container(param)
      unless @weapon_displayer.include?(container_to_check.id)
        result = Lich::Util.issue_command("look in ##{container_to_check.id}", /In the .*$|That is closed\.|^You glance at/, silent: true, quiet: true) if container_to_check.contents.nil?
        fput "open ##{container_to_check.id}" if result.include?('That is closed.')
        @weapon_displayer.push(container_to_check.id) if GameObj.containers.find { |item| item[0] == container_to_check.id }.nil?
      end
      return container_to_check
    end

    # Executes a command and waits for a condition block to return true within a timeout.
    #
    # Issues the command with .fput, then repeatedly yields the fput result to the
    # caller's block until the block returns true or the timeout expires. Raises an
    # error if the timeout is exceeded.
    #
    # @param seconds [Numeric] how long to wait (default: 2)
    # @param command [String] the command to execute
    # @yield [result] yields the fput result string to the block; block should return true when condition is met
    # @return [void]
    # @raise [RuntimeError] "Error[command: ..., seconds: ...]" if timeout exceeded
    # @example Wait for a successful result
    #   Lich::Stash.try_or_fail(seconds: 3, command: "get sword") { |result| !result.include?("You can't find that") }
    def self.try_or_fail(seconds: 2, command: nil)
      result = fput(command)
      expiry = Time.now + seconds
      wait_until do yield(result) || Time.now > expiry end
      fail "Error[command: #{command}, seconds: #{seconds}]" if Time.now > expiry
    end

    # Moves an item into a container using _drag.
    #
    # Drags the item into the bag and polls for confirmation that it arrived. Handles
    # three special cases: bandolier weapons (which dissolve into vapor and are cached),
    # ethereal weapons (checked by name pattern), and normal items. Retries for up to
    # 2 seconds until the item is no longer in either hand and is present in the
    # container or marked as stashed (for bandolier).
    #
    # @param bag [String, GameObj] container name or container GameObj
    # @param item [GameObj] the item to move
    # @return [Boolean] true if item was successfully moved or cached as bandolier; false if timeout
    # @example
    #   Lich::Stash.add_to_bag("backpack", GameObj.right_hand)
    def self.add_to_bag(bag, item)
      bag = container(bag)
      try_or_fail(command: "_drag ##{item.id} ##{bag.id}") do |result|
        # Check for vapor message first (bandolier)
        if result.is_a?(String) && result =~ /As you drop .+ it dissolves into vapor\./
          @bandolier_weapon[item.name] = "unknown"
          return true
        end

        20.times {
          return true if @bandolier_weapon[item.name]
          return true if ![GameObj.right_hand, GameObj.left_hand].map(&:id).compact.include?(item.id) && @weapon_displayer.include?(bag.id)
          return true if (![GameObj.right_hand, GameObj.left_hand].map(&:id).compact.include?(item.id) && bag.contents.to_a.map(&:id).include?(item.id))
          return true if item.name =~ /^ethereal \w+$/ && ![GameObj.right_hand, GameObj.left_hand].map(&:id).compact.include?(item.id)
          sleep 0.1
        }
        return false
      end
    end

    # Attempts to move an item from worn equipment to inventory via the wear command.
    #
    # Uses the wear command to toggle an item off, which places it in inventory.
    # Polls for up to 2 seconds for the item to leave both hands and appear in
    # inventory. Caches the result in @worn_items. If the item cannot be worn to
    # inventory (e.g., due to wear slot limitations), records false in the cache.
    #
    # @param item [GameObj] the equipped item to move to inventory
    # @return [Boolean] false if the item could not be worn to inventory; true if successful
    # @api private
    def self.wear_to_inv(item)
      try_or_fail(command: "wear ##{item.id}") do |result|
        20.times {
          return true if (![GameObj.right_hand, GameObj.left_hand].map(&:id).compact.include?(item.id) && GameObj.inv.to_a.map(&:id).include?(item.id))
          return true if item.name =~ /^ethereal \w+$/ && ![GameObj.right_hand, GameObj.left_hand].map(&:id).compact.include?(item.id)
          sleep 0.1
        } unless result.is_a?(String) && result =~ /You can only wear two items in that location\./

        return @worn_items[item.name] = false
      end
    end

    # Locates which bandolier bag (if any) contains a bandolier weapon.
    #
    # Returns a cached container ID if valid and the container still exists in inventory.
    # Otherwise queries inventory for all containers, then checks each one for the item's
    # noun surrounded by swirling mist (the bandolier's display indicator). Caches the
    # result as the container's ID or "unknown" if not found.
    #
    # @param item [GameObj] the weapon to search for
    # @return [String, nil] the container ID if found; nil if not found in any bandolier
    # @note Performs multiple server queries; may be slow when called for many items
    # @example
    #   bag_id = Lich::Stash.find_bandolier_bag(my_sword)
    #   fput("rub ##{bag_id}") if bag_id
    def self.find_bandolier_bag(item)
      # Return cached value if valid and item exists in inventory
      cached_id = @bandolier_weapon[item.name]
      return cached_id if cached_id && cached_id != "unknown" &&
                          GameObj.inv.any? { |inv_item| inv_item.id == cached_id }

      # Regex patterns for parsing
      look_in_regex = Regexp.union(
        /^I could not find what you were referring to./,
        /^Surrounded by some swirling mist is /,
        /^In the /,
        /contains (?:DOSE|TINCTURE)s of the following /,
        /There is nothing in there\./,
        /<exposeContainer/,
        /<dialogData/,
        /<container/,
        /you glance/,
        /That is closed\./
      )

      item_regex = %r{<a exist="(?<id>[^"]+)" noun="(?<noun>[^"]+)">(?<name>[^<]+)</a>}

      # Collect all containers from inventory
      waitrt?
      results = Lich::Util.issue_command("inventory containers", /^You are holding /, timeout: 3, silent: true, quiet: true)
      containers = results.flat_map { |line|
        line.scan(item_regex).map { |id, _noun, _name| GameObj[id] }
      }.compact

      # Find container with the item using mist indicator
      item_noun_regex = /\b#{Regexp.escape(item.noun)}\b/
      found_container = containers.find do |container|
        waitrt?
        results = Lich::Util.issue_command(
          "look in ##{container.id}",
          look_in_regex,
          timeout: 2,
          silent: true,
          quiet: true
        )

        results.any? { |line|
          line.include?("Surrounded by some swirling mist is") && line.match?(item_noun_regex)
        }
      end

      @bandolier_weapon[item.name] = found_container&.id || "unknown"
    end

    # Queues actions to stash items from one or both hands into containers.
    #
    # Constructs and caches a list of Procs that will move the current right hand,
    # left hand, or both to appropriate containers based on ReadyList and StowList
    # configuration. Prioritizes sheaths, then weaponsacks for weapons, then the
    # lootsack, then any other available containers. Also handles ethereal weapons
    # (rub tattoo) and bandolier weapons (rub bag). Call .equip_hands later to
    # execute the queued actions.
    #
    # @param right [Boolean] if true, queue actions to stash the right hand item
    # @param left [Boolean] if true, queue actions to stash the left hand item
    # @param both [Boolean] if true, queue actions to stash both hands (takes precedence)
    # @return [void]
    # @note Requires ReadyList and StowList to be valid; checks and updates them automatically
    # @see .equip_hands
    def self.stash_hands(right: false, left: false, both: false)
      $fill_hands_actions ||= Array.new
      $fill_left_hand_actions ||= Array.new
      $fill_right_hand_actions ||= Array.new

      actions = Array.new
      right_hand = GameObj.right_hand
      left_hand = GameObj.left_hand

      # extending to use sheath / 2sheath wherever possible
      unless ReadyList.valid?
        ReadyList.check(silent: true, quiet: true)
      end
      # extending to use default stow container wherever possible
      unless StowList.valid?
        StowList.check(silent: true, quiet: true)
      end
      if ReadyList.sheath
        unless ReadyList.secondary_sheath
          sheath = second_sheath = ReadyList.sheath
        else
          sheath = ReadyList.sheath if ReadyList.sheath
          second_sheath = ReadyList.secondary_sheath if ReadyList.secondary_sheath
        end
      elsif ReadyList.secondary_sheath
        sheath = second_sheath = ReadyList.secondary_sheath
      else
        sheath = second_sheath = nil
      end
      # weaponsack for both hands
      if UserVars.weapon.is_a?(String) && UserVars.weaponsack.is_a?(String) && !UserVars.weapon.empty? && !UserVars.weaponsack.empty? && (right_hand.name =~ /#{Regexp.escape(UserVars.weapon.strip)}/i || right_hand.name =~ /#{Regexp.escape(UserVars.weapon).sub(' ', ' .*')}/i)
        weaponsack = nil unless (weaponsack = find_container(UserVars.weaponsack, loud_fail: false)).is_a?(GameObj) # (Lich::Gemstone::GameObj)
      end
      # lootsack for both hands
      if !UserVars.lootsack.is_a?(String) || UserVars.lootsack.empty?
        lootsack = nil
      else
        lootsack = nil unless (lootsack = find_container(UserVars.lootsack, loud_fail: false)).is_a?(GameObj) # (Lich::Gemstone::GameObj)
      end
      # finding another container if needed
      other_containers_var = nil
      other_containers = proc {
        results = Lich::Util.issue_command('inventory containers', /^(?:You are (?:carrying nothing|holding no containers) at this time|You are wearing)/, silent: true, quiet: true)
        other_containers_ids = results.to_s.scan(/exist=\\"(.*?)\\"/).flatten - [lootsack.id]
        other_containers_var = GameObj.inv.find_all { |obj| other_containers_ids.include?(obj.id) }
        other_containers_var
      }

      if (left || both) && left_hand.id
        waitrt?
        if (left_hand.noun =~ /shield|buckler|targe|heater|parma|aegis|scutum|greatshield|mantlet|pavis|arbalest|bow|crossbow|yumi|arbalest/) && @worn_items[left_hand.name] != false && Lich::Stash::wear_to_inv(left_hand)
          actions.unshift proc {
            fput "remove ##{left_hand.id}"
            20.times { break if GameObj.left_hand.id == left_hand.id || GameObj.right_hand.id == left_hand.id; sleep 0.1 }

            if GameObj.right_hand.id == left_hand.id
              dothistimeout 'swap', 3, /^You don't have anything to swap!|^You swap/
            end
          }
        else
          actions.unshift proc {
            if left_hand.name =~ /^ethereal \w+$/
              fput "rub #{left_hand.noun} tattoo"
              20.times { break if (GameObj.left_hand.name == left_hand.name) || (GameObj.right_hand.name == left_hand.name); sleep 0.1 }
            elsif @bandolier_weapon[left_hand.name]
              fput "rub ##{find_bandolier_bag(left_hand)}"
              20.times { break if (GameObj.left_hand.name == left_hand.name) || (GameObj.right_hand.name == left_hand.name); sleep 0.1 }
            else
              fput "get ##{left_hand.id}"
              20.times { break if (GameObj.left_hand.id == left_hand.id) || (GameObj.right_hand.id == left_hand.id); sleep 0.1 }
            end

            if GameObj.right_hand.id == left_hand.id || (GameObj.right_hand.name == left_hand.name && left_hand.name =~ /^ethereal \w+$/)
              dothistimeout 'swap', 3, /^You don't have anything to swap!|^You swap/
            end
          }
          if (ready_item = ReadyList.ready_list.find { |_k, v| v.id.eql?(GameObj.left_hand.id) }) && ReadyList.store_list[ready_item[0]]
            result = Lich::Stash.add_to_bag(sheath, GameObj.left_hand) if ReadyList.store_list[ready_item[0]].eql?("put in sheath")
            result = Lich::Stash.add_to_bag(second_sheath, GameObj.left_hand) if ReadyList.store_list[ready_item[0]].eql?("put in secondary sheath")
            result = Lich::Stash.add_to_bag(StowList.default, GameObj.left_hand) if ["worn if possible, stowed otherwise", "stowed"].include?(ReadyList.store_list[ready_item[0]])
          elsif !second_sheath.nil? && GameObj.left_hand.type =~ /weapon/
            result = Lich::Stash.add_to_bag(second_sheath, GameObj.left_hand)
          elsif weaponsack && GameObj.left_hand.type =~ /weapon/
            result = Lich::Stash::add_to_bag(weaponsack, GameObj.left_hand)
          elsif lootsack
            result = Lich::Stash::add_to_bag(lootsack, GameObj.left_hand)
          else
            result = nil
          end
          if result.nil? || !result
            for container in other_containers.call
              result = Lich::Stash::add_to_bag(container, GameObj.left_hand)
              break if result
            end
          end
        end
      end
      if (right || both) && right_hand.id
        waitrt?
        actions.unshift proc {
          if right_hand.name =~ /^ethereal \w+$/
            fput "rub #{right_hand.noun} tattoo"
            20.times { break if GameObj.left_hand.name == right_hand.name || GameObj.right_hand.name == right_hand.name; sleep 0.1 }
          elsif @bandolier_weapon[right_hand.name]
            fput "rub ##{find_bandolier_bag(right_hand)}"
            20.times { break if GameObj.left_hand.name == right_hand.name || GameObj.right_hand.name == right_hand.name; sleep 0.1 }
          else
            fput "get ##{right_hand.id}"
            20.times { break if GameObj.left_hand.id == right_hand.id || GameObj.right_hand.id == right_hand.id; sleep 0.1 }
          end

          if GameObj.left_hand.id == right_hand.id || (GameObj.left_hand.name == right_hand.name && right_hand.name =~ /^ethereal \w+$/)
            dothistimeout 'swap', 3, /^You don't have anything to swap!|^You swap/
          end
        }
        if (ready_item = ReadyList.ready_list.find { |_k, v| v.id.eql?(GameObj.right_hand.id) }) && ReadyList.store_list[ready_item[0]]
          result = Lich::Stash.add_to_bag(sheath, GameObj.right_hand) if ReadyList.store_list[ready_item[0]].eql?("put in sheath")
          result = Lich::Stash.add_to_bag(second_sheath, GameObj.right_hand) if ReadyList.store_list[ready_item[0]].eql?("put in secondary sheath")
          result = Lich::Stash.add_to_bag(StowList.default, GameObj.right_hand) if ["worn if possible, stowed otherwise", "stowed"].include?(ReadyList.store_list[ready_item[0]])
        elsif !sheath.nil? && GameObj.right_hand.type =~ /weapon/
          result = Lich::Stash.add_to_bag(sheath, GameObj.right_hand)
        elsif weaponsack && GameObj.right_hand.type =~ /weapon/
          result = Lich::Stash::add_to_bag(weaponsack, GameObj.right_hand)
        elsif lootsack
          result = Lich::Stash::add_to_bag(lootsack, GameObj.right_hand)
        else
          result = nil
        end
        sleep 0.1
        if result.nil? || !result
          for container in other_containers.call
            result = Lich::Stash::add_to_bag(container, GameObj.right_hand)
            break if result
          end
        end
      end
      $fill_hands_actions.push(actions) if both
      $fill_left_hand_actions.push(actions) if left
      $fill_right_hand_actions.push(actions) if right
    end

    # Executes queued stashing actions for one or both hands.
    #
    # Pops and calls the Procs that were queued by a prior call to .stash_hands.
    # If both are specified, executes the both-hands queue. If left or right are
    # specified, executes their respective queues. If none are specified, executes
    # the right-hand queue if available, otherwise the left-hand queue.
    #
    # @param both [Boolean] if true, execute queued both-hands actions
    # @param left [Boolean] if true, execute queued left-hand actions
    # @param right [Boolean] if true, execute queued right-hand actions
    # @return [void]
    # @see .stash_hands
    def self.equip_hands(left: false, right: false, both: false)
      if both
        for action in $fill_hands_actions.pop
          action.call
        end
      elsif left
        for action in $fill_left_hand_actions.pop
          action.call
        end
      elsif right
        for action in $fill_right_hand_actions.pop
          action.call
        end
      else
        if $fill_right_hand_actions.length > 0
          for action in $fill_right_hand_actions.pop
            action.call
          end
        elsif $fill_left_hand_actions.length > 0
          for action in $fill_left_hand_actions.pop
            action.call
          end
        end
      end
    end
  end
end
