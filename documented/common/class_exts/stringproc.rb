# Carve out from lich.rbw
# extension to StringProc class 2024-06-13

# Namespace for the Lich5 scripting engine.
module Lich
  # Namespace for shared utility classes used across Lich5.
  module Common
    # A wrapper around a Ruby source string that behaves like a Proc when evaluated.
    #
    # StringProc stores and normalizes source text, converting all `\r\n` and `\r` newlines to `\n`,
    # then delegates to a dynamically created Proc when called. It is used internally to serialize and
    # deserialize script code in the Lich5 system.
    #
    # @see #initialize for construction; #call to evaluate the wrapped source
    class StringProc
      ##
      # Create a StringProc that wraps the provided source text and normalizes CRLF and CR newlines to LF.
      # The input is converted with `to_s` and stored with all `\r\n` and `\r` replaced by `\n`.
      # @param [Object] string - The source text to wrap; will be converted to a String and normalized.
      # @param string [String, #to_s] Ruby source text to evaluate when called.
      def initialize(string)
        @string = string.to_s.gsub(/\r\n?/, "\n")
      end

      ##
      # Determine whether an empty Proc is an instance of the given class or module.
      # @param [Module] type - The class or module to check against.
      # @return [Boolean] `true` if a Proc is kind of `type`, `false` otherwise.
      def kind_of?(type)
        Proc.new {}.kind_of? type
      end

      # Returns the class of an empty Proc.
      #
      # @return [Class] always Proc
      # @api private
      def class
        Proc
      end

      # Evaluates the wrapped source string within a new Proc context.
      #
      # The source is eval'd inside a block, so it shares the binding of the current scope
      # when called. Arguments passed to this method are accepted but ignored.
      #
      # @param _a [Object] variable arguments, ignored
      # @return [Object] the result of evaluating the wrapped source
      # @raise [SyntaxError] if the wrapped source contains invalid Ruby syntax
      # @raise [NameError] if the source references an undefined variable or method
      # @raise [StandardError] for other errors raised during eval
      # @example
      #   sp = StringProc.new("1 + 2")
      #   sp.call #=> 3
      def call(*_a)
        proc { eval(@string) }.call
      end

      # Returns the normalized source string for serialization.
      #
      # The optional depth parameter is accepted but ignored; it is provided for compatibility
      # with Ruby's marshaling protocol.
      #
      # @param _d [Integer, nil] depth parameter, ignored
      # @return [String] the wrapped source text with all newlines normalized to `\n`
      # @api private
      def _dump(_d = nil)
        @string
      end

      # Returns a string representation of this StringProc instance.
      #
      # @return [String] a string in the format `StringProc.new(...)` with the wrapped source inspected
      # @example
      #   StringProc.new("x = 1").inspect #=> "StringProc.new(\"x = 1\")"
      def inspect
        "StringProc.new(#{@string.inspect})"
      end

      # Converts this StringProc to a JSON-compatible representation as a Lich5 inline command.
      #
      # The source is serialized as a command string prefixed with `;e ` (inline eval), then
      # converted to JSON. Additional arguments are passed to the String#to_json method.
      #
      # @param args [Object] variable arguments forwarded to String#to_json
      # @return [String] JSON-encoded representation of the `;e <source>` command
      # @api private
      def to_json(*args)
        ";e #{_dump}".to_json(args)
      end

      # Reconstructs a StringProc instance from its serialized form.
      #
      # This method is part of Ruby's marshaling protocol, called automatically when unmarshaling
      # a StringProc object. It creates a new instance from the given source string.
      #
      # @param string [String] the normalized source text
      # @return [StringProc] a new StringProc instance wrapping the provided source
      # @api private
      def StringProc._load(string)
        StringProc.new(string)
      end
    end
  end
end
