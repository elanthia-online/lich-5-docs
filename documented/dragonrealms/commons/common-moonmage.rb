# frozen_string_literal: true

# Namespace for the Lich scripting engine.
module Lich
  # Namespace for DragonRealms-specific functionality.
  module DragonRealms
    # Module for common moonmage script utilities in DragonRealms.
    # Provides methods for celestial observations, divination tools, moon weapon
    # handling, and moonwatch data management.
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

      # The moons moonwatch publishes in UserVars.moons, each with a 'timer'.
      MOON_NAMES = %w[katamba yavash xibar].freeze

      # Seconds check_moonwatch waits, after starting moonwatch or when
      # moonwatch is already running, for it to publish real moon data (and,
      # separately, for another caller's start of moonwatch to finish).
      MOONWATCH_READY_TIMEOUT = 10

      # Extra seconds a caller queued behind another caller's start of
      # moonwatch waits for that start to finish, beyond its own timeout. The
      # holder's wait for the data begins only once start_script returns, so
      # without this margin a caller that queued while the holder was still in
      # start_script would time out just before the holder's own wait does.
      MOONWATCH_LOCK_WAIT_MARGIN = 1

      # Seconds between polls while check_moonwatch waits for moonwatch.
      MOONWATCH_POLL_INTERVAL = 0.1

      # Seconds check_moonwatch waits before starting moonwatch again after
      # its own start of moonwatch failed (moonwatch could not be found, did
      # not start, or stopped before publishing). Without this, a moonwatch
      # that crashes at startup would be restarted by every moon check.
      MOONWATCH_RESTART_COOLDOWN = 60

      # Serializes check_moonwatch's not-running -> reset -> start sequence so two
      # callers never both start moonwatch, and a late caller never wipes data a
      # freshly started moonwatch has already published.
      MOONWATCH_START_LOCK = Mutex.new

      # Makes the stuck-start latch's set and clear atomic with taking and
      # releasing MOONWATCH_START_LOCK (see note_moonwatch_start_stuck).
      MOONWATCH_STATE_LOCK = Mutex.new

      # Set when a wait for moonwatch's data timed out while moonwatch kept
      # running: by await_running_moonwatch, or by check_moonwatch's own start
      # (via note_moonwatch_start_failure). See note_moonwatch_stall.
      @moonwatch_data_stalled = false

      # Monotonic time before which check_moonwatch does not start moonwatch
      # again (see note_moonwatch_start_failure); nil when it may.
      @moonwatch_restart_blocked_until = nil

      # Set when a caller timed out waiting for another caller's start of
      # moonwatch to finish (that caller's script is paused, or its start is
      # stuck). While that start still holds MOONWATCH_START_LOCK, later
      # callers queued on the lock do not wait for it again. Cleared when a
      # caller gets the lock and again when it releases the lock.
      @moonwatch_start_stuck = false

      # Counts check_moonwatch's acquisitions of MOONWATCH_START_LOCK, so a
      # caller that timed out on one start never latches a later one as stuck.
      @moonwatch_start_generation = 0

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

      # Observes a celestial body or the heavens using the observe command.
      #
      # @param thing [String] the body or location to observe, e.g. "yavash",
      #   "xibar", "katamba", or "heavens" for a general observation
      # @return [String] the game output from the observe command
      # @example
      #   DRCMM.observe('yavash')
      #   DRCMM.observe('heavens')
      def observe(thing)
        output = "observe #{thing} in heavens"
        output = 'observe heavens' if thing.eql?('heavens')
        DRC.bput(output.to_s, *OBSERVE_MESSAGES)
      end

      # Predicts the state of celestial bodies or all predictions using the predict command.
      #
      # @param thing [String] the body to predict or "all" for all predictions
      # @return [String] the game output from the predict command
      # @example
      #   DRCMM.predict('yavash')
      #   DRCMM.predict('all')
      def predict(thing)
        output = "predict #{thing}"
        output = 'predict state all' if thing.eql?('all')
        DRC.bput(output.to_s, 'You predict that', 'You are far too', 'you lack the skill to grasp them fully', /(R|r)oundtime/i, 'You focus inwardly')
      end

      # Studies the sky to sense portents and lingering celestial impressions.
      #
      # @return [String] the game output from the study sky command
      # @example
      #   DRCMM.study_sky
      def study_sky
        DRC.bput('study sky', 'You feel a lingering sense', 'You feel it is too soon', 'Roundtime', 'You are unable to sense additional information', 'detect any portents')
      end

      # Retrieves a telescope from storage (tied, in a container, or on the ground).
      #
      # Returns true if the telescope is already in hand, if retrieval succeeds, or if
      # no storage location is configured. Returns false only if retrieval fails when a
      # storage location exists.
      #
      # @param telescope_name [String] the name of the telescope item, defaults to
      #   "telescope"
      # @param storage [Hash] storage configuration with optional keys 'tied' (location
      #   to untie from), 'container' (container to get from)
      # @return [Boolean] true if the telescope is in hand or retrieval succeeded,
      #   false if retrieval failed
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

      # Stores a telescope away to tied location, container, or ground.
      #
      # Returns true if the telescope is not in hand or if storage succeeds. Returns
      # false only if storage fails when the telescope is in hand.
      #
      # @param telescope_name [String] the name of the telescope item, defaults to
      #   "telescope"
      # @param storage [Hash] storage configuration with optional keys 'tied' (location
      #   to tie to), 'container' (container to put in)
      # @return [Boolean] true if the telescope was not in hand or storage succeeded,
      #   false if storage failed
      # @example
      #   storage = { 'container' => 'pack' }
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

      # Peers through a telescope to examine constellations or learn about the future.
      #
      # Issues the peer command and waits for roundtime. Patterns matched are specific
      # to telescope use, including learning completion and vision quality messages.
      #
      # @return [void]
      # @example
      #   DRCMM.peer_telescope
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

      # Centers a telescope on a celestial target (planet or constellation).
      #
      # Sends the center command and handles conditional responses: if the telescope
      # is closed, attempts to open it; if the planet is not visible, logs a message.
      #
      # @param target [String] the planet or constellation name to center on
      # @return [void]
      # @example
      #   DRCMM.center_telescope('lornon')
      def center_telescope(target)
        case DRC.bput("center telescope on #{target}", *CENTER_TELESCOPE_MESSAGES)
        when 'The pain is too much', "That's a bit tough to do when you can't see the sky"
          Lich::Messaging.msg("bold", "DRCMM: Planet #{target} not visible. Are you indoors perhaps?")
        when "You'll need to open it to make any use of it"
          fput("open my telescope")
          fput("center telescope on #{target}")
        end
      end

      # Aligns internal focus on a moonmage skill.
      #
      # @param skill [String] the skill name to align on, e.g. "lunar", "stellar"
      # @return [String] the game output from the align command
      # @example
      #   DRCMM.align('lunar')
      def align(skill)
        DRC.bput("align #{skill}", 'You focus internally')
      end

      # Retrieves divination bones from storage (tied or in a container).
      #
      # Returns true if retrieval succeeds or no storage location is configured.
      # Returns false only if retrieval fails when a storage location exists.
      #
      # @param storage [Hash] storage configuration with optional keys 'tied' (location
      #   to untie from), 'container' (container to get from)
      # @return [Boolean] true if retrieval succeeded or storage not configured,
      #   false if retrieval failed
      # @example
      #   storage = { 'container' => 'sack' }
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

      # Stores divination bones away to tied location or container.
      #
      # Returns true if storage succeeds or bones are not in hand. Returns false only
      # if storage fails when bones are in hand.
      #
      # @param storage [Hash] storage configuration with optional keys 'tied' (location
      #   to tie to), 'container' (container to put in)
      # @return [Boolean] true if storage succeeded or bones not in hand,
      #   false if storage failed
      # @example
      #   storage = { 'container' => 'sack' }
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

      # Retrieves bones, rolls them for divination, and stores them away.
      #
      # Retrieves from storage, executes "roll my bones", waits for roundtime, and
      # stores the bones back. Logs a message and returns early if retrieval fails.
      # Logs a separate message if storing fails after rolling.
      #
      # @param storage [Hash] storage configuration with 'tied' or 'container' keys
      # @return [void]
      # @example
      #   storage = { 'container' => 'sack' }
      #   DRCMM.roll_bones(storage)
      def roll_bones(storage)
        unless get_bones?(storage)
          Lich::Messaging.msg('bold', 'DRCMM: Failed to get bones, aborting roll_bones.')
          return
        end

        DRC.bput('roll my bones', 'roundtime')
        waitrt?

        Lich::Messaging.msg('bold', 'DRCMM: Failed to store bones after rolling.') unless store_bones?(storage)
      end

      # Retrieves a divination tool from storage (tied, worn, or in a container).
      #
      # Returns true if retrieval succeeds or no storage location is configured.
      # Returns false only if retrieval fails when a storage location exists.
      #
      # @param tool [Hash] tool configuration with 'name' (item name) and optional keys
      #   'tied' (location to untie from), 'worn' (whether worn), 'container' (container
      #   to get from)
      # @return [Boolean] true if retrieval succeeded or storage not configured,
      #   false if retrieval failed
      # @example
      #   tool = { 'name' => 'bones', 'container' => 'sack' }
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

      # Stores a divination tool away to tied location, wears it, or puts it in a container.
      #
      # Returns true if storage succeeds or the tool is not in hand. Returns false only
      # if storage fails when the tool is in hand.
      #
      # @param tool [Hash] tool configuration with 'name' (item name) and optional keys
      #   'tied' (location to tie to), 'worn' (whether to wear it), 'container'
      #   (container to put in)
      # @return [Boolean] true if storage succeeded or tool not in hand,
      #   false if storage failed
      # @example
      #   tool = { 'name' => 'bones', 'container' => 'sack' }
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

      # Retrieves a divination tool, uses it (with appropriate verb for the tool type),
      # and stores it away.
      #
      # For each tool keyword in DIV_TOOL_VERBS that matches the tool name, executes
      # the corresponding verb (e.g., "review my charts", "roll my bones") and waits
      # for roundtime. Logs messages on retrieval or storage failure.
      #
      # @param tool_storage [Hash] tool configuration with 'name' and optional storage
      #   keys 'tied', 'worn', 'container'
      # @return [void]
      # @example
      #   tool = { 'name' => 'bones', 'container' => 'sack' }
      #   DRCMM.use_div_tool(tool)
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

      # Determines which moon (katamba, yavash, or xibar) was used to summon the
      # currently held moon weapon.
      #
      # Examines a held moonblade or moonstaff by its color adjective and returns the
      # corresponding moon name. Returns nil if no moon weapon is held or the moon
      # cannot be determined. Results are non-deterministic if multiple moon weapons
      # are summoned simultaneously on different moons.
      #
      # @return [String, nil] the moon name ('katamba', 'yavash', or 'xibar'),
      #   or nil if no moon weapon is held
      # @example
      #   DRCMM.moon_used_to_summon_weapon #=> 'xibar'
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

      # Updates astral spell data with cast targeting information for moons or planets.
      #
      # Routes to #set_moon_data or #set_planet_data based on the data type. Modifies
      # the data hash by setting a 'cast' key with the target ('moon_name', 'planet_name',
      # or 'ambient'). Returns nil if no valid target is available (logged with a message).
      #
      # @param data [Hash] astral spell data with 'moon' or 'stats' key; typically
      #   includes 'name' and 'abbrev' for logging
      # @param settings [OpenStruct, nil] optional settings with telescope configuration
      #   for planet visibility checks
      # @return [Hash, nil] the updated data hash with 'cast' key set, or nil if
      #   targeting failed
      # @example
      #   data = { 'moon' => true, 'name' => 'Moonburst' }
      #   DRCMM.update_astral_data(data) #=> { 'moon' => true, 'name' => 'Moonburst', 'cast' => 'cast yavash' }
      def update_astral_data(data, settings = nil)
        if data['moon']
          data = set_moon_data(data)
        elsif data['stats']
          data = set_planet_data(data, settings)
        end
        data
      end

      # Returns the names in +planets+ that did not turn up fruitless through the
      # telescope (any other reply, such as daylight or indoors, still counts as
      # visible), or nil when there is no telescope to look through (no settings,
      # or it can't be fetched).
      def find_visible_planets(planets, settings = nil)
        # Without settings there is no telescope name or storage, so don't send
        # a bare "get" for a nil item.
        unless settings
          Lich::Messaging.msg("bold", "DRCMM: No settings given, so no telescope to find visible planets.")
          return
        end

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

      # Sets the cast target for a planet-based astral spell to a visible planet.
      #
      # Checks which planets in the constellation data are currently visible through
      # a telescope (requires settings with telescope configuration). Finds the first
      # planet that matches both the spell's stat requirements and visibility. Sets
      # the 'cast' key and returns the data; returns nil (with a message) if no
      # visible planet matches or no telescope is available.
      #
      # @param data [Hash] astral spell data with 'stats' key listing spell requirements
      # @param settings [OpenStruct, nil] optional settings with telescope_name and
      #   telescope_storage for planet visibility checks
      # @return [Hash, nil] the updated data hash with 'cast' key set, or nil if no
      #   visible planet is available
      # @example
      #   data = { 'stats' => ['strength'], 'abbrev' => 'SF' }
      #   DRCMM.set_planet_data(data, settings)
      def set_planet_data(data, settings = nil)
        return data unless data['stats']

        planets = get_data('constellations')[:constellations].select { |planet| planet['stats'] }
        planet_names = planets.map { |planet| planet['name'] }
        # find_visible_planets returns nil when there is no telescope to look through.
        visible_planets = find_visible_planets(planet_names, settings) || []
        data['stats'].each do |stat|
          cast_on = planets.map { |planet| planet['name'] if planet['stats'].include?(stat) && visible_planets.include?(planet['name']) }.compact.first
          next unless cast_on

          data['cast'] = "cast #{cast_on}"
          return data
        end
        Lich::Messaging.msg("bold", "DRCMM: Could not set planet data. Cannot cast #{data['abbrev']}.")
        # Messaging.msg returns a truthy Array; callers test the result with `if data`.
        nil
      end

      # Sets the cast target for a moon-based astral spell to a visible moon or ambient.
      #
      # Finds the first visible moon (katamba, yavash, or xibar) and sets the 'cast' key.
      # If no moon is visible and the spell is "cage of light", allows casting on ambient.
      # Returns nil (with a message) if no moon or ambient casting is possible.
      #
      # @param data [Hash] astral spell data with 'moon' key and 'name' for logging
      # @return [Hash, nil] the updated data hash with 'cast' key set (e.g.
      #   'cast yavash' or 'cast ambient'), or nil if no valid target is available
      # @example
      #   data = { 'moon' => true, 'name' => 'Moonburst' }
      #   DRCMM.set_moon_data(data) #=> { 'moon' => true, 'name' => 'Moonburst', 'cast' => 'cast xibar' }
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
      #  False when moonwatch's data is unavailable (see check_moonwatch), the
      #  same answer as "nothing up". A caller that must not act on unknown
      #  data (for example a spell gated on nothing being up) should check
      #  that check_moonwatch returns true first.
      def bright_celestial_object?
        return false unless check_moonwatch

        (UserVars.sun['day'] && UserVars.sun['timer'] >= MOON_VISIBILITY_TIMER_THRESHOLD) || moon_visible?('xibar') || moon_visible?('yavash')
      end

      # returns true if at least one moon (katamba, yavash, xibar) or the sun are
      #  above the horizon and won't set for at least another ~4 minutes.
      #  False when moonwatch's data is unavailable (see check_moonwatch), the
      #  same answer as "nothing up". A caller that must not act on unknown
      #  data (for example a spell gated on nothing being up) should check
      #  that check_moonwatch returns true first.
      def any_celestial_object?
        return false unless check_moonwatch

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
      # Empty when moonwatch's data is unavailable (see check_moonwatch), even
      # if UserVars.moons still holds saved timers.
      def visible_moons
        return [] unless check_moonwatch

        UserVars.moons.select { |moon_name, moon_data| UserVars.moons['visible'].include?(moon_name) && moon_data['timer'] >= MOON_VISIBILITY_TIMER_THRESHOLD }
                .map { |moon_name, _moon_data| moon_name }
      end

      # Whether UserVars.moons holds real moon data: every moon has a numeric
      # 'timer' and 'visible' is a list. moonwatch first writes an empty
      # skeleton ({'katamba' => {}, ..., 'visible' => []}) and fills in the
      # timers afterwards, so the skeleton does not count as ready.
      #
      # moonwatch sets 'running' to false when it exits. UserVars persist
      # between sessions, so data marked that way is left over from a
      # moonwatch that has stopped and does not count as ready either. Data
      # without a 'running' key (older moonwatch versions) is judged by the
      # timers alone.
      #
      # moonwatch publishes the moons first and the sun right after, and the
      # celestial checks read both. So while moonwatch has marked
      # UserVars.sun as running but not yet written its 'timer' (the last key
      # those checks read, written after 'day'), the data is not ready. Sun
      # data without a 'running' key (older moonwatch versions) is not
      # checked.
      #
      # moonwatch's 'running' => false marker is saved only when Lich shuts
      # down in an orderly way. After a crash the saved data can still say
      # 'running' => true, and while a newly started moonwatch has not yet
      # written its skeleton (normally a few milliseconds) that saved data
      # counts as ready.
      #
      # @return [Boolean]
      def moon_data_ready?
        moons = UserVars.moons
        return false unless moons.is_a?(Hash) && moons['visible'].is_a?(Array)
        return false if moons['running'] == false
        return false unless MOON_NAMES.all? { |moon| moons[moon].is_a?(Hash) && moons[moon]['timer'].is_a?(Numeric) }

        sun = UserVars.sun
        !(sun.is_a?(Hash) && sun['running'] == true && !sun['timer'].is_a?(Numeric))
      end

      # Makes sure moonwatch is running, starting it if needed, and waits a
      # bounded time for it to publish real moon data (see moon_data_ready?).
      #
      # When moonwatch is running and the data is ready, this returns at once.
      # When moonwatch is running but the data is not ready yet (it was
      # started elsewhere, for example by autostart, and is still starting
      # up), this waits for the data. If any wait for the data (this one or
      # the one after starting moonwatch) times out while moonwatch keeps
      # running, later calls return false at once instead of waiting again,
      # until the data becomes ready or moonwatch is seen stopped. That
      # includes calls already queued behind another caller's start or wait.
      # When another caller's start is in progress, it waits for that start
      # to finish (returning as soon as the data is ready), allowing
      # MOONWATCH_LOCK_WAIT_MARGIN beyond the timeout. If that wait times out
      # (the other caller's script is paused, or its start is stuck), later
      # calls do not wait on that start again until it finishes: they return
      # false at once while moonwatch is not running, and wait only for the
      # data of a running moonwatch. Otherwise it
      # clears the saved UserVars.moons and UserVars.sun (they may be stale),
      # starts moonwatch and waits until moon_data_ready? is true. The wait
      # ends early, with a message, when moonwatch cannot be found or stops
      # before publishing, and ends at the deadline when it never starts or
      # never publishes. The saved data is never restored on failure, so moon
      # and sun checks see nothing up rather than stale timers. After such a
      # failure, while moonwatch is not running, calls return false without
      # starting it again until MOONWATCH_RESTART_COOLDOWN seconds have
      # passed; a moonwatch started some other way in the meantime is still
      # used.
      #
      # A nil from start_script is not treated as a failure unless moonwatch
      # cannot be found (see moonwatch_findable?): Lich also returns nil while
      # another start of moonwatch is still in progress, so in that case this
      # waits (up to the deadline) for that start to finish.
      #
      # The timeout bounds each wait separately. A caller queued behind
      # another caller's start waits up to timeout + MOONWATCH_LOCK_WAIT_MARGIN
      # for the lock. If, once it has the lock, it finds a moonwatch that was
      # started elsewhere in the meantime and has not published yet, it then
      # waits up to timeout for that data too. So one call can take up to
      # 2 * timeout + MOONWATCH_LOCK_WAIT_MARGIN (21 s by default) in that
      # sequence; every other call takes at most timeout + the margin.
      #
      # Only waits of at least MOONWATCH_READY_TIMEOUT set the stall latch or
      # the stuck-start latch. A caller passing a shorter timeout gets false
      # when its own wait runs out, but does not make other callers skip
      # theirs.
      #
      # @param timeout [Numeric] seconds to wait for another caller's start to
      #   finish (plus MOONWATCH_LOCK_WAIT_MARGIN), and again for moonwatch to
      #   publish (after starting it, or when it is already running). Must be a
      #   positive, finite number.
      # @return [Boolean] true when moonwatch is running and has published
      #   real moon data; false when moon data is unavailable
      # @raise [ArgumentError] when timeout is not a positive, finite number
      def check_moonwatch(timeout: MOONWATCH_READY_TIMEOUT)
        validate_moonwatch_timeout!(timeout)

        if Script.running?('moonwatch')
          return moonwatch_data_ready! if moon_data_ready?
          return await_running_moonwatch(timeout) unless MOONWATCH_START_LOCK.locked?
        else
          @moonwatch_data_stalled = false
        end

        lock_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout + MOONWATCH_LOCK_WAIT_MARGIN
        start_generation = @moonwatch_start_generation
        until MOONWATCH_START_LOCK.try_lock
          # The other start may publish while the lock is still held (its
          # holder can be paused or slow to return), so keep checking. When
          # the holder's wait has just timed out on a running moonwatch (the
          # stall latch is set), stop waiting too. When an earlier wait on
          # this start timed out (the holder is stuck), wait only on a running
          # moonwatch itself, not on the holder.
          if Script.running?('moonwatch')
            return true if moon_data_ready?
            return false if @moonwatch_data_stalled
            return await_running_moonwatch(timeout) if @moonwatch_start_stuck
          elsif @moonwatch_start_stuck
            return false
          end
          if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= lock_deadline
            Lich::Messaging.msg("bold", "DRCMM: Timed out waiting for another start of moonwatch to finish. Moon data is unavailable.")
            note_moonwatch_start_stuck(start_generation) if full_moonwatch_wait?(timeout)
            return false
          end
          pause MOONWATCH_POLL_INTERVAL
        end

        begin
          # A stuck start, if any, has released the lock.
          moonwatch_start_lock_taken
          # Another caller started moonwatch (or another wait on it ran) while
          # this one waited for the lock: wait for its data, honouring the latch.
          return await_running_moonwatch(timeout) if Script.running?('moonwatch')
          if moonwatch_restart_blocked?
            # A start failed moments ago. moonwatch is not running, so any
            # saved data is stale; clear it as a start would, so moon and sun
            # checks see nothing up rather than old timers. Look again first:
            # a moonwatch started another way since the check above has just
            # written its skeleton, which must not be wiped. Writing only when
            # there is something to clear keeps this off the usual path (the
            # failed start already cleared the data). A moonwatch started in
            # the moment between that last look and the write can still lose
            # its skeleton; only moonwatch itself could close that window.
            return await_running_moonwatch(timeout) if Script.running?('moonwatch')

            UserVars.moons = {} unless UserVars.moons == {}
            UserVars.sun = {} unless UserVars.sun == {}
            return false
          end

          Lich::Messaging.msg("bold", "DRCMM: moonwatch is not running. Starting it now.")
          @moonwatch_data_stalled = false
          UserVars.moons = {}
          UserVars.sun = {}
          started = start_script('moonwatch') ? true : false
          if !started && !Script.running?('moonwatch') && !moonwatch_findable?
            Lich::Messaging.msg("bold", "DRCMM: moonwatch could not be found. Moon data is unavailable.")
            note_moonwatch_start_failure(timeout)
            return false
          end
          if await_moonwatch_data(started, timeout)
            # Only suggest autostart once this start has actually worked.
            Lich::Messaging.msg("plain", "DRCMM: Run `#{$clean_lich_char}e autostart('moonwatch')` to avoid this in the future.") if started
            return moonwatch_data_ready!
          end

          note_moonwatch_start_failure(timeout)
          false
        ensure
          release_moonwatch_start_lock if MOONWATCH_START_LOCK.owned?
        end
      end

      # Waits for an already-running moonwatch (started outside check_moonwatch,
      # for example by autostart) to publish real moon data. Returns false at
      # once while a previous wait is latched as stalled (see
      # note_moonwatch_stall), unless the data has become ready since.
      #
      # @param timeout [Numeric] seconds to wait
      # @return [Boolean] true when moon data is ready
      def await_running_moonwatch(timeout)
        return false if @moonwatch_data_stalled && !(Script.running?('moonwatch') && moon_data_ready?)

        return moonwatch_data_ready! if await_moonwatch_data(true, timeout)

        note_moonwatch_stall if full_moonwatch_wait?(timeout)
        false
      end

      # Raises unless timeout is a positive, finite number of seconds. A zero,
      # negative or infinite timeout would make the waits end at once or
      # never; nil would fail deep inside a wait.
      #
      # @param timeout [Object] the value passed as check_moonwatch's timeout:
      # @raise [ArgumentError]
      def validate_moonwatch_timeout!(timeout)
        return if timeout.is_a?(Numeric) && timeout.real? && timeout.finite? && timeout.positive?

        raise ArgumentError, "DRCMM.check_moonwatch: timeout must be a positive, finite number of seconds, got #{timeout.inspect}"
      end

      # Whether a wait of timeout seconds was long enough to latch its failure
      # for other callers (see note_moonwatch_stall, note_moonwatch_start_stuck).
      # A caller that chose a shorter wait only answers for itself.
      #
      # @param timeout [Numeric] seconds the wait allowed
      # @return [Boolean]
      def full_moonwatch_wait?(timeout)
        timeout >= MOONWATCH_READY_TIMEOUT
      end

      # Called when a wait for another caller's start of moonwatch timed out:
      # until that start releases the lock, callers queued on it return false
      # at once while moonwatch is not running (see check_moonwatch).
      #
      # Latches only while the start that was waited on still holds the lock.
      # If it released the lock after the deadline check (and another caller
      # may already have taken it for a fresh start), nothing is latched.
      #
      # @param start_generation [Integer] @moonwatch_start_generation when the
      #   wait began
      def note_moonwatch_start_stuck(start_generation)
        latched = MOONWATCH_STATE_LOCK.synchronize do
          next false unless start_generation == @moonwatch_start_generation && MOONWATCH_START_LOCK.locked?

          @moonwatch_start_stuck = true
        end
        return unless latched

        Lich::Messaging.msg("plain", "DRCMM: Not waiting for that start of moonwatch again until it finishes. Moon checks report no moon until then, unless moonwatch is running.")
      end

      # Called by check_moonwatch right after it takes MOONWATCH_START_LOCK:
      # starts a new generation and clears the stuck-start latch.
      def moonwatch_start_lock_taken
        MOONWATCH_STATE_LOCK.synchronize do
          @moonwatch_start_generation += 1
          @moonwatch_start_stuck = false
        end
      end

      # Clears the stuck-start latch and releases MOONWATCH_START_LOCK as one
      # step, so a waiter cannot latch this start after the clear.
      def release_moonwatch_start_lock
        MOONWATCH_STATE_LOCK.synchronize do
          @moonwatch_start_stuck = false
          MOONWATCH_START_LOCK.unlock
        end
      end

      # Called when moonwatch is running with real moon data: clears the stall
      # latch and the restart cooldown.
      #
      # @return [true]
      def moonwatch_data_ready!
        @moonwatch_data_stalled = false
        @moonwatch_restart_blocked_until = nil
        true
      end

      # Called after check_moonwatch's own start of moonwatch failed. When
      # moonwatch is running (it never published), latches the stall (see
      # note_moonwatch_stall) if the wait was a full one (see
      # full_moonwatch_wait?). Otherwise blocks further starts for
      # MOONWATCH_RESTART_COOLDOWN seconds, so a moonwatch that cannot start
      # is not restarted, with its messages, by every moon check.
      #
      # @param timeout [Numeric] seconds the failed wait allowed
      def note_moonwatch_start_failure(timeout)
        if Script.running?('moonwatch')
          note_moonwatch_stall if full_moonwatch_wait?(timeout)
          return
        end

        @moonwatch_restart_blocked_until = Process.clock_gettime(Process::CLOCK_MONOTONIC) + MOONWATCH_RESTART_COOLDOWN
        Lich::Messaging.msg("plain", "DRCMM: Not starting moonwatch again for #{MOONWATCH_RESTART_COOLDOWN} seconds. Moon checks report no moon until then, unless moonwatch is started another way.")
      end

      # Whether a recent failed start (see note_moonwatch_start_failure) still
      # blocks check_moonwatch from starting moonwatch.
      #
      # Reads the deadline once: another thread's moonwatch_data_ready! may
      # clear it at any moment.
      #
      # @return [Boolean]
      def moonwatch_restart_blocked?
        blocked_until = @moonwatch_restart_blocked_until
        !blocked_until.nil? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < blocked_until
      end

      # Called after a wait for moon data has failed. When moonwatch is still
      # running, it is running without publishing, so later calls return false
      # at once rather than stalling every caller for the full timeout; that
      # latch clears when the data becomes ready or moonwatch is seen stopped.
      def note_moonwatch_stall
        return unless Script.running?('moonwatch')

        @moonwatch_data_stalled = true
        Lich::Messaging.msg("plain", "DRCMM: Not waiting for moonwatch's moon data again until it publishes the data or stops.")
      end

      # Whether Lich can find a moonwatch script file. Script.exists? does not
      # look in custom/<subdir>/, which Script.start does, so when it says no
      # this asks Script.version, which resolves names the same way
      # Script.start does and returns nil when no file matches.
      #
      # @return [Boolean]
      def moonwatch_findable?
        return true if Script.exists?('moonwatch')

        !Script.version('moonwatch').nil?
      rescue ArgumentError
        true # the file was found, but its version header is malformed
      end

      # Polls until moonwatch is running with real moon data, moonwatch stops
      # after having been seen running, or the deadline passes.
      #
      # @param seen_running [Boolean] whether moonwatch is known to have started;
      #   until it has, only the deadline ends the wait
      # @param timeout [Numeric] seconds to wait
      # @return [Boolean] true when moon data is ready
      def await_moonwatch_data(seen_running, timeout)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        loop do
          running = Script.running?('moonwatch')
          return true if running && moon_data_ready?

          if running
            seen_running = true
          elsif seen_running
            Lich::Messaging.msg("bold", "DRCMM: moonwatch stopped before its moon data was ready. Moon data is unavailable.")
            return false
          end

          if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            if seen_running
              Lich::Messaging.msg("bold", "DRCMM: moonwatch did not publish moon data within #{timeout} seconds. Moon data is unavailable.")
            else
              Lich::Messaging.msg("bold", "DRCMM: moonwatch did not start within #{timeout} seconds. Moon data is unavailable.")
            end
            return false
          end

          pause MOONWATCH_POLL_INTERVAL
        end
      end
    end
  end
end
