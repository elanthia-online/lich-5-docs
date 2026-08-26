# frozen_string_literal: true

# Namespace for the Lich 5 scripting engine.
module Lich
  # Namespace for DragonRealms-specific functionality in Lich 5.
  module DragonRealms
    # DragonRealms moonmage utility library.
    #
    # Provides methods for observing and predicting celestial bodies, managing
    # summoned moon weapons, operating divination tools, and tracking moon/planet
    # visibility for spell casting. Most methods wrap game commands and parse their
    # output. Requires drinfomon to be running for UserVars.moons and UserVars.sun.
    module DRCMM
      module_function

      # Moon weapon detection regex. Matches summoned moon weapons in hand.
      # Colors: black (Katamba), red-hot (Yavash), blue-white (Xibar).
      MOON_WEAPON_REGEX = /^(?:black|red-hot|blue-white) moon(?:blade|staff)$/i.freeze

      # Canonical moon weapon base names for glance/hold operations.
      MOON_WEAPON_NAMES = ['moonblade', 'moonstaff'].freeze

      # Expected game messages when wearing a summoned moon weapon.
      MOON_WEAR_MESSAGES = ["You're already", "You can't wear", "Wear what", "telekinetic"].freeze

      # Expected game messages when dropping a summoned moon weapon.
      MOON_DROP_MESSAGES = ["As you open your hand", "What were you referring to"].freeze

      # Maps moon weapon color adjective to moon name.
      MOON_COLOR_TO_NAME = {
        'black'      => 'katamba',
        'red-hot'    => 'yavash',
        'blue-white' => 'xibar'
      }.freeze

      # Regex for extracting moon color from glance output.
      MOON_GLANCE_REGEX = /You glance at a .* (?<color>black|red-hot|blue-white) moon(?:blade|staff)/i.freeze

      # Regex for extracting the spelled-out remaining duration from FOCUSing a
      # moon weapon, e.g. "You judge that the moonblade will last for roughly
      # twenty-nine roisaen." The count is captured as words (a compound like
      # "twenty-nine" or a single word like "five"). The unit is "roisaen"
      # (plural) or "roisan" (singular, i.e. one); one roisaen == 60 seconds.
      MOON_FOCUS_DURATION_REGEX = /will last for roughly (?<count>[a-z][a-z-]*) roisae?n/i.freeze

      # Near expiry (under one roisaen remaining) FOCUS drops the "roughly <count>"
      # form entirely and reports "will last for less than one roisan" -- no
      # spelled count. moon_weapon_duration treats this as 0 roisaen (expiring now).
      MOON_FOCUS_EXPIRING_REGEX = /will last for less than one roisae?n/i.freeze

      # Maps divination tool keywords to their use verb.
      DIV_TOOL_VERBS = {
        'charts' => 'review',
        'bones'  => 'roll',
        'mirror' => 'gaze',
        'bowl'   => 'gaze',
        'prism'  => 'raise'
      }.freeze

      # Minimum minutes remaining before a celestial body sets to be considered "visible."
      MOON_VISIBILITY_TIMER_THRESHOLD = 4

      # Expected game responses when centering a telescope on a target.
      CENTER_TELESCOPE_MESSAGES = [
        'Center what',
        'You put your eye',
        'open it to make any use of it',
        'The pain is too much',
        "That's a bit tough to do when you can't see the sky",
        "You would probably need a periscope to do that",
        'Your search for',
        'Your vision is too fuzzy',
        "You'll need to open it to make any use of it",
        'You must have both hands free'
      ].freeze

      # Expected game responses when observing celestial bodies.
      # Used by `observe` method to match bput responses.
      # Patterns validated via in-game testing with test_observe_comprehensive.lic
      # Note: Roundtime is intentionally NOT included - every observation that produces
      # a Roundtime also produces a more specific pattern that matches first.
      OBSERVE_MESSAGES = [
        'Your search for',                           # Covers: fruitless, foiled by daylight/darkness
        'You see nothing regarding the future',      # No vision available
        'Clouds obscure',                            # Weather blocking
        'The following heavenly bodies are visible:', # Observe heavens listing
        "That's a bit hard to do while inside",      # Indoor blocking
        'too close to the sun',                      # Planet visibility (solar conjunction)
        'too faint for you to pick out',             # Requires telescope
        'You learn nothing of the future',           # Circle too low for body
        'below the horizon',                         # Body not visible
        'You have not pondered',                     # Observation cooldown
        'You are unable to make use',                # Cooldown followup
        'While the sighting',                        # Partial success
        'You learned something useful'               # Full success
      ].freeze

      # Observes a celestial body or list of visible bodies.
      #
      # Sends the observe command and matches common game responses. Pass "heavens"
      # to list all visible bodies; otherwise pass a planet or moon name.
      #
      # @param thing [String] the celestial body or "heavens"
      # @return [String] the game response matched by bput
      # @example
      #   DRCMM.observe('sun')
      #   DRCMM.observe('heavens')
      def observe(thing)
        output = "observe #{thing} in heavens"
        output = 'observe heavens' if thing.eql?('heavens')
        DRC.bput(output.to_s, *OBSERVE_MESSAGES)
      end

      # Predicts the outcome of a spell or spell category.
      #
      # Sends the predict command for a skill or stat and matches common responses.
      # Pass "all" to predict all states at once.
      #
      # @param thing [String] the skill name or "all"
      # @return [String] the game response matched by bput
      # @example
      #   DRCMM.predict('Telekinesis')
      #   DRCMM.predict('all')
      def predict(thing)
        output = "predict #{thing}"
        output = 'predict state all' if thing.eql?('all')
        DRC.bput(output.to_s, 'You predict that', 'You are far too', 'you lack the skill to grasp them fully', /(R|r)oundtime/i, 'You focus inwardly')
      end

      # Studies the sky to gather celestial information.
      #
      # Sends the study sky command and matches common responses.
      #
      # @return [String] the game response matched by bput
      def study_sky
        DRC.bput('study sky', 'You feel a lingering sense', 'You feel it is too soon', 'Roundtime', 'You are unable to sense additional information', 'detect any portents')
      end

      # Gets a telescope from storage and holds it in hand.
      #
      # Retrieves the telescope from the location specified in the storage hash,
      # handling tied, container, or ground storage. Returns true if already in
      # hands or successfully retrieved; false if retrieval fails.
      #
      # @param telescope_name [String] the telescope's item name, defaults to "telescope"
      # @param storage [Hash] storage location hash with keys 'tied' (location string),
      #   'container' (container noun), or neither for ground storage
      # @return [Boolean] true if telescope is now in hands, false otherwise
      # @example
      #   storage = { 'container' => 'pack' }
      #   DRCMM.get_telescope?('spyglass', storage)
      def get_telescope?(telescope_name = 'telescope', storage)
        return true if DRCI.in_hands?(telescope_name)

        if storage['tied']
          DRCI.untie_item?(telescope_name, storage['tied'])
        elsif storage['container']
          unless DRCI.get_item?(telescope_name, storage['container'])
            Lich::Messaging.msg("plain", "DRCMM: Telescope not found in container. Trying to get it from anywhere we can.")
            return DRCI.get_item?(telescope_name)
          end
          true
        else
          DRCI.get_item?(telescope_name)
        end
      end

      # Stores a telescope in the location specified by the storage hash.
      #
      # Puts away the telescope to its tied location, container, or drops it on
      # the ground. Returns true if not in hands or successfully stored; false if
      # storage fails.
      #
      # @param telescope_name [String] the telescope's item name, defaults to "telescope"
      # @param storage [Hash] storage location hash with keys 'tied' (location string),
      #   'container' (container noun), or neither for ground storage
      # @return [Boolean] true if telescope is now stored or not in hands, false otherwise
      # @example
      #   storage = { 'tied' => 'belt' }
      #   DRCMM.store_telescope?('spyglass', storage)
      def store_telescope?(telescope_name = "telescope", storage)
        return true unless DRCI.in_hands?(telescope_name)

        if storage['tied']
          DRCI.tie_item?(telescope_name, storage['tied'])
        elsif storage['container']
          DRCI.put_away_item?(telescope_name, storage['container'])
        else
          DRCI.put_away_item?(telescope_name)
        end
      end

      # @deprecated Use get_telescope? instead
      def get_telescope(storage)
        return if get_telescope?('telescope', storage)

        Lich::Messaging.msg('bold', 'DRCMM: Failed to get telescope.')
      end

      # @deprecated Use store_telescope? instead
      def store_telescope(storage)
        return if store_telescope?('telescope', storage)

        Lich::Messaging.msg('bold', 'DRCMM: Failed to store telescope.')
      end

      # Peers through the telescope to learn about the future.
      #
      # Issues the peer telescope command and blocks until roundtime clears.
      # Matches constellation-specific observation messages from the constellations
      # data file.
      #
      # @return [void]
      # @note Incurs roundtime; do not call every tick
      def peer_telescope
        telescope_regex_patterns = Regexp.union(
          /The pain is too much/,
          /You see nothing regarding the future/,
          /You believe you've learned all that you can about/,
          Regexp.union(get_data('constellations').observe_finished_messages),
          /open it/,
          /Your vision is too fuzzy/,
        )
        Lich::Util.issue_command("peer my telescope", telescope_regex_patterns, /Roundtime: /, usexml: false)
      end

      # Centers the telescope on a planet or celestial target.
      #
      # Sends the center telescope command. Automatically opens the telescope if
      # needed. Messages the player if the target is not visible or if the sky
      # is blocked.
      #
      # @param target [String] the planet or celestial body name
      # @return [void]
      def center_telescope(target)
        case DRC.bput("center telescope on #{target}", *CENTER_TELESCOPE_MESSAGES)
        when 'The pain is too much', "That's a bit tough to do when you can't see the sky"
          Lich::Messaging.msg("bold", "DRCMM: Planet #{target} not visible. Are you indoors perhaps?")
        when "You'll need to open it to make any use of it"
          fput("open my telescope")
          fput("center telescope on #{target}")
        end
      end

      # Aligns with a moonmage skill.
      #
      # Sends the align command to focus internally on a skill.
      #
      # @param skill [String] the skill name to align with
      # @return [String] the game response matched by bput
      def align(skill)
        DRC.bput("align #{skill}", 'You focus internally')
      end

      # Gets divination bones from storage and holds them in hand.
      #
      # Retrieves the bones from the location specified in the storage hash,
      # handling tied, container, or ground storage. Returns true if successfully
      # retrieved; false otherwise.
      #
      # @param storage [Hash] storage location hash with keys 'tied' (location string),
      #   'container' (container noun), or neither for ground storage
      # @return [Boolean] true if bones are now in hands, false otherwise
      # @example
      #   storage = { 'container' => 'pack' }
      #   DRCMM.get_bones?(storage)
      def get_bones?(storage)
        if storage['tied']
          DRCI.untie_item?("bones", storage['tied'])
        elsif storage['container']
          DRCI.get_item?("bones", storage['container'])
        else
          DRCI.get_item?("bones")
        end
      end

      # Stores divination bones in the location specified by the storage hash.
      #
      # Puts away the bones to their tied location, container, or drops them on
      # the ground. Returns true if successfully stored; false otherwise.
      #
      # @param storage [Hash] storage location hash with keys 'tied' (location string),
      #   'container' (container noun), or neither for ground storage
      # @return [Boolean] true if bones are now stored, false otherwise
      # @example
      #   storage = { 'tied' => 'belt' }
      #   DRCMM.store_bones?(storage)
      def store_bones?(storage)
        if storage['tied']
          DRCI.tie_item?("bones", storage['tied'])
        elsif storage['container']
          DRCI.put_away_item?("bones", storage['container'])
        else
          DRCI.put_away_item?("bones")
        end
      end

      # @deprecated Use get_bones? instead
      def get_bones(storage)
        return if get_bones?(storage)

        Lich::Messaging.msg('bold', 'DRCMM: Failed to get bones.')
      end

      # @deprecated Use store_bones? instead
      def store_bones(storage)
        return if store_bones?(storage)

        Lich::Messaging.msg('bold', 'DRCMM: Failed to store bones.')
      end

      # Rolls divination bones and waits for roundtime to clear.
      #
      # Gets the bones from storage, rolls them (incurring roundtime), waits for
      # roundtime to clear, and then stores them back. Messages the player on
      # failure to get or store bones.
      #
      # @param storage [Hash] storage location hash with keys 'tied' (location string),
      #   'container' (container noun), or neither for ground storage
      # @return [void]
      # @note Incurs roundtime; do not call every tick
      def roll_bones(storage)
        unless get_bones?(storage)
          Lich::Messaging.msg('bold', 'DRCMM: Failed to get bones, aborting roll_bones.')
          return
        end

        DRC.bput('roll my bones', 'roundtime')
        waitrt?

        Lich::Messaging.msg('bold', 'DRCMM: Failed to store bones after rolling.') unless store_bones?(storage)
      end

      # Gets a divination tool from storage and holds or wears it.
      #
      # Retrieves a divination tool (charts, bones, mirror, bowl, prism) from the
      # location specified in the tool hash, handling tied, worn, or container
      # storage. Returns true if successfully retrieved; false otherwise.
      #
      # @param tool [Hash] tool configuration hash with keys 'name' (tool noun),
      #   'tied' (location string), 'worn' (boolean), and 'container' (container noun)
      # @return [Boolean] true if tool is now in hands or worn, false otherwise
      # @example
      #   tool = { 'name' => 'bones', 'container' => 'pack' }
      #   DRCMM.get_div_tool?(tool)
      def get_div_tool?(tool)
        if tool['tied']
          DRCI.untie_item?(tool['name'], tool['container'])
        elsif tool['worn']
          DRCI.remove_item?(tool['name'])
        else
          DRCI.get_item?(tool['name'], tool['container'])
        end
      end

      # Stores a divination tool in the location specified by the tool hash.
      #
      # Puts away a divination tool to its tied location, wears it, or stores it
      # in a container. Returns true if successfully stored; false otherwise.
      #
      # @param tool [Hash] tool configuration hash with keys 'name' (tool noun),
      #   'tied' (location string), 'worn' (boolean), and 'container' (container noun)
      # @return [Boolean] true if tool is now stored or worn, false otherwise
      # @example
      #   tool = { 'name' => 'prism', 'worn' => true }
      #   DRCMM.store_div_tool?(tool)
      def store_div_tool?(tool)
        if tool['tied']
          DRCI.tie_item?(tool['name'], tool['container'])
        elsif tool['worn']
          DRCI.wear_item?(tool['name'])
        else
          DRCI.put_away_item?(tool['name'], tool['container'])
        end
      end

      # @deprecated Use get_div_tool? instead
      def get_div_tool(tool)
        return if get_div_tool?(tool)

        Lich::Messaging.msg('bold', "DRCMM: Failed to get divination tool '#{tool['name']}'.")
      end

      # @deprecated Use store_div_tool? instead
      def store_div_tool(tool)
        return if store_div_tool?(tool)

        Lich::Messaging.msg('bold', "DRCMM: Failed to store divination tool '#{tool['name']}'.")
      end

      # Uses a divination tool by executing its associated verb and waits for roundtime.
      #
      # Gets the tool, executes the appropriate verb (review for charts, roll for bones,
      # gaze for mirror/bowl, raise for prism), waits for roundtime to clear, and then
      # stores the tool. Messages the player on failure to get or store the tool.
      #
      # @param tool_storage [Hash] tool configuration hash with keys 'name' (tool noun),
      #   'tied' (location string), 'worn' (boolean), and 'container' (container noun)
      # @return [void]
      # @note Incurs roundtime per tool; do not call every tick
      def use_div_tool(tool_storage)
        unless get_div_tool?(tool_storage)
          Lich::Messaging.msg('bold', "DRCMM: Failed to get divination tool '#{tool_storage['name']}', aborting use_div_tool.")
          return
        end

        DIV_TOOL_VERBS
          .select { |tool, _| tool_storage['name'].include?(tool) }
          .each   { |tool, verb| DRC.bput("#{verb} my #{tool}", 'roundtime'); waitrt? }

        unless store_div_tool?(tool_storage)
          Lich::Messaging.msg('bold', "DRCMM: Failed to store divination tool '#{tool_storage['name']}'.")
        end
      end

      # There are many variants of a summoned moon weapon (blade, staff, sword, etc)
      # This function checks if you're holding one then tries to wear it.
      # Returns true if what is in your hands is a summoned moon weapon that becomes worn.
      # Returns false if you're not holding a moon weapon, or you are but can't wear it.
      # https://elanthipedia.play.net/Shape_Moonblade
      def wear_moon_weapon?
        wore_it = false
        if is_moon_weapon?(DRC.left_hand)
          wore_it = wore_it || DRC.bput("wear #{DRC.left_hand}", *MOON_WEAR_MESSAGES) == "telekinetic"
        end
        if is_moon_weapon?(DRC.right_hand)
          wore_it = wore_it || DRC.bput("wear #{DRC.right_hand}", *MOON_WEAR_MESSAGES) == "telekinetic"
        end
        wore_it
      end

      # Drops the moon weapon in your hands, if any.
      # Returns true if dropped something, false otherwise.
      def drop_moon_weapon?
        dropped_it = false
        if is_moon_weapon?(DRC.left_hand)
          dropped_it = dropped_it || DRC.bput("drop #{DRC.left_hand}", *MOON_DROP_MESSAGES) == "As you open your hand"
        end
        if is_moon_weapon?(DRC.right_hand)
          dropped_it = dropped_it || DRC.bput("drop #{DRC.right_hand}", *MOON_DROP_MESSAGES) == "As you open your hand"
        end
        dropped_it
      end

      # Is a moon weapon in your hands?
      def holding_moon_weapon?
        is_moon_weapon?(DRC.left_hand) || is_moon_weapon?(DRC.right_hand)
      end

      # Try to hold a moon weapon.
      # If you end up not holding a moon weapon then returns false.
      def hold_moon_weapon?
        return true if holding_moon_weapon?
        return false if [DRC.left_hand, DRC.right_hand].compact.length >= 2

        MOON_WEAPON_NAMES.each do |weapon|
          glance = DRC.bput("glance my #{weapon}", "You glance at a .* #{weapon}", "I could not find")
          case glance
          when /You glance/
            return DRC.bput("hold my #{weapon}", "You grab", "You aren't wearing", "Hold hands with whom?", "You need a free hand") == "You grab"
          end
        end
        false
      end

      # Does the item appear to be a moon weapon?
      def is_moon_weapon?(item)
        return false unless item

        MOON_WEAPON_REGEX.match?(item)
      end

      # Returns the moon name used to summon a held or worn moon weapon.
      #
      # Glances at moonblades and moonstaffs to detect color, then maps the color
      # to the moon name (black => katamba, red-hot => yavash, blue-white => xibar).
      # Returns nil if no moon weapon is found or the color cannot be determined.
      #
      # Non-deterministic if multiple weapons are summoned on different moons.
      #
      # @return [String, nil] the moon name ("katamba", "yavash", or "xibar"), or nil
      # @example
      #   DRCMM.moon_used_to_summon_weapon #=> "yavash"
      # @see MOON_COLOR_TO_NAME
      def moon_used_to_summon_weapon
        # Note, if you have more than one weapon summoned at a time
        # then the results of this method are non-deterministic.
        # For example, if you have 2+ moonblades/staffs cast on different moons.
        MOON_WEAPON_NAMES.each do |weapon|
          glance = DRC.bput("glance my #{weapon}", MOON_GLANCE_REGEX, "I could not find")
          match = glance&.match(MOON_GLANCE_REGEX)
          return MOON_COLOR_TO_NAME[match[:color]] if match
        end
        nil
      end

      # Focuses the summoned moon weapon (moonblade/moonstaff) you are holding or
      # wearing and returns how many roisaen it will last: a positive Integer for
      # the "roughly <count> roisaen" form, 0 for the near-expiry "less than one
      # roisan" form, or nil if you have no moon weapon or the phrase could not be
      # parsed. One roisaen == 60 seconds; moonblade duration ranges 12-41 minutes.
      # https://elanthipedia.play.net/Moonblade
      #
      # NOTE: FOCUS incurs roundtime, so callers should not poll this every tick.
      def moon_weapon_duration
        MOON_WEAPON_NAMES.each do |weapon|
          result = DRC.bput("focus my #{weapon}", MOON_FOCUS_DURATION_REGEX, MOON_FOCUS_EXPIRING_REGEX, "I could not find", "Focus on what")

          # Near expiry FOCUS reports "less than one roisan" with no count; treat
          # as 0 roisaen (expiring now) so callers can refresh immediately.
          if result&.match?(MOON_FOCUS_EXPIRING_REGEX)
            waitrt?
            return 0
          end

          match = result&.match(MOON_FOCUS_DURATION_REGEX)
          next unless match

          waitrt?
          return parse_roisaen(match[:count])
        end
        nil
      end

      # Converts a spelled-out roisaen count (as reported by FOCUS, e.g. "five",
      # "twenty", "twenty-nine", "forty-one") into an Integer, or nil if any word
      # is not a recognized number. Compounds may be hyphen- or space-separated
      # and are summed ("forty-one" -> 41). Case-insensitive.
      #
      # Uses the global $NUM_MAP published by drinfomon/drvariables.rb (the same
      # number word map DRC.text2num uses) rather than the Lich::DragonRealms
      # constant, to avoid any namespace-resolution surface.
      def parse_roisaen(text)
        return nil if text.nil?
        return nil if $NUM_MAP.nil?

        words = text.downcase.tr('-', ' ').split
        return nil if words.empty?
        return nil unless words.all? { |word| $NUM_MAP.key?(word) }

        words.sum { |word| $NUM_MAP[word] }
      end

      # Updates astral casting data by setting moon or planet information.
      #
      # Delegates to {#set_moon_data} if the data hash has a 'moon' key, or to
      # {#set_planet_data} if it has a 'stats' key. Returns the updated data hash
      # with a 'cast' key set to the spell command, or nil if no moon/planet is
      # available.
      #
      # @param data [Hash] astral spell data with 'moon' or 'stats' key
      # @param settings [OpenStruct, nil] optional settings object with telescope_name
      #   and telescope_storage for planet visibility checking
      # @return [Hash, nil] the data hash with 'cast' key set, or nil if no valid moon/planet
      # @see #set_moon_data
      # @see #set_planet_data
      def update_astral_data(data, settings = nil)
        if data['moon']
          data = set_moon_data(data)
        elsif data['stats']
          data = set_planet_data(data, settings)
        end
        data
      end

      # Finds which planets are visible by centering the telescope on each.
      #
      # Gets the telescope, centers it on each planet in the list, and collects those
      # that do not produce a "fruitless" message. Stores the telescope back and returns
      # the list of visible planet names.
      #
      # @param planets [Array<String>] list of planet names to check
      # @param settings [OpenStruct, nil] settings object with telescope_name and
      #   telescope_storage
      # @return [Array<String>] visible planet names, or empty array if telescope retrieval fails
      # @note Requires moonwatch to be running
      def find_visible_planets(planets, settings = nil)
        unless get_telescope?(settings.telescope_name, settings.telescope_storage)
          Lich::Messaging.msg("bold", "DRCMM: Could not get telescope to find visible planets.")
          return
        end

        Flags.add('planet-not-visible', 'turns up fruitless')
        observed_planets = []

        begin
          planets.each do |planet|
            center_telescope(planet)
            observed_planets << planet unless Flags['planet-not-visible']
            Flags.reset('planet-not-visible')
          end
        ensure
          Flags.delete('planet-not-visible')
        end

        Lich::Messaging.msg("bold", "DRCMM: Could not store telescope after finding visible planets.") unless store_telescope?(settings.telescope_name, settings.telescope_storage)
        observed_planets
      end

      # Sets planet casting data by finding a visible planet that buffs the desired stat.
      #
      # Queries the constellations data file for planets that affect the stats in the
      # spell data, finds which planets are currently visible, and sets the 'cast' key
      # to the first matching planet. Returns the data with 'cast' key, or nil if no
      # visible planet buffs any of the requested stats.
      #
      # @param data [Hash] spell data with 'stats' key (array of stat names) and 'abbrev' key
      # @param settings [OpenStruct, nil] settings object with telescope_name and
      #   telescope_storage
      # @return [Hash, nil] the data hash with 'cast' key set, or the original data if no match
      # @see #find_visible_planets
      def set_planet_data(data, settings = nil)
        return data unless data['stats']

        planets = get_data('constellations')[:constellations].select { |planet| planet['stats'] }
        planet_names = planets.map { |planet| planet['name'] }
        visible_planets = find_visible_planets(planet_names, settings)
        data['stats'].each do |stat|
          cast_on = planets.map { |planet| planet['name'] if planet['stats'].include?(stat) && visible_planets.include?(planet['name']) }.compact.first
          next unless cast_on

          data['cast'] = "cast #{cast_on}"
          return data
        end
        Lich::Messaging.msg("bold", "DRCMM: Could not set planet data. Cannot cast #{data['abbrev']}.")
      end

      # Sets moon casting data by selecting a visible moon, or ambient for Cage of Light.
      #
      # Queries visible moons and sets the 'cast' key to the first visible moon name.
      # For Cage of Light (case-insensitive), falls back to "cast ambient" if no moons
      # are visible. Returns nil and messages the player if no moon is available for
      # other spells.
      #
      # @param data [Hash] spell data with 'moon' key and 'name' key
      # @return [Hash, nil] the data hash with 'cast' key set, or nil if no valid moon
      # @see #visible_moons
      def set_moon_data(data)
        return data unless data['moon']

        moon = visible_moons.first
        if moon
          data['cast'] = "cast #{moon}"
        elsif data['name'].downcase == 'cage of light'
          data['cast'] = "cast ambient"
        else
          Lich::Messaging.msg("bold", "DRCMM: No moon available to cast #{data['name']}.")
          data = nil
        end
        data
      end

      # returns true if at least one bright moon (yavash, xibar) or the sun are
      #  above the horizon and won't set for at least another ~4 minutes.
      def bright_celestial_object?
        check_moonwatch
        (UserVars.sun['day'] && UserVars.sun['timer'] >= MOON_VISIBILITY_TIMER_THRESHOLD) || moon_visible?('xibar') || moon_visible?('yavash')
      end

      # returns true if at least one moon (katamba, yavash, xibar) or the sun are
      #  above the horizon and won't set for at least another ~4 minutes.
      def any_celestial_object?
        check_moonwatch
        (UserVars.sun['day'] && UserVars.sun['timer'] >= MOON_VISIBILITY_TIMER_THRESHOLD) || moons_visible?
      end

      # Returns true if at least one moon (e.g. katamba, yavash, xibar)
      # is above the horizon and won't set for at least another ~4 minutes.
      def moons_visible?
        !visible_moons.empty?
      end

      # Returns true if the moon is above the horizon and won't set for at least another ~4 minutes.
      def moon_visible?(moon_name)
        visible_moons.include?(moon_name)
      end

      # Returns list of moon names (e.g. katamba, yavash, xibar)
      # that are above the horizon and won't set for at least another ~4 minutes.
      def visible_moons
        check_moonwatch
        UserVars.moons.select { |moon_name, moon_data| UserVars.moons['visible'].include?(moon_name) && moon_data['timer'] >= MOON_VISIBILITY_TIMER_THRESHOLD }
                      .map { |moon_name, _moon_data| moon_name }
      end

      # Ensures moonwatch script is running and UserVars.moons is populated.
      #
      # Checks if the moonwatch script is running. If not, starts it, initializes
      # UserVars.moons, waits for it to populate, and messages the player to
      # autostart moonwatch in the future.
      #
      # @return [void]
      # @api private
      def check_moonwatch
        return if Script.running?('moonwatch')

        Lich::Messaging.msg("bold", "DRCMM: moonwatch is not running. Starting it now.")
        UserVars.moons = {}
        start_script('moonwatch')
        Lich::Messaging.msg("plain", "DRCMM: Run `#{$clean_lich_char}e autostart('moonwatch')` to avoid this in the future.")
        pause 0.5 while UserVars.moons.empty?
      end
    end
  end
end
