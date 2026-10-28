# Carve out from lich.rbw
# class DownstreamHook 2024-06-13

require_relative 'hook_registry'
require_relative 'script_death'

# Namespace for the Lich scripting engine.
module Lich
  # Common utilities and hook infrastructure for Lich scripts.
  module Common
    # Registry and execution engine for downstream hooks.
    #
    # Downstream hooks intercept and transform text received from the game server
    # before it reaches the game client display. Hooks are registered by script and
    # executed in priority order; each hook receives the server string, may modify
    # it, and passes the result to the next hook. If a hook raises an exception, it
    # is logged and removed; execution continues with remaining hooks.
    #
    # @see HookRegistry for registration/removal API
    class DownstreamHook
      extend HookRegistry

      @@downstream_hooks ||= Hash.new
      @@downstream_hook_sources ||= Hash.new
      @@downstream_hook_owners ||= Hash.new
      @@downstream_hook_persist ||= Hash.new
      @@downstream_hook_priorities ||= Hash.new

      # Per-class storage for the shared HookRegistry methods.
      def self._hooks
        @@downstream_hooks
      end

      # Returns the storage hash mapping downstream hook identifiers to their
      # source file and line number.
      #
      # @return [Hash] hook ID to source location metadata
      # @api private
      def self._hook_sources
        @@downstream_hook_sources
      end

      # Returns the storage hash mapping downstream hook identifiers to the
      # script object IDs that registered them.
      #
      # @return [Hash] hook ID to script object ID
      # @api private
      def self._hook_owners
        @@downstream_hook_owners
      end

      # Returns the storage hash tracking which downstream hooks should survive
      # script death (persist across unload).
      #
      # @return [Hash] hook ID to persistence flag
      # @api private
      def self._hook_persist
        @@downstream_hook_persist
      end

      # Returns the storage hash mapping downstream hook identifiers to their
      # numeric execution priority (lower number = earlier execution).
      #
      # @return [Hash] hook ID to priority value
      # @api private
      def self._hook_priorities
        @@downstream_hook_priorities
      end

      # Executes all registered downstream hooks in priority order against the
      # given server string.
      #
      # Each hook is invoked with a duplicate of the string to prevent unwanted
      # side effects. The transformed result flows to the next hook. If a hook raises
      # an exception, it is logged and removed from the registry; remaining hooks
      # continue executing.
      #
      # @param server_string [String, nil] the server output to process
      # @return [String, nil] the transformed server string, or nil if a hook returns nil
      # @example
      #   result = DownstreamHook.run("[Notice: Your spell is ready.]")  #=> processed string
      # @note Hooks that return nil halt the chain; downstream hooks do not execute.
      def DownstreamHook.run(server_string)
        for key in ordered_hook_names
          return nil if server_string.nil?
          begin
            action = hook_action(key)
            next unless action

            server_string = action.call(server_string.dup) if server_string.is_a?(String)
          rescue
            remove(key)
            respond "--- Lich: DownstreamHook: #{$!}"
            respond $!.backtrace.first
          end
        end
        return server_string
      end

      # Apply this registry's per-script-death policy (remove script-scoped
      # hooks, keep persistent ones, warn on undeclared) so the kill path does
      # not need to know about DownstreamHook by name.
      ScriptDeath.on_death { |script| cleanup_on_death(script.object_id) }
    end
  end
end
