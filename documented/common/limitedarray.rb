# Carve out from lich.rbw
# class LimitedArray 2024-06-13

# Namespace for Lich 5, a Ruby scripting engine for text-based games.
module Lich
  # Namespace for common utility classes and modules.
  module Common
    # Bounded script buffer with condition-variable-backed blocking reads.
    class LimitedArray < Array
      # Mutating Array methods that require synchronization in {LimitedArray}.
      #
      # @return [Array<Symbol>] list of method names that modify the array
      SYNCHRONIZED_ARRAY_MUTATORS = %i[
        collect! compact! delete delete_at delete_if filter! keep_if map! pop
        reject! reverse! rotate! select! shuffle! slice! sort! sort_by! uniq!
      ].freeze
      # Subset of {SYNCHRONIZED_ARRAY_MUTATORS} that return an Enumerator when called without a block.
      #
      # @return [Array<Symbol>] list of method names that support lazy evaluation
      ENUMERATOR_MUTATORS = %i[collect! delete_if filter! keep_if map! reject! select! sort_by!].freeze

      # Unbound reference to Array#push, used to bypass overrides in synchronized operations.
      #
      # @return [UnboundMethod]
      RAW_PUSH    = Array.instance_method(:push)
      # Unbound reference to Array#unshift, used to bypass overrides in synchronized operations.
      #
      # @return [UnboundMethod]
      RAW_UNSHIFT = Array.instance_method(:unshift)
      # Unbound reference to Array#shift, used to bypass overrides in synchronized operations.
      #
      # @return [UnboundMethod]
      RAW_SHIFT   = Array.instance_method(:shift)
      # Unbound reference to Array#pop, used to bypass overrides in synchronized operations.
      #
      # @return [UnboundMethod]
      RAW_POP     = Array.instance_method(:pop)
      # Unbound reference to Array#empty?, used to bypass overrides in synchronized operations.
      #
      # @return [UnboundMethod]
      RAW_EMPTY   = Array.instance_method(:empty?)
      # Unbound reference to Array#length, used to bypass overrides in synchronized operations.
      #
      # @return [UnboundMethod]
      RAW_LENGTH  = Array.instance_method(:length)
      # Unbound reference to Array#clear, used to bypass overrides in synchronized operations.
      #
      # @return [UnboundMethod]
      RAW_CLEAR   = Array.instance_method(:clear)
      # Unbound reference to Array#dup, used to bypass overrides in synchronized operations.
      #
      # @return [UnboundMethod]
      RAW_DUP     = Array.instance_method(:dup)

      # Global mutex protecting initialization of per-instance synchronization primitives.
      #
      # @return [Mutex]
      # @api private
      INIT_MUTEX = Mutex.new

      # Initializes a bounded array with a default size of 200 elements.
      #
      # @param size [Integer] initial capacity; excess elements are trimmed from the front
      # @param obj [Object] initial value to fill; optional
      # @example
      #   buf = Lich::Common::LimitedArray.new(5)
      #   buf.max_size #=> 200
      def initialize(size = 0, obj = nil)
        @max_size = 200
        super
        trim_front_locked
      end

      # Returns the maximum number of elements this array will hold.
      #
      # @return [Integer] the size limit
      def max_size
        synchronize { @max_size }
      end

      # Sets the maximum number of elements, trimming the front if necessary.
      #
      # @param value [Integer] the new size limit, must be positive
      # @return [Integer] the new max_size
      # @raise [ArgumentError] if value is not a positive Integer
      def max_size=(value)
        unless value.is_a?(Integer) && value.positive?
          raise ArgumentError, 'max_size must be a positive Integer'
        end

        synchronize do
          @max_size = value
          trim_front_locked
        end
      end

      # Appends elements to the end of the array and trims the front if it exceeds max_size.
      #
      # Broadcasts to any threads waiting in {#wait_shift}.
      #
      # @param lines [Object] one or more elements to append
      # @return [self]
      # @example
      #   buf = Lich::Common::LimitedArray.new
      #   buf.push("line 1", "line 2")
      def push(*lines)
        synchronize do
          result = RAW_PUSH.bind_call(self, *lines)
          trim_front_locked
          condition.broadcast unless lines.empty?
          result
        end
      end
      alias_method :<<, :push
      alias_method :append, :push

      # Prepends elements to the beginning of the array and trims the back if it exceeds max_size.
      #
      # Broadcasts to any threads waiting in {#wait_shift}.
      #
      # @param lines [Object] one or more elements to prepend
      # @return [self]
      # @example
      #   buf = Lich::Common::LimitedArray.new
      #   buf.unshift("first", "second")
      def unshift(*lines)
        synchronize do
          result = RAW_UNSHIFT.bind_call(self, *lines)
          RAW_POP.bind_call(self) while RAW_LENGTH.bind_call(self) > @max_size
          condition.broadcast unless lines.empty?
          result
        end
      end
      alias_method :prepend, :unshift

      # Concatenates another array and trims the front if it exceeds max_size.
      #
      # @param other [Array] the array to concatenate
      # @return [self]
      def concat(other)
        bounded_mutation(:concat, other)
      end

      # Replaces the entire array contents and trims the front if it exceeds max_size.
      #
      # @param other [Array] the replacement contents
      # @return [self]
      def replace(other)
        bounded_mutation(:replace, other)
      end

      # Inserts elements at the given index and trims the front if it exceeds max_size.
      #
      # @param index [Integer] the insertion point
      # @param objects [Object] one or more elements to insert
      # @return [self]
      def insert(index, *objects)
        bounded_mutation(:insert, index, *objects)
      end

      # Sets elements by index or range and trims the front if it exceeds max_size.
      #
      # @param args [Object] index/range and value(s) to assign
      # @return [Object] the assigned value(s)
      def []=(*args)
        bounded_mutation(:[]=, *args)
      end

      # Fills the array with a value or block result and trims the front if it exceeds max_size.
      #
      # @param args [Object] value or range and value
      # @yield block to generate values
      # @return [self]
      def fill(*args, &block)
        bounded_mutation(:fill, *args, &block)
      end

      # Recursively flattens nested arrays and trims the front if it exceeds max_size.
      #
      # @param args [Integer] optional depth limit
      # @return [self, nil] self if the array changed, nil otherwise
      def flatten!(*args)
        bounded_mutation(:flatten!, *args)
      end

      # Appends an element to the end of the array (alias for push).
      #
      # @param line [Object] the element to append
      # @return [self]
      def shove(line)
        push(line)
      end

      # Returns an empty array (placeholder for compatibility).
      #
      # @return [Array] always returns an empty array
      # @api private
      def history
        Array.new
      end

      # Removes and returns the first element(s) from the front of the array.
      #
      # @param args [Integer] optional count of elements to remove
      # @return [Object, Array, nil] the removed element(s), or nil if empty
      def shift(*args)
        synchronize { RAW_SHIFT.bind_call(self, *args) }
      end

      # Returns whether the array is empty.
      #
      # @return [Boolean] true if the array has no elements
      def empty?
        synchronize { RAW_EMPTY.bind_call(self) }
      end

      # Removes all elements from the array.
      #
      # @return [self]
      def clear
        synchronize { RAW_CLEAR.bind_call(self) }
      end

      # Returns a shallow copy of the array.
      #
      # @return [Array] a new unsynchronized copy
      def dup
        synchronize { RAW_DUP.bind_call(self) }
      end

      # Wait for and remove the next item, returning nil when timeout expires.
      def wait_shift(timeout = nil)
        mutex.synchronize do
          deadline = monotonic_time + timeout.to_f if timeout
          while RAW_EMPTY.bind_call(self)
            remaining = deadline && deadline - monotonic_time
            return nil if remaining && remaining <= 0

            condition.wait(mutex, remaining)
          end
          RAW_SHIFT.bind_call(self)
        end
      end

      # Removes and returns the first element, or nil if the array is empty (non-blocking).
      #
      # @return [Object, nil] the removed element or nil
      def try_shift
        synchronize do
          return nil if RAW_EMPTY.bind_call(self)

          RAW_SHIFT.bind_call(self)
        end
      end

      # Returns a snapshot of the current array and clears it in one atomic operation.
      #
      # @return [Array] a shallow copy of the array before clearing
      # @example
      #   buf = Lich::Common::LimitedArray.new
      #   buf.push(1, 2, 3)
      #   snapshot = buf.clear_snapshot
      #   snapshot #=> [1, 2, 3]
      #   buf.empty? #=> true
      def clear_snapshot
        synchronize do
          snapshot = RAW_DUP.bind_call(self)
          RAW_CLEAR.bind_call(self)
          snapshot
        end
      end

      SYNCHRONIZED_ARRAY_MUTATORS.each do |method_name|
        define_method(method_name) do |*args, &block|
          return enum_for(method_name, *args) if block.nil? && ENUMERATOR_MUTATORS.include?(method_name)

          synchronize do
            Array.instance_method(method_name).bind_call(self, *args, &block)
          end
        end
      end

      private

      def initialize_copy(original)
        super
        @mutex = Mutex.new
        @condition = ConditionVariable.new
      end

      def initialize_synchronization
        return if @mutex && @condition

        INIT_MUTEX.synchronize do
          @mutex ||= Mutex.new
          @condition ||= ConditionVariable.new
        end
      end

      def mutex
        initialize_synchronization
        @mutex
      end

      def condition
        initialize_synchronization
        @condition
      end

      def synchronize(&block)
        mutex.synchronize(&block)
      end

      def bounded_mutation(method_name, *args, &block)
        synchronize do
          result = Array.instance_method(method_name).bind_call(self, *args, &block)
          trim_front_locked
          condition.broadcast unless RAW_EMPTY.bind_call(self)
          result
        end
      end

      def trim_front_locked
        RAW_SHIFT.bind_call(self) while RAW_LENGTH.bind_call(self) > @max_size
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
