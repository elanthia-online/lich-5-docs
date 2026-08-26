# frozen_string_literal: true

# Namespace for Lich 5, a Ruby scripting engine for GemStone IV and DragonRealms.
module Lich
  # Namespace for common utilities and abstractions shared across Lich 5.
  module Common
    # Thread-safe registry for clients sharing one detachable listener.
    class DetachableClientRegistry
      # Initializes the registry with an empty client list and mutex for thread safety.
      def initialize
        @clients = []
        @mutex = Mutex.new
      end

      # Registers a client with the registry, returning whether this is the first client.
      #
      # If the client is already registered, it is not added again. Clients are stored
      # in registration order. The registry is thread-safe via a mutex.
      #
      # @param client [Object] the client to register
      # @return [Boolean] true if the registry transitioned from empty to non-empty, false otherwise
      # @example
      #   registry = DetachableClientRegistry.new
      #   registry.register(client1) #=> true
      #   registry.register(client2) #=> false
      #   registry.register(client1) #=> false (already registered)
      def register(client)
        @mutex.synchronize do
          was_empty = @clients.empty?
          @clients << client unless @clients.include?(client)
          was_empty && !@clients.empty?
        end
      end

      # Returns whether the client was removed and whether the registry is now
      # empty. The pair lets lifecycle reporting happen outside the mutex.
      def unregister(client)
        @mutex.synchronize do
          removed = !@clients.delete(client).nil?
          [removed, @clients.empty?]
        end
      end

      # Returns a copy of the current client list.
      #
      # This is thread-safe and safe to iterate over without holding the mutex.
      #
      # @return [Array] a duplicate of the client list
      # @example
      #   clients = registry.snapshot
      #   clients.each { |client| client.notify }
      def snapshot
        @mutex.synchronize { @clients.dup }
      end

      # Returns the first registered client, or nil if the registry is empty.
      #
      # The primary client is the earliest registered; subsequent clients are considered
      # secondary listeners. This is thread-safe.
      #
      # @return [Object, nil] the primary client, or nil if no clients are registered
      def primary
        @mutex.synchronize { @clients.first }
      end

      # Returns whether the given client is the primary (first registered) client.
      #
      # Uses identity comparison, not equality. This is thread-safe.
      #
      # @param client [Object] the client to check
      # @return [Boolean] true if the client is the first registered client, false otherwise
      def primary?(client)
        @mutex.synchronize { @clients.first.equal?(client) }
      end

      # Returns the number of registered clients.
      #
      # @return [Integer] the count of clients
      def count
        @mutex.synchronize { @clients.length }
      end

      # Returns whether the registry has no registered clients.
      #
      # @return [Boolean] true if the client list is empty, false otherwise
      def empty?
        @mutex.synchronize { @clients.empty? }
      end

      # Removes all registered clients and returns the removed list.
      #
      # This atomically clears the registry and returns the clients that were removed.
      # This is thread-safe.
      #
      # @return [Array] the list of clients that were removed
      def remove_all
        @mutex.synchronize do
          clients = @clients.dup
          @clients.clear
          clients
        end
      end
    end
  end
end
