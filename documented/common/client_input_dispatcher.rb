# frozen_string_literal: true

# Root namespace for the Lich 5 scripting engine.
module Lich
  # Namespace for common utilities shared across the Lich engine.
  module Common
    # Serializes command processing across primary and detachable frontends.
    module ClientInputDispatcher
      @mutex = Mutex.new

      # Serializes client command processing by synchronizing access with a mutex.
      #
      # Yields the client string to a block within a synchronized context, ensuring
      # that only one thread processes a command at a time. This prevents race conditions
      # when multiple frontends (primary and detachable) attempt to dispatch commands
      # concurrently.
      #
      # @param client_string [String] the raw command string from the client
      # @return [void]
      # @example
      #   ClientInputDispatcher.dispatch("cast spell") { |cmd| process_command(cmd) }
      # @api private
      def self.dispatch(client_string)
        @mutex.synchronize { yield client_string }
      end
    end
  end
end
