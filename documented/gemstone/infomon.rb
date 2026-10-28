# frozen_string_literal: true

# Replacement for the venerable infomon.lic script used in Lich4 and Lich5 (03/01/23)
# Supports Ruby 3.X builds
#
#     maintainer: elanthia-online
#   contributors: Tillmen, Shaelun, Athias
#           game: Gemstone
#           tags: core
#       required: Lich > 5.6.2
#        version: 2.0
#         Source: https://github.com/elanthia-online/scripts

require 'sequel'
require 'tmpdir'
require 'logger'
require 'timeout'
require_relative 'infomon/cache'
require_relative '../common/watchable'

# Namespace for the Lich scripting engine.
module Lich
  # Namespace for GemStone IV scripting features.
  module Gemstone
    # Persistent key-value store for game state tied to character name and game.
    #
    # Stores arbitrary typed data (Integer, String, Boolean, nil) in a SQLite database,
    # indexed by character and game. Writes are queued asynchronously on a background
    # thread. Reads hit a memory cache that is flushed to disk on demand via .flush.
    # Failed writes are tracked and retried on the next .set or .upsert_batch call.
    #
    # @example Store and retrieve a character's training rank
    #   Infomon.set("tactics_trained_ranks", 24)
    #   Infomon.get("tactics_trained_ranks") #=> 24
    # @example Batch upsert multiple keys
    #   Infomon.upsert_batch({"exp_pool" => 500, "death_count" => 2})
    module Infomon
      extend Lich::Common::Watchable
      $infomon_debug = ENV["DEBUG"]
      # use temp dir in ci context
      @root = defined?(DATA_DIR) ? DATA_DIR : Dir.tmpdir
      @file = File.join(@root, "infomon.db")
      @db   = Sequel.sqlite(@file)
      @cache ||= Infomon::Cache.new
      @cache_loaded = false
      @db.loggers << Logger.new($stdout) if ENV["DEBUG"]
      @sql_queue ||= Queue.new
      @sql_mutex ||= Mutex.new
      # keys whose last attempted write failed; cleared by a later successful write.
      # Plain Hash like Cache: mutated by the worker thread and reset!; single ops are GVL-atomic.
      @unpersisted ||= {}
      # true once a write failure has been shown in game; any successful write clears it
      @failure_reported = false

      # Returns the in-memory cache of all persisted key-value pairs for the character.
      #
      # @return [Infomon::Cache] the cache object
      def self.cache
        @cache
      end

      # Returns the file path to the SQLite database.
      #
      # @return [String] absolute path to infomon.db
      def self.file
        @file
      end

      # Returns the Sequel database connection.
      #
      # @return [Sequel::Database] the SQLite database instance
      def self.db
        @db
      end

      # Returns the mutex guarding all database and cache operations.
      #
      # @return [Mutex] the synchronization lock
      # @api private
      def self.mutex
        @sql_mutex
      end

      # Acquires the database mutex if not already held by this thread.
      #
      # On error, logs and responds to the game.
      #
      # @return [void]
      # @api private
      def self.mutex_lock
        begin
          self.mutex.lock unless self.mutex.owned?
        rescue StandardError
          respond "--- Lich: error: Infomon.mutex_lock: #{$!}"
          Lich.log "error: Infomon.mutex_lock: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
        end
      end

      # Releases the database mutex if held by this thread.
      #
      # On error, logs and responds to the game.
      #
      # @return [void]
      # @api private
      def self.mutex_unlock
        begin
          self.mutex.unlock if self.mutex.owned?
        rescue StandardError
          respond "--- Lich: error: Infomon.mutex_unlock: #{$!}"
          Lich.log "error: Infomon.mutex_unlock: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
        end
      end

      # Returns the thread-safe queue of pending SQL write operations.
      #
      # @return [Queue] the work queue
      # @api private
      def self.queue
        @sql_queue
      end

      # Returns the current UTC time as a float (seconds since epoch).
      #
      # @return [Float] current time in UTC
      # @api private
      def self.current_timestamp
        Time.now.utc.to_f
      end

      # Raises an error if the character name has not yet loaded from XMLData.
      #
      # @return [void]
      # @raise [RuntimeError] if XMLData.name is empty or nil
      # @api private
      def self.context!
        return unless XMLData.name.empty? or XMLData.name.nil?
        puts Exception.new.backtrace
        fail "cannot access Infomon before XMLData.name is loaded"
      end

      # Returns the database table name for the current character, derived from game and name.
      #
      # @return [Symbol] table name in the form :gamecode_charactername
      # @raise [RuntimeError] if character name is not yet loaded
      # @api private
      def self.table_name
        self.context!
        ("%s_%s" % [XMLData.game, XMLData.name]).to_sym
      end

      # Drops the character's database table, clears the cache, and re-initializes.
      #
      # All persisted data for this character is lost. The table is recreated on next access.
      #
      # @return [void]
      # @api private
      def self.reset!
        self.mutex_lock
        Infomon.db.drop_table?(self.table_name)
        self.cache.clear
        @unpersisted.clear
        @failure_reported = false
        @cache_loaded = false
        Infomon.setup!
      end

      # Returns the Sequel dataset for the character's key-value table.
      #
      # Calls .setup! on first access to initialize the table schema.
      #
      # @return [Sequel::Dataset] the dataset for INSERT, SELECT, and DELETE operations
      # @api private
      def self.table
        @_table ||= self.setup!
      end

      # Creates or validates the character's database table, checking for schema compatibility.
      #
      # If the table exists but lacks the updated_at column (old schema), drops and recreates it.
      # Acquires and releases the database mutex during operation.
      #
      # @return [Sequel::Dataset] the dataset for the table
      # @api private
      def self.setup!
        self.mutex_lock

        # Check if table exists but missing updated_at column
        if @db.table_exists?(self.table_name)
          columns = @db.schema(self.table_name).map { |col| col[0] }
          unless columns.include?(:updated_at)
            self.mutex_unlock
            self.reset!
            return
          end
        end

        @db.create_table?(self.table_name) do
          text :key, primary_key: true
          any :value
          float :updated_at
        end
        self.mutex_unlock
        @_table = @db[self.table_name]
      end

      # Populates the cache from the database, once per character session.
      #
      # Sleeps briefly if the character name has not yet loaded. Sets @cache_loaded to true.
      #
      # @return [void]
      # @api private
      def self.cache_load
        sleep(0.01) if XMLData.name.empty?
        dataset = Infomon.table
        h = dataset.map(:key).zip(dataset.map(:value)).to_h
        self.cache.merge!(h)
        @cache_loaded = true
      end

      # Normalizes a key to lowercase with underscores instead of spaces or hyphens.
      #
      # Multiple consecutive underscores are collapsed to one.
      #
      # @param key [String, Symbol] the key to normalize
      # @return [String] the normalized key
      # @example
      #   Infomon._key("Tactics Trained Ranks") #=> "tactics_trained_ranks"
      #   Infomon._key("death-count") #=> "death_count"
      # @api private
      def self._key(key)
        key.to_s.downcase.tr(' -', '_').gsub(/_+/, '_')
      end

      # Converts string boolean literals to their boolean type; passes through other values.
      #
      # @param val [String, Integer, Boolean, nil] the value to convert
      # @return [Boolean, String, Integer, nil] the converted value
      # @example
      #   Infomon._value("true") #=> true
      #   Infomon._value("false") #=> false
      #   Infomon._value(42) #=> 42
      # @api private
      def self._value(val)
        return true if val.to_s == "true"
        return false if val.to_s == "false"
        return val
      end

      AllowedTypes = [Integer, String, NilClass, FalseClass, TrueClass]
      # Validates that the value is an allowed type and converts it.
      #
      # Allowed types are Integer, String, nil, true, and false.
      #
      # @param key [String] the key being set (used only in error messages)
      # @param value [Integer, String, Boolean, nil] the value to validate
      # @return [Integer, String, Boolean, nil] the converted value
      # @raise [RuntimeError] if value is not an allowed type
      # @api private
      def self._validate!(key, value)
        return self._value(value) if AllowedTypes.include?(value.class)
        raise "infomon:insert(%s) was called with %s\nmust be %s\nvalue=%s" % [key, value.class, AllowedTypes.map(&:name).join("|"), value]
      end

      # Retrieves the value for a key, loading the cache if needed and flushing pending writes.
      #
      # Returns nil if the key does not exist. The cache is consulted first; if the key is not
      # cached, the database is queried after flushing the write queue. On database error,
      # logs and responds to the game, then returns nil.
      #
      # @param key [String, Symbol] the key to retrieve
      # @return [Integer, String, Boolean, nil] the stored value, or nil if not found
      # @example
      #   Infomon.set("level", 85)
      #   Infomon.get("level") #=> 85
      def self.get(key)
        self.cache_load if !@cache_loaded
        key = self._key(key)
        val = self.cache.get(key) {
          # Flush queue before reading from DB to ensure we see latest writes
          self.flush
          begin
            self.mutex.synchronize do
              begin
                db_result = self.table[key: key]
                if db_result
                  db_result[:value]
                else
                  nil
                end
              rescue => exception
                pp(exception)
                nil
              end
            end
          rescue StandardError
            respond "--- Lich: error: Infomon.get(#{key}): #{$!}"
            Lich.log "error: Infomon.get(#{key}): #{$!}\n\t#{$!.backtrace.join("\n\t")}"
          end
        }
        return self._value(val)
      end

      # Retrieves the value for a key and coerces it to a boolean.
      #
      # True and false values are returned as-is. Integer 1 is treated as true; all other
      # values (including 0) are treated as false. Nil is treated as false.
      #
      # @param key [String, Symbol] the key to retrieve
      # @return [Boolean] true or false
      # @example
      #   Infomon.set("in_combat", true)
      #   Infomon.get_bool("in_combat") #=> true
      def self.get_bool(key)
        value = Infomon.get(key)
        if value.is_a?(TrueClass) || value.is_a?(FalseClass)
          return value
        elsif value == 1
          return true
        else
          return false
        end
      end

      # Retrieves the timestamp (in seconds since epoch) when the key was last written.
      #
      # Returns nil if the key does not exist or on database error. On error, logs and
      # responds to the game.
      #
      # @param key [String, Symbol] the key to check
      # @return [Float, nil] the last update time in UTC seconds, or nil if not found
      # @example
      #   Infomon.get_updated_at("level") #=> 1704067200.5
      def self.get_updated_at(key)
        key = self._key(key)
        begin
          self.mutex.synchronize do
            db_result = self.table[key: key]
            if db_result
              db_result[:updated_at]
            else
              nil
            end
          end
        rescue StandardError
          respond "--- Lich: error: Infomon.get_updated_at(#{key}): #{$!}"
          Lich.log "error: Infomon.get_updated_at(#{key}): #{$!}\n\t#{$!.backtrace.join("\n\t")}"
          nil
        end
      end

      # Inserts or updates rows in the table using Sequel's INSERT OR REPLACE conflict handling.
      #
      # @param args [Array] arguments passed to Sequel's insert method
      # @return [Integer] the number of rows affected
      # @api private
      def self.upsert(*args)
        self.table
            .insert_conflict(:replace)
            .insert(*args)
      end

      # Sets a key-value pair, queueing the write to the database asynchronously.
      #
      # The value is cached immediately; the write is performed on a background thread.
      # If the key already exists in the cache with the same value and has no pending
      # failed write, returns :noop (no operation queued). Allowed value types are
      # Integer, String, nil, true, and false.
      #
      # @param key [String, Symbol] the key to set
      # @param value [Integer, String, Boolean, nil] the value to store
      # @return [void, Symbol] void if queued, or :noop if no change needed
      # @raise [RuntimeError] if value is not an allowed type
      # @example
      #   Infomon.set("level", 85)
      #   Infomon.set("status", "hunting")
      #   Infomon.set("resting", true)
      def self.set(key, value)
        key = self._key(key)
        value = self._validate!(key, value)
        return :noop if !@unpersisted.key?(key) && self.cache.include?(key) && self.cache.get(key) == value
        self.cache.put(key, value)
        # queue items are [sql, keys] so a failed write can mark its keys unpersisted
        self.queue << ["INSERT OR REPLACE INTO %s (`key`, `value`, `updated_at`) VALUES (%s, %s, %s)
      on conflict(`key`) do update set value = excluded.value, updated_at = excluded.updated_at;" % [self.db.literal(self.table_name), self.db.literal(key), self.db.literal(value), current_timestamp], [key]]
      end

      # Deletes a key from the cache and queues a database DELETE on the background thread.
      #
      # @param key [String, Symbol] the key to delete
      # @return [void]
      # @example
      #   Infomon.delete!("old_config_key")
      def self.delete!(key)
        key = self._key(key)
        self.cache.delete(key)
        self.queue << ["DELETE FROM %s WHERE key = (%s);" % [self.db.literal(self.table_name), self.db.literal(key)], [key]]
      end

      # Flush all pending SQL operations and wait for completion.
      # This is a barrier that ensures all queued writes have been executed.
      # Returns true on success, false on timeout.
      def self.flush(timeout_seconds: 5)
        return true if self.queue.empty?

        # Create a barrier token - a Queue that the worker will signal when reached
        barrier = ::Queue.new
        self.queue << barrier

        # Wait for the worker to signal completion (with timeout)
        begin
          ::Timeout.timeout(timeout_seconds) { barrier.pop }
          true
        rescue ::Timeout::Error
          Lich.log "warning: Infomon.flush timed out after #{timeout_seconds}s"
          false
        end
      end

      # Batch inserts or updates multiple key-value pairs in a single SQL statement.
      #
      # Accepts a hash (or multiple hashes) where only keys not already in the cache
      # (or with pending failed writes) are inserted. Values are cached immediately;
      # the write is queued asynchronously. Returns :noop if no new keys are found.
      # Only Integer and String values are supported in batch mode.
      #
      # @param blob [Hash] one or more hashes of key => value pairs
      # @return [void, Symbol] void if queued, or :noop if all keys are cached
      # @raise [RuntimeError] if any value is not Integer or String
      # @example
      #   Infomon.upsert_batch({"exp_pool" => 500, "death_count" => 2})
      def self.upsert_batch(*blob)
        updated = (blob.first.map { |k, v| [self._key(k), self._validate!(k, v)] } - self.cache.to_a.reject { |k, _| @unpersisted.key?(k) })
        return :noop if updated.empty?
        now = current_timestamp
        pairs = updated.map { |key, value|
          (value.is_a?(Integer) or value.is_a?(String)) or fail "upsert_batch only works with Integer or String types"
          # add the value to the cache
          self.cache.put(key, value)
          %[(%s, %s, %s)] % [self.db.literal(key), self.db.literal(value), now]
        }.join(", ")
        # queue sql statement to run async
        self.queue << ["INSERT OR REPLACE INTO %s (`key`, `value`, `updated_at`) VALUES %s
      on conflict(`key`) do update set value = excluded.value, updated_at = excluded.updated_at;" % [self.db.literal(self.table_name), pairs], updated.map(&:first)]
      end

      Thread.new do
        loop do
          item = Infomon.queue.pop
          begin
            # Handle flush barrier tokens - signal completion and continue
            if item.is_a?(Queue)
              item << :flushed
              next
            end

            # Normal SQL statement processing
            sql, keys = item
            write_error = nil
            report_in_game = false
            Infomon.mutex.synchronize do
              begin
                Infomon.db.run(sql)
                # Safe to clear: the queue is FIFO, so any later write for these keys
                # runs after this and re-marks them if it fails.
                keys.each { |key| @unpersisted.delete(key) }
                @failure_reported = false
              rescue StandardError => e
                # Keep the cached value (Infomon's view of the game) and mark the keys so
                # the next set/upsert_batch of the same value is retried instead of a :noop.
                report_in_game = !@failure_reported
                @failure_reported = true
                keys.each { |key| @unpersisted[key] = true }
                write_error = e
              end
            end
            # Reported after releasing the DB mutex so a slow client write can't hold it.
            # The game window gets one short line per failure streak (a streak ends at
            # the next successful write); the log gets every failure in full.
            if write_error
              if report_in_game
                shown = keys.first(3).join(', ')
                shown += ', ...' if keys.size > 3
                respond "--- Lich: error: Infomon write failed for #{keys.size} key(s) (#{shown}): #{write_error.message}"
              end
              Lich.log "error: Infomon write failed for #{keys.join(', ')}: #{write_error.class}: #{write_error.message}\n\t#{write_error.backtrace.join("\n\t")}"
            end
          rescue StandardError
            respond "--- Lich: error: Infomon ThreadQueue: #{$!}"
            Lich.log "error: Infomon ThreadQueue: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
          end
        end
      end

      # Self-watching thread that triggers initialization when ready
      # Follows the ActiveSpell.watch! pattern for lifecycle management
      def self.watch!
        @init_thread ||= Thread.new do
          begin
            # Wait for character to be ready and dialogs to load
            sleep 0.1 until GameBase::Game.autostarted? && XMLData.name && !XMLData.name.empty? &&
                            !XMLData.dialogs.empty?

            # Run initial setup if needed (GS-specific only, skip for DR)
            if XMLData.game !~ /^DR/ && db_refresh_needed?
              ExecScript.start("Infomon.redo!", { quiet: true, name: "infomon_reset" })
            end

            PostLoad.game_loaded! if defined?(PostLoad)
          rescue StandardError => e
            respond 'Error in Infomon initialization thread'
            respond e.inspect
          end
        end
      end

      require_relative 'infomon/parser'
      require_relative 'infomon/xmlparser'
      require_relative 'infomon/cli'
    end
  end
end
