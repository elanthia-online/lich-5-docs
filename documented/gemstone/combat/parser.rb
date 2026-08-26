# frozen_string_literal: true

#
# Combat Parser - Core parsing methods for combat events
# Performance-optimized with lazy loading and selective pattern matching
#

require_relative 'defs/attacks'
require_relative 'defs/damage'
require_relative 'defs/statuses'
require_relative 'defs/ucs'

# Namespace for the Lich 5 scripting engine and its subsystems.
module Lich
  # Namespace for GemStone IV and DragonRealms integration.
  module Gemstone
    # Namespace for combat event parsing and tracking.
    module Combat
      # Core parsing methods for extracting combat events, damage, status effects,
      # and UCS events from game server output. Provides performance-optimized pattern
      # matching with lazy loading and early-exit conditions.
      module Parser
        # Target link pattern - extract creatures/players from XML
        TARGET_LINK_PATTERN = /<a exist="(?<id>[^"]+)" noun="(?<noun>[^"]+)">(?<name>[^<]+)<\/a>/i.freeze

        # Bold tag pattern - creatures are wrapped in bold tags
        # Non-greedy match to avoid spanning multiple creatures
        # Allow zero or more characters before <a> tag (e.g., "a creature" or just "creature")
        BOLD_WRAPPER_PATTERN = /<pushBold\/>([^<]*<a exist="[^"]+"[^>]+>[^<]+<\/a>)<popBold\/>/i.freeze

        class << self
          # Parse attack initiation
          def parse_attack(line)
            return nil if Definitions::Attacks.rejects?(line)

            Definitions::Attacks::ATTACK_LOOKUP.each do |pattern, name|
              if (match = pattern.match(line))
                target_info = extract_target_from_match(match) || extract_target_from_line(line)
                return {
                  name: name,
                  target: target_info || {},
                  damaging: true
                }
              end
            end
            nil
          end

          # Parse damage amounts using damage definitions
          def parse_damage(line)
            result = Definitions::Damage.parse(line)
            result ? result[:damage] : nil
          end

          # Parse status effects (optional - performance setting)
          def parse_status(line)
            return nil unless Tracker.settings[:track_statuses]

            # Return the full result including action field
            Definitions::Statuses.parse(line)
          end

          # Parse UCS events (position, tierup, smite)
          def parse_ucs(line)
            return nil unless Tracker.settings[:track_ucs]

            Definitions::UCS.parse(line)
          end

          # Extract creature target (must be wrapped in bold tags)
          def extract_creature_target(line)
            # Cheap gate: the wrapper pattern can't match without the bold tag,
            # and the substring check avoids two regexes on most lines
            return nil unless line.include?('<pushBold/>')

            # Check if line contains a bolded link
            bold_match = BOLD_WRAPPER_PATTERN.match(line)
            return nil unless bold_match

            # Extract the link from within the bold tags
            link_text = bold_match[1]
            link_match = TARGET_LINK_PATTERN.match(link_text)
            return nil unless link_match

            id = link_match[:id].to_i
            return nil if id <= 0 # Skip invalid IDs

            {
              id: id,
              noun: link_match[:noun],
              name: link_match[:name]
            }
          end

          # Try to extract target from regex match first, then from line
          def extract_target_from_match(match)
            return nil unless match.names.include?('target')
            target_text = match[:target]
            return nil if target_text.nil? || target_text.strip.empty?

            # Look for creature in target text
            if (target_match = TARGET_LINK_PATTERN.match(target_text))
              id = target_match[:id].to_i
              return nil if id < 0

              return {
                id: id,
                noun: target_match[:noun],
                name: target_match[:name]
              }
            end

            nil
          end

          # Extracts a creature target from a line of game output by looking for
          # bold-wrapped links. Non-bolded links (equipment, objects, NPCs) are rejected.
          #
          # @param line [String] a line of game server output containing XML tags
          # @return [Hash, nil] a hash with :id (Integer), :noun (String), and :name (String)
          #   keys if a bolded creature link is found; nil otherwise
          # @example
          #   extract_target_from_line("<pushBold/><a exist=\"12345\" noun=\"troll\">a troll</a><popBold/>") #=> {:id=>12345, :noun=>"troll", :name=>"a troll"}
          def extract_target_from_line(line)
            # ONLY accept bolded creatures as targets
            # Non-bolded links are equipment, objects, or other non-combatants
            extract_creature_target(line)
          end
        end
      end
    end
  end
end
