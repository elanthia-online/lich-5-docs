# frozen_string_literal: true

require 'openssl'
require_relative 'common/shutdown_log'
require_relative 'common/game_transport'
require_relative 'common/room_block'
require_relative 'common/markup'
require_relative 'common/room_description_filter'
require_relative 'common/client_capabilities'

# Modernized version of games.rb with separated DR and GS functionality
# Original module carve out from lich.rbw
# Refactored on 2025-04-01

# Root namespace for Lich5, a Ruby scripting engine for GemStone IV and DragonRealms.
# Encapsulates game connection management, XML parsing, client communication, and
# game-specific behavior (GemStone versus DragonRealms).
module Lich
  # Base module for game-specific functionality
  # Unknown game type module
  module Unknown
    # Placeholder module for unknown game types; games with identifiable types
    # load concrete implementations under Lich::Gemstone or Lich::DragonRealms.
    # @api private
    module Game
      # Placeholder for unknown game types
    end
  end

  # Common module for shared functionality
  module Common
    # Placeholder for common game functionality
  end

  # Namespace for game-instance base classes, mixins, and shared server-stream
  # processing logic used by both GemStone and DragonRealms.
  module GameBase
    # Game-agnostic formatting for the Lich-injected room annotations
    # (room number, obvious exits, and StringProc exits). Both the GemStone
    # and DragonRealms game instances mix this in so the font and clickable-link
    # toggles behave identically regardless of game: the module decides *how* an
    # annotation looks, while each game instance decides *which* lines/streams to
    # emit. Extracting it removes the near-duplicate exit/StringProc rendering
    # that previously lived in both #process_room_display implementations.
    #
    # Two independent settings drive it:
    # - Lich.display_room_links - clickable <d> command links vs plain text
    # - Lich.display_room_mono  - fixed-width mono style vs the proportional game font
    #
    # The mono wrapper only escapes nothing and merely brackets the line, so a
    # mono line can still contain live <d> links (the two toggles are orthogonal).
    #
    # Escaping: unlike respond (which HTML-escapes &, <, > for the classic
    # roomnumbers.lic path), neither the mono wrapper nor the plain-text entries
    # escape anything. This is deliberate - the links path emits live <d> markup
    # that must survive verbatim, and both paths are kept consistent so a toggle
    # never silently changes escaping. Exit commands and room titles come from the
    # mapdb and contain no markup in practice; if untrusted text is ever fed here
    # the caller must escape it first.
    module RoomFormatter
      # Obvious compass / up / down / out exits (usually rendered by the game
      # itself), excluded from the "Room Exits:" line. Hoisted here so the GS and
      # DR paths share a single, identical definition.
      OBVIOUS_EXIT_PATTERN = /^(?:o|d|u|n|ne|e|se|s|sw|w|nw|out|down|up|north|northeast|east|southeast|south|southwest|west|northwest)$/.freeze

      # Everything below is internal formatting detail, marked +private+ so the
      # mixin adds no new public surface to the game instances that include it.
      # The game #process_room_display methods reach these via implicit self
      # (which is legal for private methods); the unit specs exercise them
      # through a throwaway host class that re-publicizes them.
      private

      # Whether the injected room lines should render in the fixed-width mono
      # style. Gated on the frontend actually supporting mono so non-mono clients
      # never receive stray <output> tags (mirrors respond's own guard).
      # @return [Boolean]
      # @api private
      def room_mono?
        Lich.display_room_mono && Frontend.supports_mono?
      end

      # Whether room exits should render as clickable <d> command links.
      # @return [Boolean]
      # @api private
      def room_links?
        Lich.display_room_links
      end

      # Wraps a completed line body in the classic mono style when enabled, else
      # returns it unchanged. Never escapes, so any <d> links in body survive.
      # @param body [String] the fully built line (label plus entries)
      # @return [String] the styled (or unchanged) line
      # @api private
      def room_styled(body)
        room_mono? ? "<output class=\"mono\"/>#{body}<output class=\"\"/>" : body
      end

      # Builds the StringProc-exit entries for the current room, honoring the
      # links toggle. Returns [] when the feature is off so callers add no line
      # and Map is not touched.
      # NOTE: StringProc overrides #class and #kind_of? (both report Proc), so
      # detection MUST use #is_a?, which reflects the real class - see
      # lib/common/class_exts/stringproc.rb.
      # @return [Array<String>] formatted entries (links or plain labels)
      # @api private
      def room_stringproc_entries
        return [] unless Lich.display_stringprocs

        entries = []
        Map.current.wayto.each do |key, value|
          next unless value.is_a?(StringProc)
          # Only routable StringProcs (a numeric travel time) are useful to show.
          timeto = Map.current.timeto[key]
          next unless timeto.is_a?(Numeric) || (timeto.is_a?(StringProc) && timeto.call.is_a?(Numeric))
          # Guard against a dangling wayto reference (destination room missing
          # from the mapdb) rather than crashing the whole downstream hook.
          dest = Map[key]
          next if dest.nil?

          label = "#{dest.title.first.gsub(/\[|\]/, '')}#{Lich.display_lichid ? "(#{dest.id})" : ''}"
          entries << (room_links? ? "<d cmd=';go2 #{key}'>#{label}</d>" : label)
        end
        entries
      end

      # Builds the obvious-exit entries (non-compass go/climb style exits) for the
      # current room, honoring the links toggle. Returns [] when the feature is
      # off so callers add no line and Map is not touched.
      # @return [Array<String>] formatted entries (links or plain commands)
      # @api private
      def room_exit_entries
        return [] unless Lich.display_exits

        entries = []
        Map.current.wayto.each_value do |value|
          next if value.to_s =~ OBVIOUS_EXIT_PATTERN
          next if value.is_a?(StringProc)

          # Derive the command via to_s (as the OBVIOUS_EXIT_PATTERN check above
          # already does) before #dump, so a non-String wayto value is coerced
          # rather than raising NoMethodError inside the downstream hook. For the
          # String values the mapdb actually stores, value.to_s is the same object
          # so this is byte-identical to the previous value.dump.
          cmd = value.to_s.dump[1..-2]
          entries << (room_links? ? "<d cmd='#{cmd}'>#{cmd}</d>" : cmd)
        end
        entries
      end

      # Prepends the shared "StringProcs:" and "Room Exits:" lines (in that
      # order, so exits end up above StringProcs and any later room-number line
      # ends up above both) to alt_string, each only when it has entries. This is
      # the composition both games share. Entries are passed in (built once by the
      # caller) so a game that also reuses them - e.g. the GemStone room-window
      # mirror - does not iterate Map.current.wayto twice.
      # @param alt_string [String] the server string being rewritten
      # @param stringproc_entries [Array<String>] pre-built StringProc entries
      # @param exit_entries [Array<String>] pre-built obvious-exit entries
      # @return [String] alt_string with the room lines prepended
      # @api private
      def prepend_room_lines(alt_string, stringproc_entries, exit_entries)
        alt_string = "#{room_styled("StringProcs: #{stringproc_entries.join(', ')}")}\r\n#{alt_string}" unless stringproc_entries.empty?
        alt_string = "#{room_styled("Room Exits: #{exit_entries.join(', ')}")}\r\n#{alt_string}" unless exit_entries.empty?
        alt_string
      end
    end

    # Factory for creating game-specific objects
    module GameInstanceFactory
      # Factory method that instantiates a game-specific handler.
      #
      # Dispatches on the game type ("GS" for GemStone, "DR" for DragonRealms) and
      # returns the appropriate GameInstance subclass. Falls back to a basic no-op
      # implementation if the game type is unknown.
      #
      # @param game_type [String] the game identifier (e.g., "GS", "DR")
      # @return [Lich::GameBase::GameInstance::Base] a concrete game handler
      # @api private
      def self.create(game_type)
        case game_type
        when /^GS/
          Gemstone::GameInstance.new
        when /^DR/
          DragonRealms::GameInstance.new
        else
          # Default to a basic implementation if game type is unknown
          GameInstance::Base.new
        end
      end
    end

    # Game instance interface for game-specific behaviors
    module GameInstance
      # Base instance class that defines the interface
      class Base
        include RoomFormatter

        # A roundtime refusal, cut into a line when something precedes it.
        SPLIT_REFUSAL = /\.\.\.wait \d+ seconds?\.\r\n\z/.freeze

        def initialize
          @atmospherics = false
          @combat_count = 0
          @end_combat_tags = ["<prompt", "<clearStream", "<component", "<pushStream id=\"percWindow"]
          # The part of a line before a refusal cut, held for one line until
          # the rest arrives (#buffer_split_line); nil when nothing is held.
          @split_held = nil
        end

        def clean_serverstring(server_string)
          raise NotImplementedError, "#{self.class} must implement #clean_serverstring"
        end

        # Shared by both games; override in a subclass only if a game's stream handling diverges.
        def handle_combat_tags(server_string)
          if @combat_count > 0
            @end_combat_tags.each do |tag|
              if server_string.include?(tag)
                server_string = server_string.gsub(tag, "<popStream id=\"combat\" />" + tag) unless server_string.include?("<popStream id=\"combat\" />")
                @combat_count -= 1
              end
              if server_string.include?("<pushStream id=\"combat\" />")
                server_string = server_string.gsub("<pushStream id=\"combat\" />", "")
              end
            end
          end

          increment_combat_count(server_string)
          server_string
        end

        # Tracks and suppresses the atmospherics stream tag pair.
        #
        # The atmospherics stream (e.g., empath appraisals, echoes from spells/abilities)
        # wraps its content in <pushStream id="atmospherics" /> and <popStream />.
        # Some game states emit a prompt immediately after the open tag, causing a stray
        # "[story]>" to appear. This method detects and suppresses that condition,
        # tracking state in @atmospherics across calls.
        #
        # Modifies server_string in place.
        #
        # @param server_string [String] the server line being processed
        # @return [String] the line with atmospherics artifacts removed or suppressed
        # @api private
        def handle_atmospherics(server_string)
          if @atmospherics
            @atmospherics = false
            server_string.prepend('<popStream id="atmospherics" />') unless server_string =~ /<popStream id="atmospherics" \/>/
          end

          if server_string =~ /<pushStream id="familiar" \/><prompt time="[0-9]+">&gt;<\/prompt>/ # Cry For Help spell is broken...
            server_string.sub!('<pushStream id="familiar" />', '')
          elsif server_string =~ /<pushStream id="atmospherics" \/><prompt time="[0-9]+">&gt;<\/prompt>/ # pet pigs in DragonRealms are broken...
            server_string.sub!('<pushStream id="atmospherics" />', '')
          elsif (server_string =~ /<pushStream id="atmospherics" \/>/)
            @atmospherics = true
          end

          server_string
        end

        def get_documentation_url
          raise NotImplementedError, "#{self.class} must implement #get_documentation_url"
        end

        def process_game_specific_data(server_string, stripped_server = nil)
          raise NotImplementedError, "#{self.class} must implement #process_game_specific_data"
        end

        def modify_room_display(alt_string)
          raise NotImplementedError, "#{self.class} must implement #modify_room_display"
        end

        # Renders room exits, StringProc destinations, and optional room-number lines.
        #
        # Subclasses override to prepend "Room Exits:" and "StringProcs:" lines, and for
        # DragonRealms, a "Room Number:" line and room-window subtitle. Called when a
        # prompt appears after a room block, honoring the room-display toggles
        # (display_exits, display_stringprocs, display_lichid, display_uid).
        #
        # @param alt_string [String] the server string being rewritten
        # @return [String] the rewritten string with room lines prepended
        # @api private
        def process_room_display(alt_string)
          raise NotImplementedError, "#{self.class} must implement #process_room_display"
        end

        # Rewrites a client-bound line for front ends that predate parts of
        # this game's stream. Runs on the client path only, once per distinct
        # client capability set, after the downstream hooks and the <room>
        # rewrite and before the Wizard conversion (sf_to_wiz). No change
        # unless the game overrides it.
        # @param alt_string [String] the server string on its way to the client
        # @param _capabilities [Array<Symbol>, nil] the client's rich-stream
        #   capabilities (Lich::Common::ClientCapabilities); nil means the
        #   session's set (ClientCapabilities.session_default)
        # @return [String] the string to send
        def adapt_for_frontend(alt_string, _capabilities = nil)
          alt_string
        end

        # Returns the current count of open combat streams.
        #
        # Incremented when <pushStream id="combat" /> appears, decremented on
        # <popStream id="combat" />. Used to track whether combat text is active.
        #
        # @return [Integer] the count (0 or more)
        # @api private
        def combat_count
          @combat_count
        end

        # Returns whether atmospherics stream is currently open and waiting for closure.
        #
        # @return [Boolean]
        # @api private
        def atmospherics
          @atmospherics
        end

        # Sets the atmospherics stream state.
        #
        # @param value [Boolean]
        # @return [Boolean]
        # @api private
        def atmospherics=(value)
          @atmospherics = value
        end

        # Rejoins a line the server cut with a roundtime refusal. The server
        # puts "...wait N seconds.\r\n" into the line it was sending, after
        # whatever it had sent of it, and then sends the rest of the line: its
        # remaining text, or only its line end, as an empty line. A standalone
        # refusal starts its line and is never followed by an empty line.
        #
        # The refusal is returned at once as a line of its own, where
        # WAIT_RESPONSE_PATTERN finds it, and the part before it is held and
        # joined to the next line, which is released whatever it holds. The
        # game keeps each element, a <room> block included, on one line, so
        # the rest of a cut element arrives in that one line too.
        #
        # @param server_string [String]
        # @return [String] the line to process now
        def buffer_split_line(server_string)
          return hold_split_line(server_string) unless @split_held

          line = @split_held + server_string
          @split_held = nil
          Lich.log "Rejoined a line cut by a roundtime refusal: #{line.inspect}"
          hold_split_line(line)
        end

        protected

        def hold_split_line(server_string)
          match = SPLIT_REFUSAL.match(server_string)
          return server_string if match.nil? || match.pre_match.empty?

          @split_held = match.pre_match
          match[0]
        end

        def increment_combat_count(server_string)
          @combat_count += server_string.scan("<pushStream id=\"combat\" />").length
          @combat_count -= server_string.scan("<popStream id=\"combat\" />").length
          @combat_count = 0 if @combat_count < 0
        end
      end
    end

    # XML string cleaner module
    module XMLCleaner
      class << self
        # Repairs nested quotes inside XML attribute values.
        #
        # The server occasionally sends attributes with nested quotes (e.g.,
        # title='Tsetem\'s Items', or the settingsInfo space-not-found bug)
        # that break XML parsers. This method escapes the inner quotes as &apos; or &quot;
        # and logs the repair.
        #
        # Modifies server_string in place.
        #
        # @param server_string [String] the malformed server line
        # @return [String] the repaired line
        # @api private
        def clean_nested_quotes(server_string)
          # Fix nested single quotes
          unless (matches = server_string.scan(/'([^=>]*'[^=>]*)'/)).empty?
            Lich.log "Invalid nested single quotes XML tags detected: #{server_string.inspect}"
            matches.flatten.each do |match|
              server_string.gsub!(match, match.gsub(/'/, '&apos;'))
            end
            Lich.log "Invalid nested single quotes XML tags fixed to: #{server_string.inspect}"
          end

          # Fix nested double quotes
          unless (matches = server_string.scan(/"([^=>]*"[^=>]*)"/)).empty?
            Lich.log "Invalid nested double quotes XML tags detected: #{server_string.inspect}"
            matches.flatten.each do |match|
              server_string.gsub!(match, match.gsub(/"/, '&quot;'))
            end
            Lich.log "Invalid nested double quotes XML tags fixed to: #{server_string.inspect}"
          end

          server_string
        end

        # Strips invalid characters that break XML parsing.
        #
        # Removes bell characters (\a) and other encodings that Ox cannot tolerate.
        # Logs each detected and repaired instance.
        #
        # Modifies server_string in place.
        #
        # @param server_string [String] the server line
        # @return [String] the cleaned line
        # @api private
        def fix_invalid_characters(server_string)
          # Note: a bare '&' is intentionally not escaped here. REXML raised on it
          # (hence the old escaping); Ox tolerates it (convert_special: false emits
          # it verbatim with no error), so escaping is no longer needed for parsing.

          # Fix bell character
          if server_string.include?("\a")
            Lich.log "Invalid \\a detected: #{server_string.inspect}"
            server_string.gsub!("\a", '')
            Lich.log "Invalid \\a stripped out: #{server_string.inspect}"
          end

          server_string
        end

        # Repairs common XML tag malformations from the game stream.
        #
        # Fixes open-ended dynaStream and component tags, removes dangling closing tags,
        # and strips unclosed tags in long empath-appraisal strings. Logs each repair.
        #
        # Modifies server_string in place.
        #
        # @param server_string [String] the server line
        # @return [String] the repaired line
        # @api private
        def fix_xml_tags(server_string)
          # Fix open-ended XML tags
          if /^<(?<xmltag>dynaStream|component) id='.*'>[^<]*(?!<\/\k<xmltag>>)\r\n$/ =~ server_string
            Lich.log "Open-ended #{xmltag} tag: #{server_string.inspect}"
            server_string.gsub!("\r\n", "</#{xmltag}>")
            Lich.log "Open-ended #{xmltag} tag fixed to: #{server_string.inspect}"
          end

          # Remove dangling closing tags
          if server_string =~ /^(?:(\"|<compass><\/compass>))?<\/(dynaStream|component)>\r\n/
            Lich.log "Extraneous closing tag detected and deleted: #{server_string.inspect}"
            server_string = ""
          end

          # Remove unclosed tag in long strings from empath appraisals
          if server_string =~ / and <d cmd=\"transfer .+? nerves\">a/
            Lich.log "Unclosed wound (nerves) tag detected and deleted: #{server_string.inspect}"
            server_string.sub!(/ and <d cmd=\"transfer .+? nerves\">a.+?$/, " and more.")
          end

          server_string
        end
      end
    end

    # Raised when a server fragment is structurally truncated (cut off
    # mid-element) -- the stream has desynced from XML framing. Pre-Ox, strict
    # REXML raised on these fragments and Game.process_xml_data's rescue logged
    # the fragment and reset XMLData, so parser strictness doubled as desync
    # detection. Ox is permissive: it parses truncated fragments without
    # raising (auto-closing elements, fabricating empty attribute values) and
    # only reports the damage through its optional error callback. That
    # callback is now the only desync signal, so process_xml_data promotes
    # truncation-class parse errors to this exception to keep the old
    # recovery path (log + XMLData.reset).
    class GameStreamDesyncError < StandardError; end

    # Ox error-callback messages that mean the fragment ended mid-token -- the
    # only unambiguous truncation signal, since a complete line cannot end inside
    # an open tag, attribute list, or quoted value. (In practice genuine
    # truncation is an edge case: reads are newline-delimited via @socket.gets,
    # Simu keeps each tag on one line, multi-line content is reassembled upstream
    # by buffer_split_line, and #4's tag_end guard keeps @active_tags balanced
    # regardless. This is a backstop for a partial read at disconnect.)
    #
    # Ox also fires the callback for Simu's routine almost-XML -- bare text and
    # multiple top-level elements ('text not terminated', 'multiple top level
    # elements'), unescaped ampersands ('Invalid special character sequence'),
    # missing </d> end tags ('Start End Mismatch: ... not closed') -- none of
    # which match these patterns, so they stay tolerated. Nested quotes are the
    # exception: alongside 'no attribute value' they can also report 'document
    # not terminated' and 'element not closed' on a complete line, which is why
    # process_xml_data repairs them before checking.
    #
    # The message prefix matters: 'Unexpected Character: element not closed' (a
    # start tag that never got its '>') is truncation, while the similarly
    # worded 'Start End Mismatch: element ... not closed' (an element missing
    # its end tag) is routine.
    #
    # 'attribute value not in quotes' is intentionally NOT here: it fires on a
    # *complete* unquoted-attribute line (<a x=y>), so matching it false-resets a
    # fully-parsed fragment. A truncated unquoted attr (<a x=y) still resets via
    # 'attributes not terminated' / 'element not closed' below.
    STREAM_DESYNC_ERRORS = [
      /\ANot Terminated: attributes not terminated/,
      /\ANot Terminated: quoted value not terminated/,
      /\ANot Terminated: document not terminated/,
      /\AUnexpected Character: element not closed/
    ].freeze

    # Ox's signature when a tag scatters into valueless attributes: the
    # settingsInfo space-not-found bug, or a same-quote inside a quoted value
    # (e.g. title='Tsetem's Items'), where the inner quote ends the value early.
    # (A genuinely valueless attribute, <a foo>, reports the same thing, but the
    # repairs leave it unchanged so no reparse happens.)
    NO_ATTRIBUTE_VALUE_ERROR = /\AUnexpected Character: no attribute value/

    # Base Game class with common functionality
    class Game
      # Exception raised when the server-stream processing queue reaches capacity.
      #
      # @api private
      class ServerQueueOverflow < StandardError; end

      # Seconds to wait for readable game socket data before one read timeout.
      READ_TIMEOUT_SECONDS = 100

      # Consecutive read timeouts allowed before treating the game link as dead.
      MAX_CONSECUTIVE_READ_TIMEOUTS = 3

      # Sentinel returned when the game socket has no readable data before timeout.
      READ_TIMEOUT = Object.new.freeze

      # A full queue means the parser cannot preserve the game stream. Dropping
      # records or blocking the socket reader would both make recovery unsafe.
      SERVER_QUEUE_CAPACITY = 4_096

      class << self
        attr_reader :thread, :reader_thread, :server_queue, :buffer, :_buffer, :game_instance

        # Timestamp already attached by the socket reader before queueing.
        # Available only during this exact parser thread's current dispatch;
        # delayed subscribers and legacy direct calls cannot mint provenance.
        # @return [Numeric, nil] monotonic receipt time, or nil outside a valid
        #   socket-origin parser dispatch
        def current_ingress_time
          return nil unless Thread.current.equal?(@thread)

          value = Thread.current.thread_variable_get(:lich_game_ingress_time)
          value if value.is_a?(Numeric) && value.real? && value.finite? && value >= 0
        end

        # Returns whether the autostart script has run.
        #
        # @return [Boolean]
        # @api private
        def autostarted?
          @@autostarted
        end

        # Prepends the origin sentinel to every line in a multi-line string.
        #
        # Used for front ends that support the origin-sentinel feature; each line
        # receives the sentinel prefix so the client can tag output as game-sourced.
        #
        # @param string [String] a server string with one or more \r\n-delimited lines
        # @return [String] the same string with Frontend::ORIGIN_SENTINEL prepended to each line
        # @api private
        def prefix_origin_sentinel(string)
          string.gsub(/^.+$/) { |line| "#{Frontend::ORIGIN_SENTINEL}#{line}" }
        end

        # Returns whether the client settings record needs initialization.
        #
        # Set to true when the settingsInfo XML is repaired from the space-not-found bug,
        # signaling gameloader's PostLoad hook to seed a valid client entry.
        #
        # @return [Boolean]
        # @api private
        def settings_init_needed?
          @@settings_init_needed
        end

        # Initializes or resets Game thread state and buffers.
        #
        # Clears socket, mutexes, queues, and buffers; sets thread references to nil;
        # resets autostart and CLI-script flags. Called at startup and on reconnect/reset.
        # Also clears the global strip_xml multiline carry-over so a fragment left open
        # before a disconnect does not bleed into the next session.
        #
        # @return [void]
        # @api private
        def initialize_buffers
          @socket = nil
          @mutex = Mutex.new
          @last_recv = nil
          @thread = nil
          @reader_thread = nil
          @remote_eof = false
          @server_queue = SizedQueue.new(SERVER_QUEUE_CAPACITY)
          reset_server_queue_stats!
          @buffer = Lich::Common::SharedBuffer.new
          @_buffer = Lich::Common::SharedBuffer.new
          @_buffer.max_size = 1000
          @@autostarted = false
          @@settings_init_needed = false
          @cli_scripts = false
          @room_number_after_ready = false
          @last_id_shown_room_window = 0
          @game_instance = nil
          # strip_xml's multiline carry is a process-global; clear it here so a
          # fragment left open before a reconnect/session reset does not bleed
          # into the next session.
          $strip_xml_multiline = {}
        end

        # Instantiates the game-specific handler for the identified game.
        #
        # Called after the server identifies itself (via XMLData.game). Dispatches to
        # GameInstanceFactory.create, which returns the appropriate subclass
        # (Gemstone::GameInstance or DragonRealms::GameInstance).
        #
        # @param game_type [String] the game identifier ("GS" or "DR")
        # @return [void]
        # @api private
        def set_game_instance(game_type)
          @game_instance = GameInstanceFactory.create(game_type)
        end

        # Opens the connection to the game server and starts the socket's
        # wrap and main reader threads.
        #
        # @param host [String] game server hostname
        # @param port [Integer] game server port
        # @param transport [Symbol] Lich::Common::GameTransport::DIRECT (default,
        #   a raw TCP socket -- the connection method Lich has always used) or
        #   ::WEBSOCKET (opt-in; the browser WebSocket-to-TCP shim over TLS on
        #   443 -- see Genie5#356 phase 2). Socket-level tuning (keepalive,
        #   linger, timeouts, TCP_NODELAY) is applied for both.
        # @param transport_opts [Hash] forwarded to
        #   Lich::Common::GameTransport.open (WEBSOCKET-only knobs: shim_port,
        #   path, origin, subprotocol, user_agent, extra_headers, connect_timeout)
        # @return [Socket, Lich::Common::WebSocket::Stream] the connected,
        #   configured game socket
        # @note Connection errors propagate to the caller. Use
        #   {.open_with_timeout} to bound how long the connect may block.
        # @see .open_with_timeout
        def open(host, port, transport: Lich::Common::GameTransport::DIRECT, **transport_opts)
          @remote_eof = false
          @socket = Lich::Common::GameTransport.open(host, port, mode: transport, **transport_opts)
          @socket.sync = true

          start_wrap_thread
          start_main_thread

          @socket
        end

        # Connects to the game server on a background thread, enforcing a connect
        # timeout that a bare {.open} cannot. Surfaces a stuck or failed connect
        # instead of letting startup proceed with a dead socket.
        #
        # @param host [String] game server hostname
        # @param port [Integer] game server port
        # @param timeout [Integer, Float] seconds to wait for the connect to complete
        # @param transport [Symbol] see {.open}
        # @param transport_opts [Hash] see {.open}
        # @return [void]
        # @raise [RuntimeError] if the connect does not complete within +timeout+
        # @raise [StandardError] re-raises whatever {.open} raises
        #   (e.g. Errno::ECONNREFUSED) so the caller's rescue runs
        # @see .open
        def open_with_timeout(host, port, timeout = 30, transport: Lich::Common::GameTransport::DIRECT, **transport_opts)
          connect_thread = Thread.new {
            # report_on_exception off: a failed open is surfaced by the join below
            # (which re-raises it), not by an auto-printed thread warning.
            Thread.current.report_on_exception = false
            self.open(host, port, transport: transport, **transport_opts)
          }
          # join returns nil on timeout, the thread on success, and re-raises the
          # thread's exception on failure -- so a Game.open that errors (e.g.
          # connection refused) propagates to the caller's rescue instead of being
          # silently swallowed (the old `if connect_thread.status` could not tell a
          # thread that died with an exception, status nil, from a normal finish,
          # status false).
          if connect_thread.join(timeout).nil?
            connect_thread.kill rescue nil
            raise "error: timed out connecting to #{host}:#{port}"
          end
        end

        # Starts a thread that sends 'look' if autostart takes too long.
        #
        # Vacuum the database if due, then spawn a thread that waits up to 6 seconds for
        # the autostart script to complete. If the script has not set @@autostarted by then,
        # send 'look' to prompt for a room description. Ensures the player sees room data
        # even if autostart hangs or fails.
        #
        # @return [void]
        # @api private
        def start_wrap_thread
          begin
            Lich.db_vacuum_if_due!(months: 6)
          rescue => e
            Lich.log "db_maint(startup): #{e.class}: #{e.message}"
          end

          @wrap_thread = Thread.new do
            @last_recv = Time.now
            until @@autostarted || (Time.now - @last_recv >= 6)
              break if @@autostarted
              sleep 0.2
            end

            puts 'look' unless @@autostarted
          end
        end

        # Returns whether the game socket is closed or nil.
        #
        # @return [Boolean]
        # @api private
        def closed?
          @socket.nil? || @socket.closed?
        end

        # @return [Boolean] whether the game server closed its side of the socket
        def remote_eof?
          @remote_eof == true
        end

        # Zeroes queue and timing statistics.
        #
        # Clears counters for enqueue/dequeue events, queue depth tracking, hook/enqueue/
        # parse timings, and reader/parser thread status. Called at startup and when
        # explicitly requested via server_queue_stats(reset: true).
        #
        # @return [void]
        # @api private
        def reset_server_queue_stats!
          @server_queue_enqueued = 0
          @server_queue_dequeued = 0
          @server_queue_last_depth = @server_queue&.length.to_i
          @server_queue_max_depth = @server_queue_last_depth
          @server_queue_last_enqueue_at = nil
          @server_queue_last_dequeue_at = nil
          @server_queue_last_wait = nil
          @server_queue_max_wait = 0.0
          @server_queue_total_wait = 0.0
          @server_reader_hook_last = nil
          @server_reader_hook_max = 0.0
          @server_reader_hook_total = 0.0
          @server_reader_enqueue_last = nil
          @server_reader_enqueue_max = 0.0
          @server_reader_enqueue_total = 0.0
          @server_reader_process_last = nil
          @server_reader_process_max = 0.0
          @server_reader_process_total = 0.0
          @server_parser_last = nil
          @server_parser_max = 0.0
          @server_parser_total = 0.0
          nil
        end

        # Returns a snapshot of server-stream queue and timing statistics.
        #
        # Computes averages from totals, converts timings to milliseconds, and reports
        # thread status. Useful for monitoring parser performance and diagnosing stalls.
        # Can optionally reset counters after collection.
        #
        # @param reset [Boolean] whether to zero statistics after this snapshot
        # @return [Hash] keys include depth, max_depth, enqueued, dequeued, *_wait_ms,
        #   *_max_ms, *_avg_ms, reader_status, parser_status
        # @api private
        def server_queue_stats(reset: false)
          depth = @server_queue&.length.to_i
          dequeued = @server_queue_dequeued.to_i
          last_wait = @server_queue_last_wait
          max_wait = @server_queue_max_wait.to_f
          avg_wait = dequeued.positive? ? @server_queue_total_wait.to_f / dequeued : 0.0
          enqueued = @server_queue_enqueued.to_i
          hook_last = @server_reader_hook_last
          hook_max = @server_reader_hook_max.to_f
          hook_avg = enqueued.positive? ? @server_reader_hook_total.to_f / enqueued : 0.0
          enqueue_last = @server_reader_enqueue_last
          enqueue_max = @server_reader_enqueue_max.to_f
          enqueue_avg = enqueued.positive? ? @server_reader_enqueue_total.to_f / enqueued : 0.0
          process_last = @server_reader_process_last
          process_max = @server_reader_process_max.to_f
          process_avg = enqueued.positive? ? @server_reader_process_total.to_f / enqueued : 0.0
          parser_last = @server_parser_last
          parser_max = @server_parser_max.to_f
          parser_avg = dequeued.positive? ? @server_parser_total.to_f / dequeued : 0.0
          stats = {
            depth: depth,
            last_depth: @server_queue_last_depth.to_i,
            max_depth: [@server_queue_max_depth.to_i, depth].max,
            enqueued: enqueued,
            dequeued: dequeued,
            last_wait: last_wait,
            max_wait: max_wait,
            avg_wait: avg_wait,
            last_wait_ms: last_wait ? (last_wait * 1000.0).round(3) : nil,
            max_wait_ms: (max_wait * 1000.0).round(3),
            avg_wait_ms: (avg_wait * 1000.0).round(3),
            reader_hook_last_ms: hook_last ? (hook_last * 1000.0).round(3) : nil,
            reader_hook_max_ms: (hook_max * 1000.0).round(3),
            reader_hook_avg_ms: (hook_avg * 1000.0).round(3),
            reader_enqueue_last_ms: enqueue_last ? (enqueue_last * 1000.0).round(3) : nil,
            reader_enqueue_max_ms: (enqueue_max * 1000.0).round(3),
            reader_enqueue_avg_ms: (enqueue_avg * 1000.0).round(3),
            reader_process_last_ms: process_last ? (process_last * 1000.0).round(3) : nil,
            reader_process_max_ms: (process_max * 1000.0).round(3),
            reader_process_avg_ms: (process_avg * 1000.0).round(3),
            parser_process_last_ms: parser_last ? (parser_last * 1000.0).round(3) : nil,
            parser_process_max_ms: (parser_max * 1000.0).round(3),
            parser_process_avg_ms: (parser_avg * 1000.0).round(3),
            last_enqueue_at: @server_queue_last_enqueue_at,
            last_dequeue_at: @server_queue_last_dequeue_at,
            reader_status: @reader_thread&.status,
            parser_status: @thread&.status
          }
          reset_server_queue_stats! if reset
          stats
        end

        # Closes the game socket and stops reader/parser threads.
        #
        # @return [void]
        # @api private
        def close
          if @socket
            @socket.close rescue nil
            @reader_thread.kill rescue nil
            @thread.kill rescue nil
          end
        end

        # Writes a string to the game server socket.
        #
        # Thread-safe via mutex. Silently absorbs fatal connection errors
        # so callers (scripts) are not killed by a broken server link.
        # A calling script's execution guard receives an immutable copy of the
        # exact wire command: puts has already added $cmd_prefix, while direct
        # _puts callers supply their own prefix. Checks run under the write lock
        # and are charged once here, never again in puts.
        #
        # @param str [String] the raw command to send upstream
        # @return [true, nil] true when written; nil on connection error
        # @raise [Common::ScriptExecutionGuard::Interrupted] if the calling
        #   script's installed policy rejects the write
        def _puts(str)
          # Raw callers may hold other shared locks (e.g. Inventory.refresh).
          # Preserve their pause-free sends while still resolving their guard.
          script = Script.current_without_pause
          # A guard callback must not reenter the socket. Let Script's guard
          # recursion check reject it before Ruby attempts to relock the mutex.
          if @mutex.owned? && script.respond_to?(:check_execution_guard!) &&
             script.respond_to?(:execution_guard_active?) && script.execution_guard_active?
            script.check_execution_guard!(command: str.to_s.dup.freeze)
          end
          @mutex.synchronize do
            # Recheck the captured owner's current policy here
            # after lock contention; do not retain an earlier permission result.
            guarded = script.respond_to?(:check_execution_guard!) &&
                      script.respond_to?(:execution_guard_active?) && script.execution_guard_active?
            command = guarded ? str.to_s.dup.freeze : str
            script.check_execution_guard!(command: command) if guarded
            begin
              @socket.puts(command)
              true
            rescue Errno::EPIPE, Errno::ECONNRESET, Errno::ECONNABORTED, IOError, OpenSSL::SSL::SSLError => e
              Lich.log "error: _puts: #{e}\n\t#{e.backtrace.first}"
              nil
            end
          end
        end

        # Send a prefixed command and record its script-labelled client display.
        # Guarded callers pass policy checks before a command is displayed.
        # @param str [String] command without the client prefix
        # @return [String] upstream display record; not proof of game acceptance
        # @raise [Common::ScriptExecutionGuard::Interrupted] if the calling
        #   script's installed policy rejects continuation or dispatch
        def puts(str)
          script = Script.current
          if script&.file_name
            script_name = "#{script.custom? ? 'custom/' : ''}#{script.name}"
          else
            script_name = script&.name || '(unknown script)'
          end

          guarded = script.respond_to?(:check_execution_guard!) &&
                    script.respond_to?(:execution_guard_active?) && script.execution_guard_active?
          if guarded
            # Rejected guarded commands must not appear as sent. Snapshot both
            # display and wire strings so callback edits cannot change history.
            str = str.to_s.dup.freeze
            wire_command = "#{$cmd_prefix}#{str}".freeze
            _puts wire_command
          end

          $_CLIENTBUFFER_.push "[#{script_name}]#{$SEND_CHARACTER}#{guarded ? wire_command : "#{$cmd_prefix}#{str}"}\r\n"

          unless script&.silent
            respond "[#{script_name}]#{$SEND_CHARACTER}#{str}\r\n"
          end

          _puts "#{$cmd_prefix}#{str}" unless guarded
          $_LASTUPSTREAM_ = "[#{script_name}]#{$SEND_CHARACTER}#{str}"
        end

        # Reads one stripped server line from the main buffer.
        #
        # @return [String, nil] a line from the parsed stream, or nil if buffer is exhausted
        # @api private
        def gets
          @buffer.gets
        end

        # Reads one raw server line from the internal buffer (testing only).
        #
        # @return [String, nil] a line as the server sent it, or nil if buffer is exhausted
        # @api private
        def _gets
          @_buffer.gets
        end

        # Initializes the server-stream queue and spawns reader and processor threads.
        #
        # Creates a fresh SizedQueue and resets stats, then starts the socket-reader thread
        # (which pulls raw lines from the game socket) and the server-processor thread
        # (which parses and hooks into those lines). Both run until close or an error.
        #
        # @return [void]
        # @api private
        def start_main_thread
          @server_queue = SizedQueue.new(SERVER_QUEUE_CAPACITY)
          reset_server_queue_stats!
          start_socket_reader_thread
          start_server_processor_thread
        end

        # Records an enqueue event in queue statistics.
        #
        # Increments @server_queue_enqueued, updates depth tracking and timestamp.
        #
        # @return [nil]
        # @api private
        def record_server_queue_enqueue
          @server_queue_enqueued = @server_queue_enqueued.to_i + 1
          depth = @server_queue&.length.to_i
          @server_queue_last_depth = depth
          @server_queue_max_depth = depth if depth > @server_queue_max_depth.to_i
          @server_queue_last_enqueue_at = Time.now
          nil
        end

        # Pushes a parsed server string into the processing queue.
        #
        # Records the enqueue time (monotonic, for wait-time stats) and ingress time
        # (when the socket reader first received it). Raises ServerQueueOverflow if the
        # queue is at capacity; this should not occur in normal operation.
        #
        # @param server_string [String] the line to process
        # @param enqueued_monotonic_at [Numeric] monotonic timestamp of enqueue
        # @param ingress_monotonic_at [Numeric] monotonic timestamp of socket receipt
        # @return [void]
        # @raise [ServerQueueOverflow] if queue capacity is exceeded
        # @api private
        def enqueue_server_string(server_string, enqueued_monotonic_at, ingress_monotonic_at: enqueued_monotonic_at)
          @server_queue.push([server_string, enqueued_monotonic_at, ingress_monotonic_at], true)
          record_server_queue_enqueue
        rescue ThreadError
          raise ServerQueueOverflow, "game parser queue exceeded #{SERVER_QUEUE_CAPACITY} records"
        end

        # Records timing samples from the socket-reader thread.
        #
        # Captures elapsed seconds for hook execution, enqueue, and total reader-process
        # time. Updates running max and total for average calculation.
        #
        # @param hook_time [Numeric] seconds spent in SocketReadHook.run
        # @param enqueue_time [Numeric] seconds spent enqueuing to the parser queue
        # @param process_time [Numeric] seconds elapsed from reader start to enqueue finish
        # @return [nil]
        # @api private
        def record_server_reader_timing(hook_time:, enqueue_time:, process_time:)
          @server_reader_hook_last = hook_time
          @server_reader_hook_total = @server_reader_hook_total.to_f + hook_time.to_f
          @server_reader_hook_max = hook_time if hook_time.to_f > @server_reader_hook_max.to_f

          @server_reader_enqueue_last = enqueue_time
          @server_reader_enqueue_total = @server_reader_enqueue_total.to_f + enqueue_time.to_f
          @server_reader_enqueue_max = enqueue_time if enqueue_time.to_f > @server_reader_enqueue_max.to_f

          @server_reader_process_last = process_time
          @server_reader_process_total = @server_reader_process_total.to_f + process_time.to_f
          @server_reader_process_max = process_time if process_time.to_f > @server_reader_process_max.to_f
          nil
        end

        # Records a dequeue event and computes queue wait time.
        #
        # Increments @server_queue_dequeued, updates depth and timestamp, and if
        # enqueued_monotonic_at is provided, calculates and records the wait time
        # (from enqueue to dequeue) for averaging.
        #
        # @param enqueued_monotonic_at [Numeric, nil] monotonic enqueue timestamp
        # @return [nil]
        # @api private
        def record_server_queue_dequeue(enqueued_monotonic_at = nil)
          @server_queue_dequeued = @server_queue_dequeued.to_i + 1
          depth = @server_queue&.length.to_i
          @server_queue_last_depth = depth
          @server_queue_last_dequeue_at = Time.now
          if enqueued_monotonic_at
            wait = Process.clock_gettime(Process::CLOCK_MONOTONIC) - enqueued_monotonic_at.to_f
            if wait >= 0.0
              @server_queue_last_wait = wait
              @server_queue_total_wait = @server_queue_total_wait.to_f + wait
              @server_queue_max_wait = wait if wait > @server_queue_max_wait.to_f
            end
          end
          nil
        end

        # Records timing for one parse/dispatch cycle.
        #
        # @param parse_time [Numeric] elapsed seconds for this cycle
        # @return [nil]
        # @api private
        def record_server_parser_timing(parse_time)
          @server_parser_last = parse_time
          @server_parser_total = @server_parser_total.to_f + parse_time.to_f
          @server_parser_max = parse_time if parse_time.to_f > @server_parser_max.to_f
          nil
        end

        # Normalizes a server-queue item into [server_string, enqueued_monotonic_at, ingress_monotonic_at].
        #
        # Handles legacy 2-element tuples (assuming enqueue time is also ingress time),
        # 3-element tuples, and bare strings. Returns a 3-tuple for uniform processing.
        #
        # @param item [Array, String] a queue entry
        # @return [Array<(String, Numeric, Numeric)>, Array<(String, nil, nil)>] normalized tuple
        # @api private
        def unwrap_server_queue_item(item)
          if item.is_a?(Array) && item.length == 3 && item[1].is_a?(Numeric)
            item
          elsif item.is_a?(Array) && item.length == 2 && item[1].is_a?(Numeric)
            [item[0], item[1], item[1]]
          else
            [item, nil, nil]
          end
        end

        # Spawns the thread that reads raw game-server lines and enqueues them.
        #
        # Runs read_server_string in a loop with timeout handling: up to
        # MAX_CONSECUTIVE_READ_TIMEOUTS silent retries before treating the connection
        # as dead. Detects EOF, connection errors, and truncated/desynced fragments.
        # On error, records the shutdown reason and halts the thread. Passes each line
        # through SocketReadHook (if defined) before enqueuing.
        #
        # @return [void]
        # @api private
        def start_socket_reader_thread
          @reader_thread = Thread.new do
            consecutive_timeouts = 0
            max_consecutive_timeouts = MAX_CONSECUTIVE_READ_TIMEOUTS

            begin
              while true
                begin
                  server_string = read_server_string

                  if server_string.equal?(READ_TIMEOUT)
                    raise IO::TimeoutError, "no game data for #{READ_TIMEOUT_SECONDS} seconds"
                  end

                  consecutive_timeouts = 0

                  # Break if socket closed (gets returns nil)
                  if server_string.nil?
                    @remote_eof = true
                    record_shutdown_reason(:game_eof, source: :game_reader)
                    break
                  end

                  reader_process_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                  received_at = Time.now
                  monotonic_received_at = reader_process_started
                  @last_recv = received_at
                  @_buffer.update(server_string) if defined?(TESTING) && TESTING
                  hook_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                  Lich::Common::SocketReadHook.run(
                    server_string,
                    received_at: received_at,
                    monotonic_received_at: monotonic_received_at
                  ) if defined?(Lich::Common::SocketReadHook)
                  hook_finished = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                  enqueue_started = hook_finished
                  enqueue_server_string(
                    server_string,
                    enqueue_started,
                    ingress_monotonic_at: monotonic_received_at
                  )
                  enqueue_finished = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                  record_server_reader_timing(
                    hook_time: hook_finished - hook_started,
                    enqueue_time: enqueue_finished - enqueue_started,
                    process_time: enqueue_finished - reader_process_started
                  )
                rescue Errno::ETIMEDOUT, Errno::EWOULDBLOCK, IO::TimeoutError
                  consecutive_timeouts += 1

                  shutdown_log.info("socket read timeout #{consecutive_timeouts}/#{max_consecutive_timeouts} (no game data for #{READ_TIMEOUT_SECONDS}s)")

                  if consecutive_timeouts >= max_consecutive_timeouts
                    total_timeout = total_read_timeout_seconds(max_consecutive_timeouts)
                    shutdown_log.warning("game connection timed out after #{max_consecutive_timeouts} consecutive read timeouts (#{total_timeout}s)")
                    raise IO::TimeoutError, "no game data for #{total_timeout} seconds"
                  end

                  # Check if socket is still alive
                  if @socket.closed?
                    shutdown_log.info("game socket is closed; exiting server thread")
                    break
                  end

                  # Small sleep before retry
                  sleep 0.1
                  retry
                rescue Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNABORTED, OpenSSL::SSL::SSLError => conn_error
                  # Connection was reset/broken - these are fatal
                  shutdown_log.info("connection error: #{conn_error.class} - #{conn_error.message}")
                  raise conn_error
                end
              end
            rescue StandardError => e
              if intentional_shutdown_close_error?(e)
                shutdown_log.info("server thread exiting after orderly user shutdown")
                next
              end

              # Handle any other errors
              should_continue = handle_thread_error(e)
              # Only retry if handle_thread_error says it's safe and socket is still open
              if should_continue && !@socket.closed? && $_CLIENT_.alive?
                shutdown_log.debug("retrying server thread after error")
                consecutive_timeouts = 0 # Reset counter on retry
                sleep 1 # Brief pause before retry
                retry
              else
                reason = shutdown_reason_for_thread_exit(e)
                record_shutdown_reason(reason, source: :game_reader, detail: e.class)
                shutdown_log.info("server thread exiting due to #{reason}")
              end
            ensure
              @server_queue << nil if @server_queue && @thread&.alive?
            end
          end
          @reader_thread.name = 'game socket reader' if @reader_thread.respond_to?(:name=)
          @reader_thread.priority = 5
        end

        # Spawns the thread that dequeues, parses, and hooks server strings.
        #
        # Pops items from @server_queue and calls process_server_string on each,
        # recording timing and queue statistics. Exits cleanly on nil (end-of-queue
        # signal from reader thread), or on unrecoverable error (logs and records
        # shutdown reason).
        #
        # @return [void]
        # @api private
        def start_server_processor_thread
          @thread = Thread.new do
            begin
              loop do
                item = @server_queue.pop
                break if item.nil?

                server_string, enqueued_monotonic_at, ingress_monotonic_at = unwrap_server_queue_item(item)
                record_server_queue_dequeue(enqueued_monotonic_at)
                parse_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                begin
                  Thread.current.thread_variable_set(:lich_game_ingress_time, ingress_monotonic_at)
                  process_server_string(server_string)
                ensure
                  Thread.current.thread_variable_set(:lich_game_ingress_time, nil)
                end
                record_server_parser_timing(Process.clock_gettime(Process::CLOCK_MONOTONIC) - parse_started)
              end
            rescue StandardError => e
              log_error("Error processing server string", e)
              record_shutdown_reason(:unrecoverable_game_thread_error, source: :game_parser, detail: e.class)
              @socket.close rescue nil
            end
          end
          @thread.name = 'game parser' if @thread.respond_to?(:name=)
          @thread.priority = 4
        end

        # Reads one game-server line after an explicit readiness wait.
        #
        # Ruby does not reliably surface SO_RCVTIMEO through TCPSocket#gets on
        # every supported platform. Waiting on #wait_readable first makes the
        # reader's no-data timeout deterministic while preserving gets-based
        # EOF handling. #wait_readable rather than a bare IO.select call so
        # this works unchanged whether @socket is a direct-mode Socket (where
        # it's equivalent to IO.select on a single descriptor -- both trigger
        # on EOF too) or a Lich::Common::WebSocket::Stream (WEBSOCKET
        # transport), whose #wait_readable also reports readiness for a line
        # already sitting fully decoded in its buffer -- something a select
        # on the raw, TLS-wrapped socket underneath it cannot see.
        #
        # @param read_timeout [Numeric] seconds to wait for game socket data
        # @return [String, nil, Object] a server line, nil for EOF, or READ_TIMEOUT
        def read_server_string(read_timeout: READ_TIMEOUT_SECONDS)
          return READ_TIMEOUT unless @socket.wait_readable(read_timeout)

          @socket.gets
        end

        # @param timeout_count [Integer] number of consecutive read waits
        # @return [Integer] total elapsed no-data seconds represented by count
        def total_read_timeout_seconds(timeout_count = MAX_CONSECUTIVE_READ_TIMEOUTS)
          READ_TIMEOUT_SECONDS * timeout_count
        end

        # Main entry point for processing one raw server line.
        #
        # Detects game identity from XML, instantiates the game handler if needed,
        # cleans and buffers the line, handles autostart and CLI scripts, parses XML,
        # observes inventory if tracked, and runs downstream hooks. Called once per
        # server string by the parser thread.
        #
        # @param server_string [String] one line from the game socket
        # @return [void]
        # @api private
        def process_server_string(server_string)
          $cmd_prefix = String.new if server_string =~ /^\034GSw/

          # Load game-specific modules if needed
          unless (XMLData.game.nil? || XMLData.game.empty?)
            unless Module.const_defined?(:GameLoader)
              require_relative 'common/gameloader'
              GameLoader.load!
            end
          end

          # Set instance if not already set
          if @game_instance.nil? && !XMLData.game.nil? && !XMLData.game.empty?
            set_game_instance(XMLData.game)
          end

          # Clean server string based on game type
          if @game_instance
            server_string = @game_instance.clean_serverstring(server_string)
            return if server_string.nil? # A game's cleanup can drop a line
          end

          # Debug output if needed
          pp server_string if defined?($deep_debug) && $deep_debug

          # Push to server buffer
          $_SERVERBUFFER_.push(server_string)

          # Handle autostart
          handle_autostart if !@@autostarted && server_string =~ /<app char/

          # Handle CLI scripts
          if !@cli_scripts && @@autostarted && !XMLData.name.nil? && !XMLData.name.empty?
            start_cli_scripts
          end

          # Process XML data
          process_xml_data(server_string) unless server_string =~ /^<settings /

          # Passively capture the inventoryManager extended feed (read-only tap;
          # returns the string unchanged and never raises -- see
          # Lich::Common::Inventory.observe). Runs on this parser thread.
          Lich::Common::Inventory.observe(server_string) if defined?(Lich::Common::Inventory)

          # Run downstream hooks
          process_downstream_hooks(server_string)
        end

        # Runs autostart initialization: version checks, core updates, script syncs, and the autostart script.
        #
        # Compares LICH_VERSION to Lich.core_updated_with_lich_version; if a newer version is detected,
        # updates core scripts. Spawns a background thread to sync all script repositories (to avoid
        # blocking the parser while XMLData.name is populated). Starts the 'autostart' script if it
        # exists. Sets @@autostarted to true and optionally displays a Ruby-version warning.
        #
        # Called when the first <app char> tag arrives (login complete).
        #
        # @return [void]
        # @api private
        def handle_autostart
          if defined?(LICH_VERSION) && defined?(Lich.core_updated_with_lich_version) &&
             Gem::Version.new(LICH_VERSION) > Gem::Version.new(Lich.core_updated_with_lich_version)
            Lich::Messaging.mono(Lich::Messaging.monsterbold("New installation or updated version of Lich5 detected!"))
            Lich::Messaging.mono(Lich::Messaging.monsterbold("Installing newest core scripts available to ensure you're up-to-date!"))
            Lich::Messaging.mono("")
            Lich::Util::Update.update_core_data_and_scripts
          end

          # Sync script repositories on login for both DR and GS.
          # MUST run in a background thread -- sync_all_repos makes HTTP calls
          # that block the game thread, preventing process_xml_data from setting
          # XMLData.name. If Vars is accessed before XMLData.name is set, it
          # loads/saves under scope "DR:" instead of "DR:CharName", overwriting
          # real data with an empty session.
          Thread.new do
            # Wait for XMLData.name to be populated by process_xml_data
            # before touching Vars. 200 x 50ms = 10s max wait.
            200.times do
              break if !XMLData.name.nil? && !XMLData.name.empty?

              sleep 0.05
            end
            Lich::Util::Update.sync_all_repos if !XMLData.name.nil? && !XMLData.name.empty?
          rescue StandardError => e
            Lich.log "repo_sync(login): #{e.class}: #{e.message}"
          end

          Script.start('autostart') if defined?(Script) && Script.respond_to?(:exists?) && Script.exists?('autostart')
          @@autostarted = true

          display_ruby_warning if defined?(RECOMMENDED_RUBY) && Gem::Version.new(RUBY_VERSION) < Gem::Version.new(RECOMMENDED_RUBY)
        end

        # Displays a formatted warning if the Ruby version is below the recommended threshold.
        #
        # Renders a bordered table with the current and recommended versions and a link to
        # the game-specific installation guide. Uses the game instance's #get_documentation_url.
        #
        # @return [void]
        # @api private
        def display_ruby_warning
          ruby_warning = Terminal::Table.new
          ruby_warning.title = "Ruby Recommended Version Warning"
          ruby_warning.add_row(["Please update your Ruby installation."])
          ruby_warning.add_row(["You're currently running Ruby v#{Gem::Version.new(RUBY_VERSION)}!"])
          ruby_warning.add_row(["It's recommended to run Ruby v#{Gem::Version.new(RECOMMENDED_RUBY)} or higher!"])
          ruby_warning.add_row(["Future Lich5 releases will soon require this newer version."])
          ruby_warning.add_row([" "])
          ruby_warning.add_row(["Visit the following link for info on updating:"])

          # Use instance to get the appropriate documentation URL
          if @game_instance
            ruby_warning.add_row([@game_instance.get_documentation_url])
          else
            ruby_warning.add_row(["Unknown game type detected."])
            ruby_warning.add_row(["Unsure of proper documentation, please seek assistance via discord!"])
          end

          ruby_warning.to_s.split("\n").each do |row|
            Lich::Messaging.mono(Lich::Messaging.monsterbold(row))
          end
        end

        # Starts scripts specified via --start-scripts command-line argument.
        #
        # Parses --start-scripts=script1,script2 and calls Script.start on each.
        # Sets @cli_scripts to true after processing, so this runs only once. Logs the
        # logged-in character and game.
        #
        # Called when XMLData.name is populated (after autostart check).
        #
        # @return [void]
        # @api private
        def start_cli_scripts
          if (arg = ARGV.find { |a| a =~ /^\-\-start\-scripts=/ })
            arg.sub('--start-scripts=', '').split(',').each do |script_name|
              Script.start(script_name)
            end
          end
          @cli_scripts = true
          Lich.log("info: logged in as #{XMLData.game}:#{XMLData.name}")
        end

        # Parses one server string as XML and updates game state.
        #
        # Uses Ox SAX parsing in permissive mode (tolerates unescaped ampersands, missing
        # end tags, bare text). Repairs nested quotes and malformed attributes before
        # parsing; if truncation/desync is detected, logs the error, resets XMLData, and
        # returns early. On success, strips tags, splits lines, and dispatches downstream
        # to Script and Inventory observers.
        #
        # Skips parsing for <settings> blocks (those come raw).
        #
        # @param server_string [String] one server line
        # @return [void]
        # @api private
        def process_xml_data(server_string)
          begin
            # Ox is a permissive parser: it handles Simu's not-quite-XML stream
            # without the clean/retry dance REXML required (nested quotes, missing
            # 'd' end tags, etc. are tolerated rather than raised). XMLData itself
            # implements the Ox::Sax interface, so Ox parses straight into it. No
            # <root> wrapper needed: that was a REXML requirement (single root); Ox
            # handles multiple top-level elements and bare text directly.
            XMLData.sax_parse_errors.clear
            # convert_special: false keeps Ox in bytes-land: it never decodes a
            # numeric entity (e.g. &#8217;) into UTF-8. The five standard XML
            # entities are decoded by XMLData#attr/#text instead. Values are left
            # in Ox's native (ASCII-8BIT) encoding -- REXML effectively produced
            # ASCII for this (high-byte-scrubbed) stream, so retagging to
            # Windows-1252 was a divergence and caused entity corruption.
            Ox.sax_parse(XMLData, server_string, convert_special: false, symbolize: false, skip: :skip_none)
            # Repair first: a nested quote can also make Ox report desync-class
            # errors ("document not terminated", "element not closed" -- e.g. an
            # inventoryManager long value of a sleek black book titled "Style: Do
            # you have it?"), so the desync check judges the repaired parse,
            # never the junk one.
            unrepaired = repair_malformed_attributes_and_reparse(server_string)
            check_stream_desync!(XMLData.sax_parse_errors)
          rescue GameStreamDesyncError => e
            # A truncated/desynced fragment. Ox never raises on malformed stream
            # content -- it reports via the error callback, and check_stream_desync!
            # promotes truncation-class errors to this exception. Log and reset
            # rather than killing the server thread. A repair didn't save the
            # line, so undo it: the log, Inventory.observe and the clients get
            # the fragment as the server sent it. Say so, since the repair has
            # already logged a "fixed to" line for the edit being undone.
            server_string.replace(unrepaired) if unrepaired
            undone = unrepaired ? ' (repair logged above undone)' : ''
            Lich.log "warning: stream desync (#{e.message}); resetting XMLData#{undone}: #{server_string.inspect}"
            XMLData.reset
            return
          end

          stripped_server = strip_xml(server_string, type: "main")

          # Process game-specific data using instance
          if @game_instance && Module.const_defined?(:GameLoader)
            @game_instance.process_game_specific_data(server_string, stripped_server)
          end

          # Process downstream XML
          Script.new_downstream_xml(server_string) if defined?(Script)

          # Process stripped server string
          stripped_server.split("\r\n").each do |line|
            @buffer.update(line) if defined?(TESTING) && TESTING
            Script.new_downstream(line) if defined?(Script) && !line.empty?
          end
        end

        # Promote truncation-class Ox parse errors to GameStreamDesyncError so
        # a desynced stream still hits the log + reset recovery path instead of
        # being silently absorbed (see the GameStreamDesyncError comment).
        # parse_errors is XMLData's collected Ox error-callback messages for
        # the fragment just parsed.
        def check_stream_desync!(parse_errors)
          desync = parse_errors.find do |message|
            STREAM_DESYNC_ERRORS.any? { |pattern| pattern.match?(message) }
          end
          raise GameStreamDesyncError, desync if desync
        end

        # Ox reports "no attribute value" for two repairable malformations that
        # scatter a tag into junk attributes: the settingsInfo space-not-found
        # server bug, and a same-quote inside a quoted value (Simu's dynamic
        # dialogs, e.g. title='Tsetem's Items'). Both raised in REXML and were
        # repaired in the rescue; Ox tolerates them, so drive the repair off its
        # error report -- only the rare flagged line pays the cost. Apply the
        # repairs; if any changed the line, drop the junk the first parse committed
        # and parse once more (never again, so it can't loop). The repair runs
        # before the desync check, which then judges this second parse's errors:
        # a line the repair fixes is kept, a truncated one still resets (and
        # process_xml_data restores it from the returned original).
        # Escaped &apos;/&quot; round-trip back to the literal char via
        # XmlEntities.decode and the front-end's own entity decoding.
        #
        # @param server_string [String] the line, repaired in place
        # @return [String, nil] the line as received when a repair changed it, else nil
        def repair_malformed_attributes_and_reparse(server_string)
          return unless XMLData.sax_parse_errors.any? { |message| NO_ATTRIBUTE_VALUE_ERROR.match?(message) }

          before = server_string.dup
          fix_invalid_settings_info(server_string)
          XMLCleaner.clean_nested_quotes(server_string)
          return if server_string == before # nothing to repair (e.g. a genuine valueless attribute)

          XMLData.reset
          XMLData.sax_parse_errors.clear
          Ox.sax_parse(XMLData, server_string, convert_special: false, symbolize: false, skip: :skip_none)
          before
        end

        # The server sends a malformed <settingsInfo ... space not found .../> (an
        # attribute with no '=') to characters that have never connected with the
        # Wrayth/StormFront client. REXML raised on it (the rescue repaired it); Ox
        # tolerates it and emits "no attribute value", so it is repaired from
        # repair_malformed_attributes_and_reparse. @@settings_init_needed makes
        # gameloader's PostLoad seed a valid client record (see settings_init_needed?
        # and lib/common/gameloader.rb).
        def fix_invalid_settings_info(server_string)
          return unless server_string =~ /<settingsInfo .*?space not found /

          Lich.log "Invalid settingsInfo XML tags detected: #{server_string.inspect}"
          server_string.sub!(/\s\bspace not found\b\s/, " client='1.0.1.28' ")
          Lich.log "Invalid settingsInfo XML tags fixed to: #{server_string.inspect}"
          @@settings_init_needed = true
        end

        # Sends one server string to every client, after the downstream hooks
        # (which, like XMLParser and scripts, see the stream as the server sent
        # it). Each client gets the rich-stream rewrites its capabilities call
        # for (Lich::Common::ClientCapabilities): the string is rewritten once
        # per distinct capability set, then finished once per distinct result,
        # so clients that share a set (the usual case: one set for all) cost
        # one pass, as before per-client capabilities.
        def process_downstream_hooks(server_string)
          dragonrealms = XMLData.game =~ /^DR/
          # Followed before the hooks, so a hook that squelches the game's
          # reply to FLAG DESCRIPTION or the FLAG listing (DRInfomon's quiet
          # startup query) does not hide it from the filter, and whatever the
          # setting, so turning it on applies at once.
          Lich::Common::RoomDescriptionFilter.observe(server_string) if dragonrealms
          return unless (alt_string = DownstreamHook.run(server_string))

          # DragonRealms ignores FLAG DESCRIPTION OFF in the Saga-identity
          # stream's <room> block (a game bug). Opted in, every client gets the
          # character's room without its description, before the per-client
          # rewrites so both layouts come out as the legacy stream sends them.
          if dragonrealms && Lich::Common::RoomDescriptionFilter.descriptions_off? &&
             alt_string.include?('<room>') && Lich.follow_description_flag
            alt_string = Lich::Common::RoomDescriptionFilter.apply(alt_string, room_id: XMLData.room_id, room_exits: XMLData.room_exits)
          end

          outputs = []
          Lich::Common::ClientCapabilities.group(client_write_targets).each do |capabilities, clients|
            line = rich_stream_rewrite(alt_string, capabilities)
            same = outputs.find { |output| output[:line] == line }
            same ? same[:clients].concat(clients) : outputs << { line: line, clients: clients }
          end

          # Every result starts the finishing steps from the same room-number
          # state; they make the same decision for each, since no rewrite adds
          # or removes the room-name start or the prompt they look for. So with
          # N distinct results on a prompt line, process_room_display runs N
          # times: its Map.current lookups and any StringProc timeto in
          # room_stringproc_entries are evaluated once per result.
          room_number_after_ready = @room_number_after_ready
          outputs.each do |output|
            @room_number_after_ready = room_number_after_ready
            send_to_client(finish_client_line(output[:line]), output[:clients])
          end
        end

        # The rewrites that depend on a client's capabilities.
        #
        # The Saga-identity stream's inline <room> block reaches only front
        # ends that render it (:room_element, Saga); every other front end gets
        # the legacy roomName/roomDesc layout it already handles. Rewritten
        # after DownstreamHook.run, so script hooks see the block as the server
        # sent it, and before the Wizard conversion (sf_to_wiz), which keys on
        # that layout; the room-number display (process_room_information)
        # handles either.
        # They also get the legacy <compass> line the Saga-identity stream
        # dropped, except Wizard/Avalon (GSL), which get exits from XMLParser's
        # GSL codes and would see the line as a blank one.
        #
        # Then the game's own rewrites (GameInstance#adapt_for_frontend):
        # DragonRealms' links and creature bold go only to front ends that
        # handle them (:game_links, :double_bold); the rest get the legacy
        # line. After the <room> rewrite, which keeps the parts' markup, and
        # before sf_to_wiz, which turns each bold into a GSL code. GemStone
        # keeps the base no-op.
        #
        # Never modifies alt_string: the other capability sets start from it.
        #
        # @param alt_string [String] the server string after the downstream hooks
        # @param capabilities [Array<Symbol>] the client's rich-stream capabilities
        # @return [String] alt_string itself when nothing applies, else a new string
        def rich_stream_rewrite(alt_string, capabilities)
          if alt_string.include?('<room>') && !capabilities.include?(:room_element)
            alt_string = if Frontend.supports_gsl?
                           Lich::Common::RoomBlock.legacy_shape(alt_string)
                         else
                           Lich::Common::RoomBlock.legacy_shape_with_compass(alt_string)
                         end
          end
          alt_string = @game_instance.adapt_for_frontend(alt_string, capabilities) if @game_instance
          alt_string
        end

        # The steps that follow the session's front end ($frontend), whatever
        # the client's capabilities: room-number display, the Genie and
        # Frostbite subtitle edits, Wizard's GSL conversion and the origin
        # sentinel.
        #
        # @param alt_string [String] a rewritten server string (may be modified in place)
        # @return [String] the bytes to write to the client
        def finish_client_line(alt_string)
          process_room_information(alt_string)

          # Handle frontend-specific modifications
          if Frontend.client.eql?('genie') && alt_string =~ /^<streamWindow id='room' title='Room' subtitle=" - \[.*\] \((?:\d+|\*\*)\)"/
            alt_string.sub!(/] \((?:\d+|\*\*)\)/) { "]" }
          end

          if Frontend.client.eql?('frostbite') && alt_string =~ /^<streamWindow id='main' title='Story' subtitle=" - \[.*\] \((?:\d+|\*\*)\)"/
            alt_string.sub!(/] \((?:\d+|\*\*)\)/) { "]" }
          end

          # Handle room number display
          if @room_number_after_ready && alt_string =~ /<prompt /
            alt_string = @game_instance ? @game_instance.process_room_display(alt_string) : alt_string
            @room_number_after_ready = false
          end

          # Handle frontend-specific conversions
          if Frontend.supports_gsl?
            alt_string = sf_to_wiz(alt_string)
          end
          # Handle prefix origin sentinel if FE supports it
          alt_string = prefix_origin_sentinel(alt_string) if Frontend.supports_sentinel?
          alt_string
        end

        # Detects room-display lines and queues them for formatting.
        #
        # Matches the legacy roomName style or the Saga-identity <room> block.
        # If display_lichid, display_uid, or hide_uid_flag is on, calls the game
        # instance's #modify_room_display to edit the line in place, then sets
        # @room_number_after_ready = true so finish_client_line will call
        # #process_room_display when the next prompt arrives.
        #
        # @param alt_string [String] the server line
        # @return [String] the (possibly modified) string
        # @api private
        def process_room_information(alt_string)
          # The legacy roomName style, or the Saga-identity <room> block (see
          # Lich::Common::RoomBlock); the room-number rewrites work on either.
          if alt_string =~ /^(<pushStream id="familiar" ifClosedStyle="watching"\/>)?(?:<resource picture="\d+"\/>|<popBold\/>)?(?:<style id="roomName"\s+\/>|<room>)/
            if (Lich.display_lichid == true || Lich.display_uid == true || Lich.hide_uid_flag == true)
              @game_instance ? @game_instance.modify_room_display(alt_string) : alt_string
            end
            @room_number_after_ready = true
            alt_string
          end
        end

        # Writes one string to each live client in clients.
        # @param alt_string [String] the finished bytes
        # @param clients [Array] defaults to every client that receives game output
        def send_to_client(alt_string, clients = client_write_targets)
          clients.each { |client| client.write(alt_string) if client.alive? }
        end

        # The clients that receive game output: every attached detachable
        # client, else the primary client. While a detachable client is
        # attached, the primary gets none.
        #
        # @return [Array] a snapshot; the registry may change while it is used
        def client_write_targets
          detachable_clients = $_DETACHABLE_CLIENT_REGISTRY_&.snapshot || []
          detachable_clients = [$_DETACHABLE_CLIENT_] if detachable_clients.empty? && $_DETACHABLE_CLIENT_
          return detachable_clients unless detachable_clients.empty?

          $_CLIENT_ ? [$_CLIENT_] : []
        end

        # Determines whether the reader thread should retry after an error.
        #
        # Classifies the error (timeout, connection, protocol, queue overflow, desync,
        # or unknown) and returns true (retry) or false (exit). Fatal errors (connection
        # reset, protocol violation, desync) always return false. Timeouts after
        # consecutive-retry exhaustion return false. Unknown errors check socket/client
        # state; if both are alive, retry is allowed. Logs all errors.
        #
        # @param error [StandardError] the exception caught by the reader thread
        # @return [Boolean] true if the thread should retry, false to exit
        # @api private
        def handle_thread_error(error)
          if recognized_connection_disruption?(error)
            shutdown_log.info("server_thread: #{connection_disruption_log_message(error)}")
            shutdown_log.debug("server_thread backtrace: #{error.backtrace.join("\n\t")}") if error.backtrace
          else
            shutdown_log.error("server_thread: #{error}\n\t#{Array(error.backtrace).join("\n\t")}")
          end
          sleep 0.2

          case error
          when Errno::ETIMEDOUT, Errno::EWOULDBLOCK, IO::TimeoutError
            # Timeout errors reach this outer handler only after the inner
            # reader loop has exhausted its consecutive-timeout threshold.
            shutdown_log.info("game timeout - will not retry")
            return false
          when Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNABORTED, OpenSSL::SSL::SSLError
            # Connection errors are fatal
            shutdown_log.info("connection error - will not retry")
            return false
          when Lich::Common::WebSocket::Frame::ProtocolError
            # A framing violation leaves the offending bytes stuck at the
            # front of Stream's internal buffer (raised before they're
            # consumed), so every retry would just hit the same error again
            # on the same bytes -- not a transient condition.
            shutdown_log.info("WebSocket protocol error - will not retry")
            return false
          when GameStreamDesyncError
            shutdown_log.info("game stream desync detected - will not retry")
            return false
          when ServerQueueOverflow
            shutdown_log.info("game parser queue overflow - will not retry")
            return false
          else
            # Check if socket/client are closed or if it's a known fatal error
            if !$_CLIENT_.alive? || @socket.closed?
              shutdown_log.info("client or socket closed - will not retry")
              return false
            elsif error.to_s =~ /invalid argument|A connection attempt failed|An existing connection was forcibly closed|An established connection was aborted by the software in your host machine./i
              shutdown_log.info("fatal error pattern detected - will not retry")
              return false
            else
              shutdown_log.debug("unknown server thread error - will attempt retry")
              return true
            end
          end
        end

        # Maps an error to a shutdown-coordinator reason code.
        #
        # Used by the reader thread to record why it is exiting (timeout, connection
        # error, protocol error, desync, queue overflow, etc.).
        #
        # @param error [StandardError] the exception
        # @return [Symbol] a reason key (e.g., :game_timeout, :connection_reset)
        # @api private
        def shutdown_reason_for_thread_exit(error)
          case error
          when Errno::ETIMEDOUT, Errno::EWOULDBLOCK, IO::TimeoutError
            :game_timeout
          when Errno::ECONNRESET
            :connection_reset
          when Errno::EPIPE
            :connection_pipe
          when Errno::ECONNABORTED
            :connection_aborted
          when OpenSSL::SSL::SSLError
            :connection_tls_error
          when Lich::Common::WebSocket::Frame::ProtocolError
            :websocket_protocol_error
          when GameStreamDesyncError
            :game_stream_desync
          when ServerQueueOverflow
            :unrecoverable_game_thread_error
          else
            :unrecoverable_game_thread_error
          end
        end

        # Records a shutdown event via the ShutdownCoordinator.
        #
        # @param reason [Symbol] the shutdown reason code
        # @param source [Symbol] which thread/component initiated (e.g., :game_reader)
        # @param detail [Class, nil] optional error class for context
        # @return [void]
        # @api private
        def record_shutdown_reason(reason, source:, detail: nil)
          return unless defined?(Lich::Common::ShutdownCoordinator)

          Lich::Common::ShutdownCoordinator.request(reason: reason, source: source, detail: detail)
        rescue StandardError => e
          shutdown_log.warning("failed to record shutdown reason #{reason.inspect}: #{e.class}: #{e.message}")
        end

        # Returns the ShutdownLog for thread-safe error recording.
        #
        # @return [Lich::Common::ShutdownLog]
        # @api private
        def shutdown_log
          Lich::Common::ShutdownLog
        end

        # Detects whether an error is the result of an orderly user-initiated shutdown.
        #
        # Returns true only if a shutdown is in progress, the socket is closed, and the
        # error is a file-descriptor or stream-closure error (EBADF, stream closed, etc.).
        #
        # @param error [StandardError] the exception
        # @return [Boolean]
        # @api private
        def intentional_shutdown_close_error?(error)
          return false unless defined?(Lich::Common::ShutdownCoordinator)
          return false unless Lich::Common::ShutdownCoordinator.orderly_user_exit?
          return false unless @socket&.closed?

          error.is_a?(Errno::EBADF) ||
            error.to_s =~ /stream closed in another thread|closed stream|bad file descriptor/i
        end

        # Returns whether the error is a known connection or stream condition.
        #
        # Recognized errors: timeouts, connection resets/aborts/pipe errors, TLS errors,
        # WebSocket protocol errors, and game-stream desync. Used for logging classification.
        #
        # @param error [StandardError] the exception
        # @return [Boolean]
        # @api private
        def recognized_connection_disruption?(error)
          error.is_a?(Errno::ETIMEDOUT) ||
            error.is_a?(Errno::EWOULDBLOCK) ||
            error.is_a?(IO::TimeoutError) ||
            error.is_a?(Errno::ECONNRESET) ||
            error.is_a?(Errno::EPIPE) ||
            error.is_a?(Errno::ECONNABORTED) ||
            error.is_a?(OpenSSL::SSL::SSLError) ||
            error.is_a?(Lich::Common::WebSocket::Frame::ProtocolError) ||
            error.is_a?(GameStreamDesyncError)
        end

        # Formats an error as a one-line log message for connection disruptions.
        #
        # Extracts the first line of desync-error messages; for other errors, returns
        # "ClassName: message".
        #
        # @param error [StandardError] the exception
        # @return [String] a short log line
        # @api private
        def connection_disruption_log_message(error)
          return "GameStreamDesyncError: #{error.message.lines.first&.strip}" if error.is_a?(GameStreamDesyncError)

          "#{error.class}: #{error.message}"
        end

        protected

        def log_error(message, error)
          Lich.log "#{message}: #{error}\n\t#{error.backtrace.join("\n\t")}"
        end
      end
    end
  end

  # Gemstone game module
  module Gemstone
    include Lich

    # Base class for character status tracking
    class CharacterStatus
      class << self
        # Sets the GemStone injury display mode (wounds, scars, or both).
        #
        # Sends _injury commands to the server and waits up to 7.5 seconds for XMLData.injury_mode
        # to reflect the change. Allows scripts to ensure a consistent view of character wounds/scars.
        #
        # @param mode [String] "scar"/"scars", "wound"/"wounds", or "both" (default)
        # @return [void]
        # @raise [ArgumentError] if mode is invalid
        # @api private
        def fix_injury_mode(mode = 'both') # Default mode 'both' handles wounds (precedence) then scars
          case mode
          when 'scar', 'scars'
            unless XMLData.injury_mode == 1
              Game._puts '_injury 1'
              150.times { sleep 0.05; break if XMLData.injury_mode == 1 }
            end
          when 'wound', 'wounds' # future proof leaving in place, but this will likely not be used
            unless XMLData.injury_mode == 0
              Game._puts '_injury 0'
              150.times { sleep 0.05; break if XMLData.injury_mode == 0 }
            end
          when 'both'
            unless XMLData.injury_mode == 2
              Game._puts '_injury 2'
              150.times { sleep 0.05; break if XMLData.injury_mode == 2 }
            end
          else
            raise ArgumentError, "Invalid mode: #{mode}. Use 'scar', 'wound', or 'both'."
          end
        end

        # Responds to unknown CharacterStatus class methods with a helpful error.
        #
        # Returns a bold error message listing valid injury areas (arms, limbs, torso, etc.).
        #
        # @return [nil]
        # @api private
        def method_missing(_method_name = nil)
          result = Lich::Messaging.mono(Lich::Messaging.msg_format("bold", "#{self.name.split('::').last}: Invalid area, try one of these: arms, limbs, torso, #{XMLData.injuries.keys.join(', ')}"))
          # the _respond method used in Lich::Messaging returns nil upon success
          return result
        end
      end
    end

    # Gemstone-specific game instance
    class GameInstance < GameBase::GameInstance::Base
      def clean_serverstring(server_string)
        # The Rift, Scatter is broken...
        if server_string =~ /<compDef id='room text'><\/compDef>/
          server_string.sub!(/(.*)\s\s<compDef id='room text'><\/compDef>/) { "<compDef id='room desc'>#{$1}</compDef>" }
        end

        # Handle combat and atmospherics
        server_string = handle_combat_tags(server_string)
        server_string = handle_atmospherics(server_string)

        server_string
      end

      def get_documentation_url
        "https://gswiki.play.net/Lich:Software/Installation"
      end

      # Parses GemStone character data: injuries, spells, vitals, and combat info.
      #
      # Runs Infomon::XMLParser on the raw line, then Infomon::Parser on each stripped
      # text line. This populates the XMLData injury and spell trees used by scripts.
      #
      # @param server_string [String] the raw server line (needed for XML-level parsing)
      # @param stripped_server [String, nil] pre-stripped lines from the server string
      # @return [void]
      # @api private
      def process_game_specific_data(server_string, stripped_server = nil)
        # Infomon's XML-level parse needs the raw string; its line parser reuses
        # the text already stripped by process_xml_data (XMLParser.parse does not
        # mutate, so no dup or second strip_xml is needed).
        Infomon::XMLParser.parse(server_string)
        stripped_server.split("\r\n").each do |line|
          Infomon::Parser.parse(line) unless line.empty?
        end
      end

      # Edits the GemStone room-name line to show Lich ID or game UID.
      #
      # Injects or replaces room identifiers based on display_lichid and display_uid
      # settings. Maps game UIDs to Lich room IDs via Room["uXXX"]. When display_uid
      # is enabled, replaces the game UID with the Lich UID format; when display_lichid
      # is enabled, injects the Lich ID before the closing bracket.
      #
      # @param alt_string [String] the room-name line, modified in place
      # @return [String] the rewritten line
      # @api private
      def modify_room_display(alt_string)
        uid_from_string = alt_string.match(/] \((?<uid>\d+)\)/)
        if uid_from_string.nil?
          lichid_from_uid_string = Room.current.id
        else
          lichid_from_uid_string = Room["u#{uid_from_string[:uid]}"].id.to_i
        end
        if Lich.display_lichid == true
          alt_string.sub!(']') { " - #{lichid_from_uid_string}]" }
        end

        if Lich.display_uid == true
          alt_string.sub!(/] \(\d+\)/) { "]" }
          alt_string.sub!(']') { "] (#{(uid_from_string.nil? || XMLData.room_id == uid_from_string[:uid].to_i) ? ((XMLData.room_id == 0 || XMLData.room_id > 4294967296) ? "unknown" : "u#{XMLData.room_id}") : uid_from_string[:uid].to_i})" }
        end

        alt_string
      end

      # Prepends the shared exit / StringProc lines, and mirrors the exits into
      # the GemStone room window on frontends that host one (once per new room).
      # @param alt_string [String] the server string being rewritten
      # @return [String] the rewritten server string
      def process_room_display(alt_string)
        exits = room_exit_entries
        alt_string = prepend_room_lines(alt_string, room_stringproc_entries, exits)

        if !exits.empty? && Frontend.supports_room_window? && Map.current.id != Game.instance_variable_get(:@last_id_shown_room_window)
          alt_string = "#{alt_string}<pushStream id='room' ifClosedStyle='watching'/>Room Exits: #{exits.join(', ')}\r\n<popStream/>\r\n"
          Game.instance_variable_set(:@last_id_shown_room_window, Map.current.id)
        end

        alt_string
      end
    end

    # Game class for Gemstone
    class Game < GameBase::Game
      class << self
        def initialize
          initialize_buffers
          set_game_instance('GS')
        end
      end

      # Initialize the class only if not already connected
      initialize if @socket.nil?
    end
  end

  # DragonRealms game module
  module DragonRealms
    include Lich

    # DragonRealms-specific game instance
    class GameInstance < GameBase::GameInstance::Base
      # Cleans DragonRealms server strings: rejoin split lines, fix XML, handle combat/atmospherics.
      #
      # Rejoins lines cut by roundtime refusals, removes superfluous combat push/pop pairs,
      # strips invalid characters, fixes malformed XML tags, removes duplicate push streams,
      # and processes combat/atmospherics state via #handle_combat_tags and #handle_atmospherics.
      #
      # @param server_string [String] the raw server line
      # @return [String] the cleaned line
      # @api private
      def clean_serverstring(server_string)
        # Rejoin lines cut by a "...wait N seconds." roundtime refusal
        server_string = buffer_split_line(server_string)

        # Clear out superfluous tags
        server_string = server_string.gsub("<pushStream id=\"combat\" /><popStream id=\"combat\" />", "")
        server_string = server_string.gsub("<popStream id=\"combat\" /><pushStream id=\"combat\" />", "")

        # Fix encoding issues
        server_string = GameBase::XMLCleaner.fix_invalid_characters(server_string)

        # Fix combat wrapping components
        server_string = server_string.gsub("<pushStream id=\"combat\" /><component id=", "<component id=")

        # Fix XML tags
        server_string = GameBase::XMLCleaner.fix_xml_tags(server_string)

        # Fix duplicate pushStrings
        while server_string.include?("<pushStream id=\"combat\" /><pushStream id=\"combat\" />")
          server_string = server_string.gsub("<pushStream id=\"combat\" /><pushStream id=\"combat\" />", "<pushStream id=\"combat\" />")
        end

        # Handle combat and atmospherics
        server_string = handle_combat_tags(server_string)
        server_string = handle_atmospherics(server_string)

        server_string
      end

      # Returns the DragonRealms installation documentation URL.
      #
      # @return [String] "https://github.com/elanthia-online/lich-5/wiki/Documentation-for-Installing-and-Upgrading-Lich"
      # @api private
      def get_documentation_url
        "https://github.com/elanthia-online/lich-5/wiki/Documentation-for-Installing-and-Upgrading-Lich"
      end

      # Parses DragonRealms character data: experiences, injuries, and inline richness.
      #
      # Calls DRParser.parse, which modifies server_string in place via in-string markup
      # injection (e.g., expanded experience gains, creature bold toggles). The parser
      # operates on the raw XML, allowing inline edits that survive downstream.
      #
      # @param server_string [String] the raw server line
      # @param _stripped_server [String, nil] unused; kept for signature compatibility
      # @return [void]
      # @api private
      def process_game_specific_data(server_string, _stripped_server = nil)
        # Parse directly to allow inline modifications (e.g., inline exp display)
        # The parser modifies server_string in place via server_line.replace();
        # its patterns match a link-stripped copy (DRParser.match_line)
        DRParser.parse(server_string)
      end

      # Rewrites the room-name line (the "<style id=\"roomName\" />[Title]" chunk) on its way
      # to the client. Two independent concerns:
      #   1. When the player wants the room id/UID in the title (";display roomid title|both"),
      #      inject Lich's configured id/UID before the closing bracket. The game-supplied
      #      RealID (present only under the ShowRoomID flag) is preserved GemStone-style so
      #      ";display lichid" alone reads "[Town Square - 1234] (230008)" - matching how
      #      Lich::Gemstone::GameInstance#modify_room_display already behaves. It is stripped
      #      only when Lich is rendering its own UID instead ({#suppress_game_realid?}), so a
      #      ";display uid" title reads "[Town Square - 1234 - (u230008)]" with no duplicate.
      #   2. Otherwise preserve the historical behavior of hiding the game's inline RealID when
      #      the player asked to (";display uid" or ";display flaguid").
      # Edits only this outbound client string; XMLData (and therefore scripts) are untouched,
      # because process_xml_data has already parsed the inbound stream before this runs.
      # @param alt_string [String] the outbound room-name server string, modified in place
      # @return [String] the rewritten string
      # @see #suppress_game_realid?
      # @see Lich::Gemstone::GameInstance#modify_room_display
      def modify_room_display(alt_string)
        if room_id_in_title?
          alt_string.sub!(/] \((?:\d+|\*\*)\)/) { "]" } if suppress_game_realid?
          room_number = room_number_display
          alt_string.sub!(']') { " - #{room_number}]" } unless room_number.empty?
        elsif suppress_game_realid?
          alt_string.sub!(/] \((?:\d+|\*\*)\)/) { "]" }
        end

        alt_string
      end

      # Prepends the shared exit / StringProc lines, then renders the optional DragonRealms
      # room id/UID. The "Room Number:" line below the room appears for the "line" and "both"
      # placements (honoring the mono toggle). The room-window subtitle (room-window front-ends
      # only) reflects Lich's id/UID for every placement, since the window title bar is itself a
      # title surface. It also re-appends the game-supplied RealID ({#synthesized_realid_suffix})
      # whenever the game displayed it (ShowRoomID ON) - independent of ";display roomid", which
      # governs only where Lich's own id is placed, not whether the game's RealID is shown. So a
      # ShowRoomID-on room shows the RealID in the window title under every placement, matching
      # the game's own behavior and the RealID the game already leaves on the room-name line for
      # the "line"/nil placements. The RealID is synthesized from the authoritative nav UID
      # (XMLData.room_id) rather than copied from the inbound string, because the subtitle is
      # rebuilt from the (UID-free) XMLData.room_title; for a complete arrival nav and the
      # room-name literal agree, so the two surfaces read identically. The inline room-name
      # injection for the "title"/"both" placements is handled separately in #modify_room_display.
      # @param alt_string [String] the server string being rewritten
      # @return [String] the rewritten server string
      def process_room_display(alt_string)
        alt_string = prepend_room_lines(alt_string, room_stringproc_entries, room_exit_entries)

        room_number = room_number_display
        unless room_number.empty?
          if room_id_in_line?
            alt_string = "#{room_styled("Room Number: #{room_number}")}\r\n#{alt_string}"
          end
          if Frontend.supports_room_window?
            subtitle = " - [#{XMLData.room_title[2..-3]} - #{room_number}]#{synthesized_realid_suffix}"
            alt_string = "<streamWindow id='main' title='Story' subtitle=\"#{subtitle}\" location='center' target='drop'/>\r\n#{alt_string}"
            alt_string = "<streamWindow id='room' title='Room' subtitle=\"#{subtitle}\" location='center' target='drop' ifClosed='' resident='true'/>#{alt_string}"
          end
        end

        alt_string
      end

      # DragonRealms' links and bold go only to clients whose capabilities
      # include them (:game_links, :double_bold); the rest get the legacy line.
      # Without :double_bold a client also loses the single bold around a
      # creature in action and assess lines, which the legacy stream sent
      # plain; it runs first, while the link it keys on is still there.
      # GemStone sends links under both client identities, so it keeps the
      # base no-op. Doubled bold appears only in the GemStone captures recorded
      # under the Saga identity; whether it depends on the identity is not
      # known. Never modifies alt_string.
      # @param alt_string [String] the server string on its way to the client
      # @param capabilities [Array<Symbol>, nil] the client's rich-stream
      #   capabilities; nil means the session's set
      # @return [String] the string to send
      # @see Lich::GameBase::GameInstance::Base#adapt_for_frontend
      def adapt_for_frontend(alt_string, capabilities = nil)
        capabilities ||= Lich::Common::ClientCapabilities.session_default
        alt_string = Lich::Common::Markup.strip_link_bold(alt_string) unless capabilities.include?(:double_bold)
        alt_string = Lich::Common::Markup.strip_game_links(alt_string) unless capabilities.include?(:game_links)
        alt_string = Lich::Common::Markup.collapse_double_bold(alt_string) unless capabilities.include?(:double_bold)
        alt_string
      end

      private

      # Builds the DragonRealms room id / RealID string chosen via ";display lichid" and
      # ";display uid", e.g. "1234 - (u230008)", "1234", or "(u230008)". The lich id is omitted
      # (rather than raising) when the current room is unmapped, and the UID renders as "(**)"
      # for a no-UID room (XMLData.room_id.zero?). Shared by #modify_room_display (title
      # injection) and #process_room_display (below-room line and window subtitle) so the two
      # never drift in format.
      # @return [String] the formatted id/UID, or "" when there is nothing to show
      def room_number_display
        segments = []
        if Lich.display_lichid
          current = Map.current
          segments << current.id.to_s if current
        end
        segments << (XMLData.room_id.zero? ? "(**)" : "(u#{XMLData.room_id})") if Lich.display_uid
        segments.join(" - ")
      end

      # @return [Boolean] whether the id/UID is injected into the room-name (title) line;
      #   true for the "title" and "both" placements
      def room_id_in_title?
        %w[title both].include?(Lich.display_roomid_location)
      end

      # @return [Boolean] whether the id/UID is shown as a "Room Number:" line below the room;
      #   true for the "line" and "both" placements, and as the default before a game is
      #   identified (display_roomid_location still nil)
      def room_id_in_line?
        location = Lich.display_roomid_location
        location.nil? || %w[line both].include?(location)
      end

      # Whether Lich should strip the game-supplied inline RealID from the room name instead of
      # preserving it. True when Lich renders its own UID ("(u230008)") via ";display uid" - so
      # keeping the game RealID too would duplicate it - or when the player asked to hide it via
      # ";display flaguid" (hide_uid_flag). When false, the game RealID is left intact so
      # ";display lichid" reads "[Room - 1234] (230008)", matching GemStone.
      # @return [Boolean]
      # @see #modify_room_display
      def suppress_game_realid?
        Lich.display_uid == true || Lich.hide_uid_flag == true
      end

      # The RealID suffix to append to a reconstructed title (the room-window subtitle) so it
      # shows the same game RealID #modify_room_display preserves on the room-name line. The
      # subtitle is rebuilt from XMLData.room_title (which is always UID-free), so the marker is
      # synthesized here from the authoritative nav UID (XMLData.room_id) rather than copied from
      # the inbound string - <nav rm=.../> is the primary UID source for every game (see the nav
      # handler in XMLParser), the same source GemStone derives its ";display uid" marker from.
      # For a complete arrival nav and the room-name literal agree, so the two surfaces match;
      # nav wins only in the late/absent/stale-subtitle edge case #1491 introduced it to handle,
      # where it is the correct value. Empty unless the game actually displayed the RealID this
      # arrival (ShowRoomID ON, tracked by {XMLData#show_room_id}) and Lich is preserving rather
      # than replacing it ({#suppress_game_realid?}). Renders "(**)" for a ShowRoomID-on room
      # that has no UID (room_id 0), mirroring the game's own no-UID marker.
      # @return [String] " (230008)", " (**)", or "" (nothing to append)
      # @see #process_room_display
      # @see #suppress_game_realid?
      def synthesized_realid_suffix
        return '' if suppress_game_realid? || !XMLData.show_room_id

        " (#{XMLData.room_id.zero? ? '**' : XMLData.room_id})"
      end
    end

    # Game class for DragonRealms
    class Game < GameBase::Game
      class << self
        # Initializes the DragonRealms game handler.
        #
        # Calls initialize_buffers and sets the game instance type to 'DR'.
        #
        # @return [void]
        # @api private
        def initialize
          initialize_buffers
          set_game_instance('DR')
        end
      end

      # Initialize the class only if not already connected
      initialize if @socket.nil?
    end
  end
end
