# frozen_string_literal: true

#
# Status Effect Pattern Definitions
# Combat status effects like stun, prone, blind, etc.
#

require_relative 'pattern_gate'

# Namespace for Lich 5, the Ruby scripting engine for GemStone IV and DragonRealms.
module Lich
  # Namespace for GemStone IV game integration.
  module Gemstone
    # Namespace for combat system analysis and pattern matching.
    module Combat
      # Namespace for game entity definitions and patterns.
      module Definitions
        # Combat status effect pattern definitions and parsing.
        #
        # Defines patterns for recognizing status effects like stun, prone, blind,
        # webbed, poisoned, etc., along with the messages that indicate those effects
        # are applied (add_patterns) or removed (remove_patterns) on targets.
        # Provides a `.parse(line)` method for efficient pattern matching against
        # game output.
        module Statuses
          StatusDef = Struct.new(:name, :add_patterns, :remove_patterns)

          # Core status effects with both add and remove patterns
          STATUS_EFFECTS = [
            StatusDef.new(:blind,
                          [/You blinded (?<target>[^!]+)!/].freeze,
                          [/(?<target>.+?) vision clears\./].freeze),

            StatusDef.new(:immobilized,
                          [
                            /(?<target>.+?) form is entangled in an unseen force that restricts .+? movement\./,
                            /(?<target>.+?) shakes in utter terror!/
                          ].freeze,
                          [
                            /(?<target>.+?) movements no longer appear hampered as the lunar light encircling .+? fades away\./,
                            /The restricting force enveloping (?<target>.+?) fades away\./,
                          ].freeze),

            StatusDef.new(:prone,
                          [
                            /It is knocked to the ground!/,
                            /(?<target>.+?) is knocked to the ground!/,
                            /(?<target>.+?) falls to the ground!/
                          ].freeze,
                          [
                            /(?<target>.+?) stands back up\./,
                            /(?<target>.+?) gets back to .+? feet\./,
                            /(?<target>.+?) rises to .+? feet\./,
                            /(?<target>.+?) stands up\./
                          ].freeze),

            StatusDef.new(:stunned,
                          [/The (?<target>.+?) is stunned!/].freeze,
                          [
                            /(?<target>.+?) shakes off the stun effect\./,
                            /(?<target>.+?) regains .+? composure\./,
                            /(?<target>.+?) is no longer stunned\./
                          ].freeze),

            StatusDef.new(:sunburst,
                          [/(?<target>.+?) reels and stumbles under the intense flare!/].freeze,
                          [/(?<target>.+?) blinks a few times, regaining a sense of balance\./].freeze),

            StatusDef.new(:webbed,
                          [/(?<target>.+?) becomes ensnared in thick strands of webbing!/].freeze,
                          [
                            /(?<target>.+?) breaks free of the webs\./,
                            /(?<target>.+?) struggles free of the webs\./,
                            /(?<target>.+?) tears through the webbing\./,
                            /The webs dissolve from around (?<target>.+?)\./
                          ].freeze),

            StatusDef.new(:sleeping,
                          [
                            /(?<target>.+?) falls into a deep slumber\./,
                            /(?<target>.+?) falls asleep\./
                          ].freeze,
                          [
                            /(?<target>.+?) wakes up\./,
                            /(?<target>.+?) awakens\./,
                            /(?<target>.+?) opens .+? eyes\./
                          ].freeze),

            StatusDef.new(:poisoned,
                          [/(?<target>.+?) appears to be suffering from a poison\./].freeze,
                          [
                            /(?<target>.+?) looks much better\./,
                            /(?<target>.+?) recovers from the poison\./
                          ].freeze),

            StatusDef.new(:roundtime,
                          [/(?<target>.+?) struggles momentarily with the gale\./].freeze,
                          [].freeze),

            StatusDef.new(:sounds,
                          [/(?<target>.+?) seems to be distracted by something\./].freeze,
                          [].freeze),

            StatusDef.new(:calm,
                          [/A calm washes over (?<target>.+?)\./].freeze,
                          [
                            /The calmed look leaves (?<target>.+?)\./,
                            /(?<target>.+?) is enraged by your attack\!/
                          ].freeze),

            StatusDef.new(:natures_decay,
                          [
                            /An earthy, sweet aroma clings to (?<target>.+?) in a murky haze, accompanied by soot brown specks of leaf mold\./,
                            /An earthy, sweet aroma wafts from (?<target>.+?) in a murky haze\./,
                            /The earthy, sweet aroma clinging to (?<target>.+?) grows more pervasive\./
                          ].freeze,
                          [/The earthy, sweet aroma surrounding (?<target>.+?) dwindles as the murky haze disperses./].freeze),

            StatusDef.new(:tangleweed,
                          [/You notice .+? scrape into (?<target>.+?) skin. .+? suddenly looks very weak!/].freeze,
                          [/(?<target>.+?) appears to recover some strength\./].freeze)
          ].freeze

          # Create lookup tables for fast pattern matching
          ADD_LOOKUP = STATUS_EFFECTS.flat_map do |status_def|
            status_def.add_patterns.compact.map { |pattern| [pattern, status_def.name, :add] }
          end.freeze

          # Lookup table mapping remove patterns to status names and action type.
          #
          # Built from all remove_patterns across STATUS_EFFECTS. Each entry is a 3-tuple:
          # [pattern, status_name, :remove]. Used by `.parse(line)` to detect when a
          # status effect expires.
          #
          # @see ADD_LOOKUP
          # @see ALL_LOOKUP
          REMOVE_LOOKUP = STATUS_EFFECTS.flat_map do |status_def|
            status_def.remove_patterns.compact.map { |pattern| [pattern, status_def.name, :remove] }
          end.freeze

          # Combined lookup table of all add and remove patterns.
          #
          # Union of ADD_LOOKUP and REMOVE_LOOKUP. Used to build the STATUS_DETECTOR
          # regex and STATUS_GATE substring filter for efficient parsing. Each entry
          # is a 3-tuple: [pattern, status_name, action] where action is :add or :remove.
          #
          # @see ADD_LOOKUP
          # @see REMOVE_LOOKUP
          ALL_LOOKUP = (ADD_LOOKUP + REMOVE_LOOKUP).freeze

          # Compiled regex for fast detection. NOTE: costs ~1ms per
          # non-matching line (unanchored `.+?` alternatives); kept for
          # compatibility but the literal gate below is what parse uses.
          STATUS_DETECTOR = Regexp.union(ALL_LOOKUP.map(&:first)).freeze

          # Literal-substring gate (~7us/line, measured on session logs)
          STATUS_GATE, STATUS_ALWAYS_SCAN = PatternGate.build(ALL_LOOKUP.map(&:first))

          # Parse status effect from line
          def self.parse(line)
            # Fast rejection: a line can only match a status pattern if it
            # contains that pattern's literal fragment.
            return nil if PatternGate.rejects?(STATUS_GATE, STATUS_ALWAYS_SCAN, line)

            ALL_LOOKUP.each do |pattern, name, action|
              if (match = pattern.match(line))
                result = {
                  status: name,
                  action: action # :add or :remove
                }
                result[:target] = match[:target] if match.names.include?('target') && match[:target]
                return result
              end
            end
            nil
          end
        end
      end
    end
  end
end

# Disir shaking moonbeam/immobilize
# A shining winged disir's wings unfurl in a rainbow of color that brightens toward blinding white.  The forces restraining her fall away in shreds of crackling mana.
