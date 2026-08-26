# Carve out module Buffer
# 2024-06-13
# has rubocop error Lint/HashCompareByIdentity - cop disabled until reviewed

require_relative 'throttle'

# Namespace for the Lich 5 scripting engine.
module Lich
  # Namespace for common utilities shared across Lich 5.
  module Common
    # Thread-safe circular buffer for game server output and script input streams.
    #
    # Buffer maintains a fixed-size ring of lines, each tagged with a stream identifier
    # that indicates the source (game server downstream output, upstream commands, script
    # output, etc.). Each thread maintains its own read cursor and stream filter, allowing
    # independent consumption of the shared buffer while preserving thread safety via mutex.
    #
    # Threads are registered automatically on their first call to .gets, .gets?, .rewind,
    # or .clear; stale entries are cleaned up automatically via throttled sweeps to prevent
    # unbounded memory growth in long-running sessions.
    module Buffer
      DOWNSTREAM_STRIPPED = 1
      DOWNSTREAM_RAW      = 2
      DOWNSTREAM_MOD      = 4
      UPSTREAM            = 8
      UPSTREAM_MOD        = 16
      SCRIPT_OUTPUT       = 32
      @@index             = Hash.new
      @@streams           = Hash.new
      @@mutex             = Mutex.new
      @@offset            = 0
      @@buffer            = Array.new
      @@max_size          = 3000
      # @@index / @@streams are keyed by Thread#object_id and were never pruned,
      # so every thread that ever read the buffer leaked an entry that outlived
      # it. maybe_cleanup sweeps dead-thread entries from the registration path,
      # at most once every 60s via this throttle.
      @@cleanup_throttle  = Throttle.new(60.0)
      # Reads the next line from the buffer for the calling thread, blocking until one
      # is available.
      #
      # Filters the buffer by the calling thread's current stream mask, skipping lines that
      # do not match. If the thread's cursor has fallen behind the buffer (e.g., due to
      # buffer rotation), it is advanced to the oldest line. Registers the thread on first
      # call with a default stream filter of {DOWNSTREAM_STRIPPED}.
      #
      # @return [Object] a line object with .stream and text attributes
      # @example
      #   line = Buffer.gets
      #   # => line.stream => 1, line => "You scan the area...\n"
      def Buffer.gets
        thread_id = Thread.current.object_id
        if @@index[thread_id].nil?
          @@mutex.synchronize {
            @@index[thread_id] = (@@offset + @@buffer.length)
            @@streams[thread_id] ||= DOWNSTREAM_STRIPPED
          }
          maybe_cleanup
        end
        line = nil
        loop {
          if (@@index[thread_id] - @@offset) >= @@buffer.length
            sleep 0.05 while ((@@index[thread_id] - @@offset) >= @@buffer.length)
          end
          @@mutex.synchronize {
            if @@index[thread_id] < @@offset
              @@index[thread_id] = @@offset
            end
            line = @@buffer[@@index[thread_id] - @@offset]
          }
          @@index[thread_id] += 1
          break if ((line.stream & @@streams[thread_id]) != 0)
        }
        return line
      end

      # Reads the next line from the buffer for the calling thread, returning nil if no
      # matching line is available instead of blocking.
      #
      # Filters the buffer by the calling thread's current stream mask, skipping lines that
      # do not match. If the thread's cursor has fallen behind the buffer (e.g., due to
      # buffer rotation), it is advanced to the oldest line. Registers the thread on first
      # call with a default stream filter of {DOWNSTREAM_STRIPPED}.
      #
      # @return [Object, nil] a line object with .stream and text attributes, or nil if
      #   no matching line is available
      # @example
      #   line = Buffer.gets?
      #   # => line.stream => 1, line => "You scan the area...\n" OR nil
      def Buffer.gets?
        thread_id = Thread.current.object_id
        if @@index[thread_id].nil?
          @@mutex.synchronize {
            @@index[thread_id] = (@@offset + @@buffer.length)
            @@streams[thread_id] ||= DOWNSTREAM_STRIPPED
          }
          maybe_cleanup
        end
        line = nil
        loop {
          if (@@index[thread_id] - @@offset) >= @@buffer.length
            return nil
          end

          @@mutex.synchronize {
            if @@index[thread_id] < @@offset
              @@index[thread_id] = @@offset
            end
            line = @@buffer[@@index[thread_id] - @@offset]
          }
          @@index[thread_id] += 1
          break if ((line.stream & @@streams[thread_id]) != 0)
        }
        return line
      end

      # Resets the calling thread's read cursor to the oldest line in the buffer.
      #
      # Registers the thread with a default stream filter of {DOWNSTREAM_STRIPPED} if it
      # has not yet accessed the buffer. Acquires the mutex to prevent race conditions
      # during thread registration and cleanup.
      #
      # @return [self] the Buffer module
      # @example
      #   Buffer.rewind
      #   first_line = Buffer.gets
      def Buffer.rewind
        thread_id = Thread.current.object_id
        # Hold the mutex: for a thread whose first Buffer call is rewind this
        # adds new keys, which must not race a concurrent cleanup delete_if
        # (Ruby raises on a key added during iteration).
        @@mutex.synchronize {
          @@index[thread_id] = @@offset
          @@streams[thread_id] ||= DOWNSTREAM_STRIPPED
        }
        return self
      end

      # Reads all remaining lines from the buffer for the calling thread, returning them
      # as an array and advancing the cursor to the end.
      #
      # Filters the buffer by the calling thread's current stream mask, returning only lines
      # that match. If the thread's cursor has fallen behind the buffer (e.g., due to buffer
      # rotation), it is advanced to the oldest line. Registers the thread on first call with
      # a default stream filter of {DOWNSTREAM_STRIPPED}.
      #
      # @return [Array<Object>] an array of line objects matching the calling thread's
      #   stream filter, or an empty array if no matching lines remain
      # @example
      #   lines = Buffer.clear
      #   # => [line1, line2, line3]
      def Buffer.clear
        thread_id = Thread.current.object_id
        if @@index[thread_id].nil?
          @@mutex.synchronize {
            @@index[thread_id] = (@@offset + @@buffer.length)
            @@streams[thread_id] ||= DOWNSTREAM_STRIPPED
          }
          maybe_cleanup
        end
        lines = Array.new
        loop {
          if (@@index[thread_id] - @@offset) >= @@buffer.length
            return lines
          end

          line = nil
          @@mutex.synchronize {
            if @@index[thread_id] < @@offset
              @@index[thread_id] = @@offset
            end
            line = @@buffer[@@index[thread_id] - @@offset]
          }
          @@index[thread_id] += 1
          lines.push(line) if ((line.stream & @@streams[thread_id]) != 0)
        }
        return lines
      end

      # Appends a line to the buffer, optionally overriding its stream identifier.
      #
      # The line is duplicated and frozen before insertion to prevent external mutation.
      # If the buffer exceeds the maximum size (3000 lines), the oldest line is discarded
      # and the offset is incremented. Acquires the mutex for thread safety.
      #
      # @param line [Object] a line object with text and optional .stream attribute
      # @param stream [Integer, nil] optional stream identifier (a bitmask constant like
      #   DOWNSTREAM_STRIPPED) to set on the frozen copy; if nil, the line's existing
      #   stream is preserved
      # @return [self] the Buffer module
      # @example
      #   line = Object.new
      #   line.stream = Buffer::DOWNSTREAM_STRIPPED
      #   Buffer.update(line)
      #   # or
      #   Buffer.update(line, Buffer::UPSTREAM)
      def Buffer.update(line, stream = nil)
        @@mutex.synchronize {
          frozen_line = line.dup
          unless stream.nil?
            frozen_line.stream = stream
          end
          frozen_line.freeze
          @@buffer.push(frozen_line)
          while (@@buffer.length > @@max_size)
            @@buffer.shift
            @@offset += 1
          end
        }
        return self
      end

      # rubocop:disable Lint/HashCompareByIdentity
      # Returns the stream filter bitmask for the calling thread.
      #
      # The result is a bitmask composed of stream constants (DOWNSTREAM_STRIPPED,
      # DOWNSTREAM_RAW, etc.) that determines which lines the thread will receive from
      # .gets, .gets?, and .clear. Returns nil if the thread has never accessed the buffer.
      #
      # @return [Integer, nil] the stream filter bitmask, or nil if the thread is not
      #   registered
      # @example
      #   Buffer.streams #=> 1  (DOWNSTREAM_STRIPPED)
      #   Buffer.streams = Buffer::UPSTREAM
      #   Buffer.streams #=> 8
      def Buffer.streams
        @@mutex.synchronize { @@streams[Thread.current.object_id] }
      end

      # Sets the stream filter bitmask for the calling thread.
      #
      # The bitmask must be a non-zero Integer with at least one of the six stream bits set
      # (bits 0-5 corresponding to the six stream constants). Acquires the mutex to prevent
      # race conditions during thread registration and cleanup. Raises no exception on invalid
      # input; instead logs an error message via respond and returns nil.
      #
      # @param val [Integer] a non-zero bitmask composed of stream constants
      #   (DOWNSTREAM_STRIPPED, DOWNSTREAM_RAW, DOWNSTREAM_MOD, UPSTREAM, UPSTREAM_MOD,
      #   SCRIPT_OUTPUT)
      # @return [void] nil
      # @example
      #   Buffer.streams = Buffer::DOWNSTREAM_STRIPPED | Buffer::UPSTREAM
      #   Buffer.streams #=> 9
      def Buffer.streams=(val)
        if (!val.is_a?(Integer)) or ((val & 63) == 0)
          respond "--- Lich: error: invalid streams value\n\t#{$!.caller[0..2].join("\n\t")}"
        else
          # Hold the mutex: setting streams for a thread that has not registered
          # yet adds a new key, which must not race the cleanup delete_if sweep
          # (Ruby raises on a key added during iteration).
          @@mutex.synchronize { @@streams[Thread.current.object_id] = val }
        end
      end

      # rubocop:enable Lint/HashCompareByIdentity
      # Removes @@index / @@streams entries whose thread is no longer alive.
      # Snapshots the live thread ids once rather than recomputing them per
      # entry, and holds the mutex so it cannot race with a concurrent reader
      # mutating the same hashes.
      def Buffer.cleanup
        @@mutex.synchronize {
          live_ids = Thread.list.map(&:object_id)
          @@index.delete_if { |k, _v| !live_ids.include?(k) }
          @@streams.delete_if { |k, _v| !live_ids.include?(k) }
        }
        return self
      end

      # Throttled automatic {Buffer.cleanup}, invoked from the thread-registration
      # path so dead-thread entries do not accumulate over a long session. Must
      # be called outside @@mutex (cleanup acquires it; Ruby mutexes are not
      # reentrant).
      def Buffer.maybe_cleanup
        @@cleanup_throttle.run { cleanup }
      end
      private_class_method :maybe_cleanup
    end
  end
end
