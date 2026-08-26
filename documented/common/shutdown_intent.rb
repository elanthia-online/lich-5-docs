# frozen_string_literal: true

# Namespace for Lich 5, a Ruby scripting engine for GemStone IV and DragonRealms.
module Lich
  # Namespace for common utilities shared across Lich scripts.
  module Common
    # Detects explicit frontend shutdown commands.
    module ShutdownIntent
      # Regexp pattern that matches frontend shutdown commands.
      #
      # Matches "exit" or "quit" (case-insensitive) with optional whitespace,
      # optionally preceded by a `<c>` XML tag marker. Anchored to match the entire string.
      #
      # @return [Regexp] pattern for shutdown command detection
      # @example
      #   ShutdownIntent::USER_EXIT_COMMAND.match?("exit")      #=> true
      #   ShutdownIntent::USER_EXIT_COMMAND.match?("QUIT")      #=> true
      #   ShutdownIntent::USER_EXIT_COMMAND.match?("  <c> exit") #=> true
      #   ShutdownIntent::USER_EXIT_COMMAND.match?("stand")     #=> false
      # @see .user_exit_command?
      USER_EXIT_COMMAND = /\A\s*(?:<c>)?\s*(?:exit|quit)\s*\z/i

      # Detects whether a client string is an explicit frontend shutdown command.
      #
      # Returns true if the string matches an exit or quit command, false otherwise.
      # Safely handles nil input by returning false.
      #
      # @param client_string [String, nil] the client input to test
      # @return [Boolean] true if the string matches a shutdown command
      # @example
      #   ShutdownIntent.user_exit_command?("exit")  #=> true
      #   ShutdownIntent.user_exit_command?("quit")  #=> true
      #   ShutdownIntent.user_exit_command?(nil)     #=> false
      #   ShutdownIntent.user_exit_command?("stand") #=> false
      # @see USER_EXIT_COMMAND
      def self.user_exit_command?(client_string)
        return false if client_string.nil?

        USER_EXIT_COMMAND.match?(client_string.to_s)
      end
    end
  end
end
