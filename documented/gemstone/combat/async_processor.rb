# frozen_string_literal: true

#
# Async Combat Processor - single ordered worker thread fed by a Queue
#
# The downstream hook calls process_async from the game-stream thread, so
# enqueueing must never block. A single consumer thread guarantees chunks are
# processed in arrival order (status add/remove, UCS updates and damage all
# depend on ordering) and means creature instances are only ever mutated from
# one thread - no synchronization needed in Creature/CreatureInstance.
#

require_relative '../../util/gtk_compaction'

# Namespace for the Lich scripting engine.
module Lich
  # Namespace for GemStone IV scripting components.
  module Gemstone
    # Namespace for combat scripting and processing.
    module Combat
      # Single-threaded async combat processor that handles combat chunks in arrival order.
      #
      # Chunks are enqueued via #process_async from the game stream thread (O(1), non-blocking)
      # and consumed sequentially by a dedicated worker thread. This guarantees that status
      # updates, UCS changes, and damage events are processed in order, and ensures creature
      # instances are only mutated from one thread.
      #
      # The worker thread is automatically respawned if it dies (e.g., when the parent script
      # exits), since it can be spawned from a script thread but must survive the script's
      # lifetime to process events from the downstream hook.
      #
      # @see #process_async
      # @see #shutdown
      class AsyncProcessor
        # max_threads retained for call-site compatibility; processing is
        # intentionally single-threaded to preserve event ordering.
        def initialize(_max_threads = 1)
          @queue = Queue.new
          @processing = false
          @chunks_processed = 0
          @spawn_mutex = Mutex.new
          ensure_worker
        end

        # Enqueue a chunk; O(1), never blocks the game stream.
        #
        # Also revives the worker if it died: a worker spawned from a script
        # context (enable! via autostart/;e) belongs to that script's thread
        # group and is killed when the script exits. process_async runs on
        # the downstream-hook (game) thread, so a worker respawned here
        # survives script death.
        def process_async(chunk)
          return if chunk.empty?
          @queue.push(chunk)
          ensure_worker
          nil
        end

        # Drain remaining work and stop the worker.
        def shutdown
          respond "[Combat] Waiting for #{@queue.size} queued chunks..." if Tracker.debug?(:verbose)
          @queue.push(:shutdown)
          @worker.join

          # Force GC after shutdown to help with memory fragmentation.
          # Compaction is routed through Lich::Util::GtkCompaction, which
          # keeps it safe to use alongside gtk3.
          GC.start
          Lich::Util::GtkCompaction.safe_compact!
        end

        # Returns the current state of the async processor.
        #
        # @return [Hash] a hash with keys:
        #   - :active [Integer] 1 if currently processing a chunk, 0 otherwise
        #   - :queued [Integer] number of chunks waiting in the queue
        #   - :total [Integer] total chunks processed since initialization
        #   - :worker_alive [Boolean] true if the worker thread is running
        # @example
        #   processor.stats #=> { active: 1, queued: 0, total: 42, worker_alive: true }
        def stats
          {
            active: @processing ? 1 : 0,
            queued: @queue.size,
            total: @chunks_processed,
            worker_alive: !@worker.nil? && @worker.alive?
          }
        end

        private

        def ensure_worker
          return if @worker&.alive?

          @spawn_mutex.synchronize do
            next if @worker&.alive?

            respond '[Combat] Worker thread dead - respawning' if @worker && Tracker.debug?
            @worker = Thread.new { run_loop }
          end
        end

        def run_loop
          loop do
            chunk = @queue.pop
            break if chunk == :shutdown

            @processing = true
            started = Time.now
            begin
              Processor.process(chunk)

              elapsed = Time.now - started
              if elapsed > 0.5 && Tracker.debug?
                respond "[Combat] Processed #{chunk.size} lines in #{elapsed.round(3)}s"
              end
            rescue => e
              respond "[Combat] Processing error: #{e.message}" if Tracker.debug?(:verbose)
              respond e.backtrace.first(3) if Tracker.debug?(:verbose)
            ensure
              @processing = false
              @chunks_processed += 1
            end
          end
        end
      end
    end
  end
end
