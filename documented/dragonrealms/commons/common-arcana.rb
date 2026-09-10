# frozen_string_literal: true

# Namespace for Lich5, a Ruby scripting engine for the text-based games GemStone IV and DragonRealms.
module Lich
  # Namespace for DragonRealms-specific game logic.
  module DragonRealms
    # Common arcana utilities for spell casting, buff management, cambrinth charging, and runestones.
    #
    # Provides methods for preparing and casting spells, managing cyclic spell releases,
    # handling cambrinth items and mana calculations, activating khri and barbarian abilities,
    # and parsing game server responses for spell success/failure patterns.
    module DRCA
      module_function

      # Regex patterns matching successful cyclic spell release messages.
      #
      # Used by {#release_cyclics} to detect when a cyclic spell has been successfully
      # released from active status. Patterns cover cyclic spells across all magic guilds.
      #
      # @return [Array<Regexp>] compiled patterns for cyclic release messages
      CYCLIC_RELEASE_SUCCESS_PATTERNS = [
        # Ranger spells
        /^The world seems to accelerate around you as the spirit of the cheetah escapes you/, # Cheetah Swiftness
        /^You feel distinctly frail and vulnerable as the spirit of the bear leaves you/, # Bear Strength
        /^The forces of nature that you roused are no longer with you/, # Awaken Forest
        # Empath spells
        /^Aesandry Darlaeth loses cohesion, returning your reaction time to normal/, # Aesandry Darlaeth
        /^You sense your hold on your Guardian Spirit weaken, then evaporate entirely/, # Guardian Spirit
        /^The signs of empathic atrocity escape to the deepest pits of your personality, your touch no longer deadly/, # Icutu Zaharenela
        /^The tingling across your body diminishes as you feel the motes of energy fade away/, # Regenerate
        # Bard spells
        /^You sing, purposely warbling some of the held notes for effec/, # Abandoned Heart (ABAN)
        /^The final tones of your enchante end with an abrupt flourish that leaves stark silence in its wake/, # Aether Wolves (AEWO)
        /^With a rising crescendo in your voice, you reprise the strong lines of the chorus of Albreda's Balm before bringing it to an abrupt conclusion/, # Albreda's Balm (ALB)
        /^The final, quiet notes of Blessing of the Fae stir the air gently, and die away/, # Blessing of the Fae (BOTF)
        /^The warm air swirling around you stills and begins to cool/, # Caress of the Sun (CARE)
        /^A few fleeting, soporific notes tarry in the air before your lullaby slowly dies down like the night receding at Anduwen/, # Damaris' Lullaby (DALU)
        /^You no longer feel the clarity of vision you had, as shadows creep across the area/, # Eye of Kertigen (EYE)
        /^You let your voice fade even as the pace of Faenella's Grace slows, winding down to a quiet conclusion/, # Faenella's Grace (FAE)
        /^The aethereal static subsides, returning your spellcasting abilities to normal/, # Glythtide's Joy (GJ)
        /^As your rendition of Hodierna's Lilt winds down to a close, you let each note linger on the air a moment, drawing out the final moment with a reluctance to let the soothing melody fade/, # Hodierna's Lilt (HODI)
        /^You build the final notes of Phoenix's Pyre with an upward scale that rises into a steep crescendo, and end with an abrupt silence/, # Phoenix's Pyre (PYRE)
        /^The dome of light extinguishes as the final notes of music die away/, # Sanctuary
        # Warrior Mage spells
        /^The dark mantle of aether surrounding you fades away/, # Aether Cloak (AC)
        /^You release your connection to the Elemental Plane of Electricity, allowing the static electricity to dissipate/, # Electrostatic Eddy (EE)
        /^Your link to the Fire Rain matrix has been severed/, # Fire Rain (FR)
        /^The chilling vapor surrounding you dissipates slowly/, # Rimefang (spell) (RIM)
        /^The frost-covered blade circling around you shatters into a fine icy mist/, # Rimefang (spell) (RIM)
        /^The jagged stone spears surrounding you at .* range tremble slightly, then crumble into a grey dust that is quickly reclaimed by the earth/, # Ring of Spears (ROS)
        # Cleric spells
        /^The deadening murk around you subsides/, # Hydra Hex (HYH)
        /^The dark patch of grime around you subsides/, # Hydra Hex (HYH)
        /^You sense the dark presence depart/, # Soul Attrition (SA)
        # Resurrection (REZZ) does not have messaging that makes it usable here.
        /^The heightened sense of spiritual awareness leaves you/, # Revelation (REV)
        /^The swirling fog dissipates from around you/, # Ghost Shroud (GHS)
        # Paladin spells
        /^The holy golden radiance of your soul subsides, retreating into your body/, # Holy Warrior (HOW)
        /^Truffenyi's Rally ends, leaving behind a momentary sensation of something stuck in your throat/, # Truffenyi's Rally (TR)
        # Moon Mage spells
        /^The web of shadows twitches one last time and then goes inert/, # Shadow Web (SHW)
        /^You release your mental hold on the lunar energy that sustains your moongate/, # Moongate (MG)
        /^The refractive field surrounding you fades away/, # Steps of Vuan (SOV)
        /^A .* sphere suddenly flares with a cold light and vaporizes/, # Starlight Sphere (SLS)
        # Trader spells
        /^Your calligraphy of light assailing/, # Arbiter's Stylus (ARS)
        /^The .* moonsmoke blows away from your face/, # Mask of the Moons (MOM)
        # Necromancer spells
        /^The Rite of Contrition matrix loses cohesion, leaving your aura naked/, # Rite of Contrition (ROC)
        /^The Rite of Forbearance matrix loses cohesion, leaving you to wallow in temptation/, # Rite of Forbearance (ROF)
        /^The Rite of Grace matrix loses cohesion, leaving your body exposed/, # Rite of Grace (ROG)
        /^The greenish hues about you vanish as the Universal Solvent matrix loses its cohesion/, # Universal Solvent (USOL)
        /^You sense your Call from Within spell weaken and disperse/ # Call from Within (CFW)
      ].freeze

      # String patterns matching successful Osrel Meraud (OM) infusion outcomes.
      #
      # Used by {#infuse_om} to detect successful infusion, including when the runestone
      # reaches full capacity or mana availability is blocked by local interference.
      #
      # @return [Array<String>] success condition strings
      # @see #infuse_om
      INFUSE_OM_SUCCESS_PATTERNS = [
        'having reached its full capacity',
        'A sense of fullness',
        'Something in the area is interfering with your attempt to harness'
      ].freeze

      # String patterns matching Osrel Meraud infusion failures.
      #
      # Used by {#infuse_om} to detect when infusion cannot proceed, either because the
      # runestone is not full enough or the character lacks sufficient harnessed mana.
      #
      # @return [Array<String>] failure condition strings
      # @see #infuse_om
      INFUSE_OM_FAILURE_PATTERNS = [
        'as if it hungers for more',
        'Your infusion fails completely',
        "You don't have enough harnessed mana to infuse that much",
        'You have no harnessed'
      ].freeze

      INFUSE_OM_MAX_RETRIES = 20
      PREPARE_MAX_RETRIES = 3
      CAST_MAX_RETRIES = 3
      BARB_BUFF_MAX_RETRIES = 3
      STOW_FOCUS_MAX_RETRIES = 3

      # Regex patterns matching successful spell focus wielding messages.
      #
      # Used by {#find_focus} when a focus is configured as sheathed.
      #
      # @return [Array<Regexp>] compiled patterns for successful wield outcomes
      # @see #find_focus
      # @see WIELD_FOCUS_FAILURE_PATTERNS
      WIELD_FOCUS_SUCCESS_PATTERNS = [
        /^You draw out/,
        /^You grab/,
        /^You slip/,
        /^You deftly remove/
      ].freeze

      # Regex patterns matching failed spell focus wielding messages.
      #
      # Used by {#find_focus} when a focus is configured as sheathed to determine if
      # the wield command failed.
      #
      # @return [Array<Regexp>] compiled patterns for wield failures
      # @see #find_focus
      # @see WIELD_FOCUS_SUCCESS_PATTERNS
      WIELD_FOCUS_FAILURE_PATTERNS = [
        /^What were you/,
        /^Wield what/,
        /^You need a free hand/
      ].freeze

      # Regex patterns matching successful spell focus sheathing messages.
      #
      # Used by {#stow_focus} when a focus is configured as sheathed.
      #
      # @return [Array<Regexp>] compiled patterns for successful sheathe outcomes
      # @see #stow_focus
      # @see SHEATHE_FOCUS_FAILURE_PATTERNS
      SHEATHE_FOCUS_SUCCESS_PATTERNS = [
        /^You sheathe/,
        /^Sheathing/,
        /^You secure/,
        /^You slip/,
        /^You hang/,
        /^You strap/,
        /^You easily strap/
      ].freeze

      # Regex patterns matching failed spell focus sheathing messages.
      #
      # Used by {#stow_focus} when a focus is configured as sheathed to determine if
      # the sheathe command failed.
      #
      # @return [Array<Regexp>] compiled patterns for sheathe failures
      # @see #stow_focus
      # @see SHEATHE_FOCUS_SUCCESS_PATTERNS
      SHEATHE_FOCUS_FAILURE_PATTERNS = [
        /^Sheathe your .* where/,
        /^There's no room/
      ].freeze

      # Progression messages for Trader aura levels when perceiving aura.
      #
      # Messages proceed from faintest hint of starlight at index 0 to blinding brilliance
      # at index 9, and are indexed by {#perc_aura} to determine the numeric aura level.
      #
      # @return [Array<String>] aura level descriptions, ordered from 0 (minimal) to 9 (maximal)
      # @see #perc_aura
      STARLIGHT_MESSAGES = [
        'The smallest hint of starlight flickers within your aura',
        'A bare flicker of starlight plays within your aura',
        'A faint amount of starlight illuminates your aura',
        'Your aura pulses slowly with starlight',
        'A steady pulse of starlight runs through your aura',
        'Starlight dances vividly across the confines of your aura',
        'Strong pulses of starlight flare within your aura',
        'Your aura seethes with brilliant starlight',
        'Your aura is blinding',
        'The power contained in your aura'
      ].freeze

      # Regex patterns matching Warrior Mage elemental charge states.
      #
      # Ordered from 0 (no charge) to 11 (maximum charge). Each pattern corresponds to
      # a specific range of elemental charge, and is used by {#check_elemental_charge}
      # to determine the character's current charge state via the 'pathway sense' command.
      #
      # @return [Array<Regexp>] compiled patterns for elemental charge levels
      # @see #check_elemental_charge
      # @example
      #   CHARGE_LEVELS[0] #=> /^You sense nothing out of the ordinary\..*$/
      #   CHARGE_LEVELS[11] #=> /^You have reached the limits of your body's capacity\..*$/
      CHARGE_LEVELS = [
        /^You sense nothing out of the ordinary.  Only magic could detect the useless trace of .* still in your system.$/,
        /^A small charge lingers within your body, just above the threshold of perception.$/,
        /^A small charge lingers within your body.$/,
        /^A charge dances through your body.$/,
        /^A charge dances just below the threshold of discomfort.$/,
        /^A charge circulates through your body, causing a low hum to vibrate through your bones.$/,
        /^Elemental essence floats freely within your body, leaving little untouched.$/,
        /^Elemental essence has infused every inch of your body.  While you could contain more, you'd do so at the risk of your health.$/,
        /^Extraplanar power crackles within your body, leaving you feeling mildly feverish.$/,
        /^Extraplanar power crackles within your body, leaving you feeling acutely ill.$/,
        /^Your body sings and crackles with a barely contained charge, destroying what little cenesthesia you had left.$/,
        /^You have reached the limits of your body's capacity to store a charge.  The laws of the Elemental Plane of .* scream demands upon your physiology, threatening your life.$/
      ].freeze

      # Regex pattern for the start of Moon Mage mana perception output.
      #
      # Matches the first line of a mana stream description during 'perc mana' output,
      # used by {#perc_mana} to delimit the start of mana information parsing.
      #
      # @return [Regexp] pattern matching "streams of [type] mana"
      # @see #perc_mana
      # @see PERC_MANA_END_PATTERN
      PERC_MANA_START_PATTERN = /streams of .* mana/
      # Regex pattern for the end of perception command output.
      #
      # Matches the roundtime line that terminates perception output, used by {#perc_mana}
      # to delimit when mana stream information stops being relevant.
      #
      # @return [Regexp] pattern matching "Roundtime"
      # @see #perc_mana
      # @see PERC_MANA_START_PATTERN
      PERC_MANA_END_PATTERN = /Roundtime/
      # Regex pattern to extract the type of active symbiotic research.
      #
      # Captures the symbiosis type name (e.g., "Warding", "Utility", "Augmentation",
      # "Sorcery") from a perception message. Used by {#perc_symbiotic_research} to
      # determine which symbiosis is currently active.
      #
      # @return [Regexp] pattern with named capture group 'type' for the symbiosis name
      # @see #perc_symbiotic_research
      # @example
      #   "You combine the weaves of the Warding symbiosis".match(SYMBIOSIS_PATTERN)[:type] #=> "Warding"
      SYMBIOSIS_PATTERN = /combine the weaves of the (?<type>\w+) symbiosis/
      # Regex pattern to extract minimum mana stream requirement from sorcery discern.
      #
      # Captures the minimum number of mana streams required to cast a sorcery spell,
      # used by {#check_discern} when processing discern results for symbiosis spells.
      #
      # @return [Regexp] pattern with named capture group 'min' for the stream count
      # @see #check_discern
      # @example
      #   "This spell requires at minimum 5 mana streams".match(DISCERN_SORCERY_PATTERN)[:min] #=> "5"
      DISCERN_SORCERY_PATTERN = /requires at minimum (?<min>\d+) mana streams/
      # Regex pattern to extract min and reinforcement mana for non-sorcery discern.
      #
      # Captures both the minimum required streams and additional reinforcement mana
      # available for standard (non-sorcery) spells, used by {#check_discern} to
      # calculate total mana needed.
      #
      # @return [Regexp] pattern with named captures 'min' (required streams) and 'more' (reinforcement)
      # @see #check_discern
      # @example
      #   msg = "The spell requires at minimum 4 mana streams and you think you can reinforce it with 2 more"
      #   msg.match(DISCERN_FULL_PATTERN)[:min] #=> "4"
      #   msg.match(DISCERN_FULL_PATTERN)[:more] #=> "2"
      DISCERN_FULL_PATTERN = /minimum (?<min>\d+) mana streams and you think you can reinforce it with (?<more>\d+) more/i

      # Regex patterns matching "useless" runestone messages.
      #
      # Runestones become useless (depleted) when their stored spell can no longer be invoked.
      # Used by {#get_runestone?} to detect and dispose of depleted runestones.
      #
      # @return [Array<Regexp>] compiled patterns for useless runestone detection
      # @see #get_runestone?
      USELESS_RUNESTONE_PATTERNS = [
        /^You get a useless/
      ].freeze

      # Regex patterns matching successful runestone retrieval.
      #
      # Used by {#get_runestone?} to confirm that the runestone was obtained from storage.
      #
      # @return [Array<Regexp>] compiled patterns for successful get outcomes
      # @see #get_runestone?
      # @see GET_RUNESTONE_FAILURE_PATTERNS
      GET_RUNESTONE_SUCCESS_PATTERNS = [
        /^You get/,
        /^You pick up/
      ].freeze

      # Regex patterns matching runestone retrieval failures.
      #
      # Used by {#get_runestone?} to detect when a runestone cannot be obtained from storage.
      #
      # @return [Array<Regexp>] compiled patterns for retrieval failures
      # @see #get_runestone?
      # @see GET_RUNESTONE_SUCCESS_PATTERNS
      GET_RUNESTONE_FAILURE_PATTERNS = [
        /^What were you referring to/,
        /^I could not find/
      ].freeze

      @backfired_status = false

      # Infuses mana into an Osrel Meraud runestone until it reaches full capacity.
      #
      # Only operates if Osrel Meraud is active and below 90% duration. Optionally harnesses
      # mana before each infusion attempt. Retries up to {INFUSE_OM_MAX_RETRIES} times, pausing
      # if mana drops below 40.
      #
      # @param harness [Boolean] whether to harness mana before each infusion attempt
      # @param amount [Integer] mana amount to infuse per attempt
      # @return [void]
      # @see #harness_mana
      # @see INFUSE_OM_SUCCESS_PATTERNS
      # @see INFUSE_OM_FAILURE_PATTERNS
      def infuse_om(harness, amount)
        return unless DRSpells.active_spells['Osrel Meraud'] && DRSpells.active_spells['Osrel Meraud'] < 90
        return unless amount

        retries = 0
        loop do
          if retries >= INFUSE_OM_MAX_RETRIES
            Lich::Messaging.msg("bold", "DRCA: infuse_om exhausted #{INFUSE_OM_MAX_RETRIES} retries - giving up")
            break
          end
          retries += 1

          pause 5 while DRStats.mana <= 40
          harness_mana([amount]) if harness
          break if INFUSE_OM_SUCCESS_PATTERNS.include?(DRC.bput("infuse om #{amount}", INFUSE_OM_SUCCESS_PATTERNS, INFUSE_OM_FAILURE_PATTERNS))

          pause 0.5
          waitrt?
        end
      end

      # Attempts to harness a given amount of mana.
      #
      # @param mana [Integer] mana amount to harness
      # @return [Boolean] true if the harness command matched "You tap into", false otherwise
      # @api private
      def harness?(mana)
        result = DRC.bput("harness #{mana}", 'You tap into', 'Strain though you may')
        pause 0.5
        waitrt?
        return result =~ /You tap into/
      end

      # Harnesses multiple amounts of mana sequentially.
      #
      # Iterates through the provided amounts and calls {#harness?} for each. Stops when
      # any harness attempt fails.
      #
      # @param amounts [Array<Integer>] mana amounts to harness in order
      # @return [void]
      # @see #harness?
      def harness_mana(amounts)
        amounts.each do |mana|
          break unless harness?(mana)
        end
      end

      # Activates a set of khri abilities.
      #
      # Iterates through each khri ability set and attempts to activate it, respecting
      # the kneel_khri setting from configuration.
      #
      # @param khris [Array<String>] khri ability names to activate
      # @param settings [OpenStruct] configuration including kneel_khri
      # @return [void]
      # @see #activate_khri?
      def start_khris(khris, settings)
        khris
          .each do |khri_set|
            activate_khri?(settings.kneel_khri, khri_set)
          end
      end

      # Needs to handle (based on current usage):
      # - Hasten
      # - Delay Hasten
      # - Hasten Focus
      # - Delay Hasten Focus
      # - Khri Hasten
      # - Khri Delay Hasten
      # - Khri Delay Hasten Focus
      def activate_khri?(settings_kneel, ability)
        abilities = ability.split.map(&:capitalize)

        # Standardize for with/without 'Khri' on the front
        abilities = abilities.drop(1) if abilities.first.casecmp('khri') == 0

        # Handling for 'Delay'
        should_delay = abilities.first.casecmp('delay') == 0
        abilities = abilities.drop(1) if should_delay

        # Check each khri in the list against Active Spells, Drop any that are active
        needed_abilities = abilities.select { |ability_to_check| DRSpells.active_spells["Khri #{ability_to_check}"].nil? }
        return true if needed_abilities.empty?

        kneel = needed_abilities.any? { |ability_to_check| kneel_for_khri?(settings_kneel, ability_to_check) }
        DRC.retreat if kneel
        DRC.bput('kneel', 'You kneel', 'You are already', 'You rise', "While swimming?  Don't be silly") if kneel && !kneeling?

        result = DRC.bput("Khri #{should_delay ? 'Delay ' : ''}#{needed_abilities.join(' ')}", get_data('spells').khri_preps)
        waitrt?
        DRC.fix_standing

        return ['Your mind and body are willing', 'Your body is willing', 'You have not recovered'].none?(result)
      end

      # Determines whether kneeling is required to activate a specific khri ability.
      #
      # If kneel is an Array, checks if the ability (with 'khri ' prefix removed) is
      # in the list (case-insensitive). Otherwise returns the kneel value as-is.
      #
      # @param kneel [Boolean, Array<String>] kneel configuration: true/false or array of ability names
      # @param ability [String] the khri ability name to check
      # @return [Boolean] true if kneeling is needed for this ability
      # @api private
      def kneel_for_khri?(kneel, ability)
        if kneel.is_a? Array
          kneel.map(&:downcase).include? ability.downcase.sub('khri ', '')
        else
          kneel
        end
      end

      # Activates a list of barbarian abilities.
      #
      # Iterates through the provided ability names and attempts to activate each using
      # {#activate_barb_buff?} with settings from the configuration.
      #
      # @param abilities [Array<String>] barbarian ability names to activate
      # @param settings [OpenStruct] configuration including meditation_pause_timer and sit_to_meditate
      # @return [void]
      # @see #activate_barb_buff?
      def start_barb_abilities(abilities, settings)
        abilities.each { |name| activate_barb_buff?(name, settings.meditation_pause_timer, settings.sit_to_meditate) }
      end

      # Activates a single barbarian ability or meditation.
      #
      # Returns immediately if the ability is already active. Handles kneeling/sitting requirements,
      # meditation pause timing, and retriable conditions (unengaged, sitting, standing). Logs a
      # message and returns false if retries are exhausted.
      #
      # @param name [String] the barbarian ability name
      # @param meditation_pause_timer [Integer] pause duration (seconds) for meditation abilities; default 20
      # @param sit_to_meditate [Boolean] whether to sit before meditation abilities; default false
      # @param retries [Integer] remaining retry attempts; default {BARB_BUFF_MAX_RETRIES}
      # @return [Boolean] true if the ability was activated successfully, false otherwise
      # @example
      #   activate_barb_buff?("Power Meditation") #=> true
      def activate_barb_buff?(name, meditation_pause_timer = 20, sit_to_meditate = false, retries: BARB_BUFF_MAX_RETRIES)
        # Note, you must know Power meditation or Powermonger mastery
        # for your active abilities to be detected by DRSpells.
        return true if DRSpells.active_spells[name]

        if retries <= 0
          Lich::Messaging.msg("bold", "DRCA: activate_barb_buff? exhausted #{BARB_BUFF_MAX_RETRIES} retries for '#{name}' - giving up")
          return false
        end

        activated = false
        ability_data = get_data('spells').barb_abilities[name]
        if ability_data['type'].eql?('meditation') && sit_to_meditate
          DRC.retreat
          DRC.bput('sit', 'You sit', 'You are already', 'You rise', 'While swimming?')
        end
        case DRC.bput(ability_data['start_command'], ability_data['activated_message'], 'You have not been trained', 'But you are already', 'Your inner fire lacks', 'find yourself lacking the inner fire', 'You should stand', 'You must be sitting', 'You must be unengaged', 'While swimming?')
        when 'You must be unengaged'
          DRC.retreat
          activated = activate_barb_buff?(name, meditation_pause_timer, sit_to_meditate, retries: retries - 1)
        when 'You must be sitting'
          DRC.retreat
          case DRC.bput('sit', 'You sit', 'You are already', 'You rise', 'While swimming?')
          when 'While swimming?'
            Lich::Messaging.msg("bold", "DRCA: cannot sit to activate '#{name}' - water is too deep")
            activated = false
          else
            activated = activate_barb_buff?(name, meditation_pause_timer, sit_to_meditate, retries: retries - 1)
          end
        when 'You should stand'
          DRC.fix_standing
          activated = activate_barb_buff?(name, meditation_pause_timer, sit_to_meditate, retries: retries - 1)
        when /#{ability_data['activated_message']}/
          # Pause at least for the preferred amount of time
          # to let the meditation take effect else it may fail.
          if ability_data['type'].eql?('meditation') && meditation_pause_timer
            pause meditation_pause_timer
          end
          # Wait for any remaining RT before proceeding
          waitrt?
          activated = true
        else
          activated = false
        end
        DRC.fix_standing
        activated
      end

      # Determines whether any buffs from a list need to be reapplied.
      #
      # For Commoners, always returns true (no way to check buffs). For Barbarians and Thieves,
      # checks if any ability is not currently active. For other guilds, checks if any buff is
      # missing or has a remaining duration shorter than its recast time.
      #
      # @param buff_list [Array, Hash, nil] buff names (Barbarian/Thief) or spell hashes with recast data (Mages)
      # @return [Boolean] true if any buff needs reapplication, false if all buffs are active/current
      # @example
      #   need_buffs?(nil) #=> false
      #   need_buffs?({"Spirit Ward" => {"recast" => 60}}) #=> true if not active or duration < 60
      def need_buffs?(buff_list)
        # no need to iterate if list of buffs is already empty
        return false if buff_list.nil? || buff_list.size == 0

        # commoner's don't really have a way to check buffs so assume always yes
        return true if DRStats.guild == "Commoner"

        # no need to iterate if no buffs active and buff_list is not empty
        return true if DRSpells.active_spells.empty?

        case DRStats.guild
        when 'Barbarian'
          # barbarian buffs are an array of strings so we can just iterate over it and check if any are not in the active spells hash
          buff_list.each { |buff| return true if !DRSpells.active_spells.key?("#{buff}") }
        when 'Thief'
          # thieves need special handling to convert buff_list to an array of JUST khri names due to the different options supported
          buff_list.map { |buff| buff.sub(/khri /i, '') }
                   .map { |buff| buff.sub(/delay /i, '') }
                   .join(' ')
                   .split(' ')
                   .each { |khri| return true if !DRSpells.active_spells.key?("Khri #{khri}") }
        else
          # for MUs check list of required buffs against list of active spells and their durations/recast
          buff_list.each do |spell, data|
            # ignore spells which don't recast (ignite, etf, etc.) but not cyclics
            next if data['recast'] < 0 && !data['cyclic']
            # if any buff is not in the active spells, or whose duration is less than recast, need to buff
            return true if !DRSpells.active_spells.key?(spell) || DRSpells.active_spells[spell] <= (data['recast'] ? data['recast'] : 1)
          end
        end

        # all buffs were in active spells with longer durations than recast, no need to buff
        return false
      end

      # Compiles a single player-supplied message into a case-insensitive Regexp
      # for use as a bput pattern, matching how bput treats the built-in string
      # patterns; leading/trailing whitespace is trimmed so an accidental space in
      # yaml does not silently break matching. Returns nil -- so the entry is
      # dropped rather than applied -- when the message is not a String, is
      # blank/whitespace-only (an empty pattern compiles to //, matching every
      # line), or is not a valid regular expression (which would otherwise raise
      # inside bput). Shared guard for every custom_*_message key.
      #
      # @param message [String, nil] the player-supplied message
      # @return [Regexp, nil] a case-insensitive pattern, or nil if not a usable string
      def custom_message_pattern(message)
        return nil unless message.is_a?(String)

        stripped = message.strip
        return nil if stripped.empty?

        Regexp.new(stripped, Regexp::IGNORECASE)
      rescue RegexpError
        nil
      end

      # Appends the player's validated custom message patterns to a built-in
      # message list. Each custom message is compiled by {#custom_message_pattern}
      # and silently dropped if blank or invalid. (Duplicate detection is left to
      # config validation, e.g. validate.lic; a duplicate here is merely redundant.)
      #
      # @param base_messages [Array<String>] built-in messages from base-spells.yaml
      # @param custom_messages [Array<String, nil>] player messages to validate and append
      # @return [Array<String, Regexp>] the built-in messages followed by the valid custom patterns
      def with_custom_messages(base_messages, *custom_messages)
        base_messages + custom_messages.filter_map { |message| custom_message_pattern(message) }
      end

      # The bput patterns for invoking: the built-in invoke messages plus the
      # player's custom_invoke_message additions -- the per-character one (their
      # ritual focus, from settings) and, for a runestone spell, the per-spell one
      # from the spell's data.
      #
      # @param spell_custom_invoke_message [String, nil] a spell's custom_invoke_message (runestone spells)
      # @return [Array<String, Regexp>] built-in invoke messages plus the valid custom patterns
      def invoke_messages(spell_custom_invoke_message = nil)
        with_custom_messages(get_data('spells').invoke_messages, get_settings.custom_invoke_message, spell_custom_invoke_message)
      end

      # Prepares a spell -- via a normal prep, or by invoking a runestone when
      # +runestone_name+ is given -- retrying the transient "desire slips away"
      # case and bailing on hard failures.
      #
      # @param abbrev [String, nil] the spell's prep abbreviation; returns false if nil
      # @param mana [Integer] mana to prepare with
      # @param symbiosis [Boolean] prepare a symbiosis first, releasing it on failure
      # @param command [String] the prep command ('prepare', 'prep', 'incant', ...)
      # @param tattoo_tm [Boolean] target after preparing (tattoo TM)
      # @param runestone_name [String, nil] a runestone to invoke instead of a normal prep
      # @param runestone_tm [Boolean] target after invoking the runestone
      # @param custom_prep_message [String, nil] a per-spell prep message to also accept (see {#with_custom_messages})
      # @param custom_invoke_message [String, nil] a per-spell invoke message to also accept when preparing via a runestone
      # @param custom_spell_prep [String, nil] the global prep-message fallback (the custom_spell_prep setting); validated independently of custom_prep_message, so a blank/invalid per-spell value never suppresses a valid global one
      # @param retries [Integer] remaining retries for the transient "slips away" case
      # @return [String, false] the matched prep message, or false on failure
      def prepare?(abbrev, mana, symbiosis = false, command = 'prepare', tattoo_tm = false, runestone_name = nil, runestone_tm = false, custom_prep_message = nil, custom_invoke_message: nil, custom_spell_prep: nil, retries: PREPARE_MAX_RETRIES)
        return false unless abbrev
        spell_prep_messages = with_custom_messages(get_data('spells').prep_messages, custom_prep_message, custom_spell_prep)

        DRC.bput('prepare symbiosis', 'You recall the exact details of the', 'But you\'ve already prepared', 'Please don\'t do that here') if symbiosis
        if runestone_name.nil?
          match = DRC.bput("#{command} #{abbrev} #{mana}", spell_prep_messages)
        else
          match = DRC.bput("#{command} my #{runestone_name}", invoke_messages(custom_invoke_message))
        end
        case match
        when 'Your desire to prepare this offensive spell suddenly slips away'
          if retries <= 0
            Lich::Messaging.msg("bold", "DRCA: prepare? exhausted #{PREPARE_MAX_RETRIES} retries for '#{abbrev}' - giving up")
            return false
          end
          pause 1
          return prepare?(abbrev, mana, symbiosis, command, tattoo_tm, runestone_name, runestone_tm, custom_prep_message, custom_invoke_message: custom_invoke_message, custom_spell_prep: custom_spell_prep, retries: retries - 1)
        when 'Something in the area interferes with your spell preparations', 'You shouldn\'t disrupt the area right now', 'You have no idea how to cast that spell', 'You have yet to receive any training in the magical arts', 'Please don\'t do that here', 'You cannot use the tattoo while maintaining the effort to stay hidden'
          DRC.bput('release symbiosis', 'You release the', 'But you haven\'t') if symbiosis
          return false
        when 'Well, that was fun'
          DRCI.dispose_trash(runestone_name)
          return false
        when 'You\'ll have to hold it'
          return false
        end

        DRC.bput("target", spell_prep_messages) if tattoo_tm || runestone_tm

        match
      end

      # Returns true if preparing a spell, false otherwise.
      def spell_preparing?
        !spell_preparing.nil?
      end

      # Returns true if you're prepared to cast your spell.
      # Infers this if you're preparing a spell and there's no more prep time to wait.
      def spell_prepared?
        spell_preparing? && checkcastrt <= 0
      end

      # Returns name of the spell being prepared, or nil if not preparing one.
      def spell_preparing
        name = XMLData.prepared_spell
        name = nil if name.empty? || name.eql?('None')
        name
      end

      # Performs a full ritual spell: prepare, find focus, invoke, stow focus, and cast.
      #
      # Handles all stages of ritual magic from preparation through casting. Manages focus
      # retrieval and storage based on configuration (worn, tied, sheathed, or in-hand).
      # Supports both normal preps and runestone invocation.
      #
      # @param data [Hash] spell data with keys: abbrev, mana, symbiosis, prep_type, runestone_name, focus, worn_focus, tied_focus, sheathed_focus, custom_prep_message, custom_invoke_message, prep_time, cast, before, after, custom_cast_message, skip_retreat
      # @param settings [OpenStruct] configuration including ignored_npcs and custom_spell_prep
      # @return [void]
      # @see #prepare?
      # @see #invoke
      # @see #cast?
      def ritual(data, settings)
        DRC.retreat(settings.ignored_npcs) unless data['skip_retreat']
        DRC.release_invisibility
        DRC.set_stance('shield') unless data['skip_retreat']

        command = 'prepare'
        command = data['prep'] if data['prep']
        command = data['prep_type'] if data['prep_type']

        return unless prepare?(data['abbrev'], data['mana'], data['symbiosis'], command, data['tattoo_tm'], data['runestone_name'], data['runestone_tm'], data['custom_prep_message'], custom_invoke_message: data['custom_invoke_message'], custom_spell_prep: settings['custom_spell_prep'])

        prepare_time = Time.now
        find_focus(data['focus'], data['worn_focus'], data['tied_focus'], data['sheathed_focus'])

        invoke(data['focus'], nil, nil)
        stow_focus(data['focus'], data['worn_focus'], data['tied_focus'], data['sheathed_focus'])
        DRC.retreat(settings.ignored_npcs) unless data['skip_retreat']

        if data['prep_time']
          pause until Time.now - prepare_time >= data['prep_time']
        else
          waitcastrt?
        end

        return unless cast?(data['cast'], data['symbiosis'], data['before'], data['after'], data['custom_cast_message'])

        DRC.retreat(settings.ignored_npcs) unless data['skip_retreat']
      end

      # Prepares to cast by retrieving a runestone from storage.
      #
      # Checks if the runestone is already in the character's inventory. If not, attempts
      # to retrieve it from configured storage. Returns false and logs if retrieval fails
      # or the runestone is not available.
      #
      # @param spell [Hash] spell data with key runestone_name and optional runestone_name
      # @param settings [OpenStruct] configuration including runestone_storage
      # @return [Boolean] true if the runestone is available or retrieved; false on failure
      # @see #get_runestone?
      def prepare_to_cast_runestone?(spell, settings)
        if DRCI.inside?("#{spell['runestone_name']}", settings.runestone_storage)
          return false unless get_runestone?(spell['runestone_name'], settings)
        else
          Lich::Messaging.msg("bold", "DRCA: out of #{spell['runestone_name']}!")
          return false
        end
        true
      end

      # Retrieves a runestone from storage, handling useless/depleted runestones.
      #
      # Returns true if the runestone is already in hand. Otherwise attempts to retrieve it
      # from configured storage. If the runestone is useless (depleted), it is disposed of
      # and the method returns false. Logs errors on failure.
      #
      # @param runestone [String] the runestone noun to retrieve
      # @param settings [OpenStruct] configuration with runestone_storage location
      # @return [Boolean] true if the runestone is now in hand or was already held; false if not found or useless
      # @see #USELESS_RUNESTONE_PATTERNS
      # @see #GET_RUNESTONE_SUCCESS_PATTERNS
      # @see #GET_RUNESTONE_FAILURE_PATTERNS
      def get_runestone?(runestone, settings)
        return true if DRCI.in_hands?(runestone)

        result = DRC.bput(
          "get my #{runestone} from my #{settings.runestone_storage}",
          USELESS_RUNESTONE_PATTERNS, GET_RUNESTONE_SUCCESS_PATTERNS, GET_RUNESTONE_FAILURE_PATTERNS
        )
        if USELESS_RUNESTONE_PATTERNS.any? { |pat| pat.match?(result) }
          DRCI.dispose_trash(runestone)
          Lich::Messaging.msg("bold", "DRCA: got a useless #{runestone} - disposing and giving up")
          return false
        elsif GET_RUNESTONE_FAILURE_PATTERNS.any? { |pat| pat.match?(result) }
          Lich::Messaging.msg("bold", "DRCA: could not find #{runestone} in #{settings.runestone_storage}")
          return false
        end
        true
      end

      # Returns true if the most recently cast spell backfired.
      #
      # @return [Boolean] true if last spell backfired, false otherwise
      # @see #cast?
      def backfired?
        @backfired_status || false
      end

      # Casts the prepared spell, inferring success from the absence of a failure
      # flag (see the Flags below), and handling the WM barrage fallback and the
      # cyclic-too-recent / full-preparation retry cases.
      #
      # @param cast_command [String] the cast command ('cast', 'cast at ...', 'incant ...', 'barrage ...')
      # @param symbiosis [Boolean] whether a symbiosis was prepared (released on failure)
      # @param before [Array<Hash>] actions ({'message', 'matches'}) to bput before casting
      # @param after [Array<Hash>] actions to bput after casting
      # @param custom_cast_message [String, nil] a per-spell cast message to also accept (see {#with_custom_messages})
      # @param retries [Integer] remaining retries for barrage-fallback / cyclic-too-recent / full-prep
      # @return [Boolean] true if the spell cast without a failure flag being set
      def cast?(cast_command = 'cast', symbiosis = false, before = [], after = [], custom_cast_message = nil, retries: CAST_MAX_RETRIES)
        before.each { |action| DRC.bput(action['message'], action['matches']) }

        Flags.add('unknown-command', "Please rephrase that command")
        Flags.add('barrage-fail', "That was an invalid attack choice.", "Wouldn't it be better if you used a melee weapon?", "You'll need to be using a weapon to BARRAGE your target", "You must have a fully developed target matrix to make a barrage attack", "You are unable to muster the energy to do that", "You do not know how to manipulate that pathway.", "You cannot BARRAGE with that spell.")
        Flags.add('spell-fail', 'Currently lacking the skill to complete the pattern', "You don't have a spell prepared!", /^Your spell .*backfires/, 'Something is interfering with the spell', 'There is nothing else to face', 'You strain, but are too mentally fatigued', 'The spell pattern resists the influx of unfocused mana', 'Your target pattern dissipates because')
        Flags.add('cyclic-too-recent', 'The mental strain of initiating a cyclic spell so recently prevents you from formulating the spell pattern')
        Flags.add('spell-full-prep', /^This pattern may only be cast with full preparation/)
        Flags.add('spell-backfired', /^Your spell .*backfires/)

        cast_messages = with_custom_messages(get_data('spells').cast_messages, custom_cast_message)
        case DRC.bput(cast_command || 'cast', cast_messages)
        when /^Your target pattern dissipates/, /^You can't cast that at yourself/, /^You need to specify a body part to consume/, /^There is nothing else to face/
          DRC.bput('release spell', 'You let your concentration lapse', "You aren't preparing a spell")
          DRC.bput('release mana', 'You release all', "You aren't harnessing any mana")
        when /You gesture/
          pause 0.25
        end
        waitrt?

        # Warrior Mage failed to use (or doesn't know) barrage ability. Do regular cast instead.
        if cast_command =~ /\b(barrage)\b/i && (Flags['unknown-command'] || Flags['barrage-fail'])
          return cast?('cast', symbiosis, [], after, custom_cast_message, retries: retries - 1) if retries > 0

          Lich::Messaging.msg("bold", "DRCA: cast? barrage fallback exhausted retries - giving up")
          return false
        end

        if Flags['cyclic-too-recent'] || Flags['spell-full-prep']
          if retries <= 0
            Lich::Messaging.msg("bold", "DRCA: cast? exhausted #{CAST_MAX_RETRIES} retries waiting for cyclic/full-prep - giving up")
            return false
          end
          pause 1
          Flags.delete('spell-full-prep')
          return cast?(cast_command, symbiosis, [], after, custom_cast_message, retries: retries - 1)
        end

        after.each { |action| DRC.bput(action['message'], action['matches']) }

        if symbiosis && Flags['spell-fail']
          DRC.bput('release mana', 'You release all', "You aren't harnessing any mana")
          DRC.bput('release symbiosis', 'You release', 'But you haven\'t prepared')
        elsif Flags['spell-fail']
          DRC.bput('release mana', 'You release all', "You aren't harnessing any mana")
        end

        @backfired_status = Flags['spell-backfired']

        !Flags['spell-fail']
      end

      # Finds cambrinth, charges it with specified amounts, invokes it, and stows it.
      #
      # Orchestrates the complete cambrinth cycle: retrieval, charging, invocation, and storage.
      # Returns immediately if charges is nil or falsy.
      #
      # @param cambrinth [String] the cambrinth item noun
      # @param stored_cambrinth [Boolean] whether the cambrinth is stored (true) or worn (false)
      # @param cambrinth_cap [Integer] the mana capacity of the cambrinth
      # @param dedicated_camb_use [String, nil] optional dedicated cambrinth use mode
      # @param charges [Array<Integer>] mana amounts to charge in sequence
      # @param invoke_exact_amount [Integer, nil] exact mana to invoke; if nil, sum of all charges is used
      # @return [void]
      # @see #find_cambrinth
      # @see #charge_and_invoke
      # @see #stow_cambrinth
      def find_charge_invoke_stow(cambrinth, stored_cambrinth, cambrinth_cap, dedicated_camb_use, charges, invoke_exact_amount = nil)
        return unless charges

        find_cambrinth(cambrinth, stored_cambrinth, cambrinth_cap)
        charge_and_invoke(cambrinth, dedicated_camb_use, charges, invoke_exact_amount)
        stow_cambrinth(cambrinth, stored_cambrinth, cambrinth_cap)
      end

      # Retrieves a spell focus from its configured location.
      #
      # Handles four storage modes: worn (remove from body), tied (untie), sheathed (wield),
      # or in-hand (get from storage). Returns immediately if focus is nil.
      #
      # @param focus [String, nil] the focus item noun
      # @param worn [Boolean] whether the focus is worn on the body
      # @param tied [String, nil] location the focus is tied to, or false/nil if not tied
      # @param sheathed [Boolean] whether the focus is sheathed and needs wielding
      # @return [void]
      def find_focus(focus, worn, tied, sheathed)
        return unless focus

        if worn
          DRCI.remove_item?(focus)
        elsif tied
          DRCI.untie_item?(focus, tied)
        elsif sheathed
          result = DRC.bput("wield my #{focus}", WIELD_FOCUS_SUCCESS_PATTERNS, WIELD_FOCUS_FAILURE_PATTERNS)
          WIELD_FOCUS_FAILURE_PATTERNS.none? { |pattern| pattern =~ result }
        else
          DRCI.get_item?(focus)
        end
      end

      # Stows a spell focus back to its configured location after casting.
      #
      # Handles four storage modes: worn (wear item), tied (tie item with retries on failure),
      # sheathed (sheathe), or in-hand storage (stow). Returns immediately if focus is nil.
      # Retries up to {STOW_FOCUS_MAX_RETRIES} times on tie failures by retreating and retrying.
      #
      # @param focus [String, nil] the focus item noun
      # @param worn [Boolean] whether the focus should be worn
      # @param tied [String, nil] location to tie the focus; false/nil if not tied
      # @param sheathed [Boolean] whether the focus should be sheathed
      # @param retries [Integer] remaining tie retry attempts; default {STOW_FOCUS_MAX_RETRIES}
      # @return [Boolean, void] true if focus was successfully stowed (or was nil), false on persistent tie failure
      # @see #find_focus
      def stow_focus(focus, worn, tied, sheathed, retries: STOW_FOCUS_MAX_RETRIES)
        return unless focus

        if worn
          DRCI.wear_item?(focus)
        elsif tied
          result = DRCI.tie_item?(focus, tied)
          unless result
            if retries <= 0
              Lich::Messaging.msg("bold", "DRCA: stow_focus exhausted #{STOW_FOCUS_MAX_RETRIES} retries tying #{focus} - giving up")
              return false
            end
            DRC.retreat
            return stow_focus(focus, worn, tied, sheathed, retries: retries - 1)
          end
          result
        elsif sheathed
          result = DRC.bput("sheathe my #{focus}", SHEATHE_FOCUS_SUCCESS_PATTERNS, SHEATHE_FOCUS_FAILURE_PATTERNS)
          SHEATHE_FOCUS_FAILURE_PATTERNS.none? { |pattern| pattern =~ result }
        else
          DRCI.stow_item?(focus)
        end
      end

      # Locates a cambrinth item, handling both worn and stored configurations.
      #
      # If stored_cambrinth is true, ensures the cambrinth is in hand. If false (worn) and
      # Arcana skill is insufficient to charge while worn, retrieves it. If worn and skill
      # is sufficient, assumes it is already in position without verification.
      #
      # @param cambrinth [String] the cambrinth item noun
      # @param stored_cambrinth [Boolean] true if configured to be stored, false if worn
      # @param cambrinth_cap [Integer] the mana capacity for {#skilled_to_charge_while_worn?} check
      # @return [Boolean] true if the cambrinth is now available; false only if retrieval methods all fail
      # @see #skilled_to_charge_while_worn?
      # @see #stow_cambrinth
      def find_cambrinth(cambrinth, stored_cambrinth, cambrinth_cap)
        if stored_cambrinth
          # Your config says you keep your cambrinth stowed.
          # If item not in your hands, maybe you're wearing it by accident?
          DRCI.get_item_if_not_held?(cambrinth) || DRCI.remove_item?(cambrinth)
        elsif !skilled_to_charge_while_worn?(cambrinth_cap)
          # Your config says you wear your cambrinth.
          # But you're not skilled to charge it while worn.
          # If item not in your hands, maybe you're wearing it or stowed it by accident?
          DRCI.in_hands?(cambrinth) || DRCI.remove_item?(cambrinth) || DRCI.get_item?(cambrinth)
        else
          # Your config says you wear your cambrinth
          # and you're skilled to charge it while worn.
          # Let's hope you're wearing or holding it :)
          # To verify that would require more commands
          # and more time, and be more spammy.
          # For now, no validation or recovery for this scenario.
          true
        end
      end

      # Stows a cambrinth item back to its configured location.
      #
      # If configured as stored, ensures it is in storage. If configured as worn and currently
      # in hand, wears it (or stows it as fallback). If worn and not in hand, assumes it is
      # already worn and takes no action.
      #
      # @param cambrinth [String] the cambrinth item noun
      # @param stored_cambrinth [Boolean] true if should be stored, false if should be worn
      # @param _cambrinth_cap [Integer] unused
      # @return [Boolean] always returns true
      # @see #find_cambrinth
      def stow_cambrinth(cambrinth, stored_cambrinth, _cambrinth_cap)
        if stored_cambrinth
          # Your config says you keep your cambrinth stowed.
          # If item not in your hands and not stowed, maybe you're wearing it by accident?
          DRCI.get_item_if_not_held?(cambrinth) || DRCI.remove_item?(cambrinth)
          DRCI.stow_item?(cambrinth)
        elsif DRCI.in_hands?(cambrinth)
          # Your config says you wear your cambrinth.
          # For some reason it's currently in your hands.
          # If can't wear item for some reason then stow it.
          DRCI.wear_item?(cambrinth) || DRCI.stow_item?(cambrinth)
        else
          # Your config says you wear your cambrinth
          # and you're not currently holding it so
          # we'll assume you're wearing it.
          # No further action needed.
          true
        end
      end

      # Checks if Arcana skill is sufficient to charge a cambrinth while wearing it.
      #
      # The requirement is: Arcana rank >= (cambrinth_cap × 2) + 100.
      #
      # @param cambrinth_cap [Integer] the mana capacity of the cambrinth
      # @return [Boolean] true if skilled enough to charge while worn, false otherwise
      # @example
      #   skilled_to_charge_while_worn?(600) #=> true if Arcana >= 1300
      def skilled_to_charge_while_worn?(cambrinth_cap)
        DRSkill.getrank('Arcana').to_i >= ((cambrinth_cap.to_i * 2) + 100)
      end

      # Charges a cambrinth item sequentially and then invokes it.
      #
      # Returns immediately if charges is nil or empty. Charges each amount in sequence,
      # stopping if any charge fails. Then invokes the cambrinth with either the exact sum
      # of all charges or the provided invoke_exact_amount.
      #
      # @param cambrinth [String] the cambrinth item noun
      # @param dedicated_camb_use [String, nil] optional dedicated cambrinth use mode
      # @param charges [Array<Integer>, nil] mana amounts to charge in sequence
      # @param invoke_exact_amount [Integer, nil] exact mana to invoke; if nil, sum of charges is used
      # @return [void]
      # @see #charge?
      # @see #invoke
      def charge_and_invoke(cambrinth, dedicated_camb_use, charges, invoke_exact_amount = nil)
        return unless charges&.any?

        charges.each do |mana|
          break unless charge?(cambrinth, mana)
        end

        invoke_amount = invoke_exact_amount ? charges.inject(0, :+) : nil

        invoke(cambrinth, dedicated_camb_use, invoke_amount)
      end

      # Invokes a cambrinth item to release charged mana.
      #
      # Returns immediately if cambrinth is nil. On "too clumsy" error (Arcana too low),
      # logs a message. If the cambrinth is not currently in hand, attempts to retrieve it,
      # retry invoke, and then re-stow it. Handles the invoke attempt in a single command
      # by building "invoke my [cambrinth] [amount] [dedicated_use]".strip.
      #
      # @param cambrinth [String, nil] the cambrinth item noun
      # @param dedicated_camb_use [String, nil] optional dedicated cambrinth use mode
      # @param invoke_amount [Integer, nil] optional exact mana to invoke
      # @return [void]
      # @see #invoke_messages
      # @see #charge_and_invoke
      def invoke(cambrinth, dedicated_camb_use, invoke_amount)
        return unless cambrinth

        result = DRC.bput("invoke my #{cambrinth} #{invoke_amount} #{dedicated_camb_use}".strip, invoke_messages, 'Invoke what?')
        pause
        waitrt?
        case result
        when /you find it too clumsy/
          Lich::Messaging.msg("bold", "DRCA: your arcana skill is too low to invoke your cambrinth while worn")
          # If the cambrinth is in your hands and you can't invoke it, nothing else to do.
          unless DRCI.in_hands?(cambrinth)
            # Otherwise, try to find the cambrinth and get it to your hands.
            find_cambrinth(cambrinth, false, 999)
            # If you were able to get the cambrinth into a hand then retry invoking it.
            # You might not have been able to if your hands were full.
            if DRCI.in_hands?(cambrinth)
              invoke(cambrinth, dedicated_camb_use, invoke_amount)
              stow_cambrinth(cambrinth, false, 999)
            end
          end
        end
      end

      # Charges a cambrinth item with a specified mana amount.
      #
      # Returns true if the charge was successful (absorbs message received). On "You are in
      # no condition" error, attempts to harness instead. On wear/clumsy errors or missing
      # cambrinth, attempts to retrieve it from storage and retry. Returns false on failure.
      #
      # @param cambrinth [String] the cambrinth item noun
      # @param mana [Integer] mana amount to charge
      # @return [Boolean] true if charged successfully, false on failure
      # @see #harness?
      # @see #charge_and_invoke
      def charge?(cambrinth, mana)
        charged = false
        result = DRC.bput("charge my #{cambrinth} #{mana}", get_data('spells').charge_messages, 'I could not find')
        pause
        waitrt?
        case result
        when /You are in no condition to do that/
          charged = harness?(mana)
        when /You'll have to hold it/
          # You're not wearing nor holding your cambrinth item, go find it again.
          # Likely it's configured in your yaml that you wear it but it's stowed for some reason.
          # Try to find the cambrinth and get it to your hands.
          Lich::Messaging.msg("bold", "DRCA: where did your cambrinth go?")
          retry_find_cambrinth = true
        when /you find it too clumsy/
          Lich::Messaging.msg("bold", "DRCA: your arcana skill is too low to charge your cambrinth while worn")
          retry_find_cambrinth = true
        else
          charged = result =~ /absorbs? all of the energy/
        end
        if retry_find_cambrinth
          # If the cambrinth is in your hands and you can't charge it, nothing else to do.
          unless DRCI.in_hands?(cambrinth)
            # Otherwise, try to find the cambrinth and get it to your hands.
            find_cambrinth(cambrinth, false, 999)
            # If you were able to get the cambrinth into a hand then retry charging it.
            # You might not have been able to if your hands were full.
            if DRCI.in_hands?(cambrinth)
              charged = charge?(cambrinth, mana)
              stow_cambrinth(cambrinth, false, 999)
            end
          end
        end
        charged
      end

      # Releases all active cyclic spells, optionally excluding specified ones.
      #
      # Filters active spells to find those marked as cyclic in the spell data, removes any
      # in the exclusion list, and releases each via its abbreviation.
      #
      # @param cyclic_no_release [Array<String>] spell names to exclude from release
      # @return [void]
      # @see CYCLIC_RELEASE_SUCCESS_PATTERNS
      def release_cyclics(cyclic_no_release = [])
        get_data('spells')
          .spell_data
          .select { |_name, properties| properties['cyclic'] }
          .select { |name, _properties| DRSpells.active_spells.keys.include?(name) }
          .reject { |name| cyclic_no_release.include?(name) }
          .map { |_name, properties| properties['abbrev'] }
          .each { |abbrev| DRC.bput("release #{abbrev}", CYCLIC_RELEASE_SUCCESS_PATTERNS, 'Release what?') }
      end

      # Parses worn combat regalia crystals for Traders.
      #
      # Returns nil if the character is not a Trader. Otherwise queries worn combat equipment
      # and filters for rough-cut, faceted, or resplendent crystals, returning their nouns.
      #
      # @return [Array<String>, nil] list of regalia crystal nouns, or nil if not a Trader
      # @see #shatter_regalia?
      def parse_regalia
        return unless DRStats.trader?

        snapshot = Lich::Util.issue_command("inv combat", /All of your worn combat|You aren't wearing anything like that/, /Use INVENTORY HELP for more options/, usexml: false, include_end: false)
                             .map(&:strip)
        regalia_items = snapshot - ["All of your worn combat equipment:", "You aren't wearing anything like that."]
        regalia_items.select { |item| item.include?('rough-cut crystal') || item.include?('faceted crystal') || item.include?('resplendent crystal') }
                     .map { |item| DRC.get_noun(item) }
      end

      # Shatters worn combat regalia crystals for Traders.
      #
      # Returns false if not a Trader or if no regalia is worn. Otherwise removes each regalia
      # item, converting it into motes of silvery energy. Defaults to parsing current worn
      # regalia if not provided.
      #
      # @param worn_regalia [Array<String>, nil] list of regalia nouns to shatter; auto-detected if nil
      # @return [Boolean] true if one or more regalia were shattered, false if none were available
      # @see #parse_regalia
      def shatter_regalia?(worn_regalia = nil)
        return false unless DRStats.trader?

        worn_regalia ||= parse_regalia
        return false if worn_regalia.empty?

        worn_regalia.each do |item|
          DRC.bput("remove my #{item}", 'into motes of silvery', 'Remove what?', "You .*#{item}")
        end
        true
      end

      # Extracts the numeric mana level from a mana perception message.
      #
      # Parses the adjective at the end of the message to determine the mana strength level.
      # Keywords "weak", "developing", or "improving" select a mana map; otherwise "good" is used.
      # Returns the index + 1 of the adjective in the appropriate mana map.
      #
      # @param mana_msg [String] a mana perception message (e.g., "strong mana streams")
      # @return [Integer] 1-indexed mana level based on the adjective in the message
      # @api private
      # @see #perc_mana
      def parse_mana_message(mana_msg)
        manalevels = if mana_msg.include? 'weak'
                       $MANA_MAP['weak']
                     elsif mana_msg.include? 'developing'
                       $MANA_MAP['developing']
                     elsif mana_msg.include? 'improving'
                       $MANA_MAP['improving']
                     else
                       $MANA_MAP['good']
                     end

        adj = mana_msg.split(' ')[-1]

        manalevels.index(adj).to_i + 1
      end

      # Perceives the character's mana level in their trained schools.
      #
      # For Moon Mages, returns a Hash with four keys (enlightened_geometry, moonlight_manipulation,
      # perception, psychic_projection), each mapping to a numeric mana level. For other Mages,
      # returns a single Integer mana level. Returns nil for Barbarians, Thieves, Traders, Commoners,
      # or if perception fails.
      #
      # @return [Hash<String, Integer>, Integer, nil] mana level(s), or nil if unavailable
      # @example
      #   perc_mana #=> {"enlightened_geometry" => 3, "moonlight_manipulation" => 2, ...}
      #   perc_mana #=> 4 (for non-Moon Mages)
      # @see #parse_mana_message
      # @see PERC_MANA_START_PATTERN
      # @see PERC_MANA_END_PATTERN
      def perc_mana
        return nil if DRStats.barbarian? || DRStats.thief? || DRStats.trader? || DRStats.commoner?

        if DRStats.moon_mage?
          lines = Lich::Util.issue_command(
            'perc mana',
            PERC_MANA_START_PATTERN,
            PERC_MANA_END_PATTERN,
            usexml: false,
            include_end: false,
            quiet: true,
            timeout: 5
          )
          return nil if lines.nil?

          mana_msgs = lines.map(&:strip).select { |line| line.include?('streams') }[0..3]
          return nil if mana_msgs.length < 4

          mana_msgs.collect! { |mana_msg| mana_msg.split(' streams')[0] }

          {
            'enlightened_geometry'   => parse_mana_message(mana_msgs[0]),
            'moonlight_manipulation' => parse_mana_message(mana_msgs[1]),
            'perception'             => parse_mana_message(mana_msgs[2]),
            'psychic_projection'     => parse_mana_message(mana_msgs[3])
          }
        else
          mana_msg = DRC.bput('perc', '^You reach out with your .* and (see|hear) \w+')
          parse_mana_message(mana_msg)
        end
      end

      # Perceives the Trader's current aura level, cap status, and growth conditions.
      #
      # Only works for Traders. Issues 'perceive aura' and captures starlight level, cap status,
      # and growth conditions using Flags. Returns a Hash with level (0-9), capped (Boolean),
      # and growing (Boolean) keys.
      #
      # @return [Hash{String => (Integer, Boolean)}] aura state with keys 'level', 'capped', 'growing'
      # @example
      #   perc_aura #=> {"level" => 5, "capped" => false, "growing" => true}
      # @see STARLIGHT_MESSAGES
      def perc_aura
        return unless DRStats.trader?

        Flags.add('aura-level', Regexp.union(STARLIGHT_MESSAGES))
        Flags.add('aura-capped?', 'Your aura contains as much starlight as you can safely handle')
        Flags.add('aura-growing?', 'Local conditions permit optimal growth of your aura', 'Local conditions are hindering the growth of your aura')
        aura = {}
        DRC.bput('perceive aura', 'Roundtime')
        aura['level'] = Flags['aura-level'] ? STARLIGHT_MESSAGES.index(Flags['aura-level'][0]) : 0
        aura['capped'] = Flags['aura-capped?'] ? true : false
        aura['growing'] = Flags['aura-growing?'] ? true : false
        Flags.delete('aura-level')
        Flags.delete('aura-capped?')
        Flags.delete('aura-growing?')
        aura
      end

      # Casts a series of spells, applying buffs and respecting resource thresholds.
      #
      # Iterates through the spell list, skipping spells that are already active with sufficient
      # remaining duration. Waits for mana and concentration to reach configured thresholds before
      # casting each spell. Infuses Osrel Meraud before starting. Calls the lifecycle lambda
      # (if provided) at key phases.
      #
      # @param spells [Hash{String => Hash}] spell name => data mapping
      # @param settings [OpenStruct] configuration with waggle_spells_mana_threshold, concentration_threshold, osrel_no_harness, osrel_amount
      # @param force_cambrinth [Boolean] force use of cambrinth even if harness is available; default false
      # @param cast_lifecycle_lambda [Proc, nil] optional callback(phase, data, settings) called at 'pre-prep', 'post-prep', 'pre-cast', 'post-cast'
      # @return [void]
      # @see #cast_spell
      # @see #infuse_om
      def cast_spells(spells, settings, force_cambrinth = false, cast_lifecycle_lambda = nil)
        infuse_om(!settings.osrel_no_harness, settings.osrel_amount)
        spells.each do |name, data|
          next if DRSpells.active_spells[name] && (data['recast'].nil? || DRSpells.active_spells[name].to_i > data['recast'])

          while DRStats.mana < settings.waggle_spells_mana_threshold || DRStats.concentration < settings.waggle_spells_concentration_threshold
            Lich::Messaging.msg("plain", "DRCA: waiting on mana over #{settings.waggle_spells_mana_threshold} or concentration over #{settings.waggle_spells_concentration_threshold}...")
            pause 15
          end
          cast_spell(data, settings, force_cambrinth, cast_lifecycle_lambda)
        end
      end

      # Boolean wrapper for {#cast_spell} that returns true on success, false on failure.
      #
      # @param data [Hash] spell data
      # @param settings [OpenStruct] configuration
      # @param force_cambrinth [Boolean] force cambrinth use; default false
      # @param cast_lifecycle_lambda [Proc, nil] optional lifecycle callback
      # @return [Boolean] true if the spell was cast successfully
      # @see #cast_spell
      def cast_spell?(data, settings, force_cambrinth = false, cast_lifecycle_lambda = nil)
        !!cast_spell(data, settings, force_cambrinth, cast_lifecycle_lambda)
      end

      # Prepares and casts a single spell with full lifecycle support.
      #
      # Handles ritual spells (via {#ritual}) separately. For normal spells: releases active cyclics
      # (if needed), prepares the spell (with optional symbiosis), harnesses or charges mana, waits
      # for prep time, and casts. Supports custom prep messages, runestones, and lifecycle callbacks
      # at 'pre-prep', 'post-prep', 'pre-cast', and 'post-cast' phases.
      #
      # Returns false immediately if data or settings are nil. Returns false if preparation fails.
      # Returns the result of {#cast?} after casting, or nil if a ritual.
      #
      # @param data [Hash] spell data with keys: abbrev, mana, prep_time, cast, ritual, runestone_name, symbiosis, cyclic, cambrinth, custom_prep_message, custom_invoke_message, before, after, custom_cast_message, tattoo_tm, runestone_tm, prep_type
      # @param settings [OpenStruct] configuration with cambrinth, cambrinth_cap, stored_cambrinth, dedicated_camb_use, use_harness_when_arcana_locked, custom_spell_prep, runestone_storage
      # @param force_cambrinth [Boolean] force cambrinth use over harness; default false
      # @param cast_lifecycle_lambda [Proc, nil] optional callback(phase, data, settings) for lifecycle events
      # @return [Boolean, nil] true if cast successfully, false on failure, nil for rituals
      # @see #prepare?
      # @see #cast?
      # @see #ritual
      # @see #check_discern
      def cast_spell(data, settings, force_cambrinth = false, cast_lifecycle_lambda = nil)
        return unless data
        return unless settings

        data = DRCMM.update_astral_data(data, settings)
        return unless data # DRCMM.update_astral_data returns nil on failure

        if (data['abbrev'] =~ /locat/i) && !DRSpells.active_spells['Clear Vision']
          cast_spell({ 'abbrev' => 'cv', 'mana' => 1, 'prep_time' => 5 }, settings)
        end

        if data['ritual']
          ritual(data, settings)
          return
        end

        if data['runestone_name']
          return unless prepare_to_cast_runestone?(data, settings)
        end

        cast_lifecycle_lambda&.call('pre-prep', data, settings)

        command = 'prep'
        command = data['prep'] if data['prep']
        command = data['prep_type'] if data['prep_type']

        if command == 'segue'
          return if segue?(data['abbrev'], data['mana'])

          command = 'prep'
        end

        release_cyclics if data['cyclic']
        DRC.bput('release spell', 'You let your concentration lapse', "You aren't preparing a spell") unless checkprep == 'None'
        DRC.bput('release mana', 'You release all', "You aren't harnessing any mana")

        return unless prepare?(data['abbrev'], data['mana'], data['symbiosis'], command, data['tattoo_tm'], data['runestone_name'], data['runestone_tm'], data['custom_prep_message'], custom_invoke_message: data['custom_invoke_message'], custom_spell_prep: settings['custom_spell_prep'])

        DRCI.put_away_item?(data['runestone_name'], settings.runestone_storage) if DRCI.in_hands?(data['runestone_name'])
        prepare_time = Time.now

        normalize_cambrinth_items(settings)
        if check_to_harness(settings.use_harness_when_arcana_locked) && !force_cambrinth
          harness_mana(data['cambrinth'].flatten)
        else
          charge_cambrinth_items(data, settings)
        end

        cast_lifecycle_lambda&.call('post-prep', data, settings)

        if data['prep_time']
          pause until Time.now - prepare_time >= data['prep_time']
        else
          waitcastrt?
        end

        cast_lifecycle_lambda&.call('pre-cast', data, settings)
        spell_cast = cast?(data['cast'], data['symbiosis'], data['before'], data['after'], data['custom_cast_message'])
        cast_lifecycle_lambda&.call('post-cast', data, settings)

        spell_cast
      end

      # Attempts to segue from one cyclic spell to another.
      #
      # Returns false if the character is not performing a cyclic spell, if it is too soon to segue,
      # or if the character lacks bardic flair. Returns true on success.
      #
      # @param abbrev [String] the spell abbreviation to segue to
      # @param mana [Integer] mana to prepare the next spell with
      # @return [Boolean] true if segue succeeded, false on error conditions
      # @api private
      def segue?(abbrev, mana)
        case DRC.bput("segue #{abbrev} #{mana}", get_data('spells').segue_messages)
        when 'You must be performing a cyclic spell to segue from', 'It is too soon to segue', 'You are lacking the bardic flair'
          return false
        end
        true
      end

      # Discerns spell requirements and caches mana/cambrinth calculations.
      #
      # Caches per-spell mana discern data in UserVars.discerns. For sorcery or symbiosis spells,
      # extracts only the minimum mana streams. For other spells, uses the full discern pattern
      # to get min and reinforcement values. Calculates total mana and cambrinth distribution via
      # {#calculate_mana}. Re-discerns if cache is stale, timer expires, or settings change.
      # Returns the modified spell data with 'mana' and 'cambrinth' keys set.
      #
      # @param data [Hash] spell data with key 'abbrev'
      # @param settings [OpenStruct] configuration including check_discern_timer_in_hours, prep_scaling_factor, cambrinth settings
      # @param spell_is_sorcery [Boolean] whether the spell is a sorcery spell; default false
      # @param more_override [Integer, nil] override for reinforcement mana; if set, forces re-discern
      # @return [Hash] the modified spell data with mana and cambrinth populated
      # @example
      #   data = {"abbrev" => "cs", "mana" => 1}
      #   check_discern(data, settings) #=> {"abbrev" => "cs", "mana" => 42, "cambrinth" => [[5, 5, ...]]}
      # @see #calculate_mana
      # @see DISCERN_SORCERY_PATTERN
      # @see DISCERN_FULL_PATTERN
      def check_discern(data, settings, spell_is_sorcery = false, more_override = nil)
        UserVars.discerns = {} unless UserVars.discerns
        discern_data = UserVars.discerns[data['abbrev']] || {}
        if data['symbiosis'] || spell_is_sorcery
          if discern_data.empty? || discern_data['min'].nil? || more_override
            DRC.retreat
            discern_result = DRC.bput("discern #{data['abbrev']}", 'requires at minimum \d+ mana streams')
            match = discern_result.match(DISCERN_SORCERY_PATTERN)
            if match
              discern_data['mana'] = match[:min].to_i
              discern_data['cambrinth'] = nil
              discern_data['min'] = match[:min].to_i
              discern_data['more'] = (more_override || 0)
            end
          end
          calculate_mana(discern_data['min'], discern_data['more'], discern_data, false, settings)
        elsif discern_data.empty? || discern_data['time_stamp'].nil? || Time.now - discern_data['time_stamp'] > settings.check_discern_timer_in_hours * 60 * 60 || !discern_data['more'].nil? || stale_cambrinth_caps?(discern_data, settings)
          discern_data['time_stamp'] = Time.now
          DRC.retreat
          case discern = DRC.bput("discern #{data['abbrev']}", 'The spell requires at minimum \d+ mana streams and you think you can reinforce it with \d+ more', 'You don\'t think you are able to cast this spell', 'You have no idea how to cast that spell', 'You don\'t seem to be able to move to do that')
          when /you don't think you are able/i, 'You have no idea how to cast that spell', 'You don\'t seem to be able to move to do that'
            discern_data['mana'] = 1
            discern_data['cambrinth'] = nil
          else
            match = discern.match(DISCERN_FULL_PATTERN)
            calculate_mana(match[:min].to_i, match[:more].to_i, discern_data, data['cyclic'] || data['ritual'], settings) if match
          end
        end
        waitrt?
        UserVars.discerns[data['abbrev']] = discern_data
        data['mana'] = discern_data['mana']
        data['cambrinth'] = discern_data['cambrinth']
        data
      end

      # Calculates total mana and cambrinth charge distribution from discern values.
      #
      # Computes total mana as (min + more) × prep_scaling_factor, then distributes remaining mana
      # across configured cambrinth items respecting their caps. For cyclic/ritual spells, all mana
      # goes to the base prep (no cambrinth). Updates discern_data Hash in place with 'mana' and
      # 'cambrinth' keys.
      #
      # Uses either per-item distribution ({#calculate_mana_by_item}) or ratio-based distribution
      # ({#calculate_mana_by_ratio}) based on the cambrinth_distribute_charges setting.
      #
      # @param min [Integer] minimum mana streams from discern
      # @param more [Integer] additional reinforcement mana from discern
      # @param discern_data [Hash] cache entry to update with mana and cambrinth keys
      # @param cyclic_or_ritual [Boolean] true for cyclic or ritual spells (no cambrinth)
      # @param settings [OpenStruct] configuration with prep_scaling_factor, cambrinth_distribute_charges, cambrinth_items, cambrinth_num_charges
      # @return [void]
      # @api private
      # @see #calculate_mana_by_item
      # @see #calculate_mana_by_ratio
      def calculate_mana(min, more, discern_data, cyclic_or_ritual, settings)
        total = min + more
        total = (total * settings.prep_scaling_factor).floor
        discern_data['mana'] = [(total / 5.0).ceil, min].max
        remaining = total - discern_data['mana']
        normalize_cambrinth_items(settings)
        # Ignore cambrinth if charges to use is nil or 0
        settings.cambrinth_num_charges ||= 0
        if settings.cambrinth_distribute_charges
          calculate_mana_by_item(total, remaining, discern_data, cyclic_or_ritual, settings)
        else
          calculate_mana_by_ratio(total, remaining, discern_data, cyclic_or_ritual, settings)
        end
      end

      # Default. Splits the mana by the cap ratio of each cambrinth item, then gives
      # every charge of an item the same size. It can charge an item past its cap,
      # and integer division can drop mana. Kept as the default because a change to
      # the charge amounts affects every profile.
      def calculate_mana_by_ratio(total, remaining, discern_data, cyclic_or_ritual, settings)
        settings.cambrinth_items = [] if settings.cambrinth_num_charges == 0
        total_cambrinth_cap = settings.cambrinth_items.map { |x| x['cap'] }.inject(&:+) || 0
        charges_count_floor = remaining >= settings.cambrinth_num_charges ? settings.cambrinth_num_charges : 1
        settings.cambrinth_items.each do |item|
          item['charges'] = ((item['cap'].to_f / total_cambrinth_cap) * charges_count_floor).ceil
        end
        total_cambrinth_charges = settings.cambrinth_items.map { |x| x['charges'] }.inject(&:+) || 0
        if remaining > total_cambrinth_cap
          discern_data['mana'] = discern_data['mana'] + (remaining - total_cambrinth_cap)
          remaining = total - discern_data['mana']
        end
        if cyclic_or_ritual || total_cambrinth_charges == 0
          discern_data['cambrinth'] = nil
          discern_data['mana'] = discern_data['mana'] + remaining
        elsif remaining > 0
          total_cambrinth_mana = [remaining, total_cambrinth_cap].min
          settings.cambrinth_items.each_with_index do |item, index|
            discern_data['cambrinth'] ||= []
            charge_amount = (total_cambrinth_mana / total_cambrinth_charges) * item['charges']
            discern_data['cambrinth'][index] = []
            charge_amount.times do |i|
              # Lich patches NilClass#+ so that nil + 1 is 1. Spell it out here so
              # that this does not depend on the patch.
              slot = i % item['charges']
              discern_data['cambrinth'][index][slot] = (discern_data['cambrinth'][index][slot] || 0) + 1
            end
          end
        else
          discern_data['cambrinth'] = nil
        end
      end

      # Opt in with cambrinth_distribute_charges. Splits the mana into whole charges,
      # then fills each item up to its cap before it uses the next, the same way
      # cast.lic does. No item goes over its cap and no mana is dropped.
      def calculate_mana_by_item(total, remaining, discern_data, cyclic_or_ritual, settings)
        cambrinth_items = settings.cambrinth_num_charges == 0 ? [] : settings.cambrinth_items
        discern_data['cambrinth_caps'] = cambrinth_caps(settings)
        total_cambrinth_cap = cambrinth_items.map { |item| item['cap'].to_i }.sum
        if remaining > total_cambrinth_cap
          discern_data['mana'] = discern_data['mana'] + (remaining - total_cambrinth_cap)
          remaining = total - discern_data['mana']
        end
        if cyclic_or_ritual || cambrinth_items.empty?
          discern_data['cambrinth'] = nil
          discern_data['mana'] = discern_data['mana'] + remaining
        elsif remaining > 0
          num_charges = remaining >= settings.cambrinth_num_charges ? settings.cambrinth_num_charges : 1
          distribution, leftover = allocate_cambrinth_charges(remaining, cambrinth_items, num_charges)
          # Mana that fits in no cambrinth item goes into the base prep instead.
          discern_data['mana'] = discern_data['mana'] + leftover
          discern_data['cambrinth'] = distribution.empty? ? nil : distribution
        else
          discern_data['cambrinth'] = nil
        end
      end

      # The mana capacity of one cambrinth item. An unset or non-positive cap means
      # the config never declared a limit, so do not enforce one.
      def cambrinth_item_cap(item)
        cap = item['cap'].to_i
        cap <= 0 ? Float::INFINITY : cap
      end

      # Works out how to charge an amount of mana into the cambrinth items.
      #
      # Each item takes as much as its cap allows, in the order the config lists
      # them, so a small worn item fills before a large stored one. Each item then
      # splits its own share into charges. Returns the per-item nested array and
      # the mana that fits in no item.
      def allocate_cambrinth_charges(mana, cambrinth_items, num_charges)
        return [[], mana] if mana <= 0 || num_charges <= 0
        return [[], mana] if cambrinth_items.nil? || cambrinth_items.empty?

        allocations = Array.new(cambrinth_items.length, 0)
        unallocated = mana
        usable_cambrinth_indexes(cambrinth_items, num_charges).each do |index|
          allocations[index] = [unallocated, cambrinth_item_cap(cambrinth_items[index])].min
          unallocated -= allocations[index]
        end

        counts = cambrinth_charge_counts(allocations, num_charges)
        distribution = allocations.each_with_index.map do |allocation, index|
          split_cambrinth_charges(allocation, counts[index])
        end
        # Drop trailing empty entries so unused items are skipped entirely.
        [distribution.reverse.drop_while(&:empty?).reverse, unallocated]
      end

      # Every item that holds mana needs at least one charge, so the charge budget
      # limits how many items can be used. When there are more items than charges,
      # keep the items with the largest caps.
      def usable_cambrinth_indexes(cambrinth_items, num_charges)
        indexes = (0...cambrinth_items.length).to_a
        return indexes if indexes.length <= num_charges

        indexes.max_by(num_charges) { |index| cambrinth_item_cap(cambrinth_items[index]) }.sort
      end

      # Gives one charge to every item that holds mana, then spends what is left of
      # the charge budget on the largest charge, while that makes it smaller. This
      # keeps each charge inside what the character can channel at once.
      def cambrinth_charge_counts(allocations, num_charges)
        counts = allocations.map { |allocation| allocation > 0 ? 1 : 0 }
        funded = allocations.each_index.select { |index| allocations[index] > 0 }
        spare = num_charges - funded.length
        while spare > 0
          index = funded.max_by { |i| [allocations[i].to_f / counts[i], allocations[i]] }
          break if counts[index] >= allocations[index]

          largest = funded.map { |i| allocations[i].to_f / counts[i] }.max
          split = funded.map { |i| allocations[i].to_f / (i == index ? counts[i] + 1 : counts[i]) }.max
          break if split >= largest

          counts[index] += 1
          spare -= 1
        end
        counts
      end

      # Splits an amount of mana into num_charges charge values, largest first.
      # For example, 53 mana over 4 charges becomes [14, 13, 13, 13].
      def split_cambrinth_charges(total_mana, num_charges)
        return [] if total_mana <= 0 || num_charges <= 0

        charge_values = []
        rest = total_mana
        charges_left = num_charges
        while rest > 0 && charges_left > 0
          next_charge = (rest * 1.0 / charges_left).ceil
          charge_values << next_charge
          rest -= next_charge
          charges_left -= 1
        end
        charge_values
      end

      # Packs a flat list of charge values into the cambrinth items. Each item is
      # filled up to its cap before the next item is used. Returns the per-item
      # nested array and the mana that fits in no item.
      def distribute_cambrinth_charges(charge_values, cambrinth_items)
        pending = Array(charge_values).flatten.map(&:to_i).reject { |value| value <= 0 }
        return [[], pending.sum] if cambrinth_items.nil? || cambrinth_items.empty?

        distribution = Array.new(cambrinth_items.length) { [] }
        charged = Array.new(cambrinth_items.length, 0)
        leftover = 0
        pending.each do |charge_value|
          index = cambrinth_items.each_index.find do |i|
            charged[i] + charge_value <= cambrinth_item_cap(cambrinth_items[i])
          end
          if index
            distribution[index] << charge_value
            charged[index] += charge_value
          else
            leftover += charge_value
          end
        end
        # Drop trailing empty entries so unused items are skipped entirely.
        [distribution.reverse.drop_while(&:empty?).reverse, leftover]
      end

      # Signature of the configured cambrinth items. A change to it invalidates any
      # cached discern data, because the cached charges are split per item.
      def cambrinth_caps(settings)
        normalize_cambrinth_items(settings)
        settings.cambrinth_items.map { |item| item['cap'].to_i }
      end

      # True when cached discern data was calculated against a different set of
      # cambrinth items. Only the cambrinth_distribute_charges path records the
      # signature, so the default path never invalidates on it.
      def stale_cambrinth_caps?(discern_data, settings)
        return false unless settings.cambrinth_distribute_charges

        discern_data['cambrinth_caps'] != cambrinth_caps(settings)
      end

      # Determines whether to harness mana instead of charging cambrinth.
      #
      # Returns false if should_harness is false, or if Attunement XP exceeds Arcana XP.
      # (Harnessing scales with Arcana; a lower Arcana than Attunement indicates other skills
      # are preferred.)
      #
      # @param should_harness [Boolean] configuration enabling harness path
      # @return [Boolean] true if harness should be used, false otherwise
      # @api private
      # @see #infuse_om
      def check_to_harness(should_harness)
        return false unless should_harness
        return false if DRSkill.getxp('Attunement') > DRSkill.getxp('Arcana')

        true
      end

      # Casts a spell during crafting without preparation, assuming it is already prepared.
      #
      # Charges cambrinth or harnesses mana, then casts. Skips all prep steps. Returns false
      # if data or settings are nil.
      #
      # @param data [Hash] spell data with keys: cast, symbiosis, before, after, custom_cast_message, cambrinth
      # @param settings [OpenStruct] configuration for cambrinth and harness
      # @return [Boolean] true if cast succeeded, false on failure
      # @api private
      # @see #cast?
      # @see #charge_and_invoke
      def crafting_cast_spell(data, settings)
        return unless data
        return unless settings

        normalize_cambrinth_items(settings)
        if check_to_harness(settings.use_harness_when_arcana_locked)
          harness_mana(data['cambrinth'].flatten)
        else
          charge_cambrinth_items(data, settings)
        end

        cast?(data['cast'], data['symbiosis'], data['before'], data['after'], data['custom_cast_message'])
      end

      # Prepares a spell for crafting, skipping preparation if lunar moons are unavailable.
      #
      # Calls {#DRCMM.set_moon_data} to check lunar availability. Releases active cyclics
      # and existing preps before preparing. Returns false if data or settings are nil, or if
      # moon data is unavailable.
      #
      # @param data [Hash] spell data with keys: abbrev, mana, symbiosis, cyclic, prep_type, runestone_name, tattoo_tm, runestone_tm, custom_prep_message, custom_invoke_message
      # @param settings [OpenStruct] configuration including custom_spell_prep
      # @return [String, Boolean] matched prep message on success, false on failure
      # @api private
      # @see #prepare?
      def crafting_prepare_spell(data, settings)
        return unless data
        return unless settings

        # Skip preparing lunar spell if no moons available
        return unless DRCMM.set_moon_data(data)

        release_cyclics if data['cyclic']
        DRC.bput('release spell', 'You let your concentration lapse', "You aren't preparing a spell") unless checkprep == 'None'
        DRC.bput('release mana', 'You release all', "You aren't harnessing any mana")

        command = 'prep'
        command = data['prep'] if data['prep']
        command = data['prep_type'] if data['prep_type']

        prepare?(data['abbrev'], data['mana'], data['symbiosis'], command, data['tattoo_tm'], data['runestone_name'], data['runestone_tm'], data['custom_prep_message'], custom_invoke_message: data['custom_invoke_message'], custom_spell_prep: settings['custom_spell_prep'])
      end

      # Executes a crafting magic routine to train spells during downtime.
      #
      # Skips if no training spells are configured or mana is too low. If a spell is already
      # prepared, casts it. Otherwise selects the lowest-XP training spell (Warding, Utility,
      # Augmentation, optional Sorcery) and prepares it for casting. Does not cast—that happens
      # on the next cycle.
      #
      # @param settings [OpenStruct] configuration with crafting_training_spells, waggle_spells_mana_threshold, crafting_training_spells_enable_sorcery, crafting_training_spells_enable_sorcery_forging
      # @return [void]
      # @api private
      # @see #crafting_prepare_spell
      # @see #crafting_cast_spell
      def crafting_magic_routine(settings)
        training_spells = settings.crafting_training_spells

        return if training_spells.empty?
        return if DRStats.mana <= settings.waggle_spells_mana_threshold

        if checkcastrt > 0
          return
        elsif !XMLData.prepared_spell.eql?('None') && checkcastrt == 0
          spell = XMLData.prepared_spell
          data = training_spells.find { |_skill, info| info['name'] == spell }.last
          crafting_cast_spell(data, settings)
        end

        return if checkcastrt > 0

        needs_training = %w[Warding Utility Augmentation]
        needs_training.append("Sorcery") if (settings.crafting_training_spells_enable_sorcery && !Script.running?('forge')) ||
                                            (settings.crafting_training_spells_enable_sorcery && settings.crafting_training_spells_enable_sorcery_forging)
        needs_training = needs_training.select { |skill| training_spells[skill] }
                                       .select { |skill| DRSkill.getxp(skill) < 31 }
                                       .sort_by { |skill| [DRSkill.getxp(skill), DRSkill.getrank(skill)] }
                                       .first

        return unless needs_training

        crafting_prepare_spell(training_spells[needs_training], settings)
      end

      # Applies buffs from a named waggle set based on guild.
      #
      # Routes to {#start_barb_abilities} for Barbarians, {#start_khris} for Thieves, or
      # {#cast_spells} for Mages (filtering for day/night and discerning auto-mana spells).
      # Returns immediately if the waggle set is not configured.
      #
      # @param settings [OpenStruct] configuration with waggle_sets, waggle_force_cambrinth
      # @param set_name [String] the name of the waggle set to apply
      # @return [void]
      # @see #start_barb_abilities
      # @see #start_khris
      # @see #cast_spells
      def do_buffs(settings, set_name)
        return unless settings.waggle_sets[set_name]

        spells = settings.waggle_sets[set_name]

        if DRStats.barbarian?
          start_barb_abilities(spells, settings)
        elsif DRStats.thief?
          start_khris(spells, settings)
        else
          spells
            .select! { |_name, data| data['night'] ? UserVars.sun['night'] : true }
            .select! { |_name, data| data['day'] ? UserVars.sun['day'] : true }

          spells.values
                .select { |spell| spell['use_auto_mana'] }
                .each { |spell| check_discern(spell, settings) }

          cast_spells(spells, settings, settings.waggle_force_cambrinth)
        end
      end

      # Updates the Avtalia cambrinth tracking system with current charge state.
      #
      # Issues 'focus cambrinth' and parses the mana value from the output. Waits for roundtime.
      #
      # @return [void]
      # @api private
      # @see #invoke_avtalia
      # @see #charge_avtalia
      def update_avtalia
        DRC.bput("focus cambrinth", /^The .+ pulses? .+ (\d+)/, 'dim, almost magically null', '^You let your magical senses wander')
        waitrt?
      end

      # Invokes a cambrinth item and updates Avtalia tracking if avtalia.lic is running.
      #
      # Invokes the cambrinth and deducts the invoked amount from Avtalia's cached mana.
      # Returns without action if cambrinth is nil or avtalia script is not running.
      #
      # @param cambrinth [String, nil] the cambrinth item noun
      # @param dedicated_camb_use [String, nil] optional dedicated cambrinth use mode
      # @param invoke_amount [Integer, nil] exact mana to invoke
      # @return [void]
      # @api private
      # @see #invoke
      # @see #charge_avtalia
      def invoke_avtalia(cambrinth, dedicated_camb_use, invoke_amount)
        return unless cambrinth
        return unless Script.running?('avtalia')

        invoke(cambrinth, dedicated_camb_use, invoke_amount)
        UserVars.avtalia[cambrinth]['mana'] -= [DRStats.mana, invoke_amount].min
      end

      # Charges a cambrinth item and updates Avtalia tracking if avtalia.lic is running.
      #
      # On successful charge, estimates mana decay over elapsed time and recalculates assumed reserve.
      # On charge failure, resets to the cap. Returns without action if cambrinth is nil or avtalia
      # script is not running. Updates the time_seen timestamp.
      #
      # @param cambrinth [String, nil] the cambrinth item noun
      # @param charge_amount [Integer] mana amount to charge
      # @return [void]
      # @api private
      # @see #charge?
      # @see #invoke_avtalia
      def charge_avtalia(cambrinth, charge_amount)
        return unless cambrinth
        return unless Script.running?('avtalia')

        if !charge?(cambrinth, charge_amount)
          UserVars.avtalia[cambrinth]['mana'] = UserVars.avtalia[cambrinth]['cap']
        else
          # Experiments show very roughly 10% falloff regardless of cap every 10 minutes
          # Assume 10% every 5 minutes.  No falloff in starlight, but that's not tracked ATM.
          time_diff = Time.now - UserVars.avtalia[cambrinth]['time_seen']
          time_mod = (time_diff / 300.0).floor
          time_adjust = 1 - [time_mod * 0.10, 1.0].min
          assumed_reserve = (UserVars.avtalia[cambrinth]['mana'] * time_adjust).floor + charge_amount
          UserVars.avtalia[cambrinth]['mana'] = [assumed_reserve, UserVars.avtalia[cambrinth]['cap']].min
        end
        UserVars.avtalia[cambrinth]['time_seen'] = Time.now
      end

      # Selects the best cambrinth from Avtalia tracking for a charge attempt.
      #
      # Filters UserVars.avtalia for items that have been seen recently (within 600 seconds),
      # have sufficient mana percentage, and can provide at least charge_needed/10 mana.
      # Returns the cambrinth with the highest current mana, or nil if none qualify.
      #
      # @param charge_needed [Integer] total mana needed
      # @param mana_percentage [Integer] minimum mana level as a percentage of cap
      # @return [Array, nil] [cambrinth_noun, data_hash] or nil if no suitable cambrinth found
      # @api private
      # @see #charge_avtalia
      def choose_avtalia(charge_needed, mana_percentage)
        UserVars.avtalia.select { |_camb, data| data['time_seen'] && data['cap'] && data['mana'] }
                        .select { |_camb, data| Time.now - data['time_seen'] < 600.0 }
                        .select { |_camb, data| (data['mana'].to_f / data['cap'].to_f) * 100 >= mana_percentage }
                        .select { |_camb, data| data['mana'] > charge_needed / 10 }
                        .max_by { |_camb, data| data['mana'] }
      end

      # Determine the numerical range of a Warrior Mage's elemental charge.
      # This can be used to know if the mage is ready to perform certain abilities, like barrage.
      # Returns a number between 0 (no charge) and 11 (max charge).
      # https://elanthipedia.play.net/Summoning_skill#Charge_levels
      def check_elemental_charge
        return 0 unless DRStats.warrior_mage?

        result = DRC.bput("pathway sense", *CHARGE_LEVELS)
        CHARGE_LEVELS.find_index { |pattern| pattern =~ result }
      end

      # check which symbiotic research is active
      def perc_symbiotic_research
        result = DRC.bput('perceive', SYMBIOSIS_PATTERN, /Roundtime/)
        match = result.match(SYMBIOSIS_PATTERN)
        match ? match[:type] : nil
      end

      # release symbiotic research
      def release_magical_research
        2.times { DRC.bput("release symbiosis", "Are you sure", "You intentionally wipe", "But you haven't") }
      end

      # Normalizes cambrinth configuration from legacy single-item format to multi-item format.
      #
      # If cambrinth_items[0] has no 'name' key, replaces it with a single-item array using
      # the legacy cambrinth, cambrinth_cap, and stored_cambrinth settings. No-op if already
      # in multi-item format.
      #
      # @param settings [OpenStruct] configuration to normalize in place
      # @return [void]
      # @api private
      def normalize_cambrinth_items(settings)
        return if settings.cambrinth_items[0]['name']

        settings.cambrinth_items = [{
          'name'   => settings.cambrinth,
          'cap'    => settings.cambrinth_cap,
          'stored' => settings.stored_cambrinth
        }]
      end

      # Routes cambrinth charging to per-item or per-list distribution based on config.
      #
      # Delegates to {#charge_cambrinth_items_by_item} if cambrinth_distribute_charges is true,
      # otherwise to {#charge_cambrinth_items_repeated}.
      #
      # @param data [Hash] spell data with 'cambrinth' key (Array of charges)
      # @param settings [OpenStruct] configuration with cambrinth_distribute_charges flag
      # @return [void]
      # @api private
      # @see #charge_cambrinth_items_by_item
      # @see #charge_cambrinth_items_repeated
      def charge_cambrinth_items(data, settings)
        if settings.cambrinth_distribute_charges
          charge_cambrinth_items_by_item(data, settings)
        else
          charge_cambrinth_items_repeated(data, settings)
        end
      end

      # Default. A nested cambrinth list gives one entry to each item. A flat list
      # goes to every item in full, so several items each charge the whole list.
      def charge_cambrinth_items_repeated(data, settings)
        settings.cambrinth_items.each_with_index do |item, index|
          case data['cambrinth'].first
          when Array
            find_charge_invoke_stow(item['name'], item['stored'], item['cap'], settings.dedicated_camb_use, data['cambrinth'][index], settings.cambrinth_invoke_exact_amount)
          when Integer
            find_charge_invoke_stow(item['name'], item['stored'], item['cap'], settings.dedicated_camb_use, data['cambrinth'], settings.cambrinth_invoke_exact_amount)
          end
        end
      end

      # Opt in with cambrinth_distribute_charges. A flat list is spread over the
      # items instead of charged into every one of them.
      def charge_cambrinth_items_by_item(data, settings)
        charges = data['cambrinth']
        return unless charges.is_a?(Array) && !charges.empty?

        unless charges.first.is_a?(Array)
          return unless charges.first.is_a?(Integer)

          charges = spread_flat_cambrinth_charges(charges, settings.cambrinth_items)
        end

        settings.cambrinth_items.each_with_index do |item, index|
          item_charges = charges[index]
          next if item_charges.nil? || item_charges.empty?

          find_charge_invoke_stow(item['name'], item['stored'], item['cap'], settings.dedicated_camb_use, item_charges, settings.cambrinth_invoke_exact_amount)
        end
      end

      # Turns one flat list of charge values, as written in a spell config, into one
      # list for each cambrinth item.
      #
      # A single item takes the list unchanged. In this path cambrinth_cap feeds the
      # arcana check in skilled_to_charge_while_worn?, not a charge limit, and many
      # configs charge well past it on purpose.
      #
      # Several items need the list spread over them, because the whole list into
      # every item charges the same mana again for each item.
      def spread_flat_cambrinth_charges(charge_values, cambrinth_items)
        return [charge_values] if cambrinth_items.nil? || cambrinth_items.length <= 1

        distribution, leftover = distribute_cambrinth_charges(charge_values, cambrinth_items)
        return distribution if leftover <= 0

        # Never drop mana. What fits nowhere goes to the item with the largest cap.
        largest = cambrinth_items.each_with_index.max_by { |item, _index| item['cap'].to_i }.last
        distribution[largest] = (distribution[largest] || []) + [leftover]
        Lich::Messaging.msg("bold", "DRCA: #{leftover} mana does not fit your cambrinth_items caps and went into your #{cambrinth_items[largest]['name']}. Check those caps.")
        distribution
      end
    end
  end
end
