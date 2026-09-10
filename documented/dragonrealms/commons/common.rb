# frozen_string_literal: true

require_relative '../custom_substitutions'

# Namespace for the Lich scripting engine and its public APIs.
module Lich
  # Namespace for DragonRealms game integration.
  module DragonRealms
    # DragonRealms common library: shared utilities for item interaction, command
    # execution, combat, music, and character state management.
    #
    # Methods in this module are called as functions: `DRC.bput(...)`, `DRC.forage?(...)`,
    # etc. They wrap low-level Lich APIs (fput, get?, GameObj) and game-specific knowledge
    # into higher-level abstractions for scripting convenience.
    module DRC
      $pause_all_lock ||= Mutex.new
      $safe_pause_lock ||= Mutex.new

      module_function

      # -- Constants --------------------------------------------------------

      # Pattern for XML tags
      XML_TAG_PATTERN = /<[^>]+>/.freeze

      # Pattern for game wait/roundtime responses in bput
      WAIT_RESPONSE_PATTERN = /(?:\.\.\.wait |Wait |\.\.\. wait )(?<seconds>[0-9]+)/.freeze

      # Collect command response messages
      COLLECT_MESSAGES = [
        'As you rummage around',
        'believe you would probably have better luck trying to find a dragon',
        'if you had a bit more luck',
        'The room is too cluttered',
        'one hand free to properly collect',
        'You are sure you knew',
        'You begin to forage around,',
        'You begin scanning the area before you',
        'You begin exploring the area, searching for',
        'You find something dead and lifeless',
        'You cannot collect anything',
        'you fail to find anything',
        'You forage around but are unable to find anything',
        'You manage to collect a pile',
        'You survey the area and realize that any collecting efforts would be futile',
        'You wander around and poke your fingers',
        'You forage around for a while and manage to stir up a small mound of fire ants!'
      ].freeze

      # Retreat command response patterns
      RETREAT_ESCAPE_MESSAGES = [
        /You are already as far away as you can get/,
        /You retreat from combat/,
        /You sneak back out of combat/,
        /Retreat to where/,
        /There's no place to retreat to/
      ].freeze

      # Response patterns that indicate a retreat or movement blocking event.
      # Matched during retreat loop to detect when the character has broken combat,
      # tried to retreat, or hit obstacles.
      #
      # @return [Array<Regexp>] patterns including /retreat/, /sneak/, /grip/,
      #         /You must stand first/, and /You are already/
      # @example
      #   bput("retreat", *DRC::RETREAT_MESSAGES)
      # @see RETREAT_ESCAPE_MESSAGES
      # @see #retreat
      RETREAT_MESSAGES = [
        /retreat/,
        /sneak/,
        /grip on you/,
        /grip remains solid/,
        /You try to back/,
        /You must stand first/,
        /You stop advancing/,
        /You are already/
      ].freeze

      # Assess teach parsing patterns
      ASSESS_TEACH_TEACHER_PATTERN = /(?<teacher>.*) is teaching a class on (?<skill>.*) which is still open to new students/.freeze
      # Regex to extract filtered skill names from assess teach output.
      # Matches the portion after "(compared to what you already know)" in a teacher's skill line.
      #
      # @return [Regexp] pattern with named capture group `filtered_skill`
      # @example
      #   line = "Combat (compared to what you already know) Melee"
      #   line.match(ASSESS_TEACH_SKILL_FILTER_PATTERN)[:filtered_skill] #=> "Melee"
      # @see ASSESS_TEACH_TEACHER_PATTERN
      # @see #assess_teach
      # @see #parse_assess_teach_lines
      ASSESS_TEACH_SKILL_FILTER_PATTERN = /.* \(compared to what you already know\) (?<filtered_skill>.*)/.freeze

      # Common ranged weapon nouns
      COMMON_RANGED_WEAPONS_PATTERN = /^(bow|shortbow|longbow|crossbow|stonebow|latchbow|slurbow|lockbow|pelletbow|arbalest|sling|slingshot|blowgun)$/i.freeze

      # Gamgweth/racial ranged weapon nouns
      # https://elanthipedia.play.net/Genie_racial_language_item_subs
      # https://elanthipedia.play.net/Category:Language_Book
      RACIAL_RANGED_WEAPONS_PATTERN = /^(jranoki|uku'uan|uku'uanstaho|chunenguti|hhr'ibu|guti|mahil|taisgwelduan|chyeb|sverfil|tangara|alaer|kari|wami|usus|srigos|href|vrope|falocisana|stof|dzelt)$/i.freeze

      # Flavor text pattern for item descriptions
      # https://regex101.com/r/4lGY6u/13
      FLAVOR_TEXT_PATTERN = /\s?\b(?:(?:colorfully and )?(?:artfully|artistically|attractively|beautifully|bl?ack-|cleverly|clumsily|crudely|deeply|delicately|edged|elaborately|faintly|flamboyantly|front-|fully|gracefully|heavily|held|intricately|lavishly|masterfully|plentifully|prominantly|roughly|securely|sewn|shabbily|shadow-|simply|somberly|skillfully|sloppily|starkly|stitched|tied and|tightly|well-)\s?)?(?:accented|accentuated|acid-etched|adorned|affixed|appliqued|assembled|attached|augmented|awash|backed|back-laced|balanced|banded|batiked|beaded|bearded|bearing|bedazzled|bedecked|bejeweled|beset|bestrewn|blazoned|bordered|bound|braided|branded|brocaded|bristling|brushed|buckled|burned|buttoned|caked|camouflaged|capped|carved|caught|centered|chased|chiseled|cinched|circled|clasped|cloaked|closed|coated|cobbled together|coiled|colored|composed|concealed|connected|constructed|countoured|covered|crafted|crested|crisscrossed|crowded|crowned|cuffed|cut|dangling|dappled|decked|decorated|deformed|depicting|designed|detailed|discolored|displaying|divided|done|dotted|draped|drawn|dressed|drizzled|dusted|edged|elaborately|embedded|embell?ished|emblazed|emblazoned|embossed|embroidered(?: all over| painstakingly)?|enameled(?: across)?|encircled|encrusted|engraved|engulfed|enhanced|entwined|equipped|etched|fashioned(?: so)?|fastened|feathered|featuring|festooned|fettered|filed|filled|firestained|fit|fitted|fixed|flecked|fletched|forged|formed|framed|fringed|frosted|full|gathered|gleaming|glimmering|glittering|goldworked|growing|gypsy-set|hafted|hand-tooled|hanging|heavily(?:-beaded| covered)?|held fast|hemmed|hewn|hideously|highlighted|hilted|honed|hung|impressed|incised|ingeniously repurposed|inscribed|inlaid|inset|interlaced|interspersed|interwoven|jeweled|joined|laced(?: up)?|lacquered|laden|layered|limned|lined|linked|looped|knotted|made|marbled|marked|marred|meshed|mosaicked|mottled|mounted|oiled|oozing|outlined|ornamented|overlai(?:d|n)|padded|painted|paired|patched|pattern-welded|patterned|pinned|plumed|polished|printed|reinforced|reminiscent|rendered|revealing|riddled|ridged|rimed|ringed|riveted|sashed|scarred|scattered|scorched|sculpted|sealed|seamed|secured|securely|set|sewn|shaped|shimmering|shod|shot|shrouded|side-laced|slashed|slung|smeared|smudged|spangled|speckled|spiraled|splatter-dyed|splattered|spotted|sprinkled|stacked|surmounted|surrounded|suspended|stained|stamped|starred|stenciled|stippled|stitched(?: together)?|strapped|streaked|strengthened|strewn|striated|striped|strung|studded|swathed|swirled|tailored|tangled|tapered|tethered|textured|threaded|tied|tightly|tinged|tinted|tipped|tooled|topped|traced|trimmed|twined|veined|vivified|washed|webbed|weighted|whorled|worked|worn|woven|wrapped|wreathed|wrought)?\b ["]?\b(?:a hand-tooled|across|along|an|around|atop|bearing|belted|bright streaks|dangling|designed|detailing|down (?:each leg|one side)|dyed (?:a|and|deep|of|in|night|rust|shimmering|the|to|with)|engravings|entitled|errant pieces|featuring|flaunting|frescoed|from|Gnomish Pride|(?:encased |quartered )?in(?: the)?|into|labeled|leading|like|lining|matching|(?<!stick|slice|chunk|flask|hunk|series|set|pair|piece) of|on|out|overlayed gleaming silver|resembling|shades of color|sporting|surrounding|that|the|through|tinged somber black|titled|to|upon|WAR MONGER|with|within|\b(?:at|bearing|(?:accented |held |secured )?by|carrying|clutching|colored|cradling|dangling|depicting|(?:prominently )?displaying|embossed|etched|featuring|for(?:ming)?|holding|(?<!slice |chunk |flask |hunk |series |set |pair |piece )of|over|patterned|striped|suspending|textured|that)\b \b(?:a (?:band|beaded|brass|cascade|cluster|coral|crown|dead|.+ (?:ingot|boulder|stone|rock|nugget)|fierce|fanged|fringe|glowing|golden|grinning|howling|large|lotus|mosaic|pair|poorly|rainbow|roaring|row|silver(?:y|weave)?|small|snarling|spray|tailored|thick|tiny|trio|turquoise|yellowed)|(?:squared )?agonite (?:links|decorated)|alternating|an|(?:purple |blue )?and|ash|beaded fringe|blackened (?:steel(?: accents| bearing| with|$)|ironwood)|blue (?:gold|steel)|burnished golden|cascading layers|carved ivory|chain-lined|chitinous|(?:deep red|dull black|pale blue) cloth|cloudberry blossoms|colorful tightly|cotton candy|crimson steel|crisscrossed|curious design|curved|crystaline charm|dark (?:blue|green|grey|metals|windsteel) (?:and|exuding|glaes|hues|khor'vela|muracite|pennon|with)|dark supple|deepest|deeply blending|delicate|dusky (?:dreamweave|green-grey)|ebonwood$|emblazoned|enamel?led (?:steel|bronze)|etched|fine(?:-grained| black| crushed)|finely wrought|flame-kissed|forest|fused-together|fuzzy grey|gauze atop|gilded steel|glass eyeballs|glistening green|golden oak|grey fur|hammered|haralun|has|heavy (?:grey|pearl|silver)|horn|Ilithi cedar|inky black|interlocking silver|interwoven|iridescent|jagged interlocking plates|(?:soft dark|supple|thick|woven) (?:bolts|leather)|lightweight|long swaths|lustrous|kertig ravens|made|metal cogs|mirror-finished|mottled|multiple woods|naphtha|oak|oblong sanguine|one|onyx buttons|opposing images|overlapping|pale cerulean|pallid links|pastel-hued|pins|pitted (?:black iron|steel)|plush velvet|polished (?:bronze|hemlock|steel)|raccoon tails|ram's horns|rat pelts|raw|red and blue|rich (?:purple|golden)|riveted bindings|roughened|rowan|sanguine thornweave|scattered star|scorch marks|sculpted|shadows|shark cartilage|shifting (?:celadon|shades)|shipboard|(?:braided |cobalt |deep black |desert-tan |dusky red Taisidon |ebony |exquisite spider|fine leaf-green |flowing night|glimmering ebony |heavy |marigold |pale gold marquisette and virid |rich copper |spiral-braided |steel|unadorned black Musparan )?silk(?:cress)?|(?:coiled |shimmering )?silver(?:steel| and |y)?|sirese blue spun glitter|six crossed|slender|small bones|smoothly interlocking|snow leopard|soft brushed|somber black|sprawled|sun-bleached|steel links|stones|strips of|sunny yellow|teardrop plates|telothian|the|tiny (?:golden|indurium|scales|skull)|tightly braided|tomiek|torn|twists|two|undyed|vibrant multicolored|viscous|waves of|weighted|well-cured|white ironwood|windstorm gossamer|wintry faeweave|woven diamondwood))\b.*/.freeze

      # Game responses to STAND that mean standing cannot currently succeed,
      # so fix_standing must stop instead of looping forever (issue #3668).
      # These are already in the STAND match list, but matching one does not
      # change posture, so without this guard the loop spams STAND endlessly
      # (e.g. while unconscious, plummeting, held, or overburdened).
      CANNOT_STAND_PATTERN = /unconscious|plummeting to your death|prevents you from standing|don't seem to be able to move|overburdened and cannot|weight of all your possessions|no room to do much of anything/.freeze

      # -- Shared Utility Methods ------------------------------------------

      # Strips XML tags and decodes common HTML entities from game output lines.
      # @param lines [Array<String>] Array of raw game output lines
      # @return [Array<String>] Array of non-empty, trimmed strings with XML removed
      def strip_xml(lines)
        lines.map { |line| line.gsub(XML_TAG_PATTERN, '').gsub('&gt;', '>').gsub('&lt;', '<').strip }
             .reject(&:empty?)
      end

      # Like `fput` but better because will wait for RT
      # before performing command and do smart retries.
      # Will wait for matching text up to 15 seconds then timeout.
      # Also recovers from some limited failures wherein we want to
      # simply fix the issue and retry the bput, like when we're prone
      # and need to be standing. Complex handling should be done within
      # the calling script.
      def bput(message, *matches)
        options = (matches.shift if matches.first.is_a?(Hash)) || {}
        options['timeout'] ||= 15
        options['ignore_rt'] ||= false

        timeout = options['timeout']
        ignore_rt = options['ignore_rt']
        suppress = options['suppress_no_match']

        if options['debug']
          echo "bput.message=#{message}"
          echo "bput.options=#{options}"
          echo "bput.matches=#{matches}"
        end

        waitrt? unless ignore_rt
        log = []
        matches.flatten!
        matches.map! { |item| item.is_a?(Regexp) ? item : /#{item}/i }
        clear
        put message
        timer = Time.now
        while (response = get?) || (Time.now - timer < timeout)

          if response.nil?
            pause 0.1
            next
          end

          log += [response]

          case response
          when /^For some strange reason you are unable to do that\.  The world somehow seems frozen in place/
            # Zadraes - 13:32 It's a "You're in an area actively being updated" message
            pause 1
            put message
            timer = Time.now
            next
          when WAIT_RESPONSE_PATTERN
            unless ignore_rt
              wait_match = response.match(WAIT_RESPONSE_PATTERN)
              pause(wait_match[:seconds].to_i - 0.5)
              waitrt?
              put message
              timer = Time.now
            end
            next
          when /Sorry, you may only type ahead/
            pause 1
            put message
            timer = Time.now
            next
          when /^You can't do that while you are asleep./
            put 'wake'
            put message
            timer = Time.now
            next
          when /^You are a bit too busy performing to do that/, /^You should stop playing before you do that/
            put 'stop play'
            put message
            timer = Time.now
            next
          when /would give away your hiding place/
            release_invisibility
            put 'unhide'
            put message
            timer = Time.now
            next
          when /^You don't seem to be able to move to do that/
            next unless matches.include?(response)
          when /^You are still stunned/
            pause 0.5 while stunned?
            pause 0.5
            put message
            timer = Time.now
            next
          when /^You can't do that while entangled in a web/
            pause 0.5 while webbed?
            pause 0.5
            put message
            timer = Time.now
            next
          when /^You must be standing/, /^You should stand up first/, /^You'll need to stand up first/, /^You can't do that while (sitting|kneeling|lying)/, /^You should be sitting up/, /^You really should be standing to play/, /^After failing to draw a breath for what feels like forever/
            fix_standing
            waitrt?
            put message
            timer = Time.now
            next
          end

          matches.each do |match|
            if (result = response.match(match))
              return result.to_a.first
            end
          end
        end

        unless suppress
          Lich::Messaging.msg("bold", "DRC: No match was found after #{timeout} seconds for command '#{message}'")
          Lich::Messaging.msg("bold", "DRC: Messages seen: #{log.length}")
          log.reverse.each { |logged_response| Lich::Messaging.msg("bold", "DRC: > #{logged_response}") }
          Lich::Messaging.msg("bold", "DRC: Checked against: #{matches}")
        end

        ''
      end

      # Checks that one or more scripts exist in the current game environment.
      # Logs a bold message for each missing script and returns false if any are not found.
      #
      # @param script_names [String, Array<String>] script name(s) to verify
      # @return [Boolean] true if all scripts exist, false if any are missing
      # @example
      #   DRC.verify_script('safe-room') #=> true
      #   DRC.verify_script(['hunt', 'loot', 'missing-script'])
      #   # => logs "DRC: Failed to find a script named 'missing-script'", returns false
      # @see #wait_for_script_to_complete
      def verify_script(script_names)
        script_names = [script_names] unless script_names.is_a?(Array)
        state = true
        script_names
          .reject { |name| Script.exists?(name) }
          .each do |name|
            Lich::Messaging.msg("bold", "DRC: Failed to find a script named '#{name}'")
            state = false
          end
        state
      end

      # Starts a script and blocks until it finishes running, then returns its handle.
      # Verifies the script exists before starting. Pauses 2 seconds after start,
      # then polls Script.running every 0.5 seconds until the handle disappears.
      #
      # @param name [String] the script name
      # @param args [Array] command-line arguments; quoted if they contain whitespace
      # @param flags [Hash] flags passed to start_script (e.g. {quiet: true})
      # @return [OpenStruct, nil] the script handle, or nil if script does not exist
      # @example
      #   DRC.wait_for_script_to_complete('forage', ['apple'])
      #   DRC.wait_for_script_to_complete('sell', ['item'], {quiet: true})
      # @see #verify_script
      def wait_for_script_to_complete(name, args = [], flags = {})
        verify_script(name)
        script_handle = start_script(name, args.map { |arg| arg.to_s =~ /\s/ ? "\"#{arg}\"" : arg }, flags)
        if script_handle
          pause 2
          pause 0.5 while Script.running.include?(script_handle)
        end
        script_handle
      end

      # Returns true if the character can see the sky (outdoors or indoors with windows).
      # Issues a "weather" command and examines the response.
      #
      # @return [Boolean] true if outdoors or indoors with skylight/window, false if fully enclosed
      # @example
      #   DRC.can_see_sky? #=> true (if in an open area or by a window)
      def can_see_sky?
        # If you are indoors and not able to see the sky.
        inside_no_sky = "That's a bit hard to do while inside."
        # If you are indoors but able to see the sky (e.g. a window or skylight).
        inside_yes_sky = "You glance outside"
        # If you are outdoors.
        outside = "You glance up at the sky"
        # Can we see the sky?
        bput("weather", inside_no_sky, inside_yes_sky, outside) != inside_no_sky
      end

      # Forages for an item up to a maximum number of tries, returning true if successful.
      # Stops early if the room is too cluttered, foraging is futile, or hands are full.
      # Attempts to free the right hand if needed. Waits for roundtime between attempts.
      #
      # @param item [String] the item to forage for, e.g. "herb"
      # @param tries [Integer] maximum number of forage attempts (default 5)
      # @return [Boolean] true if something was found (inventory changed), false otherwise
      # @example
      #   DRC.forage?('apple', 3) #=> true if an apple was found within 3 tries
      # @see #collect
      # @see #kick_pile?
      def forage?(item, tries = 5)
        snapshot = "#{right_hand}#{left_hand}"
        while snapshot == "#{right_hand}#{left_hand}"
          tries > 0 ? tries -= 1 : (return false)
          case bput("forage #{item}", 'Roundtime', 'The room is too cluttered to find anything here', 'You really need to have at least one hand free to forage properly', 'You survey the area and realize that any foraging efforts would be futile')
          when 'The room is too cluttered to find anything here'
            return false unless kick_pile?
          when 'You survey the area and realize that any foraging efforts would be futile'
            return false
          when 'You really need to have at least one hand free to forage properly'
            Lich::Messaging.msg("bold", "DRC: Hands not emptied properly. Stowing right hand...")
            unless DRCI.stow_hand('right')
              Lich::Messaging.msg("bold", "DRC: Failed to stow right hand, cannot forage.")
              return false
            end
          end
          waitrt?
        end
        true
      end

      # Collects an item, optionally marking it as practice to gain skill.
      # Retries if the room is too cluttered after kicking the pile.
      # Waits for roundtime after completion.
      #
      # @param item [String] the item to collect, e.g. "herbs"
      # @param practice [Boolean] whether to add "practice" to the collect command (default true)
      # @return [void]
      # @example
      #   DRC.collect('herbs')
      #   DRC.collect('herbs', false)  # collect without practice flag
      # @see #forage?
      # @see #kick_pile?
      def collect(item, practice = true)
        practicing = "practice" if practice

        case bput("collect #{item} #{practicing}", COLLECT_MESSAGES)
        when 'The room is too cluttered'
          return unless kick_pile?

          collect(item)
        end
        waitrt?
      end

      # Attempts to kick a pile in the room, returning true if successfully knocked back.
      # First ensures the character is standing, then checks if a matching room object exists.
      # Returns false if no piles match or the kick does not succeed.
      #
      # @param item [String] the item name to kick (default 'pile')
      # @return [Boolean] true if kicked back successfully, false if not found or not kicked
      # @example
      #   DRC.kick_pile? #=> true if pile was kicked back
      #   DRC.kick_pile?('rubble') #=> true if rubble was kicked back
      # @see #collect
      # @see #forage?
      def kick_pile?(item = 'pile')
        fix_standing
        return unless DRRoom.room_objs.any? { |room_obj| room_obj.match?(/pile/) }
        bput("kick #{item}", 'I could not find', 'take a step back and run up to', 'Now what did the .* ever do to you', 'You lean back and kick your feet,') == 'take a step back and run up to'
      end

      # Rummages through a container with a search parameter, returning matching items as nouns.
      # Handles closed containers, invisibility, and missing items. Parses the game response
      # to extract a list of items, then applies type-specific list conversion:
      # 'B' for boxes, 'SC' for scrolls, other parameters for generic items.
      #
      # @param parameter [String] the rummage filter: 'B' for boxes, 'G' for gems, 'M' for materials, 'S' for skins, 'SC' for scrolls
      # @param container [String] the container noun, e.g. "backpack" (used in "my <container>")
      # @return [Array<String>] list of matching item nouns or adjective+noun pairs for boxes/scrolls; empty array if nothing found or container is closed
      # @example
      #   DRC.rummage('G', 'backpack') #=> ["diamond", "emerald"]
      #   DRC.rummage('B', 'crate') #=> ["oak crate", "iron box"]
      # @see #get_gems
      # @see #get_skins
      # @see #get_materials
      # @see #box_list_to_adj_and_noun
      # @see #scroll_list_to_adj_and_noun
      def rummage(parameter, container)
        result = DRC.bput("rummage /#{parameter} my #{container}", 'but there is nothing in there like that\.', 'looking for .* and see .*', 'While it\'s closed', 'I don\'t know what you are referring to', 'You feel about', 'That would accomplish nothing')

        case result
        when 'You feel about'
          release_invisibility
          return rummage(parameter, container)
        when 'but there is nothing in there like that.', 'While it\'s closed', 'I don\'t know what you are referring to', 'That would accomplish nothing'
          return []
        end

        text = result.match(/looking for .* and see (.*)\.$/).to_a[1]
        case parameter
        when 'B'
          box_list_to_adj_and_noun(text)
        when 'SC'
          scroll_list_to_adj_and_noun(text)
        else
          list_to_nouns(text)
        end
      end

      # Rummages for skins in the given container.
      #
      # @param container [String] the container noun
      # @return [Array<String>] list of skin item nouns
      # @example
      #   DRC.get_skins('backpack') #=> ["fur", "scale"]
      # @see #rummage
      def get_skins(container)
        rummage('S', container)
      end

      # Rummages for gems in the given container.
      #
      # @param container [String] the container noun
      # @return [Array<String>] list of gem item nouns
      # @example
      #   DRC.get_gems('backpack') #=> ["diamond", "ruby"]
      # @see #rummage
      def get_gems(container)
        rummage('G', container)
      end

      # Rummages for materials in the given container.
      #
      # @param container [String] the container noun
      # @return [Array<String>] list of material item nouns
      # @example
      #   DRC.get_materials('backpack') #=> ["ingot", "silk"]
      # @see #rummage
      def get_materials(container)
        rummage('M', container)
      end

      # Take a game formatted list "an arrow, silver coins and a deobar strongbox"
      # And return an array ["an arrow", "silver coins", "a deobar strongbox"]
      # is this ever useful compared to the list_to_nouns?
      def list_to_array(list)
        list.strip.split(/(?:,|(?:, |\s)?and\s?)(?:\s?<pushBold\/>\s?)?(?=\s\ba\b|\s\ban\b|\s\bsome\b|\s\bthe\b)/i).reject(&:empty?)
      end

      # Post-match box name rewrites (applied via gsub after a box is matched).
      # "ironwood" -> "iron" because the game parser wants the shortened noun.
      # Players extend this via the +custom_box_substitutions+ setting; see
      # {box_list_to_adj_and_noun}.
      #
      # @return [Array<Array(String, String)>] ordered [from, to] literal pairs
      DEFAULT_BOX_SUBSTITUTIONS = [%w[ironwood iron]].freeze

      # Take a game formatted list of boxes "a reinforced wooden strongbox and a
      # plain ironwood crate" and return ["wooden strongbox", "iron crate"].
      #
      # The recognized wood and container words are {BOX_WOODS} and
      # {BOX_CONTAINERS} merged with the player's +custom_box_woods+ /
      # +custom_box_containers+ settings, so a player can teach Lich about a box
      # material or container it does not yet know without a Lich release. The
      # global +$box_regex+ (built from the same defaults) is left untouched for
      # third-party scripts. Post-match rewrites come from
      # {DEFAULT_BOX_SUBSTITUTIONS} merged with +custom_box_substitutions+.
      #
      # @param list [String] game-formatted box list (e.g. from rummage /B)
      # @return [Array<String>] gettable box adjective+noun names
      # @example
      #   box_list_to_adj_and_noun('an ironwood crate') #=> ['iron crate']
      # @see CustomSubstitutions.resolve
      # @see #scroll_list_to_adj_and_noun
      def box_list_to_adj_and_noun(list)
        woods = CustomSubstitutions.resolve(:custom_box_woods, BOX_WOODS, type: :names)
        containers = CustomSubstitutions.resolve(:custom_box_containers, BOX_CONTAINERS, type: :names)
        substitutions = CustomSubstitutions.resolve(:custom_box_substitutions, DEFAULT_BOX_SUBSTITUTIONS, type: :pairs)
        box_regex = /((?:#{woods.map { |wood| Regexp.escape(wood) }.join('|')}) (?:#{containers.map { |container| Regexp.escape(container) }.join('|')}))/
        list.strip
            .split(box_regex)
            .reject(&:empty?)
            .select { |item| item =~ box_regex }
            .map { |box| substitutions.reduce(box) { |current, (from, to)| current.gsub(from, to) } }
      end

      # Item-specific scroll rewrites applied *before* {SCROLL_KEYWORD_COLLAPSE}.
      # These full game descriptions contain keywords the collapse would
      # otherwise mangle (e.g. "icy blue vellum scroll" -> "icy scroll", not
      # "icy blue vellum"), or must be caught before the collapse can run.
      # Order matters and is preserved. Players extend this list via the
      # +custom_scroll_substitutions+ setting; see
      # {scroll_list_to_adj_and_noun}.
      #
      # @return [Array<Array(String, String)>] ordered [from, to] literal pairs
      DEFAULT_SCROLL_SUBSTITUTIONS_PRE = [
        ['large midnight-blue scale torn with symbols', 'midnight-blue scale'],
        ['icy blue vellum scroll', 'icy scroll'],
        ['green vellum scroll', 'green scroll'],
        ['fetid antelope vellum', 'antelope vellum'],
        ['papyrus roll', 'papyrus.roll'],
        ['pallid red scroll', 'pallid scroll']
      ].freeze

      # Adjective-pair scroll rewrites applied *after* {SCROLL_KEYWORD_COLLAPSE},
      # reducing already-collapsed forms (e.g. "stormy grey" -> "stormy"). Order
      # matters and is preserved. Not player-extensible (these operate on the
      # collapsed noun, not the raw description).
      #
      # @return [Array<Array(String, String)>] ordered [from, to] literal pairs
      DEFAULT_SCROLL_SUBSTITUTIONS_POST = [
        ['crumpled paper', 'crumpled'],
        ['pale ricepaper', 'pale'],
        ['stormy grey', 'stormy'],
        ['mossy green', 'mossy'],
        ['dark purple', 'dark'],
        ['vibrant red', 'vibrant'],
        ['bright green', 'bright'],
        ['icy blue', 'blue'],
        ['pearl-white silk', 'silk'],
        ['ghostly white', 'white'],
        ['crinkled violet', 'crinkled'],
        ['drawing paper', 'drawing']
      ].freeze

      # Structural collapse: reduce "<adj> <keyword> <flavor...>" to "<adj>
      # <keyword>" by keeping the noun keyword and dropping trailing flavor.
      # Sandwiched between the pre and post substitution passes.
      #
      # @return [Regexp]
      SCROLL_KEYWORD_COLLAPSE = /\s(bark|leaf|ostracon|papyrus|parchment|roll|scroll|tablet|vellum|manuscript)\s.*/.freeze

      # Converts a game rummage scroll list into gettable adjective+noun forms.
      #
      # Pipeline per entry: strip the leading article, strip "labeled with...",
      # apply the pre-collapse literal substitutions ({DEFAULT_SCROLL_SUBSTITUTIONS_PRE}
      # merged with the player's +custom_scroll_substitutions+), apply the
      # {SCROLL_KEYWORD_COLLAPSE}, then apply the post-collapse substitutions
      # ({DEFAULT_SCROLL_SUBSTITUTIONS_POST}).
      #
      # @param list [String] game-formatted scroll list (e.g. from rummage /SC)
      # @return [Array<String>] gettable scroll names
      # @example
      #   scroll_list_to_adj_and_noun(' an icy blue parchment') #=> ['blue parchment']
      # @see CustomSubstitutions.resolve
      # @see #box_list_to_adj_and_noun
      def scroll_list_to_adj_and_noun(list)
        pre_substitutions = CustomSubstitutions.resolve(:custom_scroll_substitutions, DEFAULT_SCROLL_SUBSTITUTIONS_PRE, type: :pairs)
        list_to_array(list).map do |entry|
          without_article = entry
                            .sub(/(an|some|a(?: piece of)?)\s/, '')
                            .sub(/\slabeled with.*/, '')
          with_pre = pre_substitutions.reduce(without_article) { |text, (from, to)| text.sub(from, to) }
          collapsed = with_pre.sub(SCROLL_KEYWORD_COLLAPSE, ' \1')
          DEFAULT_SCROLL_SUBSTITUTIONS_POST.reduce(collapsed) { |text, (from, to)| text.sub(from, to) }.strip
        end
      end

      # Take a game formatted list "an arrow, silver coins and a deobar strongbox"
      # And return an array of nouns ["arrow", "coins", "strongbox"]
      def list_to_nouns(list)
        list_to_array(list)
          .map { |long_name| get_noun(long_name) }
          .compact
          .reject { |noun| noun == '' }
      end

      # Extracts the gettable noun from an item long name by stripping flavor text
      # and returning the rightmost word.
      #
      # @param long_name [String] the full item name, e.g. "a sword adorned with rubies"
      # @return [String, nil] the noun, e.g. "sword", or nil if no noun found
      # @example
      #   DRC.get_noun('a sword adorned with rubies') #=> "sword"
      #   DRC.get_noun('silver coins') #=> "coins"
      # @see #remove_flavor_text
      def get_noun(long_name)
        remove_flavor_text(long_name).strip.scan(/[a-z\-']+$/i).first
      end

      # Strips descriptive flavor text ("... adorned with ...") from an item
      # name, leaving the gettable noun phrase.
      #
      # Applies the built-in {FLAVOR_TEXT_PATTERN} first, then any player-defined
      # +custom_flavor_text_patterns+ (regular expressions) for flavor the
      # built-in pattern misses -- letting a player strip a new flavor phrasing
      # without a Lich release. User patterns are compiled with a per-pattern
      # timeout and validated/guarded by {CustomSubstitutions}; an invalid or
      # runaway pattern is reported and skipped, never raising here.
      #
      # @param item [String] the item long name
      # @return [String] the item name with flavor text removed
      # @example
      #   remove_flavor_text('a sword adorned with rubies of deep crimson') #=> 'a sword'
      # @see CustomSubstitutions.resolve
      # @see CustomSubstitutions.apply_regexes
      def remove_flavor_text(item)
        custom_patterns = CustomSubstitutions.resolve(:custom_flavor_text_patterns, [], type: :regexes)
        CustomSubstitutions.apply_regexes(item.sub(FLAVOR_TEXT_PATTERN, ''), custom_patterns)
      end

      # Items class. Name is the noun of the object. Leather/metal boolean. Is the item worn (defaults to true). Does it hinder lockpicking? (false)
      # Item.new(name:'gloves', leather:true, worn:true, hinders_locks:true, adjective:'ring', bound:true)
      class Item
        attr_reader :name, :leather, :worn, :hinders_lockpicking, :container, :swappable, :tie_to, :adjective, :bound, :wield, :transforms_to, :transform_verb, :transform_text, :lodges, :skip_repair, :ranged, :needs_unloading

        # Creates an Item instance to describe equipment for outfit management.
        #
        # @param name [String, nil] the item noun used for get/stow commands
        # @param leather [Boolean, nil] whether the item is leather (vs metal)
        # @param worn [Boolean] whether the item is worn on the body (default false)
        # @param hinders_locks [Boolean, nil] whether wearing this item blocks lockpicking
        # @param container [String, nil] container noun if this item is a container (e.g. "backpack")
        # @param swappable [Boolean] whether this item can be freely swapped in/out during actions (default false)
        # @param tie_to [String, nil] another item noun this should be tied to (e.g. "bag" for a cord)
        # @param adjective [String, nil] the descriptive adjective used in get commands (e.g. "ring" in "ring.sword")
        # @param bound [Boolean] whether this item is bound and cannot be dropped (default false)
        # @param wield [Boolean] whether the item should be wielded in hand (default false)
        # @param transforms_to [String, nil] noun of the item after a transform (e.g. "rope" -> "coil")
        # @param transform_text [String, nil] text to look for to trigger the transform (e.g. "coil it")
        # @param transform_verb [String, nil] the verb to trigger the transform (e.g. "coil")
        # @param lodges [Boolean] whether the item can lodge/stick in targets (default true)
        # @param skip_repair [Boolean] whether to skip repairing this item (default false)
        # @param ranged [Boolean, nil] whether this is a ranged weapon; auto-detected from name if nil
        # @param needs_unloading [Boolean, nil] whether the item needs unloading; defaults to ranged value if nil
        # @example
        #   DRC::Item.new(name: 'sword', worn: true, adjective: 'broadsword')
        #   DRC::Item.new(name: 'backpack', container: true)
        # @see .from_text
        def initialize(name: nil, leather: nil, worn: false, hinders_locks: nil, container: nil, swappable: false, tie_to: nil, adjective: nil, bound: false, wield: false, transforms_to: nil, transform_text: nil, transform_verb: nil, lodges: true, skip_repair: false, ranged: nil, needs_unloading: nil)
          @name = name
          @leather = leather
          @worn = worn
          @hinders_lockpicking = hinders_locks
          @container = container
          @swappable = swappable
          @tie_to = tie_to
          @adjective = adjective
          @bound = bound
          @wield = wield
          @transforms_to = transforms_to
          @transform_verb = transform_verb
          @transform_text = transform_text
          @lodges = lodges.nil? ? true : lodges
          @skip_repair = skip_repair
          @ranged = ranged.nil? ? ranged_weapon?(name) : ranged
          @needs_unloading = needs_unloading.nil? ? @ranged : needs_unloading
        end

        # Returns a compact get-friendly name combining adjective and noun.
        # Used by outfit/equipment scripts as the basis for get/stow commands.
        #
        # @return [String] the adjective + '.' + name if adjective is set, else just name
        # @example
        #   Item.new(name: 'sword', adjective: 'broadsword').short_name #=> "broadsword.sword"
        #   Item.new(name: 'sword').short_name #=> "sword"
        def short_name
          @adjective ? "#{@adjective}.#{@name}" : @name
        end

        # Returns a case-insensitive regex for matching this item in game output.
        # Matches the adjective (if present) followed by the noun as word boundaries.
        #
        # @return [Regexp] a pattern like /\b#{adjective}.*\b#{name}/i or /\b#{name}/i
        # @example
        #   Item.new(name: 'sword', adjective: 'broadsword').short_regex
        #   # => /\bbroadsword.*\bsword/i
        def short_regex
          @adjective ? /\b#{@adjective}.*\b#{@name}/i : /\b#{@name}/i
        end

        # Determines if a noun is a ranged weapon by matching against known patterns.
        # Checks both common ranged weapons (bow, crossbow, sling, etc.) and racial
        # ranged weapons (Gamgweth weapons like jranoki, uku'uan).
        #
        # @param noun [String, nil] the weapon noun to test
        # @return [Boolean] true if the noun matches a ranged weapon pattern, false otherwise
        # @example
        #   item = Item.new(name: 'bow')
        #   item.ranged_weapon?('bow') #=> true
        #   item.ranged_weapon?('sword') #=> false
        # @see COMMON_RANGED_WEAPONS_PATTERN
        # @see RACIAL_RANGED_WEAPONS_PATTERN
        def ranged_weapon?(noun)
          return false if noun.nil?

          return true if COMMON_RANGED_WEAPONS_PATTERN.match?(noun)
          return true if RACIAL_RANGED_WEAPONS_PATTERN.match?(noun)

          false
        end

        # Convenience method to parse the text of an item as shown when in your hands, with or without an adjective,
        # into an Item class instance. Originally designed to support DRCI and equipmanager methods.
        def self.from_text(text)
          return nil if text.nil? || text.to_s.strip.empty?

          normalized = text
                       .sub('.', ' ') # convert 'foo.bar' => 'foo bar' so more easily split into adjective and noun
                       .squeeze(' ') # condense repeated runs of whitespace with a single space
                       .strip # remove leading/trailing whitespace
          parts = normalized.split
          if parts.size > 1
            DRC::Item.new(adjective: parts.first, name: parts.last)
          else
            DRC::Item.new(name: normalized)
          end
        end
      end

      # Looks up the canonical name of the town based on the given text.
      # Utility to help identify the canonical town name based on arbitrary text.
      # For example, "Theren" for "Therenborough" and "Haven" for "Riverhaven".
      # It also handles missing apostrophes and the occasional space between names
      # like "merkresh" or "Mer'Kresh" or "ainghazal" or "Ain Ghazal".
      # Returns nil if unable to find a match.
      def get_town_name(text)
        towns = $HOMETOWN_REGEX_MAP.select { |_town, regex| regex =~ text }.keys
        if towns.length > 1
          Lich::Messaging.msg("bold", "DRC: Found multiple towns that match '#{text}': #{towns}")
          Lich::Messaging.msg("bold", "DRC: Using first town that matched: #{towns.first}")
          Lich::Messaging.msg("bold", "DRC: To avoid ambiguity, please use the town's full name: https://elanthipedia.play.net/Category:Cities")
        end
        towns.first
      end

      # windows only I believe.
      def beep
        echo("\a")
      end

      # Issues STAND until the character is standing, giving up when the game
      # reports a state from which standing cannot currently succeed. Without
      # the CANNOT_STAND_PATTERN guard these states loop forever spamming
      # STAND, because matching the message never makes standing? true
      # (issue #3668: safe-room spamming STAND while unconscious).
      # @return [void]
      def fix_standing
        loop do
          break if standing?

          result = bput('stand', 'You stand', 'You are so unbalanced', 'As you stand', 'You are already', 'weight of all your possessions', 'You are overburdened and cannot', 'You\'re unconscious', 'You swim back up into a vertical position', "You don't seem to be able to move to do that", 'prevents you from standing', 'You\'re plummeting to your death', 'There\'s no room to do much of anything here')
          break if result =~ CANNOT_STAND_PATTERN
        end
      end

      # Attempts to listen to a teacher for skill training, handling class restrictions.
      # Stops listening if the skill is forbidden for the character's class (e.g., Thief cannot
      # learn Sorcery). Returns true if successfully listening or already listening to an allowed skill.
      #
      # @param teacher [String, nil] the NPC teacher name
      # @param observe_flag [Boolean] whether to use the "observe" flag to listen without joining (default false)
      # @return [Boolean] true if now listening to an allowed skill, false if teacher not found, skill forbidden, or in combat
      # @example
      #   DRC.listen?('Mage Trainer') #=> true (if allowed for your class)
      #   DRC.listen?('invalid teacher') #=> false
      # @see #assess_teach
      def listen?(teacher, observe_flag = false)
        return false if teacher.nil?
        return false if teacher.empty?

        bad_classes = %w[Thievery Sorcery]
        bad_classes += ['Life Magic', 'Holy Magic', 'Lunar Magic', 'Elemental Magic', 'Arcane Magic', 'Targeted Magic', 'Arcana', 'Attunement'] if DRStats.barbarian? || DRStats.thief?
        bad_classes += ['Utility'] if DRStats.barbarian?

        observe = observe_flag ? 'observe' : ''

        result = bput("listen to #{teacher} #{observe}", 'begin to listen to \w+ teach the .* skill', 'already listening', 'could not find who', 'You have no idea', 'isn\'t teaching a class', 'don\'t have the appropriate training', 'Your teacher appears to have left', 'isn\'t teaching you anymore', 'experience differs too much from your own', 'but you don\'t see any harm in listening', 'invitation if you wish to join this class', 'You cannot concentrate to listen to .* while in combat')
        if (skill_match = result.match(/begin to listen to \w+ teach the (?<skill>.*) skill/))
          return true if bad_classes.grep(/#{skill_match[:skill]}/i).empty?

          bput('stop listening', 'You stop listening')
        elsif result == 'already listening'
          return true
        elsif result == "but you don't see any harm in listening"
          bput('stop listening', 'You stop listening')
        end

        false
      end

      # Runs an "assess teach" command and parses the output into a teacher=>skill hash.
      # Returns an empty hash if no one is teaching or if the character is teaching a class.
      # Waits for roundtime after completion.
      #
      # @return [Hash<String, String>] mapping of teacher names to skill names (e.g. {"Mage Trainer" => "Utility"})
      # @example
      #   DRC.assess_teach #=> {"Master Trainer" => "Magic"}
      # @see #parse_assess_teach_lines
      # @see #listen?
      def assess_teach
        lines = Lich::Util.issue_command(
          'assess teach',
          /is teaching a class|No one seems to be teaching|You are teaching a class/,
          /Roundtime/,
          usexml: false,
          quiet: true,
          include_end: false
        )
        waitrt?
        return {} if lines.nil?
        return {} if lines.any? { |l| l.match?(/No one seems to be teaching|You are teaching a class/) }

        parse_assess_teach_lines(lines.map(&:strip).reject(&:empty?))
      end

      # Pure parsing method for assess teach output (unit-testable)
      def parse_assess_teach_lines(lines)
        lines.each_with_object({}) do |line, hash|
          match = line.match(ASSESS_TEACH_TEACHER_PATTERN)
          next unless match

          teacher = match[:teacher]
          skill = match[:skill]
          skill_filter = skill.match(ASSESS_TEACH_SKILL_FILTER_PATTERN)
          skill = skill_filter[:filtered_skill] if skill_filter
          hash[teacher] = skill
        end
      end

      # Attempts to hide or stalk until the character is successfully hiding.
      # Recovers from common failures: stops playing music if too busy, stops stalking if
      # already stalking, waits if not enough time has passed. Returns final hiding status.
      #
      # @param hide_type [String] the hide command to use: 'hide' or 'stalk' (default 'hide')
      # @return [Boolean] true if now hiding, false if hiding failed
      # @example
      #   DRC.hide? #=> true (if successfully hidden)
      #   DRC.hide?('stalk') #=> true (if stalking)
      def hide?(hide_type = 'hide')
        unless hiding?
          case bput(hide_type, 'Roundtime', 'too busy performing', 'can\'t see any place to hide yourself', 'Stalk what', 'You\'re already stalking', 'Stalking is an inherently stealthy', 'You haven\'t had enough time', 'You search but find no place to hide')
          when 'too busy performing'
            bput('stop play', 'You stop playing', 'In the name of')
            return hide?(hide_type)
          when "You're already stalking"
            put 'stop stalk'
            return hide?(hide_type)
          when 'You haven\'t had enough time'
            pause 1
            return hide?(hide_type)
          end
          pause
          waitrt?
        end
        hiding?
      end

      # Simplifies multi-word item names by extracting just first and last words.
      # Removes " and chain" substring if present. Returns original string if fewer than 3 words.
      # Used internally to normalize item names from GameObj (which can contain verbose descriptions).
      #
      # @param string [String] the item name to simplify
      # @return [String] simplified name with first and last words, or original if too short
      # @example
      #   DRC.fix_dr_bullshit('a shiny broadsword of elanthia') #=> "a elanthia"
      #   DRC.fix_dr_bullshit('a ball and chain') #=> "a chain"
      # @api private
      def fix_dr_bullshit(string)
        return string if string.split.length <= 2

        string = string.sub(' and chain', '') if string =~ /ball and chain/

        match = string.match(/(?<first>\S+) .* (?<last>\S+)/)
        return string unless match

        "#{match[:first]} #{match[:last]}"
      end

      # Returns the cleaned-up name of the item in the left hand, or nil if empty.
      # Applies fix_dr_bullshit to normalize verbose descriptions from GameObj.
      #
      # @return [String, nil] the left-hand item name, or nil if hand is empty
      # @example
      #   DRC.left_hand #=> "sword" (or nil if hand is empty)
      # @see #right_hand
      # @see #left_hand_noun
      def left_hand
        GameObj.left_hand.name == 'Empty' ? nil : fix_dr_bullshit(GameObj.left_hand.name)
      end

      # Returns the cleaned-up name of the item in the right hand, or nil if empty.
      # Applies fix_dr_bullshit to normalize verbose descriptions from GameObj.
      #
      # @return [String, nil] the right-hand item name, or nil if hand is empty
      # @example
      #   DRC.right_hand #=> "sword" (or nil if hand is empty)
      # @see #left_hand
      # @see #right_hand_noun
      def right_hand
        GameObj.right_hand.name == 'Empty' ? nil : fix_dr_bullshit(GameObj.right_hand.name)
      end

      # Returns the noun (gettable name) of the item in the left hand, or nil if empty.
      # Returns the raw noun from GameObj without cleanup.
      #
      # @return [String, nil] the left-hand item noun, or nil if hand is empty
      # @example
      #   DRC.left_hand_noun #=> "sword"
      # @see #left_hand
      # @see #right_hand_noun
      def left_hand_noun
        GameObj.left_hand == 'Empty' ? nil : GameObj.left_hand.noun
      end

      # Returns the noun (gettable name) of the item in the right hand, or nil if empty.
      # Returns the raw noun from GameObj without cleanup.
      #
      # @return [String, nil] the right-hand item noun, or nil if hand is empty
      # @example
      #   DRC.right_hand_noun #=> "sword"
      # @see #right_hand
      # @see #left_hand_noun
      def right_hand_noun
        GameObj.right_hand == 'Empty' ? nil : GameObj.right_hand.noun
      end

      # Releases all active invisibility spells and khri abilities to become visible.
      # Queries spell data for spells with the invisibility flag, then releases each active one.
      # Also handles Khri Silence and Khri Vanish (thief-only) if active.
      #
      # @return [void]
      # @example
      #   DRC.release_invisibility  # ends Invisibility, Khri Silence, Khri Vanish
      # @see DRSpells.active_spells
      def release_invisibility
        get_data('spells')
          .spell_data
          .select { |_name, properties| properties['invisibility'] }
          .select { |name, _properties| DRSpells.active_spells.keys.include?(name) }
          .map { |_name, properties| properties['abbrev'] }
          .each { |abbrev| fput("release #{abbrev}") }

        # handle khri silence as it's not part of base-spells data, and method of ending it differs from spells
        bput('khri stop silence', 'You attempt to relax') if DRSpells.active_spells.keys.include?('Khri Silence')
        bput('khri stop vanish', /^You would need to start Vanish/, /^Your control over the limited subversion of reality falters/, /^You are not trained in the Vanish meditation/) if (DRStats.guild == "Thief" && invisible?)
      end

      # Returns the character's encumbrance level as a numeric constant or string.
      # Optionally queries the game with an "encumbrance" command to refresh the status
      # before looking it up in the encumbrance map.
      #
      # @param refresh [Boolean] whether to issue an encumbrance command first (default true)
      # @return [Integer, String] the mapped encumbrance value from $ENC_MAP
      # @example
      #   DRC.check_encumbrance #=> 5 (if refreshed and heavily encumbered)
      #   DRC.check_encumbrance(false) #=> 3 (uses cached DRStats.encumbrance)
      # @see DRStats.encumbrance
      def check_encumbrance(refresh = true)
        encumbrance = DRStats.encumbrance
        if refresh
          encumbrance_pattern = /(?:Encumbrance)\s:\s(?<encumbrance>.*)/
          result = bput('encumbrance', encumbrance_pattern)
          enc_match = result.match(encumbrance_pattern)
          encumbrance = enc_match[:encumbrance] if enc_match
        end
        $ENC_MAP[encumbrance]
      end

      # Attempts to retreat from combat, ignoring a list of NPCs (summoned allies or unavoidable enemies).
      # Returns early if no hostile NPCs are present after filtering. Loops until retreat succeeds or
      # the room becomes safe, fixing standing if needed between attempts.
      #
      # @param ignored_npcs [Array<String>] NPC names to ignore (e.g. summoned creatures)
      # @return [Boolean, void] true if successfully retreated, nil if no combat
      # @example
      #   DRC.retreat #=> true (if in combat and retreat succeeds)
      #   DRC.retreat(['summoned_mage']) #=> true (ignores the summoned ally)
      # @see RETREAT_ESCAPE_MESSAGES
      # @see RETREAT_MESSAGES
      def retreat(ignored_npcs = [])
        return if (DRRoom.npcs - ignored_npcs).empty?

        loop do
          case DRC.bput("retreat", *RETREAT_ESCAPE_MESSAGES, *RETREAT_MESSAGES)
          when *RETREAT_ESCAPE_MESSAGES
            return true
          else
            DRC.fix_standing
          end
        end
      end

      # Converts English text numbers (e.g. "forty-two") to integers using a global $NUM_MAP.
      # Handles multipliers like "hundred" and "thousand". Returns nil if an unknown number word is found.
      #
      # @param text_num [String] the text number, e.g. "one hundred twenty-three"
      # @return [Integer, nil] the numeric value, or nil if an unknown word is encountered
      # @example
      #   DRC.text2num('forty-two') #=> 42
      #   DRC.text2num('one hundred') #=> 100
      #   DRC.text2num('unknownword') #=> nil (logs error, returns nil)
      def text2num(text_num)
        text_num = text_num.tr('-', ' ')
        split_words = text_num.split(' ')
        g = 0

        split_words.each do |word|
          x = $NUM_MAP.fetch(word, nil)
          if word.eql?('hundred') && (g != 0)
            g *= 100
          elsif word.eql?('thousand') && (g != 0)
            g *= 1000
          elsif x.nil?
            Lich::Messaging.msg("bold", "DRC: Unknown number word '#{word}' in '#{text_num}'")
            return nil
          else
            g += x
          end
        end

        g
      end

      # Plays a song from a list, cycling to the next song if the current one fails.
      # Tracks the current song and climbing song separately in UserVars. Resets tracking
      # when instrument changes. Handles common failures: missing/wrong instrument, out-of-tune,
      # dirty instrument (cleans if Performance rank < 20), stunned, playing already, etc.
      # Returns false if playing fails due to environment (in water, not the right time).
      #
      # @param settings [OpenStruct] outfit settings with worn_instrument, instrument, cleaning_cloth keys
      # @param song_list [Array, Hash] list/hash of songs to cycle through
      # @param worn [Boolean] whether instrument is worn (remove/wear) vs in inventory (get/stow) (default true)
      # @param skip_clean [Boolean] whether to skip cleaning the instrument (default false)
      # @param climbing [Boolean] whether to use climbing_song tracking instead of song (default false)
      # @param skip_tuning [Boolean] whether to skip tuning if out of tune (default false)
      # @return [Boolean] true if song was played or is already playing, false if environment prevents playing
      # @example
      #   settings = OpenStruct.new(worn_instrument: 'lute', cleaning_cloth: 'chamois')
      #   DRC.play_song?(settings, ['ballad', 'march', 'waltz'])
      #   # => true if any song plays successfully
      # @see #stop_playing
      # @see #clean_instrument
      # @see #tune_instrument
      def play_song?(settings, song_list, worn = true, skip_clean = false, climbing = false, skip_tuning = false)
        instrument = worn ? settings.worn_instrument : settings.instrument

        if UserVars.instrument.nil?
          Lich::Messaging.msg("plain", "DRC: No previous instrument setting detected. Cleaning stored song data.")
          UserVars.song = nil
          UserVars.climbing_song = nil
          UserVars.instrument = instrument
        elsif UserVars.instrument != instrument
          Lich::Messaging.msg("plain", "DRC: New instrument #{instrument} detected; old instrument: #{UserVars.instrument}. Resetting stored song data.")
          UserVars.song = nil
          UserVars.climbing_song = nil
          UserVars.instrument = instrument
        end
        UserVars.song = song_list.first.first unless UserVars.song
        UserVars.climbing_song = song_list.first.first unless UserVars.climbing_song
        song_to_play = climbing ? UserVars.climbing_song : UserVars.song
        play_command = "play #{song_to_play}"
        if instrument
          play_command = play_command + " on my #{instrument}"
        end
        fput('release ecry') if DRSpells.active_spells["Eillie's Cry"].to_i > 0
        result = bput(play_command, 'too damaged to play', 'dirtiness may affect your performance', 'slightest hint of difficulty', 'fumble slightly', /Your .+ is submerged in the water/, 'You begin a', 'You struggle to begin', 'You\'re already playing a song', 'You effortlessly begin', 'You begin some', 'You cannot play', 'Play on what instrument', 'Are you sure that\'s the right instrument', 'now isn\'t the best time to be playing', 'Perhaps you should find somewhere drier before trying to play', 'You should stop practicing', /^You really need to drain/, /Your .* tuning is off, and may hinder your performance/)
        case result
        when 'Play on what instrument', 'Are you sure that\'s the right instrument'
          unless DRCI.get_item?(instrument)
            Lich::Messaging.msg("bold", "DRC: Failed to get #{instrument}.")
            return false
          end
          if worn && !DRCI.wear_item?(instrument)
            Lich::Messaging.msg("bold", "DRC: Failed to wear #{instrument}.")
            return false
          end
          play_song?(settings, song_list, worn, skip_clean, climbing, skip_tuning)
        when 'now isn\'t the best time to be playing', 'Perhaps you should find somewhere drier before trying to play', 'You should stop practicing'
          false
        when 'You\'re already playing a song'
          fput('stop play')
          play_song?(settings, song_list, worn, skip_clean, climbing, skip_tuning)
        when 'You cannot play'
          wait_for_script_to_complete('safe-room')
        when /Your .* tuning is off, and may hinder your performance/
          Lich::Messaging.msg("bold", "DRC: Instrument out of tune. Attempting to tune it.")
          return true if DRSkill.getrank('Performance') < 20
          return true if skip_tuning
          return true unless DRC.tune_instrument(settings)

          play_song?(settings, song_list, worn, skip_clean, climbing, skip_tuning)
        when 'dirtiness may affect your performance', /^You really need to drain/
          return true if DRSkill.getrank('Performance') < 20
          return true if skip_clean
          return true unless clean_instrument(settings, worn)

          play_song?(settings, song_list, worn, skip_clean, climbing, skip_tuning)
        when 'slightest hint of difficulty', 'fumble slightly'
          true
        when 'You begin a', 'You effortlessly begin', 'You begin some'
          return true if song_to_play == song_list.to_a.last.last
          # Ignore difficulty messages if we have an offset
          return true if climbing && UserVars.climbing_song_offset

          stop_playing
          UserVars.climbing_song = song_list[UserVars.climbing_song] || song_list.first.first if climbing
          UserVars.song = song_list[UserVars.song] || song_list.first.first unless climbing
          play_song?(settings, song_list, worn, skip_clean, climbing, skip_tuning)
        when 'You struggle to begin'
          return true if song_to_play == song_list.first.first
          # Ignore difficulty messages if we have an offset
          return true if climbing && UserVars.climbing_song_offset

          stop_playing
          UserVars.climbing_song = song_list.first.first if climbing
          UserVars.song = song_list.first.first unless climbing
          play_song?(settings, song_list, worn, skip_clean, climbing, skip_tuning)
        else
          false
        end
      end

      # Stops playing the current song by issuing the "stop play" command.
      # Waits for roundtime after stopping.
      #
      # @return [void]
      # @example
      #   DRC.stop_playing
      # @see #play_song?
      def stop_playing
        bput('stop play', 'You stop playing your song', 'In the name of', "But you're not performing")
      end

      # Cleans and dries an instrument using a cleaning cloth (chamois).
      # Removes the instrument if worn, gets it if not. Wipes and wrings the cloth until dry,
      # then cleans the instrument until it needs no more cleaning. Re-wears if originally worn.
      # Returns false if hands are not empty, cloth/instrument cannot be retrieved, or standing is needed.
      #
      # @param settings [OpenStruct] outfit settings with cleaning_cloth and worn_instrument/instrument keys
      # @param worn [Boolean] whether the instrument is worn (vs in inventory) (default true)
      # @return [Boolean] true if successfully cleaned, false if preconditions fail
      # @example
      #   settings = OpenStruct.new(cleaning_cloth: 'chamois', worn_instrument: 'lute')
      #   DRC.clean_instrument(settings) #=> true (if cleaned successfully)
      # @see #tune_instrument
      # @see #play_song?
      def clean_instrument(settings, worn = true)
        cloth = settings.cleaning_cloth
        instrument = worn ? settings.worn_instrument : settings.instrument

        unless DRCI.get_item?(cloth)
          Lich::Messaging.msg("bold", "DRC: You have no chamois cloth -- this could cause problems with playing an instrument!")
          DRC.beep
          return false
        end
        DRC.stop_playing

        if worn
          unless DRCI.remove_item?(instrument)
            Lich::Messaging.msg("bold", "DRC: Could not remove #{instrument}, putting away cloth, and not trying to clean.")
            DRCI.stow_item?(cloth)
            DRC.beep
            return false
          end
        else
          unless DRCI.get_item?(instrument)
            Lich::Messaging.msg("bold", "DRC: Could not get #{instrument}, putting away cloth, and not trying to clean.")
            DRCI.stow_item?(cloth)
            DRC.beep
            return false
          end
        end

        loop do
          case DRC.bput("wipe my #{instrument} with my #{cloth}", 'Roundtime', 'not in need of drying', 'You should be sitting up')
          when 'not in need of drying'
            break
          when 'You should be sitting up'
            DRC.fix_standing
            next
          end
          pause 1
          waitrt?

          until /you wring a dry/i =~ DRC.bput("wring my #{cloth}", 'You wring a dry', 'You wring out')
            pause 1
            waitrt?
          end
        end

        until /not in need of cleaning/i =~ DRC.bput("clean my #{instrument} with my #{cloth}", 'Roundtime', 'not in need of cleaning')
          pause 1
          waitrt?
        end

        DRCI.wear_item?(instrument) if worn
        DRCI.stow_item?(cloth)
        true
      end

      # Tunes an instrument to correct pitch, removing/getting it as needed.
      # Requires two free hands. Handles worn vs inventory instruments. Calls do_tune recursively
      # to adjust sharp/flat. Re-wears the instrument after tuning if it was originally worn.
      # Returns false if no instrument is configured, hands are full, or instrument cannot be retrieved.
      #
      # @param settings [OpenStruct] outfit settings with worn_instrument and/or instrument keys
      # @return [Boolean] true if successfully tuned, false if preconditions fail
      # @example
      #   settings = OpenStruct.new(worn_instrument: 'lute')
      #   DRC.tune_instrument(settings) #=> true (if tuned successfully)
      # @see #do_tune
      # @see #clean_instrument
      # @see #play_song?
      def tune_instrument(settings)
        instrument = settings.worn_instrument || settings.instrument

        unless instrument
          Lich::Messaging.msg("bold", "DRC: Neither worn_instrument nor instrument set. Doing nothing.")
          return false
        end

        DRC.stop_playing

        unless (DRC.left_hand.nil? && DRC.right_hand.nil?) || DRCI.in_hands?(instrument)
          Lich::Messaging.msg("bold", "DRC: Need two free hands. Not tuning now.")
          return false
        end

        if settings.worn_instrument
          unless DRCI.remove_item?(instrument) || DRCI.in_hands?(instrument)
            Lich::Messaging.msg("bold", "DRC: Could not remove #{instrument}. Not trying to tune.")
            DRC.beep
            return false
          end
        else
          unless DRCI.get_item?(instrument) || DRCI.in_hands?(instrument)
            Lich::Messaging.msg("bold", "DRC: Could not get #{instrument}. Not trying to tune.")
            DRC.beep
            return false
          end
        end
        DRC.do_tune(instrument)
        waitrt?
        pause 1
        DRCI.wear_item?(instrument) if settings.worn_instrument
        true
      end

      # Recursively tunes an instrument, adjusting for sharp/flat responses.
      # Issues a "tune my <instrument>" command, then recursively adjusts with "sharp" or "flat"
      # if needed. Fixes standing if required. Returns false if the instrument is not in hands.
      #
      # @param instrument [String] the instrument noun
      # @param tuning [String] tuning directive to append ("sharp", "flat", or empty for initial attempt) (default "")
      # @return [Boolean] true if tuned successfully, false if instrument not in hands
      # @example
      #   DRC.do_tune('lute') #=> true (if tuned)
      # @see #tune_instrument
      def do_tune(instrument, tuning = "")
        unless instrument && DRCI.in_hands?(instrument)
          Lich::Messaging.msg("bold", "DRC: No instrument found in hands. Not trying to tune.")
          DRC.beep
          return false
        end

        case DRC.bput("tune my #{instrument} #{tuning}",
                      /^You should be sitting up/,
                      /After a moment, you .* flat/,
                      /After a moment, you .* sharp/,
                      /After a moment, you .* tune/)
        when /After a moment, you .* tune/
          Lich::Messaging.msg("plain", "DRC: Instrument tuned.")
          return true
        when /After a moment, you .* flat/
          DRC.do_tune(instrument, "sharp")
        when /After a moment, you .* sharp/
          DRC.do_tune(instrument, "flat")
        when /^You should be sitting up/
          DRC.fix_standing
          DRC.do_tune(instrument)
        end
      end

      # Pauses all running scripts except the current one, using a global lock.
      # Scripts already paused before this call are marked and not unpaused by unpause_all.
      # Returns false if the lock cannot be acquired. Pauses for 1 second after pausing scripts.
      #
      # @return [Boolean] true if successfully acquired lock and paused scripts, false if lock already held
      # @example
      #   DRC.pause_all #=> true (if paused; false if already held)
      # @see #unpause_all
      # @see #smart_pause_all
      # @see #safe_pause_list
      # @api private
      def pause_all
        return false unless $pause_all_lock.try_lock

        @pause_all_no_unpause = []

        Script.running.find_all(&:paused?).each do |script|
          @pause_all_no_unpause << script
        end

        Script.running.find_all do |script|
          !script.paused? &&
            !script.no_pause_all &&
            script != Script.current
        end
              .each(&:pause)

        pause 1
        true
      end

      # Unpauses scripts that were paused by pause_all, but not those that were already paused.
      # Clears the tracking list and releases the global lock.
      # Returns false if the lock is not held by the current script.
      #
      # @return [Boolean] true if successfully unpaused and released lock, false if lock not held
      # @example
      #   DRC.pause_all
      #   # ... do work ...
      #   DRC.unpause_all #=> true
      # @see #pause_all
      # @see #smart_pause_all
      # @see #safe_unpause_list
      # @api private
      def unpause_all
        return false unless $pause_all_lock.owned?

        Script.running.find_all do |script|
          script.paused? &&
            !@pause_all_no_unpause.include?(script)
        end
              .each(&:unpause)

        @pause_all_no_unpause = []
        $pause_all_lock.unlock

        true
      end

      # Pauses all running scripts except the current one and logs which were paused.
      # Unlike pause_all, does not use a global lock and does not restore paused state.
      # Returns an array of paused script names for later restoration.
      #
      # @return [Array<String>] names of scripts that were paused
      # @example
      #   paused = DRC.smart_pause_all
      #   # => ["hunt", "loot"]
      #   # ... do exclusive work ...
      #   DRC.unpause_all_list(paused)
      # @see #unpause_all_list
      def smart_pause_all
        paused_script_list = []
        Script.running.find_all { |s| !s.paused? && !s.no_pause_all && s.name != Script.self.name }.each do |s|
          s.pause
          paused_script_list << s.name
        end
        Lich::Messaging.msg("plain", "DRC: Pausing #{paused_script_list} to run #{Script.self.name}")
        return paused_script_list
      end

      # Unpauses a specific list of scripts by name, logging the completion.
      # Returns silently if the list is empty.
      #
      # @param scripts_to_unpause [Array<String>] names of scripts to unpause
      # @return [void]
      # @example
      #   paused = DRC.smart_pause_all
      #   # ... do work ...
      #   DRC.unpause_all_list(paused)
      # @see #smart_pause_all
      def unpause_all_list(scripts_to_unpause)
        if scripts_to_unpause.empty?
          Lich::Messaging.msg("plain", "DRC: #{Script.self.name} has finished.")
        else
          Lich::Messaging.msg("plain", "DRC: Unpausing #{scripts_to_unpause}, #{Script.self.name} has finished.")
          Script.running.find_all { |s| s.paused? && !s.no_pause_all && scripts_to_unpause.include?(s.name) }.each(&:unpause)
        end
      end

      # Pauses all running scripts except the current one using a global lock.
      # Makes the lock holder immune to pause while it holds the lock, preventing deadlock
      # from pause_script while holding the lock. Returns the actual paused Script objects
      # (not names) for use with safe_unpause_list, ensuring exact restoration even if scripts
      # have come and gone from Script.running.
      # Returns false if the lock cannot be acquired.
      #
      # @return [Array<OpenStruct>, Boolean] array of paused Script objects, or false if lock already held
      # @example
      #   paused = DRC.safe_pause_list
      #   # => [<Script name='hunt'>, <Script name='loot'>]
      #   # ... do exclusive work ...
      #   DRC.safe_unpause_list(paused)
      # @see #safe_unpause_list
      # @api private
      def safe_pause_list
        return false unless $safe_pause_lock.try_lock

        # Pausing is cooperative: a paused script is a live thread that keeps
        # every mutex it holds (Ruby frees a mutex on thread death, not on
        # pause). So a script that gets pause_script'd while holding
        # $safe_pause_lock never releases it, and every peer spins forever on
        # try_lock -> false. Make the lock-holder immune to pause for as long as
        # it owns the lock, so this deadlock cannot form. Save the prior value
        # (and the holder itself) so we restore exactly what was there for a
        # caller that was already ignoring pauses, e.g. mid-travel.
        @safe_pause_holder = Script.self
        @safe_pause_prev_ignore_pause = @safe_pause_holder&.ignore_pause
        @safe_pause_holder&.ignore_pause = true

        # Capture the exact Script objects we pause -- not their names. The
        # matching safe_unpause_list restores from this list directly instead of
        # re-scanning Script.running by name. A name + live-rescan restore
        # silently drops any script that has left Script.running between pause
        # and unpause (gone hidden, or mid start/teardown) or whose pause flags
        # changed, stranding it paused forever while the log still claims it was
        # unpaused. Holding the objects makes the restore undo exactly what the
        # pause did.
        paused_scripts = []
        Script.running.find_all { |s| !s.paused? && !s.no_pause_all && s.name != Script.self.name }.each do |s|
          s.pause
          paused_scripts << s
        end
        Lich::Messaging.msg("plain", "DRC: Pausing #{paused_scripts.map(&:name)} to run #{Script.self.name}")
        return paused_scripts
      end

      # Unpauses Script objects that were paused by safe_pause_list, restores the lock holder's
      # previous pause immunity state, and releases the global lock.
      # Skips any scripts already unpaused by a peer to avoid spurious noise.
      # Returns false if the lock is not held.
      #
      # @param paused_scripts [Array<OpenStruct>] Script objects returned from safe_pause_list
      # @return [Boolean] true if successfully unpaused and lock released, false if lock not held
      # @example
      #   paused = DRC.safe_pause_list
      #   # ... do exclusive work ...
      #   DRC.safe_unpause_list(paused) #=> true
      # @see #safe_pause_list
      # @api private
      def safe_unpause_list(paused_scripts)
        return false unless $safe_pause_lock.owned?

        if paused_scripts.empty?
          Lich::Messaging.msg("plain", "DRC: #{Script.self.name} has finished.")
        else
          Lich::Messaging.msg("plain", "DRC: Unpausing #{paused_scripts.map(&:name)}, #{Script.self.name} has finished.")
          # Unpause exactly the objects we paused, regardless of their current
          # Script.running visibility or flags. Skip any a peer already unpaused
          # so we neither emit spurious "is not paused" noise nor fight another
          # coordinator that has since taken ownership of the pause.
          paused_scripts.each { |s| s.unpause if s.paused? }
        end
        # Restore the holder's pre-lock pause immunity before releasing the lock,
        # so we never leave a script permanently unpausable.
        @safe_pause_holder&.ignore_pause = @safe_pause_prev_ignore_pause
        @safe_pause_holder = nil
        @safe_pause_prev_ignore_pause = nil
        $safe_pause_lock.unlock
      end

      # Sets the character's defensive stance based on a skill name and computed defending ranks.
      # Stance distribution depends on guild: Paladins use 50x divisor, Barbarians/Rangers/Traders/Commoners use 60x,
      # others use 70x. Excess points beyond 100 are distributed to secondary/tertiary.
      #
      # @param skill [String] the skill name: 'evasion', 'parry', or 'shield' (case-insensitive)
      # @return [void]
      # @example
      #   DRC.set_stance('evasion') #=> issues "stance set 100 X Y"
      #   DRC.set_stance('parry')   #=> issues "stance set X 100 Y"
      # @see DRStats.guild
      # @see DRSkill.getrank
      def set_stance(skill)
        div = if DRStats.guild == 'Paladin'
                50
              elsif %w[Barbarian Ranger Trader Commoner].include?(DRStats.guild)
                60
              else
                70
              end

        points = 80 + DRSkill.getrank('Defending') / div
        secondary = points > 100 ? 100 : points
        tertiary = points > 100 ? points - 100 : 0

        stance = case skill.downcase
                 when 'evasion'
                   "100 #{secondary} #{tertiary}"
                 when 'parry'
                   "#{secondary} 100 #{tertiary}"
                 when 'shield'
                   "#{secondary} #{tertiary} 100"
                 else
                   "100 #{secondary} #{tertiary}"
                 end

        DRC.bput("stance set #{stance}", /Setting your/)
      end

      # Sends a message to the atmospherics window.
      # By default the message is bold.
      # DEPRECATED in favor of log_window
      def atmo(text, make_bold = true)
        log_window(text, "atmospherics", make_bold)
      end

      # Sends a message to the specified window. Replaces the deprecated atmo method.
      # By default the message is bold. Creates window upon request. Pre-clears window upon request.
      def log_window(text, window_name, make_bold = true, create_window = false, pre_clear_window = false)
        if create_window
          _respond("<streamWindow id=\"#{window_name}\" title=\"#{window_name}\" location=\"center\" save=\"true\" />")
          _respond("<exposeStream id=\"#{window_name}\"/>")
        end

        if pre_clear_window
          _respond("<clearStream id=\"#{window_name}\"/>\r\n")
        end

        _respond(
          "<pushStream id=\"#{window_name}\"/>" + (make_bold ? bold(text) : text),
          "<popStream id=\"#{window_name}\" /><prompt time=\"#{XMLData.server_time.to_i}\">&gt;</prompt>"
        )
      end

      # Helper function to wrap text in the necessary markup
      # to make it render as bold in a frontend client.
      # Used by `atmo` and `log_window` methods.
      def bold(text)
        prefix = Frontend.supports_gsl? ? "\034GSL\r\n " : "<pushBold\/>"
        suffix = Frontend.supports_gsl? ? "\034GSM\r\n " : "<popBold\/>"
        "#{prefix}#{text}#{suffix}"
      end

      # Sends a message to the game window.
      # By default the message is bold.
      # Delegates to Lich::Messaging.msg for consistent multi-frontend support.
      def message(text, make_bold = true)
        Lich::Messaging.msg(make_bold ? "bold" : "plain", text, encode: false)
      end
    end
  end
end
