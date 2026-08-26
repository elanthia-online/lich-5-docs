# frozen_string_literal: true

# Namespace for the Lich 5 scripting engine.
module Lich
  # Namespace for shared utilities and hooks.
  module Common
    # Read-only hooks that run immediately after a complete line is read from
    # the game socket, before XML parsing, RawHook, DownstreamHook, or frontend
    # writes. Hooks intentionally run inline, like the existing hook chains, to
    # preserve exact reader-before-parser ordering.
    class SocketReadHook
      Event = Struct.new(:server_string, :received_at, :monotonic_received_at, keyword_init: true)

      @@hooks ||= {}
      @@hook_sources ||= {}
      @@mutex ||= Mutex.new

      # Registers a proc to run on every complete line read from the game socket.
      #
      # Hooks run inline before XML parsing and are invoked in registration order.
      # If a hook raises, it is automatically removed and logged; execution continues
      # with the next hook.
      #
      # @param name [String, Symbol] unique name for this hook; used with .remove
      # @param action [Proc, nil] the hook proc; if nil, the block is used instead
      # @yield a Proc that receives arguments based on arity:
      #   - 0 args: hook.call (no data)
      #   - 1 arg: hook.call(server_string)
      #   - 2+ args: hook.call(server_string, event)
      # @return [String] the hook name as a string
      # @raise [ArgumentError] if neither action nor block is a Proc
      # @example Register with a proc
      #   SocketReadHook.add("my_hook") { |line| puts line }
      # @example Register with an explicit proc
      #   action = ->(line) { puts line }
      #   SocketReadHook.add("my_hook", action)
      def self.add(name, action = nil, &block)
        action ||= block
        unless action.is_a?(Proc)
          raise ArgumentError, "SocketReadHook: not a Proc (#{action.inspect})"
        end

        @@mutex.synchronize do
          @@hook_sources[name.to_s] = current_source
          @@hooks[name.to_s] = action
        end
        name
      end

      # Registers a hook that persists for the daemon lifetime.
      #
      # Equivalent to .add; provided for API clarity when hooks are added from
      # daemon startup code.
      #
      # @param name [String, Symbol] unique name for this hook
      # @yield a Proc to run on each socket read
      # @return [String] the hook name as a string
      # @see .add
      def self.add_daemon_hook(name, &block)
        add(name, &block)
      end

      # Registers a hook that removes itself when the calling script exits.
      #
      # Calls .before_dying to schedule hook removal on script termination.
      # No-op if before_dying is not available (e.g., in non-script contexts).
      #
      # @param name [String, Symbol] unique name for this hook
      # @yield a Proc to run on each socket read
      # @return [String] the hook name as a string
      # @see .add
      def self.add_script_hook(name, &block)
        add(name, &block)
        before_dying { remove(name) } if defined?(before_dying)
        name
      end

      # Unregisters a hook by name.
      #
      # Safe to call on non-existent hook names; no error is raised.
      #
      # @param name [String, Symbol] the hook name
      # @return [void]
      def self.remove(name)
        @@mutex.synchronize do
          @@hook_sources.delete(name.to_s)
          @@hooks.delete(name.to_s)
        end
      end

      # Returns the names of all registered hooks.
      #
      # @return [Array<String>] hook names in registration order
      def self.list
        @@mutex.synchronize { @@hooks.keys.dup }
      end

      # Returns a mapping of hook names to the source that registered them.
      #
      # Source is the current script name, or 'core' for daemon/core hooks, or
      # 'Unknown' if the source could not be determined.
      #
      # @return [Hash<String, String>] hash of hook name => source
      def self.hook_sources
        @@mutex.synchronize { @@hook_sources.dup }
      end

      # Prints a formatted table of all registered hooks and their sources to
      # the foreground (via Lich::Messaging.mono).
      #
      # Useful for debugging hook registration during development.
      #
      # @return [void]
      def self.sources
        info_table = Terminal::Table.new :headings => ['Hook', 'Source'],
                                         :rows     => hook_sources.to_a,
                                         :style    => { :all_separators => true }
        Lich::Messaging.mono(info_table.to_s)
      end

      # Invokes all registered hooks with a newly-read server line.
      #
      # Hooks are run synchronously and in-order. The server_string argument is
      # frozen before passing to hooks to prevent accidental mutation. If any hook
      # raises an exception, that hook is removed, the error is logged, and
      # execution continues with the next hook.
      #
      # @param server_string [String] a complete line read from the game socket
      # @param received_at [Time] the wall-clock time the line was received (default: Time.now)
      # @param monotonic_received_at [Float] the monotonic clock time in seconds (default: current monotonic time)
      # @return [void]
      # @note Intended to be called only by the socket reader, immediately after parsing a newline.
      def self.run(server_string, received_at: Time.now, monotonic_received_at: monotonic_now)
        raw = server_string.dup.freeze
        event = Event.new(
          server_string: raw,
          received_at: received_at,
          monotonic_received_at: monotonic_received_at
        ).freeze

        entries.each do |name, action|
          invoke(action, raw, event)
        rescue StandardError => e
          remove(name)
          Lich.log "SocketReadHook #{name}: #{e.class}: #{e.message}\n\t#{e.backtrace&.first}"
        end
        nil
      end

      # @api private
      # Returns the current hook registry as an array of [name, action] pairs.
      #
      # @return [Array<Array>] hook entries copied from the internal registry
      def self.entries
        @@mutex.synchronize { @@hooks.to_a }
      end

      # @api private
      # Determines the script or core source of the calling code.
      #
      # @return [String] the script name, 'core', or 'Unknown' on error
      def self.current_source
        if defined?(Script) && Script.respond_to?(:current) && Script.current
          Script.current.name || 'Unknown'
        else
          'core'
        end
      rescue StandardError
        'Unknown'
      end

      # @api private
      # Calls a hook proc, adapting the argument count to its arity.
      #
      # Lambdas are called with the exact arity they declare; procs are called
      # with both raw and event arguments.
      #
      # @param action [Proc] the hook proc
      # @param raw [String] the frozen server line
      # @param event [Event] the event struct with timing metadata
      # @return [Object] the return value of the hook (not used by caller)
      # @see Event
      def self.invoke(action, raw, event)
        if action.lambda?
          case action.arity
          when 0
            action.call
          when 1
            action.call(raw)
          else
            action.call(raw, event)
          end
        else
          action.call(raw, event)
        end
      end

      # @api private
      # Returns the current monotonic clock time for measuring elapsed time.
      #
      # @return [Float] seconds since process start
      def self.monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      private_class_method :entries, :current_source, :invoke, :monotonic_now
    end
  end
end
