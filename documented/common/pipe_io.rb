# frozen_string_literal: true

# Namespace for the Lich 5 scripting engine.
module Lich
  # Shared utilities for Lich 5.
  module Common
    # Duplex IO adapter that lets stdin/stdout stand in for a front-end client
    # socket in --pipe mode. Reads come from +input+ ($stdin), writes go to
    # +output+ ($stdout).
    #
    # Designed to be wrapped in a SynchronizedSocket, exactly like the real
    # client TCPSocket. The rest of the codebase then talks to $_CLIENT_ the
    # same way it always does (#gets / #write / #puts / #alive? / #close).
    #
    # Liveness is defined as "have not yet hit EOF on the input stream":
    # once #gets returns nil (the upstream pipe closed), #closed? returns true,
    # so SynchronizedSocket#alive? (@alive && !delegate.closed?) flips to false
    # and the normal disconnect/shutdown path runs.
    class PipeIO
      # Creates a duplex IO adapter wrapping standard input and output streams.
      #
      # @param input [IO] the input stream to read from (default: $stdin)
      # @param output [IO] the output stream to write to (default: $stdout)
      # @return [void]
      def initialize(input: $stdin, output: $stdout)
        @input  = input
        @output = output
        @output.sync = true # pipes must flush downstream output immediately
        @eof = false
      end

      # Client read loop calls this via SynchronizedSocket#method_missing.
      # Returns nil at EOF, which both ends the read loop and marks us closed.
      def gets(*args)
        line = @input.gets(*args)
        @eof = true if line.nil?
        line
      end

      # Writes data to the output stream.
      #
      # Delegates to the wrapped output stream's write method.
      #
      # @param args [Object] arguments passed to the output stream's write method
      # @return [Integer] the number of bytes written
      # @api private
      def write(*args, &block)
        @output.write(*args, &block)
      end

      # Writes lines to the output stream.
      #
      # Delegates to the wrapped output stream's puts method.
      #
      # @param args [Object] arguments passed to the output stream's puts method
      # @return [nil]
      # @api private
      def puts(*args, &block)
        @output.puts(*args, &block)
      end

      # Consulted (through SynchronizedSocket#alive?) by the server read loop's
      # retry guard and the client thread. True once the input stream is spent.
      def closed?
        @eof
      end

      # Marks the IO adapter as closed and flushes pending output.
      #
      # Sets the EOF flag to true, signaling to SynchronizedSocket#alive? that the
      # pipe is no longer active. The standard input and output file descriptors
      # themselves are not closed.
      #
      # @return [nil]
      def close
        @eof = true
        @output.flush rescue nil
        # Intentionally do not close the $stdin/$stdout file descriptors.
      end

      # Sets whether the output stream flushes after each write.
      #
      # @param value [Boolean] true to enable synchronous writes, false otherwise
      # @return [Boolean]
      # @api private
      def sync=(value)
        @output.sync = value
      end

      # Returns whether the output stream is in synchronous write mode.
      #
      # @return [Boolean] true if the output stream flushes after each write
      # @api private
      def sync
        @output.sync
      end
    end
  end
end
