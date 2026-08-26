# Namespace for the Lich scripting engine and its standard library.
module Lich
  # Namespace for common functionality shared across Lich scripts.
  module Common
    # Namespace for account and character information retrieved from the game server.
    #
    # Stores the account name, current character, subscription type, game code,
    # and the list of available characters on the account.
    module Account
      @@name ||= nil
      @@subscription ||= nil
      @@game_code ||= nil
      @@members ||= {}
      @@character ||= nil

      # Returns the account name.
      #
      # @return [String, nil] the account name, or nil if not yet initialized
      # @example
      #   Lich::Common::Account.name #=> "MyAccountName"
      def self.name
        @@name
      end

      # Sets the account name.
      #
      # @param value [String] the account name
      # @return [String] the assigned value
      def self.name=(value)
        @@name = value
      end

      # Returns the name of the currently logged-in character.
      #
      # @return [String, nil] the character name, or nil if not yet initialized
      # @example
      #   Lich::Common::Account.character #=> "Zephyr"
      def self.character
        @@character
      end

      # Sets the name of the currently logged-in character.
      #
      # @param value [String] the character name
      # @return [String] the assigned value
      def self.character=(value)
        @@character = value
      end

      # Returns the subscription type for the account.
      #
      # @return [String, nil] the subscription type ("NORMAL", "PREMIUM", "TRIAL", "INTERNAL", or "FREE"), or nil if not yet set
      # @example
      #   Lich::Common::Account.subscription #=> "PREMIUM"
      def self.subscription
        @@subscription
      end

      # Returns the account type from the game server, available only in GemStone IV.
      #
      # Queries Infomon for the account type via the "account.type" key.
      #
      # @return [String, nil] the account type string, or nil if not in GemStone IV or if Infomon returns nil
      # @api private
      def self.type
        if XMLData.game.is_a?(String) && XMLData.game =~ /^GS/
          Infomon.get("account.type")
        end
      end

      # Sets the subscription type, extracting the recognized type from the input string.
      #
      # Only stores the subscription type if the value contains one of the recognized types:
      # "NORMAL", "PREMIUM", "TRIAL", "INTERNAL", or "FREE". The entire matched word is
      # extracted and stored; the rest of the input is ignored.
      #
      # @param value [String] a string containing a subscription type keyword
      # @return [String, nil] the extracted subscription type, or the original @@subscription if no match is found
      def self.subscription=(value)
        if value =~ /(NORMAL|PREMIUM|TRIAL|INTERNAL|FREE)/
          @@subscription = Regexp.last_match(1)
        end
      end

      # Returns the game code identifying the current game (GemStone IV or DragonRealms).
      #
      # @return [String, nil] the game code, or nil if not yet initialized
      # @example
      #   Lich::Common::Account.game_code #=> "GS"
      def self.game_code
        @@game_code
      end

      # Sets the game code.
      #
      # @param value [String] the game code
      # @return [String] the assigned value
      def self.game_code=(value)
        @@game_code = value
      end

      # Returns a hash mapping character codes to character names for all characters on the account.
      #
      # @return [Hash] a hash with character codes as keys and character names as values; empty if not yet initialized
      # @example
      #   Lich::Common::Account.members #=> {"1" => "Zephyr", "2" => "Elanthia"}
      def self.members
        @@members
      end

      # Parses and stores the members list from a game server response string.
      #
      # Expects a tab-delimited format: the first field is discarded (account data),
      # followed by character records of "code\tname". Extracts all character code/name pairs
      # into a hash.
      #
      # @param value [String] the raw member list string from the game server
      # @return [Hash] the parsed members hash
      # @example
      #   Lich::Common::Account.members = "C\t1\t0\t0\t0\t1\tZephyr\t2\tElanthia"
      #   Lich::Common::Account.members #=> {"1" => "Zephyr", "2" => "Elanthia"}
      def self.members=(value)
        potential_members = {}
        for code_name in value.sub(/^C\t[0-9]+\t[0-9]+\t[0-9]+\t[0-9]+[\t\n]/, '').scan(/[^\t]+\t[^\t\n]+/)
          char_code, char_name = code_name.split("\t")
          potential_members[char_code] = char_name
        end
        @@members = potential_members
      end

      # Returns the list of character names available on the account.
      #
      # @return [Array<String>] an array of character names; empty if no characters are stored
      # @example
      #   Lich::Common::Account.characters #=> ["Zephyr", "Elanthia"]
      def self.characters
        @@members.values
      end
    end
  end
end
