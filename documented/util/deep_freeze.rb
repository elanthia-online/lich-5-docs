# frozen_string_literal: true

# Namespace for the Lich 5 scripting engine.
module Lich
  # Namespace for utility functions.
  module Util
    # Recursively freezes Arrays, Hashes, and their nested contents.
    #
    # @param value [Object] object to freeze
    # @return [Object] the original object after recursive freezing
    def self.deep_freeze(value)
      deep_freeze_value(value, {}.compare_by_identity)
    end

    # Recursively freezes a single value and all nested Arrays and Hashes, tracking visited objects to handle cycles.
    #
    # @param value [Object] object to freeze
    # @param seen [Hash] identity-based Hash tracking already-frozen objects to prevent infinite recursion
    # @return [Object] the original object after recursive freezing
    # @api private
    def self.deep_freeze_value(value, seen)
      case value
      when Hash
        return value if seen.key?(value)

        seen[value] = true
        value.each do |key, item|
          deep_freeze_value(key, seen)
          deep_freeze_value(item, seen)
        end
      when Array
        return value if seen.key?(value)

        seen[value] = true
        value.each { |item| deep_freeze_value(item, seen) }
      end
      value.freeze
    end
    private_class_method :deep_freeze_value
  end
end
