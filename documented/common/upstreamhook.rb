# Carve out from lich.rbw
# UpstreamHook class 2024-06-13

require_relative 'hook_registry'
require_relative 'script_death'

# Namespace for the Lich 5 scripting engine.
module Lich
  # Namespace for shared engine utilities.
  module Common
    # Registry for hooks that intercept and transform text flowing from the game server to the client.
    #
    # Upstream hooks receive each line of unprocessed server output and may modify or suppress it.
    # Script-scoped hooks are automatically removed when a script dies; persistent hooks remain active.
    #
    # @api private
    class UpstreamHook
      extend HookRegistry

      @@upstream_hooks ||= Hash.new
      @@upstream_hook_sources ||= Hash.new
      @@upstream_hook_owners ||= Hash.new
      @@upstream_hook_persist ||= Hash.new

      # Per-class storage for the shared HookRegistry methods.
      def self._hooks
        @@upstream_hooks
      end

      # Returns the registry of script sources for upstream hooks.
      #
      # @return [Hash] maps hook keys to their defining scripts
      # @api private
      def self._hook_sources
        @@upstream_hook_sources
      end

      # Returns the registry of script owners for upstream hooks.
      #
      # @return [Hash] maps hook keys to their owning script object IDs
      # @api private
      def self._hook_owners
        @@upstream_hook_owners
      end

      # Returns the registry of persistence flags for upstream hooks.
      #
      # @return [Hash] maps hook keys to boolean persistence flags
      # @api private
      def self._hook_persist
        @@upstream_hook_persist
      end

      # Invokes all registered upstream hooks in sequence to transform server output.
      #
      # Each hook receives the client string and may modify or return nil to suppress it.
      # If a hook raises an error, it is removed from the registry, an error message is sent,
      # and processing stops.
      #
      # @param client_string [String] the text flowing from the game server to the client
      # @return [String, nil] the transformed text, or nil if any hook suppressed it
      # @api private
      def UpstreamHook.run(client_string)
        for key in @@upstream_hooks.keys
          begin
            client_string = @@upstream_hooks[key].call(client_string)
          rescue
            @@upstream_hooks.delete(key)
            respond "--- Lich: UpstreamHook: #{$!}"
            respond $!.backtrace.first
          end
          return nil if client_string.nil?
        end
        return client_string
      end

      # Apply this registry's per-script-death policy (remove script-scoped
      # hooks, keep persistent ones, warn on undeclared) so the kill path does
      # not need to know about UpstreamHook by name.
      ScriptDeath.on_death { |script| cleanup_on_death(script.object_id) }
    end
  end
end
