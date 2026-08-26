# Carve out class SharedBuffer
# 2024-06-13
# has rubocop Lint/HashCompareByIdentity errors that require research - temporarily disabled

require_relative 'throttle'

# Namespace for the Lich scripting engine.
module Lich
  # Namespace for common Lich utilities.
  module Common
    # Thread-safe circular buffer for sharing lines between reader threads.
    #
    # Each calling thread maintains its own position in the buffer, allowing
    # independent consumers to read at different speeds. The buffer automatically
    # discards old entries when it exceeds {#max_size}, and periodically removes
    # index entries for dead threads to prevent memory leaks.
    #
    # @see Throttle
    class SharedBuffer
      attr_accessor :max_size

      # Creates a new shared buffer.
      #
      # @param args [Hash] optional configuration
      # @option args [Integer] :max_size (500) maximum number of lines to retain
      # @return [void]
      def initialize(args = {})
        @buffer = Array.new
        @buffer_offset = 0
        @buffer_index = Hash.new
        @buffer_mutex = Mutex.new
        @max_size = args[:max_size] || 500
        # Sweeps dead-thread entries from @buffer_index (keyed by
        # Thread#object_id, previously never pruned) at most once every 60s.
        @cleanup_throttle = Throttle.new(60.0)
        # return self # rubocop does not like this - Lint/ReturnInVoidContext
      end

      # Waits for and returns the next line from the buffer for the calling thread.
      #
      # Blocks with {sleep} 0.05s until a line is available. On first call, registers
      # the thread and initializes its position to the end of the buffer.
      #
      # @return [String, nil] the next buffered line, or nil if the buffer is empty
      # @note If the thread's position has fallen behind (line was deleted due to
      #   buffer overflow), silently jumps forward to the oldest available line.
      # @example
      #   # In a reader thread
      #   line = buffer.gets  #=> "You say, \"hello\""
      def gets
        thread_id = Thread.current.object_id
        if @buffer_index[thread_id].nil?
          @buffer_mutex.synchronize { @buffer_index[thread_id] = (@buffer_offset + @buffer.length) }
          maybe_cleanup_threads
        end
        if (@buffer_index[thread_id] - @buffer_offset) >= @buffer.length
          sleep 0.05 while ((@buffer_index[thread_id] - @buffer_offset) >= @buffer.length)
        end
        line = nil
        @buffer_mutex.synchronize {
          if @buffer_index[thread_id] < @buffer_offset
            @buffer_index[thread_id] = @buffer_offset
          end
          line = @buffer[@buffer_index[thread_id] - @buffer_offset]
        }
        @buffer_index[thread_id] += 1
        return line
      end

      # Returns the next line from the buffer for the calling thread, or nil if
      # no line is ready.
      #
      # Non-blocking variant of {#gets}: returns immediately. On first call, registers
      # the thread and initializes its position to the end of the buffer.
      #
      # @return [String, nil] the next buffered line, or nil if none is available
      # @note If the thread's position has fallen behind (line was deleted due to
      #   buffer overflow), silently jumps forward to the oldest available line.
      # @example
      #   # In a reader thread
      #   line = buffer.gets?  #=> "You say, \"hello\"" or nil
      def gets?
        thread_id = Thread.current.object_id
        if @buffer_index[thread_id].nil?
          @buffer_mutex.synchronize { @buffer_index[thread_id] = (@buffer_offset + @buffer.length) }
          maybe_cleanup_threads
        end
        if (@buffer_index[thread_id] - @buffer_offset) >= @buffer.length
          return nil
        end

        line = nil
        @buffer_mutex.synchronize {
          if @buffer_index[thread_id] < @buffer_offset
            @buffer_index[thread_id] = @buffer_offset
          end
          line = @buffer[@buffer_index[thread_id] - @buffer_offset]
        }
        @buffer_index[thread_id] += 1
        return line
      end

      # Returns all available lines for the calling thread and advances to the end.
      #
      # Equivalent to calling {#gets?} repeatedly until nil. On first call, registers
      # the thread and initializes its position to the end of the buffer.
      #
      # @return [Array<String>] all buffered lines not yet read by this thread,
      #   or an empty array if none are available
      # @note If the thread's position has fallen behind (line was deleted due to
      #   buffer overflow), silently jumps forward to the oldest available line.
      # @example
      #   # In a reader thread
      #   lines = buffer.clear  #=> ["You say, \"hello\"", "Person says, \"hi\""]
      def clear
        thread_id = Thread.current.object_id
        if @buffer_index[thread_id].nil?
          @buffer_mutex.synchronize { @buffer_index[thread_id] = (@buffer_offset + @buffer.length) }
          maybe_cleanup_threads
          return Array.new
        end
        if (@buffer_index[thread_id] - @buffer_offset) >= @buffer.length
          return Array.new
        end

        lines = Array.new
        @buffer_mutex.synchronize {
          if @buffer_index[thread_id] < @buffer_offset
            @buffer_index[thread_id] = @buffer_offset
          end
          lines = @buffer[(@buffer_index[thread_id] - @buffer_offset)..-1]
          @buffer_index[thread_id] = (@buffer_offset + @buffer.length)
        }
        return lines
      end

      # rubocop:disable Lint/HashCompareByIdentity
      # Resets the calling thread's position to the beginning of the buffer.
      #
      # The next call to {#gets}, {#gets?}, or {#clear} will return the oldest
      # available line. On first call, registers the thread.
      #
      # @return [SharedBuffer] self
      # @example
      #   # In a reader thread, replay the buffer from the start
      #   buffer.rewind.gets  #=> oldest line
      def rewind
        # Hold the mutex: a first-call rewind adds a new key, which must not
        # race a concurrent cleanup_threads delete_if.
        @buffer_mutex.synchronize { @buffer_index[Thread.current.object_id] = @buffer_offset }
        return self
      end

      # rubocop:enable Lint/HashCompareByIdentity
      # Appends a line to the buffer and removes old lines if the buffer exceeds max_size.
      #
      # The line is frozen to prevent accidental mutation by readers. Old lines are
      # removed from the front (FIFO) as needed.
      #
      # @param line [String] the line to append; will be duplicated and frozen
      # @return [SharedBuffer] self
      # @example
      #   buffer.update("You say, \"hello\"")
      def update(line)
        @buffer_mutex.synchronize {
          fline = line.dup
          fline.freeze
          @buffer.push(fline)
          while (@buffer.length > @max_size)
            @buffer.shift
            @buffer_offset += 1
          end
        }
        return self
      end

      # Removes @buffer_index entries whose thread is no longer alive.
      # Snapshots the live thread ids once rather than recomputing them per
      # entry, and holds the mutex so it cannot race with a concurrent reader
      # mutating the hash.
      def cleanup_threads
        @buffer_mutex.synchronize {
          live_ids = Thread.list.map(&:object_id)
          @buffer_index.delete_if { |k, _v| !live_ids.include?(k) }
        }
        return self
      end

      # Throttled automatic {#cleanup_threads}, invoked from the
      # thread-registration path so dead-thread entries do not accumulate over a
      # long session. Must be called outside @buffer_mutex (cleanup_threads
      # acquires it; Ruby mutexes are not reentrant).
      def maybe_cleanup_threads
        @cleanup_throttle.run { cleanup_threads }
      end
      private :maybe_cleanup_threads
    end
  end
end
