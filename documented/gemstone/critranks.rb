# frozen_string_literal: true

#
# module CritRanks used to resolve critical hits into their mechanical results
# queries against crit_tables files in lib/crit_tables/
# 20240625
#

#
# See generic_critical_table.rb for the general template used
#
module Lich
  # Namespace for GemStone IV critical hit data and parsing.
  module Gemstone
    # Resolves critical hits from combat messages into their mechanical results.
    #
    # Queries critical hit tables loaded from lib/crit_tables/*.rb files and provides
    # methods to parse incoming damage text, look up critical effects by type/location/rank,
    # and reload table data on demand.
    #
    # @see #parse
    # @see #fetch
    module CritRanks
      @critical_table ||= {}
      @types           = []
      @locations       = []
      @ranks           = []

      # Loads all critical hit table files from the critranks directory.
      #
      # This is a no-op if tables are already loaded. Automatically called at module
      # load time and may be called again after .reload!. Uses `load` instead of
      # `require` to ensure reload can re-run the table definitions.
      #
      # @return [void]
      # @api private
      def self.init
        return unless @critical_table.empty?
        Dir.glob("#{File.join(LIB_DIR, "gemstone", "critranks", "*critical_table.rb")}").each do |file|
          # load, not require: require makes reload! a no-op (already-required
          # table files never re-run, leaving the emptied table empty forever)
          load file
        end
        create_indices
      end

      # Returns the in-memory critical hit table hash.
      #
      # @return [Hash] the full critical table, keyed by type > location > rank
      def self.table
        @critical_table
      end

      # Clears all loaded critical hit tables and reloads them from disk.
      #
      # @return [void]
      # @api private
      def self.reload!
        @critical_table = {}
        @types = []
        @locations = []
        @ranks = []
        init
      end

      # Returns a list of loaded critical table names, with namespace separators removed.
      #
      # @return [Array<String>] table names derived from loaded types
      def self.tables
        @tables = []
        @types.each do |type|
          @tables.push(type.to_s.gsub(':', ''))
        end
        @tables
      end

      # Returns a list of all critical hit types in the loaded tables.
      #
      # @return [Array] the type keys (e.g., critical types defined in table files)
      def self.types
        @types
      end

      # Returns a list of all body locations in the loaded tables.
      #
      # @return [Array] the location keys (e.g., :head, :chest, :limb)
      def self.locations
        @locations
      end

      # Returns a list of all critical severity ranks in the loaded tables.
      #
      # @return [Array] the rank keys (e.g., :light, :moderate, :serious)
      def self.ranks
        @ranks
      end

      # Normalizes a key for lookup: integers stay as-is; symbols and strings are
      # downcased and whitespace/hyphens converted to underscores.
      #
      # @param key [Integer, Symbol, String] the raw key
      # @return [Integer, String, Symbol] the cleaned key in normalized form
      # @example
      #   clean_key("Head") #=> "head"
      #   clean_key("Left Arm") #=> "left_arm"
      #   clean_key(42) #=> 42
      def self.clean_key(key)
        return key.to_i if key.is_a?(Integer) || key =~ (/^\d+$/)
        return key.downcase if key.is_a?(Symbol)

        key.strip.downcase.gsub(/[ -]/, '_')
      end

      # Normalizes a key and checks it against a list of valid options.
      #
      # Raises an exception if the cleaned key is not found in the valid list.
      #
      # @param key [Integer, Symbol, String] the raw key to validate
      # @param valid [Array] the list of acceptable (already-cleaned) keys
      # @return [Integer, String, Symbol] the cleaned key
      # @raise [RuntimeError] if the cleaned key is not in the valid list
      # @example
      #   validate(:head, [:head, :chest]) #=> :head
      #   validate("head", [:head, :chest]) #=> :head
      def self.validate(key, valid)
        clean = clean_key(key)
        raise "Invalid key '#{key}', expecting one of #{valid.join(',')}" unless valid.include?(clean)

        clean
      end

      # Builds the pattern indices. Tolerates nil location/rank rows in the
      # table data (some tables carry explicit nil placeholders); a nil row
      # means that crit is simply unrecognized rather than a load failure.
      #
      # Patterns are indexed by the leading literal word of their (anchored)
      # regex, so parse only has to test the handful of patterns that could
      # possibly match a given line instead of all ~2400. Patterns that are
      # not ^-anchored to a literal word are kept in a small residual list
      # that is always checked.
      def self.create_indices
        @index_buckets = Hash.new { |hash, key| hash[key] = [] }
        @index_residual = []
        @critical_table.each do |type, typedata|
          @types.append(type)
          typedata.each do |loc, locdata|
            @locations.append(loc) unless @locations.include?(loc)
            next if locdata.nil?
            locdata.each do |rank, record|
              @ranks.append(rank) unless @ranks.include?(rank)
              next if record.nil? || record[:regex].nil?
              source = record[:regex].source
              if source.start_with?('^') && (first_word = source[1..].match(/\A([A-Za-z']+)\b/))
                @index_buckets[first_word[1].downcase].push(record)
              else
                @index_residual.push(record)
              end
            end
          end
        end
        @index_buckets.each_value(&:freeze)
        @index_buckets.default = nil # drop the auto-vivifying default proc
        @index_buckets.freeze
        @index_residual.freeze
      end

      # Matches a damage line against all loaded critical patterns and returns matching records.
      #
      # Extracts the leading word from the line to index into a bucket of candidate patterns,
      # then tests all candidates (plus residual non-anchored patterns) for a match. Returns
      # a hash mapping matching Regexp objects to their record definitions.
      #
      # @param line [String] a raw damage message from the combat feed
      # @return [Hash] a hash of {Regexp => record_hash} for all patterns that matched the line
      # @example
      #   parse("Your slash wounds the creature!") #=> {/Your slash.../=>{...}, ...}
      def self.parse(line)
        stripped = line.strip # need to strip spaces to support anchored regex in tables
        first_word = stripped[/\A[A-Za-z']+/]&.downcase
        candidates = @index_buckets.fetch(first_word, nil) ? @index_buckets[first_word] + @index_residual : @index_residual
        candidates.each_with_object({}) do |record, matches|
          matches[record[:regex]] = record if record[:regex] =~ stripped
        end
      end

      # Looks up a critical hit record by type, location, and rank.
      #
      # Validates all three arguments, then digs into the critical table. On any error,
      # logs the error and returns nil.
      #
      # @param type [Integer, Symbol, String] the critical type (e.g., "slash")
      # @param location [Integer, Symbol, String] the body location (e.g., "head")
      # @param rank [Integer, Symbol, String] the severity rank (e.g., "moderate")
      # @return [Hash, nil] the critical record, or nil if not found or validation fails
      # @example
      #   fetch("slash", "head", "moderate") #=> { regex: /.../, ...
      def self.fetch(type, location, rank)
        table.dig(
          validate(type, types),
          validate(location, locations),
          validate(rank, ranks)
        )
      rescue StandardError => e
        Lich::Messaging.msg('error', "Error! #{e}")
      end
      # startup
      init
    end
  end
end
