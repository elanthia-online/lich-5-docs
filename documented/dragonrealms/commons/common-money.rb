# frozen_string_literal: true

module Lich
  module DragonRealms
    module DRCM
      module_function

      # Strips XML tags and decodes common HTML entities from game output lines.
      # @param lines [Array<String>] Array of raw game output lines
      # @return [Array<String>] Array of non-empty, trimmed strings with XML removed
      # @see DRC.strip_xml Delegates to shared utility
      def strip_xml(lines)
        DRC.strip_xml(lines)
      end

      # Converts a copper value into an array of human-readable coin denominations.
      #
      # Breaks down the copper amount into plats, crowns, sovereigns, and remaining coppers,
      # returning only non-zero denominations.
      #
      # @param copper [Integer] the total copper value to minimize
      # @return [Array<String>] array of denomination strings, e.g. ["1 plat", "50 crowns"]
      # @example
      #   minimize_coins(5050) #=> ["1 plat", "50 crowns"]
      # @see DENOMINATIONS the constant that defines the coin hierarchy
      def minimize_coins(copper)
        DENOMINATIONS.inject([copper, []]) do |result, denomination|
          remaining = result.first
          display = result.last
          if remaining / denomination.first > 0
            display << "#{remaining / denomination.first} #{denomination.last}"
          end
          [remaining % denomination.first, display]
        end.last
      end

      # Convert an amount to copper given a denomination name (abbreviation permitted).
      # If denomination is nil/empty, assumes coppers and logs a warning.
      # Supports fractional amounts (e.g., '1.5 plat' = 15000 copper).
      def convert_to_copper(amount, denomination)
        denomination = denomination.to_s.strip
        unless denomination.empty?
          DENOMINATION_VALUES.each do |name, multiplier|
            return (amount.to_f * multiplier).to_i if name.start_with?(denomination.downcase)
          end
        end
        Lich::Messaging.msg('bold', "DRCM: Unknown denomination, assuming coppers: #{denomination}")
        amount.to_i
      end

      # Returns full canonical currency name from an abbreviation.
      # e.g., "k" -> "kronars", "li" -> "lirums"
      def get_canonical_currency(currency)
        CURRENCIES.find { |c| c.start_with?(currency) }
      end

      # Converts an amount between DR currencies, accounting for exchange fees.
      # Use a negative fee to calculate how much is needed to receive a target amount.
      # Use a positive fee to calculate how much will be received after the exchange.
      def convert_currency(amount, from, to, fee)
        if fee < 0
          ((amount / EXCHANGE_RATES[from][to]).ceil / (1 + fee)).ceil
        else
          ((amount * EXCHANGE_RATES[from][to]).ceil * (1 - fee)).floor
        end
      end

      # Returns the currency name for a given hometown.
      #
      # Looks up the currency from game data (e.g., "kronars" for Wehnimer's Landing).
      #
      # @param hometown_name [String] the hometown identifier
      # @return [String] the currency name, e.g. "kronars", "lirums", "dokoras"
      # @example
      #   hometown_currency("wehnimers_landing") #=> "kronars"
      # @see #town_currency alias for backward compatibility
      # @see #get_canonical_currency
      def hometown_currency(hometown_name)
        get_data('town')[hometown_name]['currency']
      end

      # Alias for backward compatibility - common-crafting.rb uses this name.
      def town_currency(town)
        hometown_currency(town)
      end

      # Queries the game and returns on-hand copper wealth for a specific currency.
      #
      # Sends the "wealth" command filtered by currency and parses the response.
      #
      # @param currency [String] the currency to check, e.g. "kronars"
      # @return [Integer] the copper value of on-hand wealth, or 0 if parsing fails
      # @example
      #   check_wealth("kronars") #=> 5000
      # @see #wealth queries for a specific hometown
      # @see #get_total_wealth queries all three currencies at once
      def check_wealth(currency)
        DRC.bput("wealth #{currency}", /\(\d+ copper #{currency}\)/i, /No #{currency}/i).scan(/\d+/).first.to_i
      end

      # Returns on-hand copper wealth for a given hometown.
      #
      # Derives the currency from the hometown, then checks wealth in that currency.
      #
      # @param hometown [String] the hometown identifier
      # @return [Integer] the copper value of on-hand wealth
      # @example
      #   wealth("wehnimers_landing") #=> 5000
      # @see #check_wealth queries by explicit currency
      # @see #get_total_wealth queries all currencies at once
      def wealth(hometown)
        check_wealth(hometown_currency(hometown))
      end

      # Captures total on-hand wealth across all three currencies.
      # Returns a hash of currency name => copper value.
      # Uses DRC.capture_to_prompt for reliable bounded capture.
      #
      # When the reply does not arrive in time, a bold message is printed and all
      # zeros are returned. The WEALTH reply ends on the prompt, which is how a
      # complete reply is told from one cut off by the timeout. A cut-off reply
      # prints a bold message and returns what was parsed, with 0 for any
      # currency whose line never arrived.
      def get_total_wealth
        wealth_lines, complete = DRC.capture_to_prompt('wealth', /^Wealth:/)

        result = { 'kronars' => 0, 'lirums' => 0, 'dokoras' => 0 }
        if wealth_lines.empty?
          Lich::Messaging.msg("bold", "DRCM: Failed to capture WEALTH output (timeout).")
          return result
        end

        unless complete
          Lich::Messaging.msg("bold", "DRCM: WEALTH output was cut off (timeout); the result is incomplete.")
        end

        strip_xml(wealth_lines).each do |line|
          match = line.match(WEALTH_COPPER_REGEX)
          next unless match

          result[match[:currency].downcase] = match[:coppers].to_i
        end

        result
      end

      # Ensures the character has a target copper amount on hand, withdrawing from the bank if needed.
      #
      # Checks current wealth; if insufficient, breaks down the deficit into coin denominations
      # and withdraws each amount from the bank using #withdraw_exact_amount?.
      # Uses the hometown from settings if not explicitly provided.
      #
      # @param copper [Integer] the target copper amount to have on hand
      # @param settings [OpenStruct] character settings, must include `hometown` and bank configuration
      # @param hometown [String, nil] the hometown to use (defaults to settings.hometown)
      # @return [Boolean] true if on-hand wealth meets or exceeds the target; false if any withdrawal failed
      # @example
      #   ensure_copper_on_hand(10000, settings) #=> true
      # @see #minimize_coins breaks down the deficit into denominations
      # @see #withdraw_exact_amount? performs individual withdrawals
      # @see #wealth queries current on-hand wealth
      def ensure_copper_on_hand(copper, settings, hometown = nil)
        hometown = settings.hometown if hometown.nil?

        on_hand = wealth(hometown)
        return true if on_hand >= copper

        withdrawals = minimize_coins(copper - on_hand)

        withdrawals.all? { |amount| withdraw_exact_amount?(amount, settings, hometown) }
      end

      # Withdraws a coin amount from the bank, using a bankbot if available.
      #
      # Parses the amount string (e.g., "5 crowns"), converts to copper, and either whispers
      # to a bankbot or calls #get_money_from_bank. Uses the hometown from settings if not
      # explicitly provided.
      #
      # @param amount_as_string [String] the amount to withdraw, e.g. "5 crowns" or "1 plat"
      # @param settings [OpenStruct] character settings; checks `bankbot_enabled`, `bankbot_room_id`, `bankbot_name`, and `hometown`
      # @param hometown [String, nil] the hometown for currency lookup (defaults to settings.hometown)
      # @return [Boolean] true if the withdrawal succeeded; false otherwise
      # @example
      #   withdraw_exact_amount?("5 crowns", settings) #=> true
      # @see #convert_to_copper parses denomination strings
      # @see #get_money_from_bank handles non-bankbot withdrawals
      # @see #hometown_currency derives the currency from the hometown
      def withdraw_exact_amount?(amount_as_string, settings, hometown = nil)
        hometown = settings.hometown if hometown.nil?

        if settings.bankbot_enabled
          DRCT.walk_to(settings.bankbot_room_id)
          DRC.release_invisibility
          if DRRoom.pcs.include?(settings.bankbot_name)
            amount_convert, type = amount_as_string.split
            amount = convert_to_copper(amount_convert, type)
            currency = hometown_currency(settings.hometown)
            case DRC.bput("whisper #{settings.bankbot_name} withdraw #{amount} #{currency}", 'offers you', 'Whisper what to who?')
            when 'offers you'
              DRC.bput('accept tip', 'Your current balance is')
            end
          else
            get_money_from_bank(amount_as_string, settings, hometown)
          end
        else
          get_money_from_bank(amount_as_string, settings, hometown)
        end
      end

      # Withdraws a coin amount from the bank via the teller, looping on retriable errors.
      #
      # Walks to the deposit location for the hometown, releases invisibility, and sends
      # "withdraw" commands. Handles various clerk responses: immediate success on "The clerk counts"
      # or "You count out", temporary failures (glare, rate-limiting) trigger a 15-second pause and retry,
      # permanent failures (no account, insufficient funds, maximum withdrawal) return false.
      #
      # @param amount_as_string [String] the amount to withdraw, e.g. "1 plat 50 crowns"
      # @param settings [OpenStruct] character settings, must include `hometown`
      # @param hometown [String, nil] the hometown for deposit location lookup (defaults to settings.hometown)
      # @return [Boolean] true if the withdrawal succeeded; false on permanent errors
      # @example
      #   get_money_from_bank("50 crowns", settings) #=> true
      # @see #ensure_copper_on_hand higher-level wrapper
      # @see #withdraw_exact_amount? may call this if bankbot is unavailable
      # @note Pauses for 15 seconds on rate-limit responses before retrying.
      def get_money_from_bank(amount_as_string, settings, hometown = nil)
        hometown = settings.hometown if hometown.nil?

        DRCT.walk_to(get_data('town')[hometown]['deposit']['id'])
        DRC.release_invisibility
        loop do
          case DRC.bput("withdraw #{amount_as_string}", 'The clerk counts', 'The clerk tells',
                        'The clerk glares at you.', 'You count out', 'find a new deposit jar', 'If you value your hands',
                        'Hey!  Slow down!', "You must be at a bank teller's window to withdraw money",
                        "You don't have that much money", 'have an account',
                        /The clerk says, "I'm afraid you can't withdraw that much at once/,
                        /^How much do you wish to withdraw/i)
          when 'The clerk counts', 'You count out'
            break true
          when 'The clerk glares at you.', 'Hey!  Slow down!', "I don't know what you think you're doing"
            pause 15
          when 'The clerk tells', 'If you value your hands', 'find a new deposit jar',
            "You must be at a bank teller's window to withdraw money", "You don't have that much money",
            'have an account', /The clerk says, "I'm afraid you can't withdraw that much at once/,
            /^How much do you wish to withdraw/i
            break false
          else
            break false
          end
        end
      end

      # Returns the copper value of bank debt for a given hometown.
      #
      # Sends the "wealth" command and parses the debt amount from the response.
      #
      # @param hometown [String] the hometown identifier
      # @return [Integer] the copper value of debt owed to the bank
      # @example
      #   debt("wehnimers_landing") #=> 1000
      # @see #wealth queries on-hand wealth for the same hometown
      def debt(hometown)
        currency = hometown_currency(hometown)
        DRC.bput('wealth', /\(\d+ copper #{currency}\)/i, /Wealth:/i).scan(/\d+/).first.to_i
      end

      # Deposits all coins at the bank, then re-withdraws a target amount to keep on hand.
      #
      # Walks to the deposit location, sends "deposit all", then if keeping coins for the current hometown,
      # withdraws denominations to reach the keep_copper target. Finally, queries "check balance" to parse
      # and return the updated bank balance and currency. Returns early if settings.skip_bank is true.
      # Uses the hometown from settings if not explicitly provided.
      #
      # @param keep_copper [Integer] the copper amount to re-withdraw and keep on hand (after deposit)
      # @param settings [OpenStruct] character settings, must include `hometown` and `skip_bank` flag
      # @param hometown [String, nil] the hometown for the deposit location (defaults to settings.hometown)
      # @return [Array(Integer, String)] a 2-tuple of [bank_balance_in_copper, currency_name], or nil if skip_bank is true
      # @example
      #   deposit_coins(1000, settings) #=> [5000, "Kronars"]
      # @note Handles multiple "check balance" response formats, including pre-formatted coin breakdowns.
      # @note Prints a bold message if no teller is found at the deposit location.
      # @see #minimize_coins breaks down the re-withdrawal into denominations
      # @see #withdraw_exact_amount? performs the re-withdrawal
      # @see #hometown_currency derives the currency from the hometown
      def deposit_coins(keep_copper, settings, hometown = nil)
        return if settings.skip_bank

        hometown = settings.hometown if hometown.nil?

        DRCT.walk_to(get_data('town')[hometown]['deposit']['id'])
        DRC.release_invisibility
        DRC.bput('wealth', 'Wealth:')
        case DRC.bput('deposit all', 'you drop all your', 'You hand the clerk some coins', "You don't have any",
                      'There is no teller here', 'reached the maximum balance I can permit',
                      'You find your jar with little effort', 'Searching methodically through the shelves')
        when 'There is no teller here'
          Lich::Messaging.msg('bold', "DRCM: No teller found at this location. Cannot deposit coins.")
          return
        end
        minimize_coins(keep_copper).each { |amount| withdraw_exact_amount?(amount, settings) } if settings.hometown == hometown
        balance_result = DRC.bput('check balance',
                                  /current balance is .*? (?:Kronars?|Dokoras?|Lirums?)\."$/,
                                  /If you would like to open one, you need only deposit a few (?:Kronars?|Dokoras?|Lirums?)\."$/,
                                  /As expected, there are .*? (?:Kronars?|Dokoras?|Lirums?)\.$/,
                                  'Perhaps you should find a new deposit jar for your financial needs.  Be sure to mark it with your name')
        case balance_result
        when /current balance is (?<bal>.*?) (?<cur>Kronars?|Dokoras?|Lirums?)\."$/,
             /As expected, there are (?<bal>.*?) (?<cur>Kronars?|Dokoras?|Lirums?)\.$/
          match = balance_result.match(/(?:current balance is|As expected, there are) (?<bal>.*?) (?<cur>Kronars?|Dokoras?|Lirums?)/)
          currency = match[:cur]
          balance = 0
          match[:bal].gsub(/and /, '').split(', ').each do |amount_as_string|
            amount, denomination = amount_as_string.split
            balance += convert_to_copper(amount, denomination)
          end
        when /If you would like to open one, you need only deposit a few (?<cur>Kronars?|Dokoras?|Lirums?)\."$/
          match = balance_result.match(/deposit a few (?<cur>Kronars?|Dokoras?|Lirums?)/)
          balance = 0
          currency = match[:cur]
        when /Perhaps you should find a new deposit jar/
          balance = 0
          currency = 'Dokoras'
        end
        [balance, currency]
      end
    end
  end
end
