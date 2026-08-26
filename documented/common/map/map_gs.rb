# frozen_string_literal: true

require_relative 'map_base'

# Namespace for the Lich scripting engine.
module Lich
  # Namespace for common shared functionality across Lich game servers.
  module Common
    # GemStone-specific Map implementation
    # Inherits shared functionality from MapBase
    # Includes GS-specific features: get_location, peer tags, meta:map tags, player shops
    class Map
      include Enumerable
      include MapBase

      @@loaded                   = false
      @@load_mutex               = Mutex.new
      @@list                   ||= []
      @@images                 ||= []
      @@locations              ||= []
      @@current_room_mutex       = Mutex.new
      @@current_room_id        ||= nil
      @@current_room_count     ||= -1
      @@fuzzy_room_mutex         = Mutex.new
      @@fuzzy_room_id          ||= nil
      @@fuzzy_room_count       ||= -1
      @@current_location       ||= nil
      @@current_location_count ||= -1
      @@previous_room_id       ||= nil
      @@uids                     = {}

      attr_reader :id
      attr_accessor :title, :description, :paths, :uid, :location, :climate, :terrain,
                    :wayto, :timeto, :image, :image_coords, :check_location, :unique_loot

      # @return [TagList] mutation-aware list of this room's tags
      attr_reader :tags

      # Initializes a Map room with all metadata.
      #
      # Rooms are automatically registered in the class-level @@list and made
      # available via .list, .[id], and iteration. If the map is already loaded,
      # the tag index is reset to reflect the new room; during bulk load (when
      # @@loaded is false), tag index resets are deferred until load_json finishes.
      #
      # @param id [Integer] unique room identifier
      # @param title [Array<String>] room title(s); newest first
      # @param description [Array<String>] room description(s); newest first
      # @param paths [Array<String>] exit/path strings; newest first
      # @param uid [Array<Integer>] GemStone unique IDs; default []
      # @param location [String, nil] in-game location from 'location' command; default nil
      # @param climate [String, nil] climate tag; default nil
      # @param terrain [String, nil] terrain tag; default nil
      # @param wayto [Hash] navigation hints (not currently used); default {}
      # @param timeto [Hash] travel time estimates (not currently used); default {}
      # @param image [String, nil] map image file reference; default nil
      # @param image_coords [String, nil] coordinates within the image; default nil
      # @param tags [Array<String>] searchable tags including special meta:map tags; default []
      # @param check_location [Boolean, nil] when true, require location match during current room lookup; default nil
      # @param unique_loot [Array<String>, nil] specific items that appear only in this room; default nil
      def initialize(id, title, description, paths, uid = [], location = nil,
                     climate = nil, terrain = nil, wayto = {}, timeto = {},
                     image = nil, image_coords = nil, tags = [], check_location = nil,
                     unique_loot = nil)
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
        @@list[@id] = self
        # Skipped during a bulk load: @@loaded is false throughout, load_json
        # clears the cache when it finishes, and any tag query while unloaded
        # goes through #list, which loads first. Saves one mutex per room.
        self.class.reset_tag_index if @@loaded
      end

      # Class method accessors required by MapBase
      class << self
        # Returns the room ID the current script is in, or nil if not yet set.
        #
        # @return [Integer, nil] the current room ID
        # @api private
        def current_room_id
          @@current_room_id
        end

        # Sets the room ID for the current script.
        #
        # @param id [Integer] room ID
        # @return [Integer] the new room ID
        # @api private
        def current_room_id=(id)
          @@current_room_id = id
        end

        # Returns whether the map has finished loading from the map file.
        #
        # @return [Boolean] true if the map is loaded
        # @api private
        def loaded
          @@loaded
        end

        # Returns whether the map has finished loading from the map file.
        #
        # @return [Boolean] true if the map is loaded
        # @api private
        def loaded?
          @@loaded
        end

        # Returns the room ID the current script was previously in, or nil if not yet set.
        #
        # @return [Integer, nil] the previous room ID
        # @api private
        def previous_room_id
          @@previous_room_id
        end

        # Sets the room ID for the previous location.
        #
        # @param id [Integer] room ID
        # @return [Integer] the new room ID
        # @api private
        def previous_room_id=(id)
          @@previous_room_id = id
        end

        # Returns the complete array of all loaded rooms, loading the map if needed.
        #
        # Triggers a load on first call. Thread-safe. Safe to iterate while the map
        # is being modified.
        #
        # @return [Array<Map>] all room objects
        # @example
        #   Map.list.size #=> 12345
        #   Map.list.first #=> #<Map id=1>
        def list
          self.load unless @@loaded
          @@list
        end

        # The backing array without triggering a load. Only for use inside the
        # load path, where #list would re-enter the load mutex and deadlock.
        def raw_list
          @@list
        end

        # Replaces the entire room list and normalizes tag lists for efficient searching.
        #
        # @param value [Array<Map>] new list of rooms
        # @return [Array<Map>] the new list
        # @api private
        def list=(value)
          @@list = value
          normalize_tag_lists(value)
        end

        # Returns the GemStone UID-to-room-IDs lookup table.
        #
        # @return [Hash{Integer => Array<Integer>}] maps UID to array of room IDs
        # @api private
        def uids
          @@uids
        end

        # Clears the cached tag index, forcing rebuild on next tag query.
        #
        # @return [void]
        # @api private
        def clear_tags_cache
          reset_tag_index
        end

        # Marks the map as fully loaded.
        #
        # @return [Boolean] true
        # @api private
        def mark_loaded
          @@loaded = true
        end

        # Executes a block under the map load mutex to ensure thread-safe loading.
        #
        # @yield runs the given block with the load lock held
        # @return [Object] the result of the block
        # @api private
        def synchronize_load(&block)
          @@load_mutex.synchronize(&block)
        end
      end

      # Returns the current room ID (instance method alias for class variable).
      #
      # @return [Integer, nil] the current room ID
      # @note Prefer .current over this method.
      # @api private
      def fuzzy_room_id
        @@current_room_id
      end

      # Returns a human-readable string representation of this room.
      #
      # @return [String] room ID, newest UID, title, location, description, and exits
      # @example
      #   room.to_s #=> "#1234 (u4294967295):\nRoad (Wehnimer's Landing)\nA dusty road...\nObvious exits: north, south"
      def to_s
        "##{@id} (u#{@uid[-1]}):\n#{@title[-1]} (#{@location})\n#{@description[-1]}\n#{@paths[-1]}"
      end

      # Returns the room ID of the last fuzzy match attempt, for scripts without
      # current script context (used in background thread mode).
      #
      # @return [Integer, nil] the fuzzy-matched room ID
      # @api private
      def self.fuzzy_room_id
        @@fuzzy_room_id
      end

      # GS-specific: Get location using in-game 'location' command
      def self.get_location
        unless XMLData.room_count == @@current_location_count
          if (script = Script.current)
            save_want_downstream = script.want_downstream
            script.want_downstream = true
            waitrt?
            location_result = dothistimeout(
              'location', 15,
              /^You carefully survey your surroundings and guess that your current location is .*? or somewhere close to it\.$|^You can't do that while submerged under water\.$|^You can't do that\.$|^It would be rude not to give your full attention to the performance\.$|^You can't do that while hanging around up here!$|^You are too distracted by the difficulty of staying alive in these treacherous waters to do that\.$|^You carefully survey your surroundings but are unable to guess your current location\.$|^Not in pitch darkness you don't\.$|^That is too difficult to consider here\.$/
            )
            script.want_downstream = save_want_downstream
            @@current_location_count = XMLData.room_count
            if location_result =~ /^You can't do that while submerged under water\.$|^You can't do that\.$|^It would be rude not to give your full attention to the performance\.$|^You can't do that while hanging around up here!$|^You are too distracted by the difficulty of staying alive in these treacherous waters to do that\.$|^You carefully survey your surroundings but are unable to guess your current location\.$|^Not in pitch darkness you don't\.$|^That is too difficult to consider here\.$/
              @@current_location = false
            else
              @@current_location = /^You carefully survey your surroundings and guess that your current location is (.*?) or somewhere close to it\.$/.match(location_result).captures.first
            end
          else
            return nil
          end
        end
        @@current_location
      end

      # Returns the Map room object for the previous location, or nil if not yet set.
      #
      # @return [Map, nil] the previous room
      # @example
      #   Map.previous #=> #<Map id=1234>
      #   Map.previous #=> nil  # if no previous room recorded
      def self.previous
        return nil if @@previous_room_id.nil?

        @@list[@@previous_room_id]
      end

      # Returns the Map room object for the current location, matching by UID,
      # description, title, exits, and optional peer tags and location requirements.
      #
      # Returns nil if the room cannot be matched. Caches the result per room_count
      # to avoid redundant matching on the same server message. Uses UIDs as primary
      # lookup, then falls back to multi-UID rooms and description matching.
      #
      # This method is called automatically by the game loop and is not typically
      # invoked directly from scripts.
      #
      # @return [Map, nil] the current room object, or nil if not identified
      # @see .match_current
      # @api private
      def self.current
        self.load unless @@loaded
        if Script.current
          return @@list[@@current_room_id] if XMLData.room_count == @@current_room_count && !@@current_room_id.nil?
        elsif XMLData.room_count == @@fuzzy_room_count && !@@current_room_id.nil?
          return @@list[@@current_room_id]
        end
        # GS uses large UID check instead of zero check
        ids = XMLData.room_id > 4_294_967_296 ? [] : ids_from_uid(XMLData.room_id)
        return set_current(ids[0]) if ids.size == 1

        if ids.size > 1 && !@@current_room_id.nil? && (id = match_multi_ids(ids))
          return set_current(id)
        end
        match_no_uid
      end

      # GS-specific: match_current with peer tag checking
      def self.match_current(script)
        @@current_room_mutex.synchronize do
          peer_history = {}
          need_set_desc_off = false

          check_peer_tag = proc do |r|
            begin
              script.ignore_pause = true
              peer_room_count = XMLData.room_count
              peer_tag = r.tags.find { |tag| tag =~ %r{^(set desc on; )?peer [a-z]+ =~ /.+/$} }
              if peer_tag
                need_desc, peer_direction, peer_requirement = %r{^(set desc on; )?peer ([a-z]+) =~ /(.+)/$}.match(peer_tag).captures
                need_desc = need_desc ? true : false
                peer_history[peer_room_count] ||= {}
                peer_history[peer_room_count][peer_direction] ||= {}

                if peer_history[peer_room_count][peer_direction][need_desc].nil?
                  if need_desc
                    last_roomdesc = $_SERVERBUFFER_.reverse.find { |line| line =~ /<style id="roomDesc"\/>/ }
                    unless last_roomdesc && last_roomdesc =~ %r{<style id="roomDesc"/>[^<]}
                      put 'set description on'
                      need_set_desc_off = true
                    end
                  end
                  save_want_downstream = script.want_downstream
                  squelch_started = false
                  squelch_proc = proc do |server_string|
                    if squelch_started
                      DownstreamHook.remove('squelch-peer') if server_string =~ /<prompt/
                      nil
                    elsif server_string =~ /^You peer/
                      squelch_started = true
                      nil
                    else
                      server_string
                    end
                  end
                  begin
                    script.want_downstream = true
                    DownstreamHook.add('squelch-peer', squelch_proc, persist: false)
                    result = dothistimeout "peer #{peer_direction}", 3, /^You peer|^\[Usage: PEER/
                    if result =~ /^You peer/
                      peer_results = []
                      5.times do
                        line = get?
                        if line
                          peer_results.push line
                          break if line =~ /^Obvious/
                        end
                      end
                      if XMLData.room_count == peer_room_count
                        if need_desc
                          peer_history[peer_room_count][peer_direction][true] = peer_results
                          peer_history[peer_room_count][peer_direction][false] = peer_results
                        else
                          peer_history[peer_room_count][peer_direction][false] = peer_results
                        end
                      end
                    end
                  ensure
                    # persist: false only cleans up when the owning script dies, so
                    # a usage error, timeout or exception would otherwise leave the
                    # hook registered globally. Remove it unconditionally, and put
                    # want_downstream back even if the command raised.
                    DownstreamHook.remove('squelch-peer')
                    script.want_downstream = save_want_downstream
                  end
                end
                # Nil when the peer command failed or timed out, so nothing was
                # recorded. Treat that as no match rather than relying on the
                # NilClass patch to make nil.any? return a falsy nil.
                peer_lines = peer_history[peer_room_count][peer_direction][need_desc]
                good = peer_lines.is_a?(Array) && peer_lines.any? { |line| line =~ /#{peer_requirement}/ }
              else
                good = true
              end
            ensure
              script.ignore_pause = false
            end
            good
          end

          begin
            loop do
              @@current_room_count = XMLData.room_count
              foggy_exits = XMLData.room_exits_string =~ /^Obvious (?:exits|paths): obscured by a thick fog$/
              room = @@list.find do |r|
                # Skip nil holes without relying on Lich's NilClass patch.
                r &&
                  r.title.include?(XMLData.room_title) &&
                  r.description.include?(XMLData.room_description.strip) &&
                  (r.unique_loot.nil? || (r.unique_loot.to_a - GameObj.loot.to_a.collect(&:name)).empty?) &&
                  (foggy_exits || r.paths.include?(XMLData.room_exits_string.strip) || r.tags.include?('random-paths')) &&
                  (!r.check_location || r.location == get_location) && check_peer_tag.call(r)
              end

              if room
                redo unless @@current_room_count == XMLData.room_count
                return room.id
              else
                redo unless @@current_room_count == XMLData.room_count
                desc_regex = /#{Regexp.escape(XMLData.room_description.strip.sub(/\.+$/, '')).gsub(/\\\.(?:\\\.\\\.)?/, '|')}/
                room = @@list.find do |r|
                  # Skip nil holes without relying on Lich's NilClass patch.
                  r &&
                    r.title.include?(XMLData.room_title) &&
                    (foggy_exits || r.paths.include?(XMLData.room_exits_string.strip) || r.tags.include?('random-paths')) &&
                    (XMLData.room_window_disabled || r.description.any? { |desc| desc =~ desc_regex }) &&
                    (r.unique_loot.nil? || (r.unique_loot.to_a - GameObj.loot.to_a.collect(&:name)).empty?) &&
                    (!r.check_location || r.location == get_location) && check_peer_tag.call(r)
                end

                if room
                  redo unless @@current_room_count == XMLData.room_count
                  return room.id
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

      # Matches the current location to a room, used in non-script contexts where
      # peer tags cannot be checked.
      #
      # Used by background threads and front-end clients that do not have script
      # context. Skips peer tag matching because those tags require executing
      # in-game commands that only a script can do safely. Returns nil if the room
      # has unresolved peer tag requirements.
      #
      # @return [Integer, nil] the matched room ID, or nil if no match or match has peer tags
      # @api private
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
                (r.unique_loot.nil? || (r.unique_loot.to_a - GameObj.loot.to_a.collect(&:name)).empty?) &&
                (foggy_exits || r.paths.include?(XMLData.room_exits_string.strip) || r.tags.include?('random-paths')) &&
                (!r.check_location || r.location == get_location)
            end

            if room
              redo unless @@fuzzy_room_count == XMLData.room_count
              if room.tags.any? { |tag| tag =~ %r{^(set desc on; )?peer [a-z]+ =~ /.+/$} }
                return nil
              else
                return room.id
              end
            else
              redo unless @@fuzzy_room_count == XMLData.room_count
              desc_regex = /#{Regexp.escape(XMLData.room_description.strip.sub(/\.+$/, '')).gsub(/\\\.(?:\\\.\\\.)?/, '|')}/
              room = @@list.find do |r|
                # Skip nil holes without relying on Lich's NilClass patch.
                r &&
                  r.title.include?(XMLData.room_title) &&
                  (foggy_exits || r.paths.include?(XMLData.room_exits_string.strip) || r.tags.include?('random-paths')) &&
                  (XMLData.room_window_disabled || r.description.any? { |desc| desc =~ desc_regex }) &&
                  (r.unique_loot.nil? || (r.unique_loot.to_a - GameObj.loot.to_a.collect(&:name)).empty?) &&
                  (!r.check_location || r.location == get_location)
              end

              if room
                redo unless @@fuzzy_room_count == XMLData.room_count
                if room.tags.any? { |tag| tag =~ %r{^(set desc on; )?peer [a-z]+ =~ /.+/$} }
                  return nil
                else
                  return room.id
                end
              else
                redo unless @@fuzzy_room_count == XMLData.room_count
                return nil
              end
            end
          end
        end
      end

      # GS-specific: Extended current_or_new with meta:map tag handling
      def self.current_or_new
        return nil unless Script.current

        self.load unless @@loaded
        ids = XMLData.room_id > 4_294_967_296 ? [] : ids_from_uid(XMLData.room_id)
        room = nil
        id = ids[0] if ids.size == 1
        id = match_multi_ids(ids) if ids.size > 1

        if id.nil?
          id = match_current(Script.current)
          # prevent loading uids into existing rooms with a single id unless tagged meta:map:multi-uid
          if !id.nil? && self[id].uid.size == 1 && !self[id].tags.include?('meta:map:multi-uid')
            id = nil
          end
        end

        if !id.nil?
          room = self[id]
          unless XMLData.room_id > 4_294_967_296 || room.uid.include?(XMLData.room_id)
            room.uid << XMLData.room_id
            uids_add(XMLData.room_id, room.id)
            echo "Map: Adding new uid for #{room.id}: #{XMLData.room_id}"
          end

          if (room.tags & %w[meta:map:latest-only meta:playershop]).empty?
            # update room if not meta:playershop or meta:map:latest-only
            unless room.title.include?(XMLData.room_title)
              room.title.unshift(XMLData.room_title)
              echo "Map: Adding new title for #{room.id}: '#{XMLData.room_title}'"
            end
            unless room.description.include?(XMLData.room_description.strip)
              room.description.unshift(XMLData.room_description.strip)
              echo "Map: Adding new description for #{room.id} : #{XMLData.room_description.strip.inspect}"
            end
            unless room.paths.include?(XMLData.room_exits_string.strip)
              room.paths.unshift(XMLData.room_exits_string.strip)
              echo "Map: Adding new path for #{room.id}: #{XMLData.room_exits_string.strip.inspect}"
            end
            if room.location.nil? || room.location == false || room.location == ''
              current_location = get_location
              room.location = current_location
              echo "Map: Updating location for #{room.id}: #{current_location.inspect}"
            end
          elsif !(room.tags & %w[meta:map:latest-only meta:playershop]).empty?
            # update rooms tagged meta:playershop or meta:map:latest-only
            if room.title != [XMLData.room_title]
              room.title = [XMLData.room_title]
              echo "Map: Updating title for #{room.id}: #{XMLData.room_title.inspect}"
            end
            if room.description != [XMLData.room_description.strip]
              room.description = [XMLData.room_description.strip]
              echo "Map: Updating description for #{room.id}: #{XMLData.room_description.strip.inspect}"
            end
            if room.paths != [XMLData.room_exits_string.strip]
              room.paths = [XMLData.room_exits_string.strip]
              echo "Map: Updating path for #{room.id}: #{XMLData.room_exits_string.strip.inspect}"
            end
            if room.location.nil? || room.location == false || room.location == ''
              current_location = get_location
              room.location = current_location
              echo "Map: Updating location for #{room.id}: #{current_location.inspect}"
            end
          end
          return set_current(room.id)
        end

        # new room
        id = get_free_id
        title = [XMLData.room_title]
        description = [XMLData.room_description.strip]
        paths = [XMLData.room_exits_string.strip]
        uid = XMLData.room_id > 4_294_967_296 ? [] : [XMLData.room_id]
        current_location = get_location
        room = new(id, title, description, paths, uid, current_location)
        uids_add(XMLData.room_id, room.id) unless XMLData.room_id > 4_294_967_296

        # flag identical rooms with different locations
        identical_rooms = @@list.find_all do |r|
          # Skip nil holes without relying on Lich's NilClass patch.
          r &&
            r.location != current_location &&
            r.title.include?(XMLData.room_title) &&
            r.description.include?(XMLData.room_description.strip) &&
            (r.unique_loot.nil? || (r.unique_loot.to_a - GameObj.loot.to_a.collect(&:name)).empty?) &&
            (r.paths.include?(XMLData.room_exits_string.strip) || r.tags.include?('random-paths')) &&
            !r.uid.include?(XMLData.room_id)
        end

        if identical_rooms.length.positive?
          room.check_location = true
          identical_rooms.each { |r| r.check_location = true }
        end

        echo "mapped new room, set current room to #{room.id}"
        set_current(id)
      end

      # GS-specific: Get all unique locations
      def self.locations
        self.load unless @@loaded
        @@locations = @@list.compact.each_with_object({}) { |r, h| h[r.location] = nil unless h.key?(r.location) }.keys if @@locations.empty?
        @@locations.dup
      end

      # GS-specific: Get all unique map images
      def self.images
        self.load unless @@loaded
        @@images = @@list.compact.each_with_object({}) { |r, h| h[r.image] = nil unless h.key?(r.image) }.keys if @@images.empty?
        @@images.dup
      end

      # Clears the UID-to-room-ID lookup table.
      #
      # @return [void]
      # @api private
      def self.uids_clear
        @@uids.clear
      end

      # Returns the room IDs associated with a GemStone UID, or empty array if not found.
      #
      # @param n [Integer] GemStone UID from XMLData.room_id
      # @return [Array<Integer>] matching room IDs; empty if UID not known
      # @api private
      def self.ids_from_uid(n)
        @@uids[n].nil? ? [] : @@uids[n]
      end

      # Rebuilds the UID lookup table from the current room list.
      #
      # Clears @@uids and re-indexes all UIDs from every room in @@list.
      # Called after loading the map file to make UID lookups available.
      #
      # @return [void]
      # @api private
      def self.load_uids
        self.load unless @@loaded
        @@uids.clear
        # compact rather than relying on Lich's NilClass patch to make r.uid on a
        # hole return nil; a sparse map should not need that to load.
        @@list.compact.each do |r|
          r.uid.each { |u| uids_add(u, r.id) }
        end
      end

      # Clears the entire map from memory and resets the loaded state.
      #
      # Acquires the load mutex before clearing to ensure thread safety.
      # Also clears the tag cache, location cache, image cache, and triggers
      # garbage collection.
      #
      # @return [Boolean] true
      # @api private
      def self.clear
        @@load_mutex.synchronize do
          @@list.clear
          clear_tags_cache
          @@locations.clear
          @@images.clear
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
          room['tags'], room['check_location'], room['unique_loot']
        )
      end
    end

    # Alias for Map. Scripts may use either name.
    #
    # @see Map
    class Room < Map
    end
  end
end
