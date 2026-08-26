# frozen_string_literal: true

# Namespace for the Lich scripting engine and all related APIs.
module Lich
  # Namespace for DragonRealms-specific functionality.
  module DragonRealms
    # DragonRealms Common Healing - utilities for querying and managing character health.
    #
    # Provides methods to check health status via HEALTH and PERCEIVE HEALTH commands,
    # parse wound/bleeder/parasite diagnostics, and perform wound tending.
    module DRCH
      module_function

      # Strips XML tags and decodes common HTML entities from game output lines.
      # @param lines [Array<String>] Array of raw game output lines
      # @return [Array<String>] Array of non-empty, trimmed strings with XML removed
      # @see DRC.strip_xml Delegates to shared utility
      def strip_xml(lines)
        DRC.strip_xml(lines)
      end

      def has_tendable_bleeders?
        check_health.has_tendable_bleeders?
      end

      # Uses HEALTH command to check for poisons, diseases, bleeders, parasites, and lodged items.
      # Returns a HealthResult with diagnostic information for healing prioritization.
      def check_health
        health_lines = Lich::Util.issue_command(
          'health',
          /^Your body feels\b/,
          /<prompt/,
          usexml: true,
          quiet: true,
          include_end: false
        )
        if health_lines.nil?
          Lich::Messaging.msg("bold", "DRCH: Failed to capture HEALTH output (timeout).")
          return HealthResult.new
        end

        parse_health_lines(strip_xml(health_lines))
      end

      # Parses stripped HEALTH command output lines into a HealthResult.
      def parse_health_lines(health_lines)
        parasites_regex = Regexp.union(PARASITES_REGEX)
        wounds_line = nil
        parasites_line = nil
        lodged_line = nil
        diseased = false
        poisoned = false

        health_lines.each do |line|
          case line
          when /^Your body feels\b/, /^Your spirit feels\b/, /^You are .*fatigued/, /^You feel fully rested/
            next
          when /^You have (?!no significant injuries)(?!.* lodged .* in(?:to)? your)(?!.* infection)(?!.* poison(?:ed)?)(?!.* #{parasites_regex})/
            wounds_line = line
          when /^You have .* lodged .* in(?:to)? your/
            lodged_line = line
          when /^You have a .* on your/, parasites_regex
            parasites_line = line
          when /^You have a dormant infection/, /^Your wounds are infected/, /^Your body is covered in open oozing sores/
            diseased = true
          when /^You have .* poison(?:ed)?/, /^You feel somewhat tired and seem to be having trouble breathing/
            poisoned = true
          end
        end

        bleeders = parse_bleeders(health_lines)
        wounds = parse_wounds(wounds_line)
        parasites = parse_parasites(parasites_line)
        lodged_items = parse_lodged_items(lodged_line)
        score = calculate_score(wounds)

        HealthResult.new(
          wounds: wounds,
          bleeders: bleeders,
          parasites: parasites,
          lodged: lodged_items,
          poisoned: poisoned,
          diseased: diseased,
          score: score
        )
      end

      # Uses PERCEIVE HEALTH SELF command to check for wounds and scars.
      # Returns a HealthResult with perceived wound details merged with check_health diagnostics.
      def perceive_health
        unless DRStats.empath?
          Lich::Messaging.msg("bold", "DRCH: Only empaths can perceive health.")
          return nil
        end

        lines = Lich::Util.issue_command(
          'perceive health self',
          /injuries include\.\.\.|feel only an aching emptiness/,
          /<prompt/,
          usexml: true,
          quiet: true,
          include_end: false,
          timeout: 15
        )
        if lines.nil?
          Lich::Messaging.msg("bold", "DRCH: Failed to capture PERCEIVE HEALTH output (timeout).")
          return nil
        end

        lines = strip_xml(lines)

        if lines.any? { |line| line =~ /feel only an aching emptiness/ }
          waitrt?
          return check_health
        end

        perceived = parse_perceived_health_lines(lines)
        health_data = check_health

        waitrt?

        HealthResult.new(
          wounds: perceived.wounds,
          bleeders: health_data.bleeders,
          parasites: health_data.parasites,
          lodged: health_data.lodged,
          poisoned: health_data.poisoned,
          diseased: health_data.diseased,
          vitality: perceived.vitality,
          dead: perceived.dead,
          score: perceived.score
        )
      end

      # Perceives the health of another character via empathic touch.
      #
      # Empaths only. Attempts to touch the target to establish an empathic link,
      # then parses the perceived health lines to extract wound, disease, poison,
      # and vitality information. Returns nil if the target cannot be touched or
      # if the empath does not have the PERCEIVE HEALTH skill.
      #
      # @param target [String] the character name or abbreviation to touch
      # @return [HealthResult, nil] a HealthResult with perceived wounds and status, or nil on failure
      # @note The actual target name is extracted from the empathic link message
      #   and may differ from the input (e.g., case or abbreviation).
      # @example
      #   result = DRCH.perceive_health_other("bob")
      #   if result
      #     puts "#{result.vitality}% vitality"
      #   end
      def perceive_health_other(target)
        unless DRStats.empath?
          Lich::Messaging.msg("bold", "DRCH: Only empaths can perceive health of others.")
          return nil
        end

        touch_lines = Lich::Util.issue_command(
          "touch #{target}",
          /You sense a successful empathic link|Touch what|feels cold|avoids your touch|You quickly recoil/,
          /<prompt/,
          usexml: true,
          quiet: true,
          include_end: false,
          timeout: 10
        )
        if touch_lines.nil?
          Lich::Messaging.msg("bold", "DRCH: Failed to capture TOUCH output for #{target} (timeout).")
          return nil
        end

        touch_lines = strip_xml(touch_lines)

        if touch_lines.any? { |line| line =~ /Touch what|feels cold|avoids your touch|You quickly recoil/ }
          Lich::Messaging.msg("bold", "DRCH: Unable to perceive health of #{target}.")
          return nil
        end

        # Extract actual character name from the empathic link message.
        # The target passed to the method may be abbreviated or differently cased.
        touch_lines.each do |line|
          match = line.match(/between you and (?<name>\w+)\./)
          if match
            target = match[:name]
            break
          end
        end

        parse_perceived_health_lines(touch_lines)
      end

      # Parses lines from PERCEIVE HEALTH SELF or TOUCH output into a HealthResult.
      def parse_perceived_health_lines(lines)
        parasites_regex = Regexp.union(PARASITES_REGEX)
        poisons_regex = Regexp.union([
                                       /^[\w]+ (?:has|have) a .* poison/,
                                       /having trouble breathing/,
                                       /Cyanide poison/
                                     ])
        diseases_regex = Regexp.union([
                                        /^[\w]+ wounds are (?:badly )?infected/,
                                        /^[\w]+ (?:has|have) a dormant infection/,
                                        /^[\w]+ (?:body|skin) is covered (?:in|with) open oozing sores/
                                      ])
        dead_regex = /^(?:He|She) is dead/
        vitality_regex = /has (\d+)% vitality remaining/

        perceived_wounds = Hash.new { |h, k| h[k] = [] }
        perceived_parasites = Hash.new { |h, k| h[k] = [] }
        perceived_poison = false
        perceived_disease = false
        perceived_vitality = 100
        wound_body_part = nil
        dead = false

        lines.each do |line|
          case line
          when dead_regex
            dead = true
          when vitality_regex
            perceived_vitality = Regexp.last_match(1).to_i
          when diseases_regex
            perceived_disease = true
          when poisons_regex
            perceived_poison = true
          when parasites_regex
            match = line.match(/.* on (?:his|her|your) (?<body_part>[\w\s]*)/)
            body_part = match[:body_part] if match
            perceived_parasites[1] << Wound.new(body_part: body_part, severity: 1)
          when /^Wounds to the /
            match = line.match(/^Wounds to the (?<body_part>.+):/)
            wound_body_part = match[:body_part] if match
            perceived_wounds[wound_body_part] = []
          when /^(?:Fresh|Scars) (?:External|Internal)/
            match = line.match(PERCEIVE_HEALTH_SEVERITY_REGEX)
            next unless match
            next unless wound_body_part

            severity = WOUND_SEVERITY[match[:severity]]
            perceived_wounds[wound_body_part] << Wound.new(
              body_part: wound_body_part,
              severity: severity,
              is_internal: match[:location] == 'Internal',
              is_scar: match[:freshness] == 'Scars'
            )
          end
        end

        # Bucket wounds by severity.
        wounds = Hash.new { |h, k| h[k] = [] }
        perceived_wounds.values.flatten.each do |wound|
          wounds[wound.severity] << wound
        end

        HealthResult.new(
          wounds: wounds,
          parasites: perceived_parasites,
          poisoned: perceived_poison,
          diseased: perceived_disease,
          dead: dead,
          vitality: perceived_vitality,
          score: calculate_score(wounds)
        )
      end

      # Parses bleeder lines from HEALTH command output.
      # Returns a hash keyed by severity with arrays of bleeding Wounds.
      def parse_bleeders(health_lines)
        bleeders = Hash.new { |h, k| h[k] = [] }
        return bleeders unless health_lines.grep(/^Bleeding|^\s*\bArea\s+Rate\b/).any?

        health_lines
          .drop_while { |line| !(BLEEDER_LINE_REGEX =~ line) }
          .take_while { |line| BLEEDER_LINE_REGEX =~ line }
          .each do |line|
            match = line.match(WOUND_BODY_PART_REGEX)
            next unless match

            body_part = match.names.find { |name| match[name.to_sym] }
            body_part = match[:part] if body_part == 'part'
            body_part = body_part.gsub('l.', 'left').gsub('r.', 'right')

            rate_match = line.match(/(?:head|eye|neck|chest|abdomen|back|arm|hand|leg|tail|skin)\s+(?<rate>.+)/)
            next unless rate_match

            bleed_rate = rate_match[:rate].strip
            bleed_info = BLEED_RATE_TO_SEVERITY[bleed_rate]
            next unless bleed_info

            bleeders[bleed_info[:severity]] << Wound.new(
              body_part: body_part,
              severity: bleed_info[:severity],
              bleeding_rate: bleed_rate,
              is_internal: line.start_with?('inside')
            )
          end

        bleeders
      end

      # Parses the wound description line from HEALTH command output.
      # Returns a hash keyed by severity with arrays of Wounds.
      def parse_wounds(wounds_line)
        wounds = Hash.new { |h, k| h[k] = [] }
        return wounds unless wounds_line

        wounds_line = wounds_line.gsub(WOUND_COMMA_SEPARATOR, '')
        wounds_line = wounds_line.gsub(/^You have\s+/, '').gsub(/\.$/, '')
        wounds_line.split(',').map(&:strip).each do |wound|
          WOUND_SEVERITY_REGEX_MAP.each do |regex, template|
            match = wound.match(regex)
            next unless match

            body_part = match.names.find { |name| match[name.to_sym] }
            body_part = match[:part] if body_part == 'part'

            wounds[template[:severity]] << Wound.new(
              body_part: body_part,
              severity: template[:severity],
              is_internal: template[:internal],
              is_scar: template[:scar]
            )
          end
        end

        wounds
      end

      # Parses the parasite description line from HEALTH command output.
      # Returns a hash keyed by severity with arrays of parasite Wounds.
      def parse_parasites(parasites_line)
        parasites = Hash.new { |h, k| h[k] = [] }
        return parasites unless parasites_line

        parasites_line = parasites_line.gsub(/^You have\s+/, '').gsub(/\.$/, '')
        parasites_line.split(',').map(&:strip).each do |parasite|
          match = parasite.match(PARASITE_BODY_PART_REGEX)
          next unless match

          parasites[1] << Wound.new(
            body_part: match[:part],
            severity: 1,
            is_parasite: true
          )
        end

        parasites
      end

      # Parses the lodged item description line from HEALTH command output.
      # Returns a hash keyed by severity with arrays of lodged item Wounds.
      def parse_lodged_items(lodged_line)
        lodged_items = Hash.new { |h, k| h[k] = [] }
        return lodged_items unless lodged_line

        lodged_line = lodged_line.gsub(/^You have\s+/, '').gsub(/\.$/, '')
        lodged_line.split(',').map(&:strip).each do |wound|
          match = wound.match(LODGED_BODY_PART_REGEX)
          next unless match

          body_part = match.names.find { |name| match[name.to_sym] }
          body_part = match[:part] if body_part == 'part'

          severity_match = wound.match(/\blodged\s+(?<depth>.+)\s+in(?:to)? your\b/)
          next unless severity_match

          severity = LODGED_SEVERITY[severity_match[:depth]]

          lodged_items[severity] << Wound.new(
            body_part: body_part,
            severity: severity,
            is_lodged_item: true
          )
        end

        lodged_items
      end

      # Tends a wound on a body part, removing bandages and handling dislodged items.
      #
      # Issues a TEND command for the specified body part. If the tend dislodges
      # an item (e.g., a crossbow bolt), removes and disposes of it before retrying
      # the tend. Waits for roundtime before returning.
      #
      # @param body_part [String] the body part to tend (e.g., "right arm", "head")
      # @param person [String] possessive pronoun prefix for the tend command, defaults to "my"
      # @return [Boolean] true if the wound was successfully tended, false if the tend failed
      # @note Side effect: disposes of dislodged items to the worn trashcan
      # @example
      #   DRCH.bind_wound("right arm")
      #   DRCH.bind_wound("head", "his")
      def bind_wound(body_part, person = 'my')
        result = DRC.bput("tend #{person} #{body_part}", *TEND_SUCCESS_PATTERNS, *TEND_FAILURE_PATTERNS, *TEND_DISLODGE_PATTERNS)
        waitrt?
        case result
        when *TEND_DISLODGE_PATTERNS
          dislodge_match = result.match(/^You \w+ remove (?:a|the|some) (?<item>.+) from/)
          # Only dispose the item the tend just removed, and only while it is in
          # hand. A freshly dislodged item (e.g. a crossbow bolt) lands in a free
          # hand; disposing it there is safe. But if the item is gone (the maze
          # can yank you out and clear your hands the instant it drops), a blind
          # dispose_trash would GET a same-named item from a worn container --
          # trashing the character's own ammunition -- so skip it in that case.
          if dislodge_match && DRCI.in_hands?(dislodge_match[:item])
            DRCI.dispose_trash(dislodge_match[:item], get_settings.worn_trashcan, get_settings.worn_trashcan_verb)
          end
          bind_wound(body_part, person)
        when *TEND_FAILURE_PATTERNS
          false
        else
          true
        end
      end

      # Removes bandages from a tended wound.
      #
      # Issues an UNWRAP command to reverse the effects of a prior TEND.
      # Waits for roundtime after the command completes.
      #
      # @param body_part [String] the body part to unwrap (e.g., "right arm", "head")
      # @param person [String] possessive pronoun prefix for the unwrap command, defaults to "my"
      # @return [void]
      # @example
      #   DRCH.unwrap_wound("right arm")
      def unwrap_wound(body_part, person = 'my')
        DRC.bput("unwrap #{person} #{body_part}", 'You unwrap .* bandages', 'That area is not tended', 'You may undo the affects of TENDing')
        waitrt?
      end

      # Skill check to tend a bleeding wound.
      # Returns false if unskilled - tending when unskilled may worsen the wound.
      def skilled_to_tend_wound?(bleed_rate, internal = false)
        bleed_info = BLEED_RATE_TO_SEVERITY[bleed_rate]
        return false unless bleed_info

        skill_target = internal ? :skill_to_tend_internal : :skill_to_tend
        min_skill = bleed_info[skill_target]
        return false if min_skill.nil?

        DRSkill.getrank('First Aid') >= min_skill
      end

      # Computes a weighted summary score from a wound severity map.
      # Higher severity wounds contribute quadratically more to the score.
      def calculate_score(wounds_by_severity)
        wounds_by_severity.map { |severity, wound_list| (severity**2) * wound_list.count }.reduce(:+) || 0
      end

      # Structured result from check_health or perceive_health.
      # Supports backward-compatible string-key access via [] for dr-scripts callers.
      class HealthResult
        attr_reader :wounds, :bleeders, :parasites, :lodged,
                    :poisoned, :diseased, :score, :dead, :vitality

        # Initializes a HealthResult with health diagnostic data.
        #
        # @param wounds [Hash] hash of severity => [Wound] for regular wounds
        # @param bleeders [Hash] hash of severity => [Wound] for active bleeders
        # @param parasites [Hash] hash of severity => [Wound] for parasites
        # @param lodged [Hash] hash of severity => [Wound] for lodged items
        # @param poisoned [Boolean] whether the character is poisoned
        # @param diseased [Boolean] whether the character is diseased
        # @param score [Integer] weighted health score (0 for healthy)
        # @param dead [Boolean] whether the character is dead
        # @param vitality [Integer] percentage vitality remaining (0-100)
        # @return [void]
        def initialize(wounds: {}, bleeders: {}, parasites: {}, lodged: {},
                       poisoned: false, diseased: false, score: 0, dead: false,
                       vitality: 100)
          @wounds = wounds
          @bleeders = bleeders
          @parasites = parasites
          @lodged = lodged
          @poisoned = poisoned
          @diseased = diseased
          @score = score
          @dead = dead
          @vitality = vitality
        end

        # Backward compatibility for dr-scripts callers using health_data['wounds'] etc.
        def [](key)
          send(key.to_sym)
        end

        # Checks whether the character has any injuries.
        #
        # @return [Boolean] true if the health score is greater than 0
        def injured?
          score > 0
        end

        def bleeding?
          bleeders.values.flatten.any?(&:bleeding?)
        end

        # Checks whether the character has bleeders that can be tended.
        #
        # A bleeder is tendable if the character has sufficient First Aid skill
        # or if it is a parasite or lodged item.
        #
        # @return [Boolean] true if at least one bleeder is tendable
        def has_tendable_bleeders?
          bleeders.values.flatten.any?(&:tendable?)
        end
      end

      # Represents a single wound, bleeder, parasite, or lodged item.
      class Wound
        attr_reader :body_part, :severity, :bleeding_rate

        # Initializes a Wound representing a single injury, bleeder, parasite, or lodged item.
        #
        # All boolean flags default to false. Body part and bleeding rate are downcased.
        #
        # @param body_part [String, nil] the affected body part (e.g., "right arm")
        # @param severity [Integer, nil] wound severity (1-9 or higher)
        # @param bleeding_rate [String, nil] bleeding rate description (e.g., "heavily", "tended")
        # @param is_internal [Boolean] whether the wound is internal
        # @param is_scar [Boolean] whether this is a scar rather than a fresh wound
        # @param is_parasite [Boolean] whether this is a parasite infestation
        # @param is_lodged_item [Boolean] whether this is a lodged item
        # @return [void]
        def initialize(body_part: nil, severity: nil, bleeding_rate: nil,
                       is_internal: false, is_scar: false,
                       is_parasite: false, is_lodged_item: false)
          @body_part = body_part&.downcase
          @severity = severity
          @bleeding_rate = bleeding_rate&.downcase
          @internal = !!is_internal
          @scar = !!is_scar
          @parasite = !!is_parasite
          @lodged_item = !!is_lodged_item
        end

        # Checks whether this wound is actively bleeding.
        #
        # A wound is bleeding if it has a non-empty bleeding rate that is not the
        # sentinel value "(tended)".
        #
        # @return [Boolean] true if the wound is actively bleeding
        def bleeding?
          !@bleeding_rate.nil? && !@bleeding_rate.empty? && @bleeding_rate != '(tended)'
        end

        # Checks whether this wound is internal.
        #
        # @return [Boolean] true if the wound is internal rather than external
        def internal?
          @internal
        end

        # Checks whether this wound is a scar.
        #
        # @return [Boolean] true if this is a scar rather than a fresh wound
        def scar?
          @scar
        end

        # Checks whether this wound represents a parasite infestation.
        #
        # @return [Boolean] true if this is a parasite
        def parasite?
          @parasite
        end

        # Checks whether this wound represents a lodged item.
        #
        # @return [Boolean] true if this is a lodged item
        def lodged?
          @lodged_item
        end

        # Checks whether this wound can be safely tended.
        #
        # Parasites and lodged items are always tendable. Wounds on the skin are never
        # tendable. Bleeder wounds must be actively bleeding and not yet tended or clotted,
        # and the character must have sufficient First Aid skill for the bleeding rate.
        #
        # @return [Boolean] true if the wound is safe to tend
        def tendable?
          return true if parasite?
          return true if lodged?
          return false if @body_part =~ /skin/
          return false unless bleeding?
          return false if @bleeding_rate =~ /tended|clotted/

          DRCH.skilled_to_tend_wound?(@bleeding_rate, internal?)
        end

        # Returns the wound location as "internal" or "external".
        #
        # @return [String] "internal" or "external"
        def location
          internal? ? 'internal' : 'external'
        end

        # Returns the wound type as "scar" or "wound".
        #
        # @return [String] "scar" or "wound"
        def type
          scar? ? 'scar' : 'wound'
        end

        # Converts the wound to a hash representation.
        #
        # @return [Hash] hash with keys :body_part, :severity, :bleeding_rate, :internal, :scar, :parasite, :lodged_item
        def to_h
          {
            body_part: @body_part,
            severity: @severity,
            bleeding_rate: @bleeding_rate,
            internal: @internal,
            scar: @scar,
            parasite: @parasite,
            lodged_item: @lodged_item
          }
        end

        # Returns a human-readable string representation of the wound.
        #
        # @return [String] formatted string like "Wound(right arm, severity:5, bleeding:heavily, external, wound)"
        def to_s
          parts = [@body_part || 'unknown']
          parts << "severity:#{@severity}" if @severity
          parts << "bleeding:#{@bleeding_rate}" if @bleeding_rate
          parts << location
          parts << type
          parts << 'parasite' if parasite?
          parts << 'lodged' if lodged?
          "Wound(#{parts.join(', ')})"
        end
      end
    end
  end
end
