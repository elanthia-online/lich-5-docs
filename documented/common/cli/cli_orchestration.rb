# frozen_string_literal: true

require_relative 'cli_options_registry'
require_relative 'active_sessions_query'
require_relative '../authentication/cli_password'
require_relative 'cli_conversion'
require_relative 'cli_encryption_mode_change'
require_relative '../authentication/cli'
require_relative '../authentication/login_helpers'
require_relative '../authentication/web_login'
require_relative '../gui/game_selection'
require_relative 'cli_option_validator'

# @api private
# Namespace for Lich 5, a Ruby scripting engine for text-based games
module Lich
  # @api private
  # Namespace for common Lich 5 utilities
  module Common
    # @api private
    # Namespace for CLI-related utilities
    module CLI
      # Orchestrates CLI operations: early-exit handlers for password management,
      # data conversion, and login flow. Uses CliOptionsRegistry for declarative
      # option registration and handler execution.
      module CLIOrchestration
        # Execute registered CLI operations
        # Processes ARGV for early-exit CLI operations (password mgmt, conversion)
        # Also handles conversion detection for login attempts
        def self.execute
          ActiveSessionsQuery.execute

          ARGV.each do |arg|
            case arg
            when /^--change-account-password$/, /^-cap$/
              handle_change_account_password
            when /^--add-account$/, /^-aa$/
              handle_add_account
            when /^--refresh-characters$/, /^-rc$/
              handle_refresh_characters
            when /^--add-character$/, /^-ac$/
              handle_add_character
            when /^--change-master-password$/, /^-cmp$/
              handle_change_master_password
            when /^--recover-master-password$/, /^-rmp$/
              handle_recover_master_password
            when /^--convert-entries$/
              handle_convert_entries
            when /^--change-encryption-mode$/, /^-cem$/
              handle_change_encryption_mode
            when /^--web-login-test$/
              handle_web_login_test
            end
          end

          # Check for conversion needed before login attempt
          # This is not an early-exit operation - it detects a precondition for login
          if ARGV.include?('--login')
            check_conversion_needed_for_login
          end
        end

        # Checks if legacy data conversion is required before a login attempt.
        #
        # If conversion is needed, prints a conversion help message and exits with
        # status code 1. This prevents login attempts when the entry store requires
        # migration from legacy DAT format to YAML.
        #
        # @return [void] exits the process if conversion is needed; otherwise returns normally
        # @see Lich::Common::CLI::CLIConversion.conversion_needed?
        def self.check_conversion_needed_for_login
          # Check if conversion is required
          if Lich::Common::CLI::CLIConversion.conversion_needed?(DATA_DIR)
            Lich::Common::CLI::CLIConversion.print_conversion_help_message
            exit 1
          end
        end

        # Changes the password for an existing account in the entry store.
        #
        # Reads account name and new password from ARGV (--change-account-password or -cap
        # followed by account and password arguments). Validates both arguments are present
        # and exits with status 1 if either is missing. On success or error, exits the
        # process via CLIPassword.change_account_password.
        #
        # @return [void] exits the process; never returns normally
        # @raise [SystemExit] with status 1 if account or password argument is missing
        def self.handle_change_account_password
          idx = ARGV.index { |a| a =~ /^--change-account-password$|^-cap$/ }
          account = ARGV[idx + 1]
          new_password = ARGV[idx + 2]

          if account.nil? || new_password.nil?
            lich_script = File.join(LICH_DIR, 'lich.rbw')
            $stdout.puts 'error: Missing required arguments'
            $stdout.puts "Usage: ruby #{lich_script} --change-account-password ACCOUNT NEWPASSWORD"
            $stdout.puts "   or: ruby #{lich_script} -cap ACCOUNT NEWPASSWORD"
            exit 1
          end

          exit Lich::Common::Authentication::CLIPassword.change_account_password(account, new_password)
        end

        # Adds a new account to the entry store, with optional frontend preference.
        #
        # Reads account name, password, and optional --frontend flag from ARGV.
        # If no YAML entry file exists but legacy DAT format data is present,
        # automatically converts to plaintext YAML (with warnings) before proceeding.
        # Exits with status 1 if required account or password arguments are missing,
        # or if YAML creation fails. Otherwise exits via CLIPassword.add_account.
        #
        # @return [void] exits the process; never returns normally
        # @raise [SystemExit] with status 1 if account/password missing or YAML creation fails
        def self.handle_add_account
          idx = ARGV.index { |a| a =~ /^--add-account$|^-aa$/ }
          account = ARGV[idx + 1]
          password = ARGV[idx + 2]

          if account.nil? || password.nil?
            lich_script = File.join(LICH_DIR, 'lich.rbw')
            $stdout.puts 'error: Missing required arguments'
            $stdout.puts "Usage: ruby #{lich_script} --add-account ACCOUNT PASSWORD [--frontend FRONTEND]"
            $stdout.puts "   or: ruby #{lich_script} -aa ACCOUNT PASSWORD [--frontend FRONTEND]"
            exit 1
          end

          # Check if YAML file exists; if not, check for DAT and auto-convert to plaintext
          yaml_file = Lich::Common::Authentication::EntryStore.yaml_file_path(DATA_DIR)
          unless File.exist?(yaml_file)
            if Lich::Common::CLI::CLIConversion.conversion_needed?(DATA_DIR)
              $stdout.puts ''
              $stdout.puts '=' * 80
              $stdout.puts 'WARNING: No YAML entry file found. Legacy entry.dat detected.'
              $stdout.puts 'Creating plaintext YAML file to support this operation.'
              $stdout.puts '=' * 80
              $stdout.puts ''
              $stdout.puts 'SECURITY NOTICE: Plaintext storage is not recommended except for'
              $stdout.puts 'accessibility requirements. Passwords will be stored in clear text.'
              $stdout.puts ''
              $stdout.puts 'To upgrade encryption later, use:'
              $stdout.puts "  ruby #{File.join(LICH_DIR, 'lich.rbw')} --change-encryption-mode enhanced"
              $stdout.puts '  or: -cem enhanced'
              $stdout.puts '=' * 80
              $stdout.puts ''

              # Perform plaintext conversion
              success = Lich::Common::CLI::CLIConversion.convert(DATA_DIR, :plaintext)
              unless success
                $stdout.puts 'error: Failed to create YAML file from legacy data.'
                exit 1
              end
              # Continue with add-account operation below
            end
            # No DAT file either - CLIPassword.add_account will create new YAML
          end

          frontend = ARGV[ARGV.index('--frontend') + 1] if ARGV.include?('--frontend')
          exit Lich::Common::Authentication::CLIPassword.add_account(account, password, frontend)
        end

        # Refreshes the character list for an account from the game server.
        #
        # Reads account name and optional --frontend flag from ARGV. Validates account
        # name is provided; exits with validation error if missing. Validates frontend
        # (if supplied) against known frontends. Exits via CLIPassword.refresh_characters.
        #
        # @return [void] exits the process; never returns normally
        def self.handle_refresh_characters
          idx = ARGV.index { |a| a =~ /^--refresh-characters$|^-rc$/ }
          account = ARGV[idx + 1]

          lich_script = File.join(LICH_DIR, 'lich.rbw')
          usage = "Usage: ruby #{lich_script} --refresh-characters ACCOUNT [--frontend FRONTEND]\n" \
                  "   or: ruby #{lich_script} -rc ACCOUNT [--frontend FRONTEND]"

          account = CliOptionValidator.require_positional(account, name: 'ACCOUNT', usage: usage)

          frontend = CliOptionValidator.extract_flag_value(
            '--frontend',
            usage: usage,
            valid_values: Lich::Common::Authentication::LoginHelpers::VALID_FRONTENDS
          )
          exit Lich::Common::Authentication::CLIPassword.refresh_characters(account, frontend)
        end

        # Adds a new character to an account in the entry store.
        #
        # Reads account name, character name, and required --game-code flag from ARGV.
        # Optional --frontend flag may also be provided. Validates all positional arguments
        # and --game-code (which must be a valid game code). Exits via CLIPassword.add_character
        # on success or validation error.
        #
        # @return [void] exits the process; never returns normally
        def self.handle_add_character
          idx = ARGV.index { |a| a =~ /^--add-character$|^-ac$/ }
          account = ARGV[idx + 1]
          char_name = ARGV[idx + 2]

          lich_script = File.join(LICH_DIR, 'lich.rbw')
          usage = "Usage: ruby #{lich_script} --add-character ACCOUNT CHAR_NAME --game-code CODE [--frontend FRONTEND]\n" \
                  "   or: ruby #{lich_script} -ac ACCOUNT CHAR_NAME --game-code CODE [--frontend FRONTEND]"

          account = CliOptionValidator.require_positional(account, name: 'ACCOUNT', usage: usage)
          char_name = CliOptionValidator.require_positional(char_name, name: 'CHAR_NAME', usage: usage)

          game_code = CliOptionValidator.extract_flag_value('--game-code', usage: usage)
          if game_code.nil?
            $stdout.puts 'error: --game-code is required'
            $stdout.puts usage
            exit 1
          end

          unless Lich::Common::Authentication::LoginHelpers.valid_game_code?(game_code)
            CliOptionValidator.reject_invalid_value(
              '--game-code',
              game_code,
              valid_values: Lich::Common::Authentication::LoginHelpers::VALID_GAME_CODES,
              usage: usage
            )
          end

          frontend = CliOptionValidator.extract_flag_value(
            '--frontend',
            usage: usage,
            valid_values: Lich::Common::Authentication::LoginHelpers::VALID_FRONTENDS
          )

          exit Lich::Common::Authentication::CLIPassword.add_character(
            account,
            char_name,
            game_code: game_code,
            frontend: frontend
          )
        end

        # Changes the master password for the entry store.
        #
        # Reads old password (required) and new password (optional) from ARGV.
        # If new password is not provided on command line, the user will be prompted
        # for confirmation. Exits with status 1 if old password is missing. Otherwise
        # exits via CLIPassword.change_master_password.
        #
        # @return [void] exits the process; never returns normally
        # @raise [SystemExit] with status 1 if old password argument is missing
        def self.handle_change_master_password
          idx = ARGV.index { |a| a =~ /^--change-master-password$|^-cmp$/ }
          old_password = ARGV[idx + 1]
          new_password = ARGV[idx + 2]

          if old_password.nil?
            lich_script = File.join(LICH_DIR, 'lich.rbw')
            $stdout.puts 'error: Missing required arguments'
            $stdout.puts "Usage: ruby #{lich_script} --change-master-password OLDPASSWORD [NEWPASSWORD]"
            $stdout.puts "   or: ruby #{lich_script} -cmp OLDPASSWORD [NEWPASSWORD]"
            $stdout.puts 'Note: If NEWPASSWORD is not provided, you will be prompted for confirmation'
            exit 1
          end

          exit Lich::Common::Authentication::CLIPassword.change_master_password(old_password, new_password)
        end

        # Recovers access to the entry store by setting a new master password.
        #
        # Reads optional new password from ARGV. If new password is not provided on
        # command line, the user will be prompted interactively. Exits via
        # CLIPassword.recover_master_password.
        #
        # @return [void] exits the process; never returns normally
        def self.handle_recover_master_password
          idx = ARGV.index { |a| a =~ /^--recover-master-password$|^-rmp$/ }
          new_password = ARGV[idx + 1]

          # new_password is optional - if not provided, user will be prompted interactively
          exit Lich::Common::Authentication::CLIPassword.recover_master_password(new_password)
        end

        # Converts the entry store to a new encryption mode (plaintext, standard, or enhanced).
        #
        # Reads encryption mode from ARGV (required: plaintext, standard, or enhanced).
        # For enhanced mode, prompts for a new master password and stores it in the keychain
        # before conversion. Exits with status 1 if encryption mode is missing or invalid,
        # or if enhanced-mode master password creation or keychain storage fails. On success,
        # exits with status 0 after printing confirmation.
        #
        # @return [void] exits the process; never returns normally
        # @raise [SystemExit] with status 1 if mode is missing/invalid or master password setup fails
        def self.handle_convert_entries
          idx = ARGV.index('--convert-entries')
          encryption_mode_str = ARGV[idx + 1]

          if encryption_mode_str.nil?
            lich_script = File.join(LICH_DIR, 'lich.rbw')
            $stdout.puts 'error: Missing required argument'
            $stdout.puts "Usage: ruby #{lich_script} --convert-entries [plaintext|standard|enhanced]"
            exit 1
          end

          unless %w[plaintext standard enhanced].include?(encryption_mode_str)
            $stdout.puts "error: Invalid encryption mode: #{encryption_mode_str}"
            $stdout.puts 'Valid modes: plaintext, standard, enhanced'
            exit 1
          end

          # For enhanced mode, prompt for master password and store in keychain before conversion
          # This way migrate_from_legacy will find it in keychain and not try to show GUI dialog
          if encryption_mode_str == 'enhanced'
            master_password = Lich::Common::Authentication::CLIPassword.prompt_and_confirm_password('Enter new master password for enhanced encryption')
            if master_password.nil?
              puts 'error: Master password creation cancelled'
              exit 1
            end

            # Store password in keychain so ensure_master_password_exists finds it
            require_relative '../gui/master_password_manager'
            stored = Lich::Common::GUI::MasterPasswordManager.store_master_password(master_password)
            unless stored
              puts 'error: Failed to store master password in keychain'
              exit 1
            end
          end

          # Perform conversion
          success = Lich::Common::CLI::CLIConversion.convert(
            DATA_DIR,
            encryption_mode_str
          )

          if success
            $stdout.puts 'Conversion completed successfully!'
            exit 0
          else
            $stdout.puts 'Conversion failed. Please check the logs for details.'
            exit 1
          end
        end

        # Changes the encryption mode of the entry store and optionally updates the master password.
        #
        # Reads encryption mode (required: plaintext, standard, or enhanced) and optional
        # --master-password or -mp flag from ARGV. Exits with status 1 if encryption mode
        # is missing. Otherwise exits via EncryptionModeChange.change_mode.
        #
        # @return [void] exits the process; never returns normally
        # @raise [SystemExit] with status 1 if encryption mode argument is missing
        def self.handle_change_encryption_mode
          idx = ARGV.index { |a| a =~ /^--change-encryption-mode$|^-cem$/ }
          mode_arg = ARGV[idx + 1]

          if mode_arg.nil?
            lich_script = File.join(LICH_DIR, 'lich.rbw')
            $stdout.puts 'error: Missing encryption mode'
            $stdout.puts "Usage: ruby #{lich_script} --change-encryption-mode MODE [--master-password PASSWORD]"
            $stdout.puts "       ruby #{lich_script} -cem MODE [-mp PASSWORD]"
            $stdout.puts 'Modes: plaintext, standard, enhanced'
            exit 1
          end

          new_mode = mode_arg.to_sym

          # Check for optional master password (for Enhanced mode, if automating)
          mp_index = ARGV.index('--master-password') || ARGV.index('-mp')
          master_password = ARGV[mp_index + 1] if mp_index

          exit Lich::Common::CLI::EncryptionModeChange.change_mode(new_mode, master_password)
        end

        # Standalone probe of the HTTPS web-login fallback path (see
        # docs/web-login-protocol-analysis.md). Exercises
        # WebLogin.auth_with_timeout directly against play.net -- independent
        # of the real login path (Authenticator.authenticate), which also
        # uses WebLogin, either forced via --auth-provider=web or
        # automatically as a fallback when EAccess is unreachable.
        #
        # @return [void] exits the process; never returns normally
        def self.handle_web_login_test
          idx = ARGV.index('--web-login-test')
          account = ARGV[idx + 1]
          char_name = ARGV[idx + 2]

          lich_script = File.join(LICH_DIR, 'lich.rbw')
          usage = "Usage: ruby #{lich_script} --web-login-test ACCOUNT CHAR_NAME --game-code CODE\n" \
                  "Reads the account's password from data/entry.yaml (ACCOUNT must already be saved there).\n" \
                  'This is a standalone probe of the HTTPS web-login fallback path -- it does NOT ' \
                  'touch the normal EAccess login flow.'

          account = CliOptionValidator.require_positional(account, name: 'ACCOUNT', usage: usage)
          char_name = CliOptionValidator.require_positional(char_name, name: 'CHAR_NAME', usage: usage)

          game_code = CliOptionValidator.extract_flag_value(
            '--game-code',
            usage: usage,
            valid_values: Lich::Common::Authentication::LoginHelpers::VALID_GAME_CODES
          )
          if game_code.nil?
            $stdout.puts 'error: --game-code is required'
            $stdout.puts usage
            exit 1
          end

          entries = Lich::Common::Authentication::EntryStore.load_saved_entries(DATA_DIR, false)
          entry = entries.find { |e| e[:user_id].to_s.casecmp?(account) }
          if entry.nil?
            $stdout.puts "error: Account '#{account}' not found in #{Lich::Common::Authentication::EntryStore.yaml_file_path(DATA_DIR)}"
            exit 1
          end

          $stdout.puts "Probing web login fallback for #{account} / #{char_name} (#{game_code})..."

          begin
            login_info = Lich::Common::Authentication::WebLogin.auth_with_timeout(
              account: account,
              password: entry[:password],
              character: char_name,
              game_code: game_code
            )
            $stdout.puts 'Success:'
            # KEY is a live, usable one-time game-server credential -- printing
            # it would leave a real secret in terminal scrollback/log capture
            # for a probe that never consumes it. Only non-secret connection
            # metadata is shown.
            login_info.each { |k, v| $stdout.puts "  #{k.upcase}=#{k == 'key' ? '[scrubbed]' : v}" }
            exit 0
          rescue Lich::Common::Authentication::WebLogin::AuthenticationError => e
            $stdout.puts "error: web login failed: #{e.error_code}"
            exit 1
          rescue StandardError => e
            $stdout.puts "error: #{e.class}: #{e.message}"
            exit 1
          end
        end
      end
    end
  end
end
