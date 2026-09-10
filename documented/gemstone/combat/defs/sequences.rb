# frozen_string_literal: true

#
# Sequence Pattern Definitions
# Converted from ctparser/SEQUENCE_DEFS to Lich::Gemstone::Combat namespace
#
# A sequence brackets a multi-part combat action: the start line announces
# it, per-target attack events unfold inside it, and the end line closes
# it. Used to attribute spawned casts (a Blink flare firing an imbedded
# Nature's Fury produces a full AoE sequence whose per-target events are
# children of the flare, not independent casts) and to bound multi-TARGET
# attacks like mstrike and volley. Single-target multi-round attacks
# (flurry, barrage, pummel...) are ASSAULTS - see defs/assaults.rb.
#

require_relative 'pattern_gate'

# Namespace for the Lich 5 scripting engine.
module Lich
  # Namespace for GemStone IV and DragonRealms specific functionality.
  module Gemstone
    # Namespace for combat-related parsing and event definitions.
    module Combat
      # Namespace for pattern definitions used to parse game server output.
      module Definitions
        # Namespace for sequence pattern definitions and parsing.
        #
        # Sequences bracket multi-part combat actions: a start line announces it,
        # per-target attack events unfold inside, and an end line closes it. Used to
        # attribute spawned casts (e.g., a Blink flare firing an embedded Nature's Fury
        # produces a full AoE sequence whose per-target events are children of the flare,
        # not independent casts) and to bound multi-target attacks like mstrike and volley.
        module Sequences
          SequenceDef = Struct.new(:name, :start_patterns, :end_patterns)

          # Array of sequence pattern definitions.
          #
          # Each SequenceDef contains a sequence name and the regex patterns that mark
          # its start and end lines. Patterns use named captures to extract the target.
          #
          # @return [Array<SequenceDef>]
          SEQUENCE_DEFS = [
            SequenceDef.new(:earthen_fury, [
              /The ground beneath (?<target>.+?) begins to boil violently!/,
              /The ground beneath (?<target>.+?) suddenly frosts and rumbles violently!/,
              /The ground beneath (?<target>.+?) boils with renewed vigor!/,
              /The ground beneath (?<target>.+?) rumbles with renewed vigor!/
            ].freeze, [/The ground beneath (?<target>.+?) suddenly calms\./].freeze),
            SequenceDef.new(:mstrike, [
              /With great haste, you let loose a volley of shots!/,
              /With instinctive motions, you weave to and fro striking with deliberate and unrelenting fury!/,
              /You explode into a fury of strikes and ripostes, moving with a singular purpose and will!/
            ].freeze, [
              /Your series of strikes and ripostes leaves you winded and out of position./,
              /Your series of strikes and ripostes leaves you off-balance and out of position./,
              /Your series of rapid shots and maneuvers leaves you off-balance and out of position./
            ].freeze),
            SequenceDef.new(:natures_fury, [
              /You close your eyes in a moment of intense concentration, channeling the pure natural power of your surroundings\./
            ].freeze, [/As swiftly as the chaos came to be, it recedes again into the surroundings\./].freeze),
            # Volley: the hail-shadow line opens EVERY round (rounds 2+ have
            # no bow line); per-arrow :volley attack events unfold inside.
            # The 2p bow-raise line is this sequence's PREFIX - not a def.
            SequenceDef.new(:volley, [
              /An ominous shadow falls over your surroundings as a whistling hail of arrows arcs down from above!/
            ].freeze, [/The air clears as the deadly volley of arrows abates\./].freeze)
          ].freeze

          # Lookup table mapping sequence start patterns to sequence names.
          #
          # Built from SEQUENCE_DEFS for fast O(n) pattern matching of sequence starts.
          #
          # @return [Array<[Regexp, Symbol]>]
          START_LOOKUP = SEQUENCE_DEFS.flat_map { |d| d.start_patterns.map { |rx| [rx, d.name] } }.freeze
          # Lookup table mapping sequence end patterns to sequence names.
          #
          # Built from SEQUENCE_DEFS for fast O(n) pattern matching of sequence ends.
          #
          # @return [Array<[Regexp, Symbol]>]
          END_LOOKUP   = SEQUENCE_DEFS.flat_map { |d| d.end_patterns.map { |rx| [rx, d.name] } }.freeze

          START_GATE, START_ALWAYS = PatternGate.build(START_LOOKUP.map(&:first))
          END_GATE, END_ALWAYS     = PatternGate.build(END_LOOKUP.map(&:first))

          # @return [Symbol, nil] sequence name whose start line this is
          def self.parse_start(line)
            return nil unless START_GATE.match?(line) || START_ALWAYS.any? { |rx| rx.match?(line) }

            START_LOOKUP.each { |rx, name| return name if rx.match?(line) }
            nil
          end

          # @return [Symbol, nil] sequence name whose end line this is
          def self.parse_end(line)
            return nil unless END_GATE.match?(line) || END_ALWAYS.any? { |rx| rx.match?(line) }

            END_LOOKUP.each { |rx, name| return name if rx.match?(line) }
            nil
          end
        end
      end
    end
  end
end
