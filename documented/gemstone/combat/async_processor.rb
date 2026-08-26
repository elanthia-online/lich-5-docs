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

# Namespace for the Lich5 scripting engine.
module Lich
  # Namespace for GemStone IV combat and entity tracking.
  module Gemstone
    # Namespace for combat processing and creature tracking.
    module Combat
      # Single-threaded worker that processes combat chunks in FIFO order from a queue.
      #
      # Chunks are enqueued from the game stream thread via #process_async, which never blocks.
      # A dedicated worker thread dequeues and processes chunks sequentially, preserving event
      # ordering required for accurate status tracking, UCS updates, and damage attribution.
      # Since all mutation of creature instances happens on one thread, no synchronization is
      # needed within Creature/CreatureInstance classes.
      #
      # @note Processing is intentionally single-threaded despite the max_threads parameter.
      class AsyncProcessor
        # max_threads retained for call-site compatibility; processing is
        # intentionally single-threaded to preserve event ordering.
        def initialize(_max_threads = 1)
          @queue = Queue.new
          @processing = false
          @chunks_processed = 0
          @worker = Thread.new { run_loop }
        end

        # Enqueue a chunk; O(1), never blocks the game stream.
        def process_async(chunk)
          return if chunk.empty?
          @queue.push(chunk)
          nil
        end

        # Drain remaining work and stop the worker.
        def shutdown
          respond "[Combat] Waiting for #{@queue.size} queued chunks..." if Tracker.debug?
          @queue.push(:shutdown)
          @worker.join

          # Force GC after shutdown to help with memory fragmentation.
          # Compaction is routed through Lich::Util::GtkCompaction, which
          # keeps it safe to use alongside gtk3.
          GC.start
          Lich::Util::GtkCompaction.safe_compact!
        end

        # Returns a snapshot of the processor's workload and health.
        #
        # @return [Hash] with keys :active (1 if processing, 0 otherwise), :queued (pending chunks),
        #   :total (cumulative chunks processed), :worker_alive (whether the worker thread is running)
        # @example
        #   processor.stats #=> {active: 0, queued: 3, total: 1205, worker_alive: true}
        def stats
          {
            active: @processing ? 1 : 0,
            queued: @queue.size,
            total: @chunks_processed,
            worker_alive: @worker.alive?
          }
        end

        private

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
              respond "[Combat] Processing error: #{e.message}" if Tracker.debug?
              respond e.backtrace.first(3) if Tracker.debug?
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
