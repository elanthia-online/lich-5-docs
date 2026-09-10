# frozen_string_literal: true

# CLI argument processing and orchestration (Layer 2)
# Three-layer architecture:
#   - Layer 1 (Opts): Pure parsing of ARGV -> frozen OpenStruct
#   - Layer 2 (this file): Validation, routing to handlers, side effects
#   - Layer 3 (CliPasswordManager): Domain-specific handlers

require File.join(LIB_DIR, 'util', 'opts.rb')
require File.join(LIB_DIR, 'common', 'cli', 'cli_orchestration.rb')
require File.join(LIB_DIR, 'common', 'bind_host_resolver.rb')
require File.join(LIB_DIR, 'main', 'bind_address_option.rb')
require File.join(LIB_DIR, 'main', 'arg_normalization.rb')
require File.join(LIB_DIR, 'main', 'detachable_client_target.rb')
require File.join(LIB_DIR, 'main', 'startup_theme.rb')

module Lich
  module Main
    # Orchestrates ARGV processing: parsing -> validation -> handler execution -> side effects
    module ArgvOptions
      # CLI operations are now handled by lib/common/cli/cli_orchestration.rb
      # which handles early-exit operations (password mgmt, conversion)
      # before normal argv_options processing

      # Parse ARGV and build @argv_options hash for backward compatibility
      module OptionParser
        # Parses ARGV into a hash of option flags and values, handling system integration
        # (SGE/SAL linking), game connection modes, authentication, and frontend selection.
        #
        # Recognizes long-form options (--start-scripts, --host, --game, etc.) and performs
        # early exit for installation/system linking operations. Normalizes host:port pairs,
        # resolves .sal/.~xt launch files, and applies dark mode settings.
        #
        # @return [Hash] a hash mapping option symbols (:start_scripts, :host, :game, :sal,
        #   :bind_address, :dark_mode, etc.) to their parsed values; empty if ARGV is empty
        # @note Does not apply side effects; use {SideEffects.execute} afterward
        # @api private
        def self.execute
          @argv_options = {}
          bad_args = []

          ARGV.each do |arg|
            case arg
            when '--link-to-sge'
              result = Lich.link_to_sge
              $stdout.puts(result ? 'Successfully linked to SGE.' : 'Failed to link to SGE.') if $stdout.isatty
              exit
            when '--unlink-from-sge'
              result = Lich.unlink_from_sge
              $stdout.puts(result ? 'Successfully unlinked from SGE.' : 'Failed to unlink from SGE.') if $stdout.isatty
              exit
            when '--link-to-sal'
              result = Lich.link_to_sal
              $stdout.puts(result ? 'Successfully linked to SAL files.' : 'Failed to link to SAL files.') if $stdout.isatty
              exit
            when '--unlink-from-sal'
              result = Lich.unlink_from_sal
              $stdout.puts(result ? 'Successfully unlinked from SAL files.' : 'Failed to unlink from SAL files.') if $stdout.isatty
              exit
            when '--install'
              if Lich.link_to_sge && Lich.link_to_sal
                $stdout.puts 'Install was successful.'
                Lich.log 'Install was successful.'
              else
                $stdout.puts 'Install failed.'
                Lich.log 'Install failed.'
              end
              exit
            when '--uninstall'
              if Lich.unlink_from_sge && Lich.unlink_from_sal
                $stdout.puts 'Uninstall was successful.'
                Lich.log 'Uninstall was successful.'
              else
                $stdout.puts 'Uninstall failed.'
                Lich.log 'Uninstall failed.'
              end
              exit
            when /^--start-scripts=(.+)$/i
              @argv_options[:start_scripts] = $1
            when /^--reconnect$/i
              @argv_options[:reconnect] = true
            when /^--reconnect-delay=(.+)$/i
              @argv_options[:reconnect_delay] = $1
            when /^--host=(.+):(.+)$/
              @argv_options[:host] = { domain: $1, port: $2.to_i }
            when /^--bind-address=(.+)$/i
              @argv_options[:bind_address] = $1
            when /^--hosts-file=(.+)$/i
              @argv_options[:hosts_file] = $1
            when /^--no-(?:gui|gtk)$/i
              @argv_options[:gui] = false
            when /^--gui$/i
              @argv_options[:gui] = true
            when /^--game=(.+)$/i
              @argv_options[:game] = $1
            when /^--auth-provider=(eaccess|web)$/i
              @argv_options[:auth_provider] = $1.downcase.to_sym
            when /^--account=(.+)$/i
              @argv_options[:account] = $1
            when /^--password=(.+)$/i
              @argv_options[:password] = $1
            when /^--character=(.+)$/i
              @argv_options[:character] = $1
            when /^--frontend=(.+)$/i
              @argv_options[:frontend] = $1
            when /^--frontend-command=(.+)$/i
              @argv_options[:frontend_command] = $1
            when /^--save$/i
              @argv_options[:save] = true
            when /^--pipe$/i
              @argv_options[:pipe] = true
            when /^--wine(?:\-prefix)?=.+$/i
              nil # already used when defining the Wine module
            when /\.sal$|Gse\.~xt$/i
              handle_sal_file(arg)
              bad_args.clear
            when /^--dark-mode=(true|false|on|off)$/i
              handle_dark_mode($1)
            when /^--saga$/i
              $frontend = 'saga'
            else
              bad_args.push(arg)
            end
          end

          @argv_options
        end

        # Resolves a .sal or .~xt launch file path and stores it in @argv_options[:sal].
        #
        # Attempts three resolution strategies: use the argument as-is, extract a Windows
        # path from ARGV (e.g., C:\\folder\\file.sal), and translate it to a Wine prefix
        # path if Wine is defined. Logs the final resolved path but does not validate
        # existence—that is deferred to {SideEffects#handle_sal_launch}.
        #
        # @param arg [String] the literal argument matched by the .sal/.~xt regex
        # @return [void]
        # @api private
        def self.handle_sal_file(arg)
          @argv_options[:sal] = arg
          unless File.exist?(@argv_options[:sal])
            @argv_options[:sal] = $1 if ARGV.join(' ') =~ /([A-Z]:\\.+?\.(?:sal|~xt))/i
          end
          unless File.exist?(@argv_options[:sal])
            @argv_options[:sal] = "#{Wine::PREFIX}/drive_c/#{@argv_options[:sal][3..-1].split('\\').join('/')}" if defined?(Wine)
          end
        end

        # Converts the --dark-mode argument value to a strict boolean and stores it.
        #
        # Accepts "true", "on" (case-insensitive) as truthy; all other values are falsy.
        # Ensures the stored value is a pure [Boolean], not a Regexp match result.
        #
        # @param value [String] the captured regex group from --dark-mode=(true|false|on|off)
        # @return [void]
        # @api private
        def self.handle_dark_mode(value)
          # Regex returns Integer/nil; force strict boolean for startup handling.
          @argv_options[:dark_mode] = !!(value =~ /^(true|on)$/i)
        end
      end

      # Apply side effects: dark mode, hosts-dir, bind-address, detachable-client
      module SideEffects
        # Applies side effects implied by parsed argv_options: theme, host directories,
        # bind addresses, detachable client configuration, and SAL file launching.
        #
        # Resolves hostnames to concrete IP addresses (via {BindAddressOption} and
        # {BindHostResolver}), handles --hosts-dir path validation, configures detachable
        # client binding, and launches .sal files with the appropriate system integration
        # (Win32 ShellExecute, Wine, or system). Fatal errors cause immediate exit(1).
        #
        # @param argv_options [Hash] the hash returned by {OptionParser.execute}
        # @return [Hash] the same argv_options hash, modified in-place with resolved
        #   addresses, host directories, and client configuration
        # @note Called after argument parsing; modifies global state ($frontend, Win32
        #   ShellExecute) and may exit the process
        # @api private
        def self.execute(argv_options)
          StartupTheme.apply(argv_options)
          handle_hosts_dir(argv_options)
          handle_bind_address(argv_options)
          handle_detachable_client(argv_options)
          handle_sal_launch(argv_options)
          argv_options
        end

        # Surface a message on both channels every bind handler uses.
        def self.announce(level, message)
          $stdout.puts "#{level}: #{message}"
          Lich.log "#{level}: #{message}"
        end

        # Fatal argv problem: tell the user everywhere, then stop.
        def self.die(message)
          announce('error', message)
          exit 1
        end

        # --bind-address shares the keyword vocabulary of --detachable-client
        # hosts (tailscale/lan/any). Resolve it once, up front, so the
        # frontend listener, the --game proxy, and a detachable client that
        # inherits it all bind the same concrete address -- and so the
        # exposure warning appears exactly once.
        def self.handle_bind_address(argv_options)
          result = BindAddressOption.apply(argv_options[:bind_address])
          die(result.error) if result.error
          return unless result.host

          argv_options[:bind_address] = result.host
          announce('warning', result.warning) if result.warning
        end

        # Extracts and validates the --hosts-dir option, storing the normalized path
        # in argv_options[:hosts_dir].
        #
        # Removes the argument from ARGV, converts backslashes to forward slashes, and
        # ensures the directory ends with '/'. Logs a warning to stdout if the directory
        # does not exist, but does not exit or raise.
        #
        # @param argv_options [Hash] the options hash to update with :hosts_dir key
        # @return [void]
        # @api private
        def self.handle_hosts_dir(argv_options)
          if (arg = ARGV.find { |a| a =~ /^--hosts-dir=(.+)$/i })
            hosts_dir = arg[/^--hosts-dir=(.+)$/i, 1]
            ARGV.delete(arg)
            if hosts_dir && File.exist?(hosts_dir)
              hosts_dir = hosts_dir.tr('\\', '/')
              hosts_dir += '/' unless hosts_dir[-1..-1] == '/'
              argv_options[:hosts_dir] = hosts_dir
            else
              $stdout.puts "warning: given hosts directory does not exist: #{hosts_dir}"
            end
          end
        end

        # Resolves --detachable-client address/port and applies --bind-address as default.
        #
        # Parses --detachable-client=<target> format (host and/or port), resolves the
        # host keyword (tailscale/lan/any) to a concrete IP via {BindHostResolver},
        # and defaults to --bind-address or 127.0.0.1. Port is optional. Raises
        # {DetachableClientTarget::ParseError} or {BindHostResolver::Error} on invalid
        # input, which {SideEffects} catches and exits with an error message.
        #
        # @param argv_options [Hash] the options hash to update with :detachable_client_host
        #   and :detachable_client_port keys
        # @return [void]
        # @raise [DetachableClientTarget::ParseError] if the target syntax is invalid
        # @raise [Lich::Common::BindHostResolver::Error] if hostname resolution fails
        # @api private
        def self.handle_detachable_client(argv_options)
          argv_options[:detachable_client_host] = argv_options[:bind_address] || '127.0.0.1'
          argv_options[:detachable_client_port] = nil
          arg = ARGV.find { |a| a.start_with?('--detachable-client=') }
          return unless arg

          begin
            target = DetachableClientTarget.parse(arg.split('=', 2).last)
            if target.host
              resolution = Lich::Common::BindHostResolver.resolve(target.host)
              argv_options[:detachable_client_host] = resolution.host
              announce('warning', resolution.warning) if resolution.warning
            end
            # (The port-only form inherits --bind-address, which
            # handle_bind_address already resolved and warned about; the
            # loopback default warrants no warning.)
            argv_options[:detachable_client_port] = target.port
          rescue DetachableClientTarget::ParseError, Lich::Common::BindHostResolver::Error => e
            die(e.message)
          end
        end

        # Validates and launches a .sal launch file using system integration (Win32,
        # Wine, or direct system call), then exits.
        #
        # Checks file existence, logs the path, and for SGE.sal specifically, retrieves
        # the Simutronics launcher command and executes it with elevated privileges
        # (runas on Win32 non-XP, open otherwise), substituting %1 with the file path.
        # On non-SGE files or platforms without Win32, delegates to Wine or system().
        # Always exits when invoked (does not return).
        #
        # @param argv_options [Hash] the options hash (read only; checks :sal key)
        # @return [void] (method exits unconditionally)
        # @note Exits the entire process; used only for SAL-file launch mode
        # @api private
        def self.handle_sal_launch(argv_options)
          return unless argv_options[:sal]

          unless File.exist?(argv_options[:sal])
            Lich.log "error: launch file does not exist: #{argv_options[:sal]}"
            Lich.msgbox "error: launch file does not exist: #{argv_options[:sal]}"
            exit
          end
          Lich.log "info: launch file: #{argv_options[:sal]}"

          if argv_options[:sal] =~ /SGE\.sal/i
            unless (launcher_cmd = Lich.get_simu_launcher)
              $stdout.puts 'error: failed to find the Simutronics launcher'
              Lich.log 'error: failed to find the Simutronics launcher'
              exit
            end
            launcher_cmd.sub!('%1', argv_options[:sal])
            Lich.log "info: launcher_cmd: #{launcher_cmd}"
            if defined?(Win32) && launcher_cmd =~ /^"(.*?)"\s*(.*)$/
              dir_file = $1
              param = $2
              dir = dir_file.slice(/^.*[\\\/]/)
              file = dir_file.sub(/^.*[\\\/]/, '')
              operation = (Win32.isXP? ? 'open' : 'runas')
              r = Win32.ShellExecute(lpOperation: operation, lpFile: file, lpDirectory: dir, lpParameters: param)
              Lich.log "error: Win32.ShellExecute returned #{r}; Win32.GetLastError: #{Win32.GetLastError}" if r < 33
            elsif defined?(Wine)
              system("#{Wine::BIN} #{launcher_cmd}")
            else
              system(launcher_cmd)
            end
            exit
          end
        end
      end

      # Handle game connection configuration
      module GameConnection
        # Routes ARGV flags to the appropriate game server connection handler and sets
        # game_host, game_port, and $frontend accordingly.
        #
        # Detects force-mode flags (-g/--game, --shattered, --fallen, or authentication
        # provider flags) and calls the corresponding handler. If no game mode is detected,
        # sets game_host and game_port to nil. Also initializes {Lich::Common::Frontend}
        # from the parent process for normal connections (not detachable-client mode).
        #
        # @param processed_options [Hash] the options hash from {SideEffects.execute}
        # @return [Hash] the same processed_options hash, updated with :game_host and
        #   :game_port keys; side effect is setting global $frontend and $platinum
        # @note Called after side effects; modifies global game connection state
        # @api private
        def self.execute(processed_options)
          if (arg = ARGV.find { |a| a == '-g' || a == '--game' })
            handle_explicit_game_connection(arg, processed_options)
          elsif ARGV.include?('--shattered')
            handle_shattered_connection(processed_options)
          elsif ARGV.include?('--fallen')
            handle_fallen_connection(processed_options)
          elsif Lich::Common::Authentication::LoginHelpers.gemstone_flag?(ARGV)
            handle_gemstone_connection(processed_options)
          elsif Lich::Common::Authentication::LoginHelpers.dragonrealms_flag?(ARGV)
            handle_dragonrealms_connection(processed_options)
          else
            processed_options[:game_host] = nil
            processed_options[:game_port] = nil
            Lich.log 'info: no force-mode info given'
          end
          processed_options
        end

        # Handles explicit -g/--game mode: parses host:port and sets frontend from ARGV.
        #
        # Extracts the game server address from ARGV immediately following -g or --game,
        # splits on ':', converts port to Integer, and calls {GameConnection#determine_frontend}
        # to select the UI. Initializes {Lich::Common::Frontend} from the parent process
        # unless --detachable-client is present.
        #
        # @param arg [String] the literal '-g' or '--game' flag from ARGV
        # @param processed_options [Hash] the options hash to update with :game_host
        #   and :game_port
        # @return [void]
        # @api private
        def self.handle_explicit_game_connection(arg, processed_options)
          processed_options[:game_host], processed_options[:game_port] = ARGV[ARGV.index(arg) + 1].split(':')
          processed_options[:game_port] = processed_options[:game_port].to_i
          $frontend = determine_frontend
          # Initialize frontend from parent process unless using detachable client
          unless ARGV.any? { |a| a =~ /^--detachable-client/i }
            Lich::Common::Frontend.init_from_parent(Process.ppid)
          end
        end

        # Sets game server and frontend for GemStone IV (premium or free play).
        #
        # Selects the appropriate server port based on --platinum flag and --test flag.
        # Determines frontend from -s/--stormfront, --avalon, --frostbite, --saga, or
        # defaults to wizard. Stormfront is preferred if specified; otherwise frontend
        # flags are checked in the order listed.
        #
        # @param processed_options [Hash] the options hash to update with :game_host
        #   and :game_port
        # @return [void]
        # @note Sets global $platinum and $frontend
        # @api private
        def self.handle_gemstone_connection(processed_options)
          if ARGV.include?('--platinum')
            $platinum = true
            if ARGV.any? { |a| a =~ /^-s$/i || a =~ /^--stormfront$/i }
              processed_options[:game_host] = 'storm.gs4.game.play.net'
              processed_options[:game_port] = 10124
              $frontend = 'stormfront'
            else
              processed_options[:game_host] = 'storm.gs4.game.play.net'
              processed_options[:game_port] = 10124
              $frontend = ARGV.any? { |a| a =~ /^--avalon$/i } ? 'avalon' : ARGV.any? { |a| a =~ /^--frostbite$/i } ? 'frostbite' : ARGV.any? { |a| a =~ /^--saga$/i } ? 'saga' : 'wizard'
            end
          else
            $platinum = false
            if ARGV.any? { |a| a =~ /^-s$/i || a =~ /^--stormfront$/i }
              processed_options[:game_host] = 'storm.gs4.game.play.net'
              processed_options[:game_port] = ARGV.include?('--test') ? 10624 : 10024
              $frontend = 'stormfront'
            else
              processed_options[:game_host] = 'storm.gs4.game.play.net'
              processed_options[:game_port] = ARGV.include?('--test') ? 10624 : 10024
              $frontend = ARGV.any? { |a| a =~ /^--avalon$/i } ? 'avalon' : ARGV.any? { |a| a =~ /^--frostbite$/i } ? 'frostbite' : ARGV.any? { |a| a =~ /^--saga$/i } ? 'saga' : 'wizard'
            end
          end
        end

        # Sets game server and frontend for GemStone IV: Shattered (event realm).
        #
        # Connects to storm.gs4.game.play.net port 10324. Determines frontend from
        # -s/--stormfront, --avalon, --frostbite, --saga, or defaults to wizard.
        #
        # @param processed_options [Hash] the options hash to update with :game_host
        #   and :game_port
        # @return [void]
        # @note Sets global $frontend and $platinum to false
        # @api private
        def self.handle_shattered_connection(processed_options)
          $platinum = false
          if ARGV.any? { |a| a =~ /^-s$/i || a =~ /^--stormfront$/i }
            processed_options[:game_host] = 'storm.gs4.game.play.net'
            processed_options[:game_port] = 10324
            $frontend = 'stormfront'
          else
            processed_options[:game_host] = 'storm.gs4.game.play.net'
            processed_options[:game_port] = 10324
            $frontend = ARGV.any? { |a| a =~ /^--avalon$/i } ? 'avalon' : ARGV.any? { |a| a =~ /^--frostbite$/i } ? 'frostbite' : ARGV.any? { |a| a =~ /^--saga$/i } ? 'saga' : 'wizard'
          end
        end

        # Sets game server and frontend for DragonRealms: Fallen (event realm).
        #
        # Connects to dr.simutronics.net port 11324. Determines frontend from
        # -s/--stormfront, --genie, --avalon, --frostbite, --saga, or defaults to wizard.
        # Genie is preferred if specified; Stormfront is checked next.
        #
        # @param processed_options [Hash] the options hash to update with :game_host
        #   and :game_port
        # @return [void]
        # @note Sets global $frontend and $platinum to false
        # @api private
        def self.handle_fallen_connection(processed_options)
          $platinum = false
          if ARGV.any? { |a| a =~ /^-s$/i || a =~ /^--stormfront$/i }
            processed_options[:game_host] = 'dr.simutronics.net'
            processed_options[:game_port] = 11324
            $frontend = 'stormfront'
          elsif ARGV.grep(/--genie/i).any?
            processed_options[:game_host] = 'dr.simutronics.net'
            processed_options[:game_port] = 11324
            $frontend = 'genie'
          else
            processed_options[:game_host] = 'dr.simutronics.net'
            processed_options[:game_port] = 11324
            $frontend = ARGV.any? { |a| a =~ /^--avalon$/i } ? 'avalon' : ARGV.any? { |a| a =~ /^--frostbite$/i } ? 'frostbite' : ARGV.any? { |a| a =~ /^--saga$/i } ? 'saga' : 'wizard'
          end
        end

        # Sets game server and frontend for DragonRealms (premium or free play).
        #
        # Selects the appropriate server port based on --platinum flag and --test flag.
        # Determines frontend from -s/--stormfront, --genie, --avalon, --frostbite,
        # --saga, or defaults to wizard. Stormfront is preferred if specified; Genie
        # is checked next; then the remaining flags in order.
        #
        # @param processed_options [Hash] the options hash to update with :game_host
        #   and :game_port
        # @return [void]
        # @note Sets global $platinum and $frontend
        # @api private
        def self.handle_dragonrealms_connection(processed_options)
          if ARGV.include?('--platinum')
            $platinum = true
            if ARGV.any? { |a| a =~ /^-s$/i || a =~ /^--stormfront$/i }
              processed_options[:game_host] = 'dr.simutronics.net'
              processed_options[:game_port] = 11124
              $frontend = 'stormfront'
            elsif ARGV.grep(/--genie/i).any?
              processed_options[:game_host] = 'dr.simutronics.net'
              processed_options[:game_port] = 11124
              $frontend = 'genie'
            else
              processed_options[:game_host] = 'dr.simutronics.net'
              processed_options[:game_port] = 11124
              $frontend = ARGV.any? { |a| a =~ /^--avalon$/i } ? 'avalon' : ARGV.any? { |a| a =~ /^--frostbite$/i } ? 'frostbite' : ARGV.any? { |a| a =~ /^--saga$/i } ? 'saga' : 'wizard'
            end
          else
            $platinum = false
            if ARGV.any? { |a| a =~ /^-s$/i || a =~ /^--stormfront$/i }
              processed_options[:game_host] = 'dr.simutronics.net'
              processed_options[:game_port] = ARGV.include?('--test') ? 11624 : 11024
              $frontend = 'stormfront'
            elsif ARGV.grep(/--genie/i).any?
              processed_options[:game_host] = 'dr.simutronics.net'
              processed_options[:game_port] = ARGV.include?('--test') ? 11624 : 11024
              $frontend = 'genie'
            else
              processed_options[:game_host] = 'dr.simutronics.net'
              processed_options[:game_port] = ARGV.include?('--test') ? 11624 : 11024
              $frontend = ARGV.any? { |a| a =~ /^--avalon$/i } ? 'avalon' : ARGV.any? { |a| a =~ /^--frostbite$/i } ? 'frostbite' : ARGV.any? { |a| a =~ /^--saga$/i } ? 'saga' : 'wizard'
            end
          end
        end

        # Inspects ARGV to select the active UI frontend (-s, -w, --avalon, etc.).
        #
        # Searches ARGV for frontend flags in order: -s/--stormfront, -w/--wizard,
        # --avalon, --frostbite, --saga. Returns the first match found, or 'unknown'
        # if none are present.
        #
        # @return [String] one of 'stormfront', 'wizard', 'avalon', 'frostbite', 'saga',
        #   or 'unknown'
        # @api private
        def self.determine_frontend
          if ARGV.any? { |a| a == '-s' || a == '--stormfront' }
            'stormfront'
          elsif ARGV.any? { |a| a == '-w' || a == '--wizard' }
            'wizard'
          elsif ARGV.any? { |a| a == '--avalon' }
            'avalon'
          elsif ARGV.any? { |a| a == '--frostbite' }
            'frostbite'
          elsif ARGV.any? { |a| a == '--saga' }
            'saga'
          else
            'unknown'
          end
        end
      end

      # Main orchestrator: Step 1-4 of ARGV processing
      def self.process_argv
        # Step 1: Clean launcher.exe
        ARGV.delete_if { |arg| arg =~ /launcher\.exe/i }

        begin
          ArgNormalization.normalize!(ARGV)
        rescue ArgumentError => e
          $stderr.puts "error: #{e.message}"
          exit 1
        end

        # Step 2: Handle early-exit CLI operations (now in lib/common/cli/cli_orchestration.rb)
        Lich::Common::CLI::CLIOrchestration.execute

        # Step 3: Parse normal options and build @argv_options
        processed_options = ArgvOptions::OptionParser.execute

        # Step 4: Apply side effects and handle special cases
        processed_options = ArgvOptions::SideEffects.execute(processed_options)

        # Step 5: Handle game connection configuration
        processed_options = ArgvOptions::GameConnection.execute(processed_options)

        processed_options
      end
    end
  end
end

# Execute ARGV processing
@argv_options = Lich::Main::ArgvOptions.process_argv
