# Carve out from lich.rbw
# UpstreamHook class 2024-06-13

require_relative 'hook_registry'
require_relative 'script_death'

# Namespace for the Lich 5 scripting engine and its public API.
module Lich
  # Namespace for core hook registries and script lifecycle management.
  module Common
    # Registry for hooks that process game server output before scripts receive it.
    #
    # UpstreamHook allows scripts to intercept and transform the raw XML stream from
    # the game server. Hooks are executed in priority order and receive the server
    # string; each hook can modify it before passing to the next. If a hook raises an
    # exception, it is removed and an error is logged, but processing continues.
    #
    # Hooks registered with UpstreamHook are removed when their owning script dies,
    # unless registered with persist: true.
    #
    # @see HookRegistry
    # @see ScriptDeath
    class UpstreamHook
      extend HookRegistry

      @@upstream_hooks ||= Hash.new
      @@upstream_hook_sources ||= Hash.new
      @@upstream_hook_owners ||= Hash.new
      @@upstream_hook_persist ||= Hash.new
      @@upstream_hook_priorities ||= Hash.new

      # Per-class storage for the shared HookRegistry methods.
      def self._hooks
        @@upstream_hooks
      end

      # Returns the per-class storage hash mapping hook keys to their source scripts.
      #
      # @return [Hash] hook key => source script identity
      # @api private
      def self._hook_sources
        @@upstream_hook_sources
      end

      # Returns the per-class storage hash mapping hook keys to their owning scripts.
      #
      # @return [Hash] hook key => script object_id
      # @api private
      def self._hook_owners
        @@upstream_hook_owners
      end

      # Returns the per-class storage hash tracking which hooks should survive script death.
      #
      # @return [Hash] hook key => Boolean (true if hook persists)
      # @api private
      def self._hook_persist
        @@upstream_hook_persist
      end

      # Returns the per-class storage hash mapping hook keys to their execution priorities.
      #
      # @return [Hash] hook key => priority Integer
      # @api private
      def self._hook_priorities
        @@upstream_hook_priorities
      end

      # Processes game server output through all registered upstream hooks in priority order.
      #
      # Executes each registered hook in priority order, passing the server output through
      # them sequentially. If a hook raises an exception, it is automatically removed and an
      # error is logged to the game window, but processing of remaining hooks continues.
      # If any hook returns nil, processing stops and nil is returned.
      #
      # @param client_string [String] the raw XML output from the game server
      # @return [String, nil] the transformed server output, or nil if processing was halted
      # @example
      #   upstream_output = Lich::Common::UpstreamHook.run(raw_server_xml)
      # @raise [StandardError] exceptions from individual hooks are caught and logged;
      #   the hook is removed but execution continues
      def UpstreamHook.run(client_string)
        for key in ordered_hook_names
          return nil if client_string.nil?
          begin
            action = hook_action(key)
            next unless action

            client_string = action.call(client_string)
          rescue
            remove(key)
            respond "--- Lich: UpstreamHook: #{$!}"
            respond $!.backtrace.first
          end
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
