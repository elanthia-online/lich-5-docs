# Namespace for the Lich 5 scripting engine.
module Lich
  # Namespace for GemStone IV and DragonRealms functionality.
  module Gemstone
    # Namespace for bounty task parsing and related utilities.
    class Bounty
      # Parses bounty task descriptions from GemStone IV/DragonRealms game server
      # output and extracts structured task data.
      #
      # Matches task descriptions against a set of regex patterns to determine the
      # task type and extract named captures like creature type, town, item name,
      # and numeric requirements. Handles special cases like creature name
      # normalization and town name ambiguity resolution.
      class Parser
        # Matches the opening phrase "Hmm, I've got a task here from <town>." in
        # assignment messages, with optional town name capture.
        #
        # @return [Regexp] pattern with named capture group 'town'
        # @example
        #   "Hmm, I've got a task here from Wehnimer's Landing." #=> matches with town="Wehnimer's Landing"
        # @see TASK_MATCHERS
        HMM_REGEX = /(?:Hmm, I've got a task here from .*?(?<town>[A-Z].*?)\..*?)?/
        # Matches location phrases like "near the Lich Gate" or "in the Graveyard",
        # with named captures for the area and optional nearby town.
        #
        # @return [Regexp] pattern with named capture groups 'area' and 'town'
        # @example
        #   "on the field near Wehnimer's Landing" #=> matches with area="field", town="Wehnimer's Landing"
        # @see TASK_MATCHERS
        LOCATION_REGEX = /(?:on|in|near) (?:the\s+)?(?<area>[^.]+?)(?:\s+(?:near|between|under) (?<town>[^.]+))?/
        # Matches various NPC guard and guard-like encounter descriptions, including
        # city gate guards, militia, sentries, ship pursers, and tavern keepers.
        #
        # @return [Regexp] union of patterns, some with named capture group 'town'
        # @example
        #   "one of the guardsmen just inside the Ta'Illistim City Gate" #=> matches with town="Ta'Illistim"
        #   "the sentry just outside Kraken's Fall" #=> matches with town="Kraken's Fall"
        # @see TASK_MATCHERS
        GUARD_REGEX = Regexp.union(
          /one of the guardsmen just inside the (?<town>Ta'Illistim) City Gate/,
          /one of the guardsmen just inside the Sapphire Gate/,
          /one of the guardsmen just inside the gate/,
          /one of the (?<town>.*) (?:gate|tunnel) guards/,
          /one of the (?<town>Icemule Trace) gate guards or the halfing Belle at the Pinefar Trading Post/,
          /Quin Telaren of (?<town>Wehnimer's Landing)/,
          /the dwarven militia sergeant near the (?<town>Kharam-Dzu) town gates/,
          /the sentry just outside town/,
          /the sentry just outside (?<town>Kraken's Fall)/,
          /the purser of (?<town>River's Rest)/,
          /the tavernkeeper at Rawknuckle's Common House/,
          /the captain of the (?<town>Contempt)/,
          /the elderly guard in the East Guardtower/
        )
        # Matches herb task descriptions where an NPC requires pristine herb samples
        # from a specific area, with captures for herb type, area, and quantity.
        #
        # @return [Regexp] pattern with named capture groups 'herb', 'area', and 'number'
        # @example
        #   "is working on a concoction that requires some eonake found in the Dragonspine. These samples must be in pristine condition. You have been tasked to retrieve 3 samples." #=> matches with herb="eonake", area="Dragonspine", number="3"
        # @see TASK_MATCHERS
        CONCOCTION_REGEX = /is working on a concoction that requires (?:an?|some|several) (?<herb>[^.]+?) found [oi]n (?:the\s+)?(?<area>[^.]+?)(?:\s+(?:near|under|between) [^.]+)?\.  These samples must be in pristine condition\.  You have been tasked to retrieve (?<number>\d+) (?:more\s+)?samples?\./
        # Matches the taskmaster direct-speech opening phrase for task assignment
        # messages.
        #
        # @return [Regexp] pattern for taskmaster quote prefix
        # @example
        #   "The taskmaster told you: \"I've got a mission for you.\"" #=> matches
        # @see TASK_MATCHERS
        TASK_MAYBE_REGEX = /^(?:The taskmaster told you:  ")/

        # Hash mapping task type symbols to regex patterns that identify and capture
        # details for each task type.
        #
        # Task types include: :none, :bandit_assignment, :creature_assignment,
        # :gem_assignment, :heirloom_assignment, :herb_assignment, :rescue_assignment,
        # :skin_assignment, :taskmaster, :heirloom_found, :guard, :dangerous_spawned,
        # :rescue_spawned, :bandit, :dangerous, :escort, :gem, :heirloom, :herb,
        # :rescue, :skin, :cull, and :failed.
        #
        # @return [Hash{Symbol => Regexp}] mapping of task types to their patterns
        # @see #parse
        TASK_MATCHERS = {
          :none                => /^You are not currently assigned a task/,
          :bandit_assignment   => /#{HMM_REGEX}It appears they have a bandit problem they'd like you to solve/,
          :creature_assignment => Regexp.union(
            /#{HMM_REGEX}It appears they have a creature problem they'd like you to solve/,
            /#{TASK_MAYBE_REGEX}I've got an urgent mission for you.  We have a creature problem we'd like you to solve.  Go report to the (?<town>[A-Z].*?) to find out/,
            /#{TASK_MAYBE_REGEX}I've a favor to ask of you.  We have a creature problem we'd like you to solve: you know, by killing.  Go report to the (?<town>[A-Z].*?)/
          ),
          :gem_assignment      => Regexp.union(
            /#{HMM_REGEX}The local gem dealer, (?<npc_name>[^,]+), has an order to fill and wants our help/,
            /All right.  I've a mission for you.  Our guest, the trader (?<npc_name>[^,]+)/,
          ),
          :heirloom_assignment => Regexp.union(
            /#{HMM_REGEX}It appears they need your help in tracking down some kind of lost heirloom/,
            /#{TASK_MAYBE_REGEX}?It's time for you to earn your keep around here.  I'd like you track down a lost heirloom./
          ),
          :herb_assignment     => Regexp.union(
            /#{HMM_REGEX}The local [^,]+?, (?<npc_name>[^,]+), has asked for our aid.  Head over there and see what you can do.  Be sure to ASK about BOUNTIES./,
            /#{TASK_MAYBE_REGEX}I've got a mission for you.  Our [^,]+?, (?<npc_name>[^,]+), has asked for our aid.  Head over there and see what you can do./
          ),
          :rescue_assignment   => /#{HMM_REGEX}It appears that a local resident urgently needs our help in some matter/,
          :skin_assignment     => Regexp.union(
            /#{HMM_REGEX}The local furrier (?<npc_name>.+) has an order to fill and wants our help/,
            /#{TASK_MAYBE_REGEX}?You look like you need work.  The flesh merchant (?<npc_name>.+), down in the hold, has an order to fill and wants our help./
          ),
          :taskmaster          => /^You have succeeded in your task and can return to the Adventurer's Guild/,
          :heirloom_found      => /^You have located (?:an?|some) (?<item>.+) and should bring (it back|your find) to #{GUARD_REGEX}\.$/,
          :guard               => /^You succeeded in your task and should report back to #{GUARD_REGEX}\.$/,
          :dangerous_spawned   => /^You have been tasked to hunt down and kill a particularly dangerous (?<creature>[^.]+) that has established a territory #{LOCATION_REGEX}\.  You have provoked (?:his|her|its) attention and now you must(?: return to where you left (?:him|her|it) and)? kill (?:him|her|it)!$/,
          :rescue_spawned      => /^You have made contact with the child you are to rescue and you must get (?:him|her) back alive to #{GUARD_REGEX}\.$/,
          :bandit              => /^You have been tasked to(?: help (?<assist>\w+))? suppress (?<creature>bandit) activity #{LOCATION_REGEX}\.  You need to kill (?<number>\d+) (?:more\s+)?of them to complete your task\.$/,
          :dangerous           => /^You have been tasked to hunt down and kill a (?:particularly )?dangerous (?<creature>[^.]+) that has established a territory #{LOCATION_REGEX}\.  You can get its attention by killing other creatures of the same type in its territory\.$/,
          :escort              => /#{TASK_MAYBE_REGEX}?I've got a special mission for you\.  A certain client has hired us to provide a protective escort on (?:his|her) upcoming journey\.  Go to (?<start>[^.]+) and WAIT for (?:him|her) to meet you there\.  You must guarantee (?:his|her) safety to (?<destination>[^.]+) as soon as you can, being ready for any dangers that the two of you may face\.  Good luck!"?$/,
          :gem                 => Regexp.union(
            /^The gem dealer in (?<town>[^,]+), (?<npc_name>[^,]+), has received orders from multiple customers requesting (?:an?|some) (?<gem>[^.]+)\.  You have been tasked to retrieve (?<number>\d+) (?:more\s+)?of them\.  You can SELL them to the gem dealer as you find them\.$/,
            /^The gem dealer in has received orders from multiple customers requesting (?:an?|some) (?<gem>[^.]+)\.  You have been tasked to retrieve (?<number>\d+) (?:more\s+)?of them\.  You can SELL them to the gem dealer as you find them\.$/
          ),
          :heirloom            => /^You have been tasked to recover (?:an?|some) (?<item>[^.]+) that an unfortunate citizen lost after being attacked by an? (?<creature>[^.]+?) #{LOCATION_REGEX}\.  The heirloom can be identified by the initials \w+ engraved upon it\.  [^.]*?(?<action>LOOT|SEARCH)[^.]+\.$/,
          :herb                => Regexp.union(
            /^The .+? in (?<town>[^,]+?), (?<npc_name>[^,]+), #{CONCOCTION_REGEX}$/,
            /^The .+, (?<npc_name>[^,]+), aboard the (?<town>\w+?) in .*? #{CONCOCTION_REGEX}$/
          ),
          :rescue              => /^You have been tasked to rescue the young (?:runaway|kidnapped) (?:son|daughter) of a local citizen\.  A local divinist has had visions of the child fleeing from an? (?<creature>[^.]+?) #{LOCATION_REGEX}\.  Find the area where the child was last seen and clear out the creatures that have been tormenting (?:him|her) in order to bring (?:him|her) out of hiding\.$/,
          :skin                => /^You have been tasked to retrieve (?<number>\d+) (?<skin>[^.]+?)s? of at least (?<quality>[^.]+) quality for (?<npc_name>.+) in (?<town>[^.]+?)\.  You can SKIN them off the corpse of an? (?<creature>[^.]+) or purchase them from another adventurer\.  You can SELL the skins to the furrier as you collect them\."?$/,
          :cull                => Regexp.union(
            /^You have been tasked to(?: help (?<assist>\w+))? suppress (?<creature>[^.]+) activity #{LOCATION_REGEX}\.  You need to kill (?<number>\d+) (?:more\s+)?of them to complete your task\.$/,
            /^You have been tasked to help (?<assist>\w+) rescue a missing child by suppressing (?<creature>[^.]+) activity #{LOCATION_REGEX} during the rescue attempt\.  You need to kill (?<number>\d+) (?:more\s+)?of them to complete your task\.$/,
            /^You have been tasked to help (?<assist>\w+) retrieve an heirloom by suppressing (?<creature>[^.]+) activity #{LOCATION_REGEX} during the retrieval effort\.  You need to kill (?<number>\d+) (?:more\s+)?of them to complete your task\.$/,
            /^You have been tasked to help (?<assist>\w+) kill a dangerous creature by suppressing (?<creature>[^.]+) activity #{LOCATION_REGEX} during the hunt\.  You need to kill (?<number>\d+) (?:more\s+)?of them to complete your task\.$/,
          ),
          :failed              => Regexp.union(
            /^You have failed in your task/,
            /^The child you were tasked to rescue is gone and your task is failed.  Report this failure to the Adventurer's Guild./,
          ),
        }

        # Initializes a new Parser with a bounty task description.
        #
        # @param description [String] the raw bounty task description from the game
        # @return [void]
        def initialize(description)
          @description = description
        end

        attr_reader :description

        # Parses the task description and returns structured task data.
        #
        # Iterates through TASK_MATCHERS in order to find the first matching regex,
        # then extracts named captures and processes them into a task details hash.
        #
        # @return [Hash{Symbol => Object}, nil] hash with keys :type and :requirements
        #   (plus optional task-specific captures), or nil if no pattern matches
        # @example
        #   description = "You have been tasked to retrieve 5 samples of eonake found in the Dragonspine."
        #   parser = Parser.new(description)
        #   parser.parse #=> {:type=>:herb, :town=>"Ayan", :requirements=>{...}}
        # @see TASK_MATCHERS
        def parse
          TASK_MATCHERS.each do |(task_type, regex)|
            if (md = regex.match(description))
              return (
                {
                  type: task_type,
                }.merge(
                  task_details_from(md.named_captures)
                ).compact
              )
            end
          end
        end

        # Converts matched named capture groups into normalized task requirements.
        #
        # Processes captured values by normalizing town names via #determine_town,
        # converting numeric strings to integers, downcasing action names, normalizing
        # creature names via #normalized_creature_name, and passing through other
        # values unchanged. Always includes :requirements key in returned hash.
        #
        # @param captures [Hash{String => String, nil}] named captures from regex match
        # @return [Hash{Symbol => Object}] hash with :requirements key and optional
        #   :town key, containing processed and normalized captures
        # @api private
        def task_details_from(captures)
          {
            requirements: {}
          }.tap do |task_details|
            if (town = determine_town(captures["town"]))
              task_details[:town] = town
              task_details[:requirements][:town] = town
            end

            captures.each do |(key, value)|
              task_details[:requirements][key.to_sym] =
                case key
                when "town"
                  town
                when "number"
                  value.to_i
                when "action"
                  value.downcase
                when "creature"
                  normalized_creature_name(value)
                else
                  value
                end
            end
          end
        end

        # Normalizes certain creature name patterns encountered in task descriptions.
        #
        # Extracts the significant part of creature names that include modifiers like
        # "<word> being" -> "being" or "<word> magna vereri" -> "magna vereri",
        # and passes through other names unchanged.
        #
        # @param raw_creature_name [String] the creature name from the task description
        # @return [String] the normalized creature name
        # @api private
        def normalized_creature_name(raw_creature_name)
          case raw_creature_name
          when /^\w+ being$/
            'being'
          when /^\w+ magna vereri$/
            'magna vereri'
          else
            raw_creature_name
          end
        end

        # Resolves ambiguous or missing town names based on context clues in the
        # full task description.
        #
        # Checks for specific guard/guard-like NPC locations and gem dealer references
        # to disambiguate which town is implied, returning the resolved town name or
        # the originally captured town name if no special case matches.
        #
        # @param captured_town [String, nil] the town name from regex captures, if any
        # @return [String, nil] the resolved town name, or nil if unresolvable
        # @api private
        def determine_town(captured_town)
          if description =~ /the sentry just outside town\.$/
            "Kraken's Fall"
          elsif description =~ /the tavernkeeper at Rawknuckle's Common House\.$/
            "Cold River"
          elsif description =~ /the elderly guard in the East Guardtower\.$/
            "Mist Harbor"
          elsif description =~ /\b(?:Captain|Reiya|Ataum|Galeb)\b/ || description =~ /gem dealer in has received/
            # the latter is a temporary workaround because of an actual typo in the messaging
            # that should be removed if it is ever actually fixed
            'Contempt'
          else
            captured_town
          end
        end

        # Parses a bounty task description and returns structured task data.
        #
        # Convenience class method that creates a new Parser instance and calls
        # #parse on it. Returns nil if the description is nil or empty.
        #
        # @param desc [String, nil] the task description; defaults to checkbounty
        #   result if not provided
        # @return [Hash{Symbol => Object}, nil] parsed task data hash, or nil if desc
        #   is empty or no pattern matches
        # @example
        #   Parser.parse("You are not currently assigned a task.") #=> {:type=>:none, :requirements=>{}}
        def self.parse(desc = checkbounty)
          if desc && desc.empty?
            return
          else
            self.new(desc).parse
          end
        end
      end
    end
  end
end
