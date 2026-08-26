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
require File.join(LIB_DIR, 'main', 'help_text.rb')
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
        # Parses ARGV into a hash of option flags and values for backward compatibility.
        #
        # Processes command-line arguments including help, version, SGE/SAL linking,
        # installation, game connection details, UI settings, and launch configuration.
        # Exits immediately for early-exit operations (--help, --version, --install).
        #
        # @return [Hash] option hash with keys like :start_scripts, :host, :gui, :game,
        #   :password, :character, :frontend, :save, :pipe, :sal, :dark_mode
        # @note Modifies ARGV by calling handle_sal_file and may clear bad_args
        # @note Early-exit operations (help, version, SGE/SAL links, install) call
        #   exit and do not return
        # @api private
        def self.execute
          @argv_options = {}
          bad_args = []

          ARGV.each do |arg|
            case arg
            when '-h', '--help', /^--help=.+$/
              print_help(HelpText.topic_from_argv(ARGV, arg))
              exit
            when '-v', '--version'
              print_version
              exit
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

        # Records a SAL or Gse.~xt launch file path in argv_options, resolving
        # Windows paths and Wine prefix translations as needed.
        #
        # Sets :sal key to the resolved file path. If the file does not exist,
        # attempts to extract a Windows path from ARGV, then (if Wine is defined)
        # translates the path to a Wine drive_c location.
        #
        # @param arg [String] the SAL or .~xt file path argument
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

        # Sets dark mode flag based on --dark-mode argument value.
        #
        # Converts string values like "true", "on", "false", "off" to a strict boolean.
        #
        # @param value [String] the regex capture group from --dark-mode=(true|false|on|off)
        # @return [void]
        # @api private
        def self.handle_dark_mode(value)
          # Regex returns Integer/nil; force strict boolean for startup handling.
          @argv_options[:dark_mode] = !!(value =~ /^(true|on)$/i)
        end

        # Prints help text to stdout, optionally for a specific topic.
        #
        # @param topic [String, nil] optional help topic name; if nil, prints general help
        # @return [void]
        # @api private
        def self.print_help(topic = nil)
          puts HelpText.render(topic)
        end

        # Prints version information and copyright notices to stdout.
        #
        # @return [void]
        # @api private
        def self.print_version
          puts "The Lich, version #{LICH_VERSION}"
          puts ' (an implementation of the Ruby interpreter by Yukihiro Matsumoto designed to be a \'script engine\' for text-based MUDs)'
          puts ''
          puts '- The Lich program and all material collectively referred to as "The Lich project" is copyright (C) 2005-2006 Murray Miron.'
          puts '- The Gemstone IV and DragonRealms games are copyright (C) Simutronics Corporation.'
          puts '- The Wizard front-end and the StormFront front-end are also copyrighted by the Simutronics Corporation.'
          puts '- Ruby is (C) Yukihiro \'Matz\' Matsumoto.'
          puts ''
          puts 'Thanks to all those who\'ve reported bugs and helped me track down problems on both Windows and Linux.'
        end
      end

      # Apply side effects: dark mode, hosts-dir, bind-address, detachable-client
      module SideEffects
        # Applies side effects for dark mode, hosts directory, bind address,
        # detachable client configuration, and SAL launch file handling.
        #
        # Mutates argv_options by adding or resolving :bind_address,
        # :detachable_client_host, :detachable_client_port, :hosts_dir, and
        # processing :sal launch files. May exit with error status if
        # configuration is invalid.
        #
        # @param argv_options [Hash] mutable option hash from OptionParser.execute
        # @return [Hash] the mutated argv_options hash
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

        # Processes --hosts-dir argument and sets argv_options[:hosts_dir] if valid.
        #
        # Extracts the directory path from --hosts-dir=PATH in ARGV, validates
        # existence, normalizes slashes, and removes the argument from ARGV.
        # Warns if the directory does not exist but does not exit.
        #
        # @param argv_options [Hash] mutable option hash
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

        # Processes --detachable-client argument and configures host and port.
        #
        # Parses --detachable-client=HOST:PORT or --detachable-client=PORT,
        # resolving the host via BindHostResolver (unless port-only), and
        # inherits :bind_address from argv_options if no explicit host is given.
        # Sets :detachable_client_host and :detachable_client_port in argv_options.
        #
        # @param argv_options [Hash] mutable option hash
        # @return [void]
        # @raise [DetachableClientTarget::ParseError] if argument format is invalid
        # @raise [Lich::Common::BindHostResolver::Error] if host resolution fails
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

        # Launches a SAL or Gse.~xt file if argv_options[:sal] is set.
        #
        # Validates file existence, looks up the Simutronics launcher, and
        # executes it via Win32.ShellExecute (Windows), Wine (if defined),
        # or system() (other platforms). Logs and shows error messages, then exits
        # on failure. Exits after successful launch.
        #
        # @param argv_options [Hash] option hash with optional :sal key
        # @return [void]
        # @note Exits on file not found, launcher not found, or after successful launch
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
        # Routes game connection configuration based on ARGV flags.
        #
        # Checks for explicit -g/--game, --shattered, --fallen, and game-specific
        # flags (--gemstone, --dragonrealms) in ARGV and delegates to the
        # corresponding handler. Sets :game_host and :game_port in processed_options.
        # Falls through to set both to nil if no route matches.
        #
        # @param processed_options [Hash] mutable option hash
        # @return [Hash] the mutated processed_options hash
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

        # Handles explicit -g/--game HOST:PORT connection configuration.
        #
        # Extracts host and port from the argument following -g or --game in ARGV,
        # determines the frontend from other ARGV flags, and initializes the
        # frontend from the parent process unless --detachable-client is present.
        #
        # @param arg [String] the -g or --game flag itself
        # @param processed_options [Hash] mutable option hash
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

        # Configures GemStone IV connection details based on ARGV flags.
        #
        # Sets host to storm.gs4.game.play.net, port based on --platinum, --test,
        # and --stormfront flags, and determines the frontend (stormfront, wizard,
        # avalon, frostbite, saga) from ARGV. Sets $platinum global accordingly.
        #
        # @param processed_options [Hash] mutable option hash; sets :game_host and :game_port
        # @return [void]
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

        # Configures Shattered connection details.
        #
        # Sets host to storm.gs4.game.play.net and port to 10324.
        # Determines frontend from ARGV (stormfront or wizard/avalon/frostbite/saga default).
        # Sets $platinum to false.
        #
        # @param processed_options [Hash] mutable option hash; sets :game_host and :game_port
        # @return [void]
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

        # Configures Fallen connection details.
        #
        # Sets host to dr.simutronics.net and port to 11324.
        # Determines frontend from ARGV (stormfront, genie, or wizard/avalon/frostbite/saga default).
        # Sets $platinum to false.
        #
        # @param processed_options [Hash] mutable option hash; sets :game_host and :game_port
        # @return [void]
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

        # Configures DragonRealms connection details based on ARGV flags.
        #
        # Sets host to dr.simutronics.net, port based on --platinum, --test,
        # and --stormfront/--genie flags, and determines frontend from ARGV.
        # Sets $platinum global accordingly.
        #
        # @param processed_options [Hash] mutable option hash; sets :game_host and :game_port
        # @return [void]
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

        # Returns the frontend name based on ARGV flags.
        #
        # Checks for -s/--stormfront, -w/--wizard, --avalon, --frostbite, and --saga
        # in ARGV in that order of precedence.
        #
        # @return [String] the frontend name: "stormfront", "wizard", "avalon",
        #   "frostbite", "saga", or "unknown" if no flag matches
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
