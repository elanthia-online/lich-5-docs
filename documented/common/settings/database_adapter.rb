# Namespace for the Lich 5 scripting engine.
module Lich
  # Namespace for common utilities shared across Lich 5.
  module Common
    # Database adapter to separate database concerns
    class DatabaseAdapter
      # Opens or creates a SQLite database at `data_dir/lich.db3` and initializes
      # the specified table for storing serialized settings.
      #
      # @param data_dir [String] the directory where the lich.db3 database file is stored
      # @param table_name [String] the name of the table to create or use for this adapter
      # @return [void]
      # @api private
      def initialize(data_dir, table_name)
        @file = File.join(data_dir, "lich.db3")
        @db = Lich.open_sequel_sqlite(@file)
        @table_name = table_name
        setup!
      end

      # Creates the table if it does not exist, with columns for script name, scope,
      # and a blob containing serialized settings data.
      #
      # @return [void]
      # @api private
      def setup!
        @db.create_table?(@table_name) do
          text :script
          text :scope
          blob :hash
        end
        @table = @db[@table_name]
      end

      # Returns the Sequel dataset for direct table access.
      #
      # @return [Sequel::Dataset] the underlying database table
      # @api private
      def table
        @table
      end

      # Retrieves persisted settings for a script, returning an empty hash if no
      # entry exists for the given script name and scope.
      #
      # @param script_name [String] the name of the script
      # @param scope [String] the scope identifier (default: ":")
      # @return [Hash] the deserialized settings hash, or {} if not found
      # @example
      #   adapter.get_settings("my_script", "global") #=> {"key" => "value"}
      def get_settings(script_name, scope = ":")
        entry = @table.first(script: script_name, scope: scope)
        entry.nil? ? {} : Marshal.load(entry[:hash])
      end

      # Saves or updates settings for a script by serializing the hash and upserting
      # into the database. Returns true on success, false on validation or database errors.
      #
      # Validates that settings is a Hash. On serialization or database errors, logs
      # the exception and returns false.
      #
      # @param script_name [String] the name of the script
      # @param settings [Hash] the settings hash to persist
      # @param scope [String] the scope identifier (default: ":")
      # @return [Boolean] true if saved successfully, false if validation or save failed
      # @example
      #   adapter.save_settings("my_script", {"key" => "value"}) #=> true
      def save_settings(script_name, settings, scope = ":")
        unless settings.is_a?(Hash)
          Lich::Messaging.msg("error", "--- Error: Report this - settings must be a Hash, got #{settings.class} ---")
          Lich.log("--- Error: settings must be a Hash, got #{settings.class} from call initiated by #{script_name} ---")
          Lich.log(settings.inspect)
          return false
        end

        begin
          blob = Sequel::SQL::Blob.new(Marshal.dump(settings))
        rescue => e
          Lich::Messaging.msg("error", "--- Error: failed to serialize settings ---")
          Lich.log("--- Error: failed to serialize settings ---")
          Lich.log("#{e.message}\n#{e.backtrace.join("\n")}")
          return false
        end

        begin
          @table
            .insert_conflict(target: [:script, :scope], update: { hash: blob })
            .insert(script: script_name, scope: scope, hash: blob)
          return true
        rescue Sequel::DatabaseError => db_err
          Lich::Messaging.msg("error", "--- Database error while saving settings ---")
          Lich.log("--- Database error while saving settings ---")
          Lich.log("#{db_err.message}\n#{db_err.backtrace.join("\n")}")
        rescue => e
          Lich::Messaging.msg("error", "--- Unexpected error while saving settings ---")
          Lich.log("--- Unexpected error while saving settings ---")
          Lich.log("#{e.message}\n#{e.backtrace.join("\n")}")
        end

        false
      end
    end
  end
end
