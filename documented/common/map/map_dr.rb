# frozen_string_literal: true

require_relative 'map_base'

# Namespace for the Lich 5 scripting engine and game integrations.
module Lich
  # Shared functionality and constants across Lich scripting environments.
  module Common
    # DragonRealms-specific Map implementation
    # Inherits shared functionality from MapBase
    class Map
      include Enumerable
      include MapBase

      @@loaded                   = false
      @@load_mutex               = Mutex.new
      @@list                   ||= []
      @@current_room_mutex       = Mutex.new
      @@current_room_id        ||= -1
      @@current_room_count     ||= -1
      @@fuzzy_room_mutex         = Mutex.new
      @@fuzzy_room_count       ||= -1
      @@current_location       ||= nil
      @@current_location_count ||= -1
      @@current_room_uid       ||= -1
      @@previous_room_id       ||= -1
      @@uids                     = {}

      attr_reader :id
      attr_accessor :title, :description, :paths, :location, :climate, :terrain,
                    :wayto, :timeto, :image, :image_coords, :check_location,
                    :unique_loot, :uid, :room_objects,
                    :genie_id, :genie_zone, :genie_pos

      # @return [TagList] mutation-aware list of this room's tags
      attr_reader :tags

      # Creates and registers a new room in the game map.
      #
      # @param id [Integer] unique stable room identifier in the map
      # @param title [Array<String>] room titles across server-to-client updates
      # @param description [Array<String>] room descriptions across updates
      # @param paths [Array<String>] room exit lists across updates
      # @param uid [Array<Integer>] server-provided unique identifiers for disambiguation, defaults to []
      # @param location [String] geographic location metadata, defaults to nil
      # @param climate [String] climatic zone, defaults to nil
      # @param terrain [String] terrain type, defaults to nil
      # @param wayto [Hash] navigation metadata for pathfinding, defaults to {}
      # @param timeto [Hash] traversal time metadata, defaults to {}
      # @param image [String] map image identifier, defaults to nil
      # @param image_coords [String] coordinates on the map image, defaults to nil
      # @param tags [Array<String>] script-readable tags for room properties, defaults to []
      # @param check_location [Boolean, nil] whether to verify location text matches, defaults to nil
      # @param unique_loot [String, nil] unique item spawned in this room, defaults to nil
      # @param genie_id [String, nil] genie reference node identifier, defaults to nil
      # @param genie_zone [String, nil] genie reference zone identifier, defaults to nil
      # @param genie_pos [String, nil] genie reference position data, defaults to nil
      # @note If @@loaded is true, this resets the tag index cache after registering the room.
      # @api private
      def initialize(id, title, description, paths, uid = [], location = nil,
                     climate = nil, terrain = nil, wayto = {}, timeto = {},
                     image = nil, image_coords = nil, tags = [], check_location = nil,
                     unique_loot = nil, _room_objects = nil,
                     genie_id = nil, genie_zone = nil, genie_pos = nil)
        @id = id
        @title = title
        @description = description
        @paths = paths
        @uid = uid
        @location = location
        @climate = climate
        @terrain = terrain
        @wayto = wayto
        @timeto = timeto
        @image = image
        @image_coords = image_coords
        @tags = TagList.new(tags, self.class)
        @check_location = check_location
        @unique_loot = unique_loot
        @genie_id = genie_id
        @genie_zone = genie_zone
        @genie_pos = genie_pos
        @@list[@id] = self
        # Skipped during a bulk load: @@loaded is false throughout, load_json
        # clears the cache when it finishes, and any tag query while unloaded
        # goes through #list, which loads first. Saves one mutex per room.
        self.class.reset_tag_index if @@loaded
      end

      # Generates a human-readable representation of the room.
      #
      # @return [String] the room in format "#<id> (<uid>):\n<title>\n<description>\n<paths>", using the latest values from history arrays
      def to_s
        "##{@id} (#{@uid[-1]}):\n#{@title[-1]}\n#{@description[-1]}\n#{@paths[-1]}"
      end

      # Returns extra genie-reference fields for JSON serialization.
      #
      # @return [Hash] genie-related metadata: genie_id, genie_zone, genie_pos
      # @api private
      def json_extra_fields
        { genie_id: @genie_id, genie_zone: @genie_zone, genie_pos: @genie_pos }
      end

      # Class method accessors
      class << self
        # Accessors for the room-navigation state, matching GemStone, so the
        # shared MapBase implementations can reach it without touching class
        # variables directly.
        def current_room_id
          @@current_room_id
        end

        # Sets the current room ID class variable.
        #
        # @param id [Integer] the room ID to set
        # @return [Integer] the ID
        # @api private
        def current_room_id=(id)
          @@current_room_id = id
        end

        # Returns the ID of the room the character was in before the current room.
        #
        # @return [Integer] the previous room ID, or -1 if none has been recorded
        def previous_room_id
          @@previous_room_id
        end

        # Sets the previous room ID class variable.
        #
        # @param id [Integer] the room ID to set
        # @return [Integer] the ID
        # @api private
        def previous_room_id=(id)
          @@previous_room_id = id
        end

        # Whether the map data has been loaded from persistent storage.
        #
        # @return [Boolean] true if .load has completed, false otherwise
        def loaded?
          @@loaded
        end

        # Returns the list of all rooms in the map, loading from storage if needed.
        #
        # @return [Array<Map>] all registered rooms, indexed by room ID
        # @note Triggers .load if not yet loaded; blocks on the load mutex
        def list
          self.load unless @@loaded
          @@list
        end

        # The backing array without triggering a load. Only for use inside the
        # load path, where #list would re-enter the load mutex and deadlock.
        def raw_list
          @@list
        end

        # Replaces the room list and normalizes tag metadata.
        #
        # @param value [Array<Map>] the new room list
        # @return [Array<Map>] the assigned list
        # @note Calls normalize_tag_lists on the new value
        # @api private
        def list=(value)
          @@list = value
          normalize_tag_lists(value)
        end

        # Returns the UID-to-room-IDs mapping for disambiguation.
        #
        # @return [Hash{Integer => Array<Integer>}] maps server UID to list of room IDs sharing that UID
        def uids
          @@uids
        end

        # Invalidates the tag index cache, forcing tags to be re-indexed on next query.
        #
        # @return [void]
        # @api private
        def clear_tags_cache
          reset_tag_index
        end

        # Marks the map as fully loaded from storage.
        #
        # @return [void]
        # @api private
        def mark_loaded
          @@loaded = true
        end

        # Acquires the load mutex and executes the block, preventing concurrent map loads.
        #
        # @yield Executes the block while holding the load mutex
        # @return [Object] the return value of the block
        # @api private
        def synchronize_load(&block)
          @@load_mutex.synchronize(&block)
        end
      end

      # Looks up a room by its genie (map client) zone and node identifiers.
      #
      # @param zone_id [Integer, String] the genie zone identifier
      # @param node_id [Integer, String] the genie node identifier
      # @return [Map, nil] the matched room, or nil if no room carries that genie reference
      # @note Triggers .load if not yet loaded
      def self.by_genie_ref(zone_id, node_id)
        self.load unless @@loaded
        @@list.find { |r| r&.genie_zone == zone_id.to_s && r&.genie_id == node_id.to_s }
      end

      # Returns the room the character was in before the current room.
      #
      # @return [Map, nil] the previous room, or nil if no previous room has been recorded
      def self.previous
        @@list[@@previous_room_id]
      end

      # Returns the character's current room by resolving game state to a room ID.
      #
      # Uses exact title/description/paths matching when a script is running (#match_current),
      # or fuzzy matching when scriptless (#match_fuzzy). Applies UID disambiguation to reject
      # matches if the game exposes a live UID that contradicts the matched room's stored UIDs.
      #
      # @return [Map, nil] the current room, or nil when no room matches the game state
      # @note Triggers .load if not yet loaded; caches result based on XMLData.room_count
      def self.current
        self.load unless @@loaded
        if Script.current
          return @@list[@@current_room_id] if XMLData.room_count == @@current_room_count && !@@current_room_id.nil?
        elsif XMLData.room_count == @@fuzzy_room_count && !@@current_room_id.nil?
          return @@list[@@current_room_id]
        end
        ids = XMLData.room_id.zero? ? [] : ids_from_uid(XMLData.room_id)
        return set_current(ids[0]) if ids.size == 1

        if ids.size > 1 && !@@current_room_id.nil? && (id = match_multi_ids(ids))
          return set_current(id)
        end
        match_no_uid
      end

      # Pattern identifying a room whose disambiguation depends on a manual
      # +peer+ action (for example peering through a doorway to read an adjacent
      # room before committing to a match). Such rooms cannot be told apart
      # without a running script to perform the peer, so scriptless fuzzy
      # matching declines to resolve them. Kept verbatim from the historical
      # inline checks in {match_fuzzy}.
      PEER_TAG_PATTERN = /^(set desc on; )?peer [a-z]+ =~ \/.+\/$/

      # Whether +room+ carries a peer-disambiguation tag (see {PEER_TAG_PATTERN}).
      #
      # @param room [Lich::Common::Map] a room already matched on
      #   title/description/paths
      # @return [Boolean] +true+ when the room requires a manual peer to
      #   disambiguate, +false+ otherwise
      def self.peer_disambiguation_tag?(room)
        room.tags.any? { |tag| tag =~ PEER_TAG_PATTERN }
      end

      # Resolve a room that already matched on title/description/paths down to a
      # final room id, applying UID disambiguation.
      #
      # The governing invariant is that *a stored UID must never make a room less
      # resolvable than an otherwise identical room with no UID.*
      #
      # * When the game exposes a live UID (+XMLData.room_id+ is non-zero) and the
      #   matched room carries one or more UIDs, the match only stands if the live
      #   UID is among them. This is what keeps distinct rooms that share a
      #   title/description/paths (day/night variants, look-alike maze cells) from
      #   collapsing onto one another.
      # * When the game exposes *no* UID (+XMLData.room_id+ is zero, a room the
      #   server does not surface a UID for), UID disambiguation is skipped and the
      #   title/description/paths match is trusted regardless of any UID stored on
      #   the room. Previously such a room returned +nil+ here (a stored UID can
      #   never include the zero live id), so a UID accidentally or provisionally
      #   stamped onto a no-UID room made that room permanently unresolvable
      #   (+Map.current+ became +nil+). Trusting the text match in the no-UID case
      #   removes that failure mode without weakening disambiguation when the game
      #   does expose a UID.
      #
      # @param room [Lich::Common::Map] the room matched on title/description/paths
      # @param honor_peer_tags [Boolean] when +true+, a room requiring a manual
      #   peer to disambiguate (see {peer_disambiguation_tag?}) resolves to +nil+;
      #   used by scriptless fuzzy matching, which cannot perform the peer. Exact
      #   ({match_current}) matching passes +false+ and never consults peer tags.
      # @return [Integer, nil] the resolved room id; +nil+ when a UID'd room's
      #   stored UIDs exclude the live game UID, or when a peer-tagged room cannot
      #   be disambiguated
      def self.resolve_matched_room(room, honor_peer_tags:)
        if room.uid.any? && !XMLData.room_id.zero?
          return room.uid.include?(XMLData.room_id) ? room.id : nil
        end
        return nil if honor_peer_tags && peer_disambiguation_tag?(room)

        room.id
      end

      # Resolve the current room by exact title/description/paths matching.
      #
      # Used when a script is running (see {match_no_uid}). Tries an exact
      # description match first, then a punctuation-tolerant regex description
      # match, re-reading the room whenever the live +room_count+ changes
      # mid-match. Final UID disambiguation is delegated to
      # {resolve_matched_room} (peer tags are not honored on this path).
      #
      # @param _script [Object] the running script (unused; retained for the
      #   historical call signature)
      # @return [Integer, nil] the resolved room id, or +nil+ when nothing matches
      #   or UID disambiguation rejects the match
      def self.match_current(_script)
        @@current_room_mutex.synchronize do
          need_set_desc_off = false
          begin
            loop do
              @@current_room_count = XMLData.room_count
              foggy_exits = XMLData.room_exits_string =~ /^Obvious (?:exits|paths): obscured by a thick fog$/
              room = @@list.find do |r|
                # Skip nil holes without relying on Lich's NilClass patch.
                r &&
                  r.title.include?(XMLData.room_title) &&
                  r.description.include?(XMLData.room_description.strip) &&
                  (foggy_exits || r.paths.include?(XMLData.room_exits_string.strip))
              end

              if room
                redo unless @@current_room_count == XMLData.room_count
                return resolve_matched_room(room, honor_peer_tags: false)
              else
                redo unless @@current_room_count == XMLData.room_count
                desc_regex = /#{Regexp.escape(XMLData.room_description.strip.sub(/\.+$/, '')).gsub(/\\\.(?:\\\.\\\.)?/, '|')}/
                room = @@list.find do |r|
                  # Skip nil holes without relying on Lich's NilClass patch.
                  r &&
                    r.title.include?(XMLData.room_title) &&
                    (foggy_exits || r.paths.include?(XMLData.room_exits_string.strip)) &&
                    (XMLData.room_window_disabled || r.description.any? { |desc| desc =~ desc_regex })
                end

                if room
                  redo unless @@current_room_count == XMLData.room_count
                  return resolve_matched_room(room, honor_peer_tags: false)
                else
                  redo unless @@current_room_count == XMLData.room_count
                  return nil
                end
              end
            end
          ensure
            put 'set description off' if need_set_desc_off
          end
        end
      end

      # Resolve the current room by fuzzy title/description/paths matching.
      #
      # Used when no script is running (see {match_no_uid}). Mirrors
      # {match_current} but honors peer-disambiguation tags: a room that would
      # need a manual peer to tell apart cannot be resolved without a script, so
      # it yields +nil+. Final UID disambiguation is delegated to
      # {resolve_matched_room} with +honor_peer_tags: true+.
      #
      # @return [Integer, nil] the resolved room id, or +nil+ when nothing
      #   matches, UID disambiguation rejects the match, or the room needs a peer
      def self.match_fuzzy
        @@fuzzy_room_mutex.synchronize do
          @@fuzzy_room_count = XMLData.room_count
          loop do
            foggy_exits = XMLData.room_exits_string =~ /^Obvious (?:exits|paths): obscured by a thick fog$/
            room = @@list.find do |r|
              # Skip nil holes without relying on Lich's NilClass patch.
              r &&
                r.title.include?(XMLData.room_title) &&
                r.description.include?(XMLData.room_description.strip) &&
                (foggy_exits || r.paths.include?(XMLData.room_exits_string.strip))
            end

            if room
              redo unless @@fuzzy_room_count == XMLData.room_count

              return resolve_matched_room(room, honor_peer_tags: true)
            else
              redo unless @@fuzzy_room_count == XMLData.room_count
              desc_regex = /#{Regexp.escape(XMLData.room_description.strip.sub(/\.+$/, '')).gsub(/\\\.(?:\\\.\\\.)?/, '|')}/
              room = @@list.find do |r|
                # Skip nil holes without relying on Lich's NilClass patch.
                r &&
                  r.title.include?(XMLData.room_title) &&
                  (foggy_exits || r.paths.include?(XMLData.room_exits_string.strip)) &&
                  (XMLData.room_window_disabled || r.description.any? { |desc| desc =~ desc_regex })
              end

              if room
                redo unless @@fuzzy_room_count == XMLData.room_count

                return resolve_matched_room(room, honor_peer_tags: true)
              else
                redo unless @@fuzzy_room_count == XMLData.room_count
                return nil
              end
            end
          end
        end
      end

      # Returns the current room, or mints a new room if none exists.
      #
      # Resolves the character's current location like .current, but creates and registers
      # a new room if no match is found and a script is running. Skips minting when the arrival
      # frame is blank (no UID, pitch-dark, no exits), as the server is likely still loading
      # the real room.
      #
      # @return [Map, nil] the current room (matched or newly minted), or nil if no script is running, the frame is blank, or matching fails
      # @note Adds server UIDs to room.uid and updates the @@uids index when found; only callable from a running script
      # @api private
      def self.current_or_new
        return nil unless Script.current

        @@current_room_count = -1
        @@fuzzy_room_count = -1

        self.load unless @@loaded

        id = current&.id

        echo("Map: current room id is #{id.inspect}")
        unless id.nil?
          room = self[id]
          unless XMLData.room_id.zero? || room.uid.include?(XMLData.room_id)
            room.uid << XMLData.room_id
            uids_add(XMLData.room_id, room.id)
            echo "Map: Adding new uid for #{room.id}: #{XMLData.room_id}"
          end
          return set_current(room.id)
        end

        # Guard against a blank/incomplete arrival frame. DR occasionally streams a room whose
        # <nav> UID is delayed or absent (room_id 0) before the room text populates: the
        # description is only the "pitch dark" placeholder and there are no exits. Minting a
        # room here creates a junk stub (empty title, no UID) that orphans or duplicates the
        # real room. Keep the current room instead; the real room resolves by UID once the
        # delayed nav (or a re-look) provides it.
        if XMLData.room_id.zero? &&
           XMLData.room_exits_string.to_s.strip.empty? &&
           XMLData.room_description.to_s.strip == "It's pitch dark and you can't see a thing!"
          echo 'Map: skipped blank/incomplete room frame (no uid, pitch-dark, no exits)'
          # Keep the current room - but only if one has actually resolved.
          # @@current_room_id is the -1 sentinel before the first match; passing
          # that to set_current would index @@list[-1] (the last room) and make an
          # unrelated room current, so fall back to nil in that case instead.
          return set_current(@@current_room_id) if @@current_room_id.is_a?(Integer) && @@current_room_id >= 0

          return nil
        end

        id = get_free_id
        title = [XMLData.room_title]
        description = [XMLData.room_description.strip]
        paths = [XMLData.room_exits_string.strip]
        uid = XMLData.room_id.zero? ? [] : [XMLData.room_id]
        room = new(id, title, description, paths, uid)
        uids_add(XMLData.room_id, room.id) unless XMLData.room_id.zero?
        echo "mapped new room, set current room to #{room.id}"
        set_current(id)
      end

      # Rebuilds the UID-to-room-IDs index from the current room list.
      #
      # Clears and repopulates @@uids, aggregating all UIDs stored on all rooms.
      # Handles sparse maps (nil holes) gracefully without relying on NilClass patches.
      #
      # @return [void]
      # @note Triggers .load if not yet loaded
      # @api private
      def self.load_uids
        self.load unless @@loaded
        @@uids.clear
        # compact rather than relying on Lich's NilClass patch to make r.uid on a
        # hole return nil; a sparse map should not need that to load.
        @@list.compact.each do |r|
          r.uid.each do |u|
            if @@uids[u].nil?
              @@uids[u] = [r.id]
            elsif !@@uids[u].include?(r.id)
              @@uids[u] << r.id
            end
          end
        end
      end

      # Returns the list of room IDs sharing a given server UID.
      #
      # @param n [Integer] the server UID to look up
      # @return [Array<Integer>] room IDs with that UID, or [] if the UID is unknown or zero
      def self.ids_from_uid(n)
        @@uids[n].nil? || n.zero? ? [] : @@uids[n]
      end

      # Clears all rooms from memory and resets map state.
      #
      # Clears the room list, tag index cache, and resets the loaded flag. Requests garbage
      # collection after clearing.
      #
      # @return [Boolean] always returns true
      # @note Acquires the load mutex; blocks other load attempts until completion
      # @api private
      def self.clear
        @@load_mutex.synchronize do
          @@list.clear
          clear_tags_cache
          @@loaded = false
          GC.start
        end
        true
      end

      # Construct a room from a parsed JSON hash
      # @param room [Hash]
      # @return [Map] the registered room
      def self.room_from_json(room)
        new(
          room['id'], room['title'], room['description'], room['paths'],
          room['uid'], room['location'], room['climate'], room['terrain'],
          room['wayto'], room['timeto'], room['image'], room['image_coords'],
          room['tags'], room['check_location'], room['unique_loot'],
          nil, # _room_objects
          room['genie_id'], room['genie_zone'], room['genie_pos']
        )
      end
    end

    # Alias for Map; provided for API compatibility.
    class Room < Map
    end
  end
end
