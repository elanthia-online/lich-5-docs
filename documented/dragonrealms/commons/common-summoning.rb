# frozen_string_literal: true

require_relative '../custom_substitutions'

# Root namespace for the Lich game scripting engine.
module Lich
  # Namespace for DragonRealms game scripts and utilities.
  module DragonRealms
    # DragonRealms Common Scripts: shared utilities for summoning and manipulating
    # magical weapons (moonblades/staves for Moon Mages, elemental weapons for Warrior Mages).
    module DRCS
      module_function

      # Shared response for elemental charge depletion
      LACK_CHARGE = 'You lack the elemental charge'.freeze

      # Expected game responses from the SUMMON WEAPON command.
      #
      # @see #summon_weapon
      SUMMON_WEAPON_RESPONSES = [
        LACK_CHARGE,
        'you draw out'
      ].freeze

      # Expected game responses from the BREAK command on a summoned weapon.
      #
      # @see #break_summoned_weapon
      BREAK_WEAPON_RESPONSES = [
        'Focusing your will',
        'disrupting its matrix',
        "You can't break",
        'Break what'
      ].freeze

      # Moon Mage skill-to-shape mapping for moonblades/staves
      MOON_SKILL_TO_SHAPE = {
        'Staves'          => 'blunt',
        'Twohanded Edged' => 'huge',
        'Large Edged'     => 'heavy',
        'Small Edged'     => 'normal'
      }.freeze

      # Expected game responses from shaping a Moon Mage moonblade/staff.
      #
      # @see #shape_summoned_weapon
      MOON_SHAPE_RESPONSES = [
        'you adjust the magic that defines its shape',
        'already has',
        'You fumble around'
      ].freeze

      # Expected game responses from attempting to shape a Warrior Mage summoned weapon,
      # including failures (depleted charge, unknown weapon type).
      #
      # @see #shape_summoned_weapon
      WM_SHAPE_FAILURES = [
        LACK_CHARGE,
        'You reach out',
        'You fumble around',
        "You don't know how to manipulate your weapon in that way"
      ].freeze

      # Expected game responses from the TURN command on a summoned weapon.
      #
      # @see #turn_summoned_weapon
      TURN_WEAPON_RESPONSES = [LACK_CHARGE, 'You reach out'].freeze
      # Expected game responses from the PUSH command on a summoned weapon.
      #
      # @see #push_summoned_weapon
      PUSH_WEAPON_RESPONSES = [LACK_CHARGE, 'Closing your eyes', "That's as"].freeze
      # Expected game responses from the PULL command on a summoned weapon.
      #
      # @see #pull_summoned_weapon
      PULL_WEAPON_RESPONSES = [LACK_CHARGE, 'Closing your eyes', "That's as"].freeze

      # Expected game responses from the SUMMON ADMITTANCE command, which restores
      # elemental charge for Warrior Mage summoned weapons.
      #
      # @see #summon_admittance
      SUMMON_ADMITTANCE_RESPONSES = [
        'You align yourself to it',
        'further increasing your proximity',
        'Going any further while in this plane would be fatal',
        'Summon allows Warrior Mages to draw',
        'You are a bit too distracted'
      ].freeze

      # Default element adjectives for Warrior Mage summoned weapons
      WM_ELEMENT_ADJECTIVES = %w[stone fiery icy electric].freeze

      # Summons an elemental weapon (Warrior Mage) or moonblade/staff (Moon Mage).
      #
      # For Warrior Mages: retrieves the specified ingot, casts SUMMON WEAPON with the
      # given element and skill, and stows the ingot. If elemental charge is depleted,
      # automatically calls {#summon_admittance} to restore it and retries the summon.
      # For Moon Mages: calls {Lich::DragonRealms::MM#hold_moon_weapon?}.
      #
      # @param _moon [Object, nil] unused (legacy parameter)
      # @param element [String, nil] element adjective (e.g. "fiery", "icy") for Warrior Mages
      # @param ingot [String, nil] ingot type name for Warrior Mages (e.g. "ruby", "sapphire")
      # @param skill [String, nil] weapon skill target for Warrior Mages (e.g. "melee", "ranged")
      # @return [void]
      # @note Pauses 1 second and calls {#waitrt?} and {DRC.fix_standing} at the end
      # @example Summon a fiery sword for melee skill using a ruby ingot
      #   summon_weapon(element: "fiery", ingot: "ruby", skill: "melee")
      def summon_weapon(_moon = nil, element = nil, ingot = nil, skill = nil)
        if DRStats.moon_mage?
          DRCMM.hold_moon_weapon?
        elsif DRStats.warrior_mage?
          return unless get_ingot(ingot, true)

          result = DRC.bput("summon weapon #{element} #{skill}", *SUMMON_WEAPON_RESPONSES)
          if result == LACK_CHARGE
            summon_admittance
            DRC.bput("summon weapon #{element} #{skill}", *SUMMON_WEAPON_RESPONSES)
          end
          stow_ingot(ingot)
        else
          Lich::Messaging.msg("bold", "DRCS: Unable to summon weapons as a #{DRStats.guild}")
        end
        pause 1
        waitrt?
        DRC.fix_standing
      end

      # Retrieves an ingot from storage.
      #
      # If `ingot` is nil, returns true without attempting retrieval. Otherwise,
      # gets the item matching "#{ingot} ingot" from storage using {DRCI.get_item?}.
      # If successful and `swap` is true, executes the SWAP command to exchange hands.
      #
      # @param ingot [String, nil] ingot type name (e.g. "ruby", "emerald"), or nil to skip
      # @param swap [Boolean] whether to swap the ingot to the other hand after retrieval
      # @return [Boolean] true if the ingot was retrieved (or skipped), false if retrieval failed
      # @example Get a ruby ingot without swapping
      #   get_ingot("ruby", false) #=> true
      def get_ingot(ingot, swap)
        return true unless ingot

        unless DRCI.get_item?("#{ingot} ingot")
          Lich::Messaging.msg("bold", "DRCS: Could not get #{ingot} ingot")
          return false
        end
        DRC.bput('swap', 'You move') if swap
        true
      end

      # Stows an ingot into storage.
      #
      # If `ingot` is nil, returns true without attempting stowage. Otherwise,
      # stows the item matching "#{ingot} ingot" using {DRCI.put_away_item?}.
      #
      # @param ingot [String, nil] ingot type name (e.g. "ruby", "emerald"), or nil to skip
      # @return [Boolean] true if the ingot was stowed (or skipped), false if stowage failed
      # @example Stow a sapphire ingot
      #   stow_ingot("sapphire") #=> true
      def stow_ingot(ingot)
        return true unless ingot

        unless DRCI.put_away_item?("#{ingot} ingot")
          Lich::Messaging.msg("bold", "DRCS: Could not stow #{ingot} ingot")
          return false
        end
        true
      end

      # Breaks a summoned weapon using the BREAK command.
      #
      # If `item` is nil, returns immediately without sending a command.
      #
      # @param item [String, nil] the weapon item noun (e.g. "moonblade", "sword"), or nil to skip
      # @return [void]
      # @example Break a moonblade
      #   break_summoned_weapon("moonblade")
      def break_summoned_weapon(item)
        return if item.nil?

        DRC.bput("break my #{item}", *BREAK_WEAPON_RESPONSES)
      end

      # Reshapes a summoned weapon to a different form.
      #
      # For Moon Mages: maps the skill name to a shape using {MOON_SKILL_TO_SHAPE},
      # then casts SHAPE on the held moonblade/staff (identified via {#identify_summoned_weapon}).
      #
      # For Warrior Mages: retrieves the ingot, casts SHAPE MY <weapon> TO <skill>,
      # and stows the ingot. If the weapon has a custom element adjective from a
      # Books of Binding tome, the command may be rejected; in that case,
      # {#base_summoned_weapon} strips the adjective and retries. If elemental
      # charge is depleted, automatically calls {#summon_admittance} to restore it.
      #
      # @param skill [String] the skill name to shape to (e.g. "melee", "ranged") or
      #   Moon Mage shape key (e.g. "Staves", "Small Edged")
      # @param ingot [String, nil] ingot type name for Warrior Mages, or nil to skip
      # @param settings [OpenStruct, nil] user settings for looking up custom adjectives
      # @return [void]
      # @note Pauses 1 second and calls {#waitrt?} at the end
      # @see #identify_summoned_weapon
      # @see #base_summoned_weapon
      # @see #custom_summoned_weapon_adjectives
      def shape_summoned_weapon(skill, ingot = nil, settings = nil)
        summoned_weapon = identify_summoned_weapon(settings)
        if DRStats.moon_mage?
          shape = MOON_SKILL_TO_SHAPE[skill]
          if DRCMM.hold_moon_weapon?
            DRC.bput("shape #{summoned_weapon} to #{shape}", *MOON_SHAPE_RESPONSES)
          end
        elsif DRStats.warrior_mage?
          return unless get_ingot(ingot, false)

          result = DRC.bput("shape my #{summoned_weapon} to #{skill}", *(WM_SHAPE_FAILURES + ['What type of weapon were you trying']))
          case result
          when LACK_CHARGE
            summon_admittance
            DRC.bput("shape my #{summoned_weapon} to #{skill}", *WM_SHAPE_FAILURES)
          when 'What type of weapon were you trying'
            # Custom adjectives from https://elanthipedia.play.net/Books_of_Binding tomes
            # aren't recognized for shaping summoned elemental weapons, and the error message
            # itself is misleading. Breaking, turning, pulling, pushing work fine with custom adj.
            unless summoned_weapon.nil?
              base_weapon = base_summoned_weapon(summoned_weapon, settings)
              retry_result = DRC.bput("shape my #{base_weapon} to #{skill}", *WM_SHAPE_FAILURES)
              if retry_result == LACK_CHARGE
                summon_admittance
                DRC.bput("shape my #{base_weapon} to #{skill}", *WM_SHAPE_FAILURES)
              end
            end
          end
          stow_ingot(ingot)
        else
          Lich::Messaging.msg("bold", "DRCS: Unable to shape weapons as a #{DRStats.guild}")
        end
        pause 1
        waitrt?
      end

      # Player-defined summoned-weapon adjectives (e.g. from Books of Binding
      # tomes), merged and validated. Combines the plural
      # +custom_summoned_weapons_adjectives+ list with the legacy singular
      # +summoned_weapons_adjective+ setting (kept for backward compatibility).
      # The built-in {WM_ELEMENT_ADJECTIVES} are NOT included here -- callers add
      # those where needed.
      #
      # @param settings [OpenStruct, nil] user settings (for the legacy key)
      # @return [Array<String>] validated custom adjectives
      # @see CustomSubstitutions.resolve
      def custom_summoned_weapon_adjectives(settings = nil)
        # dup: never mutate CustomSubstitutions' memoized array when adding legacy.
        adjectives = CustomSubstitutions.resolve(:custom_summoned_weapons_adjectives, [], type: :names).dup
        legacy = settings&.summoned_weapons_adjective
        adjectives << legacy if legacy.is_a?(String) && !legacy.empty? && !adjectives.include?(legacy)
        adjectives
      end

      # Strips the summoned weapon's custom element adjective so the game
      # recognizes the base weapon for shaping (custom Books-of-Binding
      # adjectives aren't accepted by SHAPE).
      #
      # Picks the LONGEST matching adjective, not the first: with a substring
      # pair like ['flame', 'flamewreathed'] a first-match would strip 'flame'
      # from "flamewreathed sword" and leave a bogus "wreathed sword".
      #
      # @param summoned_weapon [String] the held weapon's <adj> <noun>
      # @param settings [OpenStruct, nil] user settings (for the legacy key)
      # @return [String] the weapon with its custom adjective removed (if any)
      # @see #custom_summoned_weapon_adjectives
      def base_summoned_weapon(summoned_weapon, settings = nil)
        present = custom_summoned_weapon_adjectives(settings).select { |adjective| summoned_weapon.include?(adjective) }.max_by(&:length)
        present ? summoned_weapon.sub(present, '') : summoned_weapon
      end

      # Returns what kind of summoned weapon you're holding.
      # Will be the <adj> <noun> like 'red-hot moonblade' or 'electric sword'.
      # Recognizes {WM_ELEMENT_ADJECTIVES} plus any player-defined adjectives
      # ({custom_summoned_weapon_adjectives}).
      def identify_summoned_weapon(settings = nil)
        if DRStats.moon_mage?
          return DRC.right_hand if DRCMM.is_moon_weapon?(DRC.right_hand)
          return DRC.left_hand  if DRCMM.is_moon_weapon?(DRC.left_hand)
        elsif DRStats.warrior_mage?
          adjectives = (WM_ELEMENT_ADJECTIVES + custom_summoned_weapon_adjectives(settings)).map { |adjective| Regexp.escape(adjective) }.join('|')
          weapon_regex = /^You tap (?:a|an|some)(?:[\w\s\-]+)(?:(?:#{adjectives}) [\w\s\-]+) that you are holding\.$/
          # For a two-worded weapon like 'short sword' the only way to know
          # which element it was summoned with is by tapping it. That's the only
          # way we can infer if it's a summoned sword or a regular one.
          # However, the <adj> <noun> of the item we return must be what's in
          # their hands, not what the regex matches in the tap.
          return DRC.right_hand if weapon_regex.match?(DRCI.tap(DRC.right_hand).to_s)
          return DRC.left_hand if weapon_regex.match?(DRCI.tap(DRC.left_hand).to_s)
        else
          Lich::Messaging.msg("bold", "DRCS: Unable to identify summoned weapons as a #{DRStats.guild}")
        end
      end

      # Rotates a summoned weapon in hand using the TURN command.
      #
      # If elemental charge is depleted, automatically calls {#summon_admittance}
      # to restore it and retries the turn.
      #
      # @return [void]
      # @note Pauses 1 second and calls {#waitrt?} at the end
      def turn_summoned_weapon
        result = DRC.bput("turn my #{DRC.right_hand_noun}", *TURN_WEAPON_RESPONSES)
        if result == LACK_CHARGE
          summon_admittance
          DRC.bput("turn my #{DRC.right_hand_noun}", *TURN_WEAPON_RESPONSES)
        end
        pause 1
        waitrt?
      end

      # Pushes a summoned weapon forward in hand using the PUSH command.
      #
      # If elemental charge is depleted, automatically calls {#summon_admittance}
      # to restore it and retries the push.
      #
      # @return [void]
      # @note Pauses 1 second and calls {#waitrt?} at the end
      def push_summoned_weapon
        result = DRC.bput("push my #{DRC.right_hand_noun}", *PUSH_WEAPON_RESPONSES)
        if result == LACK_CHARGE
          summon_admittance
          DRC.bput("push my #{DRC.right_hand_noun}", *PUSH_WEAPON_RESPONSES)
        end
        pause 1
        waitrt?
      end

      # Pulls a summoned weapon backward in hand using the PULL command.
      #
      # If elemental charge is depleted, automatically calls {#summon_admittance}
      # to restore it and retries the pull.
      #
      # @return [void]
      # @note Pauses 1 second and calls {#waitrt?} at the end
      def pull_summoned_weapon
        result = DRC.bput("pull my #{DRC.right_hand_noun}", *PULL_WEAPON_RESPONSES)
        if result == LACK_CHARGE
          summon_admittance
          DRC.bput("pull my #{DRC.right_hand_noun}", *PULL_WEAPON_RESPONSES)
        end
        pause 1
        waitrt?
      end

      # Restores elemental charge for summoned weapons via SUMMON ADMITTANCE command.
      #
      # Loops until SUMMON ADMITTANCE succeeds. If the response is
      # "You are a bit too distracted", calls {DRC.retreat} and retries.
      #
      # @return [void]
      # @note Pauses 1 second and calls {#waitrt?} and {DRC.fix_standing} at the end
      def summon_admittance
        loop do
          result = DRC.bput('summon admittance', *SUMMON_ADMITTANCE_RESPONSES)
          if result == 'You are a bit too distracted'
            DRC.retreat
            next
          end
          break
        end
        pause 1
        waitrt?
        DRC.fix_standing
      end
    end
  end
end
