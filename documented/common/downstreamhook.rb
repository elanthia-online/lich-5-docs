# Carve out from lich.rbw
# class DownstreamHook 2024-06-13

require_relative 'hook_registry'
require_relative 'script_death'

# Namespace for the Lich 5 scripting engine.
module Lich
  # Namespace for common Lich engine utilities and hooks.
  module Common
    # Registry of hooks that process server strings as they arrive from the game.
    #
    # DownstreamHook instances intercept and transform strings received from the game server
    # before they are delivered to scripts and the UI. Hooks are executed in registration order
    # and may modify, filter, or pass through the server string unchanged. Script-scoped hooks
    # are automatically removed when their owning script dies; persistent hooks remain.
    #
    # @api private
    class DownstreamHook
      extend HookRegistry

      @@downstream_hooks ||= Hash.new
      @@downstream_hook_sources ||= Hash.new
      @@downstream_hook_owners ||= Hash.new
      @@downstream_hook_persist ||= Hash.new

      # Per-class storage for the shared HookRegistry methods.
      def self._hooks
        @@downstream_hooks
      end

      # Returns the per-class storage mapping hook IDs to their source files.
      #
      # @return [Hash] a hash keyed by hook ID
      # @api private
      def self._hook_sources
        @@downstream_hook_sources
      end

      # Returns the per-class storage mapping hook IDs to their owning script object IDs.
      #
      # @return [Hash] a hash keyed by hook ID
      # @api private
      def self._hook_owners
        @@downstream_hook_owners
      end

      # Returns the per-class storage mapping hook IDs to their persistence flags.
      #
      # @return [Hash] a hash keyed by hook ID, with boolean values indicating whether each hook persists across script death
      # @api private
      def self._hook_persist
        @@downstream_hook_persist
      end

      # Processes a server string through all registered downstream hooks in order.
      #
      # Each hook is called with a duplicate of the string and may return a modified string,
      # nil, or raise an exception. If a hook raises an exception, it is removed from the registry,
      # the error is logged to the console, and execution continues with the next hook.
      # If any hook returns nil, processing stops immediately and nil is returned.
      #
      # @param server_string [String, nil] the string received from the game server
      # @return [String, nil] the processed string after all hooks have run, or nil if any hook returned nil
      # @api private
      def DownstreamHook.run(server_string)
        for key in @@downstream_hooks.keys
          return nil if server_string.nil?
          begin
            server_string = @@downstream_hooks[key].call(server_string.dup) if server_string.is_a?(String)
          rescue
            @@downstream_hooks.delete(key)
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
