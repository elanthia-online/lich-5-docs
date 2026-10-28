# frozen_string_literal: true

# Namespace for the Lich game scripting engine.
module Lich
  # Namespace for DragonRealms-specific scripting APIs.
  module DragonRealms
    # Manages named event flags and matchers for game line pattern matching.
    #
    # The Flags class provides thread-safe storage for event flags that track whether
    # game output has matched regex patterns added by scripts. Matchers are stored in
    # a frozen hash that is atomically swapped during add/delete operations, allowing
    # the game thread to safely iterate over patterns while scripts modify the set.
    #
    # @example Add a flag matching damage lines
    #   Lich::DragonRealms::Flags.add("hit", "You strike the", /deals? \d+ damage/)
    #   # ...
    #   if Lich::DragonRealms::Flags["hit"]
    #     respond("Damage matched!")
    #   end
    class Flags
      @@flags = {}
      # DRParser.check_events iterates @@matchers on the game thread while
      # scripts add and delete flags from their own threads. Inserting a key
      # into a hash another thread is iterating raises "can't add a new key
      # into hash during iteration", so writers never mutate @@matchers in
      # place: they build a new hash and swap the reference, and an iteration
      # in progress keeps walking the hash it started with. The mutex stops
      # two writers from both copying the same hash and losing an update, and
      # makes record_match's check-and-write atomic against add and delete.
      @@matchers = {}.freeze
      @@matchers_lock = Mutex.new

      # Retrieves the current value of a flag.
      #
      # @param key [String] the flag name
      # @return [MatchData, Boolean, nil] the last MatchData if the flag matched game output, false if reset, or nil if the flag was not added
      # @example
      #   Lich::DragonRealms::Flags["hit"] #=> #<MatchData "You strike the...">
      def self.[](key)
        @@flags[key]
      end

      # Sets a flag to an arbitrary value.
      #
      # @param key [String] the flag name
      # @param value [Object] the value to store
      # @return [Object] the value
      # @api private
      def self.[]=(key, value)
        @@flags[key] = value
      end

      # Registers a new flag with regex matchers for game output.
      #
      # Patterns can be Regexp objects or strings; strings are converted to case-insensitive regexes.
      # The flag is initialized to false and will be set to the MatchData of the first matching pattern
      # when the game outputs a matching line.
      #
      # @param key [String] the flag name
      # @param matchers [Regexp, String] one or more patterns to match against game output
      # @return [Array<Regexp>] the frozen array of compiled regex matchers
      # @example
      #   Lich::DragonRealms::Flags.add("spell_cast", "You feel", /spell.*ready/, "The magic feels ready")
      # @see .record_match
      def self.add(key, *matchers)
        regexes = matchers.map { |item| item.is_a?(Regexp) ? item : /#{item}/i }.freeze
        @@matchers_lock.synchronize do
          @@flags[key] = false
          @@matchers = @@matchers.merge(key => regexes).freeze
        end
        regexes
      end

      # Sets a flag back to false.
      #
      # @param key [String] the flag name
      # @return [Boolean] false
      # @see .add
      def self.reset(key)
        @@flags[key] = false
      end

      # Unregisters a flag and removes it from storage.
      #
      # The matchers for the key are removed atomically with the flag deletion to prevent
      # stale pattern matches from re-adding the flag.
      #
      # @param key [String] the flag name
      # @return [void]
      # @see .add
      def self.delete(key)
        @@matchers_lock.synchronize do
          @@matchers = @@matchers.reject { |k, _| k == key }.freeze
          @@flags.delete key
        end
      end

      # Sets a flag to a match DRParser.check_events found, unless the flag was
      # deleted or added again since check_events took its snapshot of the
      # matchers. Without the check, a line matching a stale snapshot puts a
      # deleted flag back into flags, or sets a re-added flag from its old
      # patterns.
      # @param key [String] the flag
      # @param regexes [Array<Regexp>] the matchers check_events matched against
      # @param matches [MatchData] the match
      # @return [void]
      def self.record_match(key, regexes, matches)
        @@matchers_lock.synchronize do
          @@flags[key] = matches if @@matchers[key].equal?(regexes)
        end
      end

      # Returns the internal flags hash.
      #
      # @return [Hash] a hash mapping flag names to MatchData, false, or nil
      # @api private
      def self.flags
        @@flags
      end

      # Returns the internal matchers hash.
      #
      # @return [Hash] a frozen hash mapping flag names to frozen arrays of Regexp matchers
      # @api private
      def self.matchers
        @@matchers
      end
    end
  end
end
