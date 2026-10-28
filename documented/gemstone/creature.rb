# frozen_string_literal: true

require 'singleton'
require 'ostruct'
require_relative '../common/creature/creature_base'
require_relative '../common/creature/creature_facade'

module Lich
  module Gemstone
    # Static creature template data (ID-less reference information)
    class CreatureTemplate
      @@templates = {}
      @@loaded = false

      attr_reader :name, :url, :picture, :level, :family, :type,
                  :undead, :boss, :boss_type, :otherclass, :areas, :bcs, :max_hp,
                  :speed, :height, :size, :attack_attributes,
                  :defense_attributes, :treasure, :messaging,
                  :special_other, :abilities, :alchemy, :equipment

      # Adjectives applied by boons that are stripped from creature names for
      # template lookup. The regex built from this list removes these prefixes
      # so a "deft orc" and a bare "orc" both find the same template.
      #
      # @see .fix_template_name
      # @see BOON_REGEX
      BOON_ADJECTIVES = %w[
        adroit afflicted apt barbed belligerent blurry canny combative dazzling deft diseased drab
        dreary ethereal flashy flexile flickering flinty frenzied ghastly ghostly gleaming glittering
        glorious glowing grotesque hardy illustrious indistinct keen lanky luminous lustrous muculent
        nebulous oozing pestilent radiant raging ready resolute robust rune-covered shadowy shielded
        shifting shimmering shining sickly green sinuous slimy sparkling spindly spiny stalwart steadfast stout
        tattoed tattooed tenebrous tough twinkling unflinching unyielding wavering wispy
      ]

      def initialize(data)
        @name = data[:name]
        @url = data[:url]
        @picture = data[:picture]
        @level = data[:level]&.to_i
        @family = data[:family]
        @type = data[:type]
        @undead = data[:undead]
        # Tri-state (true/false/nil) - nil means uncatalogued/unknown, not false.
        @blood = data[:blood]
        @bones = data[:bones]
        @limbs = data[:limbs]
        @witherable = data[:witherable]
        @sympathy = data[:sympathy]
        @muggable = data[:muggable]
        @sleepable = data[:sleepable]
        @boss = data[:boss]
        # nil | "pack" | "miniboss" | "boss" - bestiary classification
        # ("boss" = the once-per-30-days uniques). Zone-dependent for a
        # few creatures; the template carries the highest tier.
        @boss_type = data[:boss_type]
        @otherclass = data[:otherclass] || []
        @areas = data[:areas] || []
        @bcs = data[:bcs]
        @max_hp = data[:max_hp]&.to_i || data[:hitpoints]&.to_i
        @speed = data[:speed]
        @height = data[:height].to_i
        @size = data[:size]

        atk = data[:attack_attributes] || {}
        @attack_attributes = OpenStruct.new(
          physical_attacks: atk[:physical_attacks] || [],
          bolt_spells: atk[:bolt_spells] || [],
          warding_spells: normalize_spells(atk[:warding_spells]),
          offensive_spells: normalize_spells(atk[:offensive_spells]),
          maneuvers: atk[:maneuvers] || [],
          special_abilities: (atk[:special_abilities] || []).map { |s| SpecialAbility.new(s) }
        )

        @defense_attributes = DefenseAttributes.new(data[:defense_attributes] || {})
        @treasure = Treasure.new(data[:treasure] || {})
        @messaging = Messaging.new(data[:messaging] || {})
        @special_other = data[:special_other]
        @abilities = data[:abilities] || []
        @alchemy = data[:alchemy] || []
        # Items seen on the creature via LOOK, as plain strings.
        @equipment = data[:equipment] || []
      end

      # Load all templates from files
      # dir defaults to the real templates directory; overridable so tests
      # can load an isolated fixture directory instead.
      def self.load_all(dir = File.join(File.dirname(__FILE__), 'creatures'))
        return if @@loaded
        return unless File.directory?(dir)

        template_count = 0
        Dir[File.join(dir, '*.rb')].each do |path|
          next if File.basename(path) == '_creature_template.rb'

          # Filename-derived name, used only as a fallback for files that
          # don't set their own :name - the file's own value takes priority
          # so a name with characters the filename can't represent (a
          # hyphen, an apostrophe) still round-trips correctly. Both the
          # display name and the lookup key come from the same source now;
          # previously both were overwritten from the filename regardless of
          # what the file itself said, silently breaking lookup for any
          # creature whose real name a slugified filename can't represent
          # exactly (e.g. "shield-maiden" -> "shield_maiden" -> "shield maiden").
          fallback_name = File.basename(path, '.rb').tr('_', ' ')

          begin
            # Safer loading with validation
            file_content = File.read(path)
            data = load_template_data(file_content, path)
            next unless data.is_a?(Hash)

            data[:name] = fallback_name if data[:name].to_s.strip.empty?
            normalized_name = fix_template_name(data[:name])
            if @@templates.key?(normalized_name) && $creature_debug
              respond "--- warning: '#{fallback_name}' collides with an already-loaded template on lookup key '#{normalized_name}' - one will silently overwrite the other"
            end
            template = new(data)
            @@templates[normalized_name] = template
            template_count += 1
          rescue StandardError, ScriptError => e
            # ScriptError (SyntaxError's parent) isn't a StandardError, so a
            # single template file with malformed Ruby would otherwise abort
            # load_all entirely instead of just being skipped.
            respond "--- error loading template #{fallback_name}: #{e.message}" if $creature_debug
          end
        end

        @@loaded = true
        respond "--- loaded #{template_count} creature templates" if $creature_debug
      end

      # Clean creature name by removing boon adjectives
      # Optimized to use single compiled regex instead of 50+ sequential matches
      BOON_REGEX = /^(#{BOON_ADJECTIVES.join('|')})\s+/i.freeze

      # Normalizes a creature name for template lookup by lowercasing and
      # stripping boon adjectives.
      #
      # Creature names from the game feed include randomly applied adjectives
      # ("deft orc", "ethereal wraith"). This method removes them so the resulting
      # key matches the stored template name regardless of boons. Uses a single
      # compiled regex for efficiency instead of 50+ sequential checks.
      #
      # @param template_name [String] the creature name to normalize
      # @return [String] lowercase name with leading boon adjectives removed and whitespace stripped
      # @example
      #   fix_template_name("deft orc") #=> "orc"
      # @example
      #   fix_template_name("Luminous Wraith") #=> "wraith"
      # @see BOON_REGEX
      def self.fix_template_name(template_name)
        name = template_name.dup.downcase
        name.sub!(BOON_REGEX, '')
        name.strip
      end

      # Safer template loading with validation
      def self.load_template_data(file_content, path)
        # Use binding.eval for slightly better isolation
        data = binding.eval(file_content, path, 1)

        # Validate it's a hash
        unless data.is_a?(Hash)
          raise "Template must return a Hash, got #{data.class}"
        end

        data
      end
      private_class_method :load_template_data

      # Lookup template by name
      def self.[](name)
        load_all unless @@loaded
        return nil unless name

        # Try exact match first
        template = @@templates[name.downcase]
        return template if template

        # Try with boon adjectives removed
        normalized_name = fix_template_name(name)
        @@templates[normalized_name]
      end

      # Get all loaded templates
      def self.all
        load_all unless @@loaded
        @@templates.values.uniq
      end

      # All game uids the creature is found at, expanded from the stored
      # ranges (memoized - ranges stay compact on disk).
      def uids
        @uids ||= @areas.flat_map { |a| Array(a[:uids]).flat_map(&:to_a) }.uniq.sort
      end

      # Whether the creature is found at the given game room uid. Checks
      # the ranges directly, so no expansion cost.
      def found_at_uid?(uid)
        @areas.any? { |a| Array(a[:uids]).any? { |r| r.cover?(uid) } }
      end

      # Templates for the creatures found at the given game room uid.
      def self.at_uid(uid)
        all.select { |t| t.found_at_uid?(uid) }
      end

      # ---- consumer views (need the Lich mapdb loaded) ----------------
      # Everything below converts uid -> Lich room id at call time via
      # Map.ids_from_uid, so stored data survives mapdb renumbering. Gaps
      # in the game's uid numbering never matter here: each uid converts
      # individually, and uids the mapdb doesn't know yet simply drop out
      # until someone maps those rooms.

      # Every Lich room id the creature is found in, across all areas -
      # ranges combined, deduped, sorted.
      def rooms
        @rooms ||= uids.flat_map { |u| Lich::Common::Map.ids_from_uid(u) }.uniq.sort
      end

      # {area name => [Lich room ids]} - the per-area display view
      # (eBestiary and friends).
      def rooms_by_area
        @rooms_by_area ||= @areas.to_h do |a|
          ids = Array(a[:uids]).flat_map { |r| r.flat_map { |u| Lich::Common::Map.ids_from_uid(u) } }
          [a[:name], ids.uniq.sort]
        end
      end

      # Rooms bordering the creature's rooms: every room an exit of the
      # creature's rooms leads to that is not one of them (bigshot's
      # perimeter list). The walk is Map.boundary_rooms_for, which works
      # over any set of rooms; the result is memoized here.
      def boundary_rooms
        @boundary_rooms ||= Lich::Common::Map.boundary_rooms_for(rooms)
      end

      # Returns whether the bestiary template says the creature has blood.
      #
      # @return [Boolean, nil] true or false when catalogued; nil when unknown.
      def has_blood?
        @blood
      end

      # Returns whether the bestiary template says the creature has bones.
      #
      # @return [Boolean, nil] true or false when catalogued; nil when unknown.
      def has_bones?
        @bones
      end

      # Returns whether Limb Disruption (708) has limbs to target on this
      # creature ("The X has no limbs left!" on a fresh target = false).
      #
      # @return [Boolean, nil] true or false when catalogued; nil when unknown.
      def has_limbs?
        @limbs
      end

      # Returns whether Wither (1115) has a body to attack on this
      # creature. Not about limbs - the spell strikes all thirteen
      # locations, chest and abdomen most often - and not about
      # corporeality either: it works on non-corporeal undead (wraiths,
      # spectres, lost souls) and fails on the golem and elemental
      # families.
      #
      # @return [Boolean, nil] true or false when catalogued; nil when unknown.
      def witherable?
        @witherable
      end

      # Returns whether Sympathy (1120) can affect this creature.
      #
      # @return [Boolean, nil] true or false when catalogued; nil when unknown.
      def sympathy?
        @sympathy
      end

      # Returns whether the bestiary template says the creature can be mugged.
      #
      # @return [Boolean, nil] true or false when catalogued; nil when unknown.
      def muggable?
        @muggable
      end

      # Returns whether the creature can be put to sleep. False comes from
      # the game's own refusal ("does not seem to be affected").
      #
      # @return [Boolean, nil] true or false when catalogued; nil when unknown.
      def sleepable?
        @sleepable
      end

      private

      def normalize_spells(spells)
        (spells || []).map do |s|
          {
            name: s[:name].to_s.strip,
            cs: parse_td(s[:cs])
          }
        end
      end

      def parse_td(val)
        return nil if val.nil?
        return val if val.is_a?(Range)

        # Parse range strings without eval (safer)
        if val.is_a?(String) && val.match?(/\A(\d+)\.\.(\d+)\z/)
          start_val, end_val = val.split('..').map(&:to_i)
          return start_val..end_val
        end

        val
      end
    end

    # Individual GemStone creature instance (runtime tracking with ID).
    #
    # Shares its id-keyed registry, room roster and `<crtrStatus>` status/flag
    # handling with DragonRealms via the {Lich::Common::CreatureBase} mixin; the
    # GemStone-specific layer here adds bestiary templates, UCS (Unarmed Combat
    # System) tracking, HP/injury modelling and the GemStone `valid_target?`
    # exclusions.
    class CreatureInstance
      include Lich::Common::CreatureBase

      attr_accessor :id, :noun, :name, :status, :injuries, :health, :damage_taken, :created_at, :fatal_crit, :status_timestamps,
                    :ucs_smote, :ucs_updated
      attr_writer :ucs_position, :ucs_tierup

      # Valid body part names for injury tracking and amputation.
      #
      # Used to validate arguments to #add_injury and #amputate! so only
      # recognized anatomy is recorded. Names match GemStone's anatomy model
      # (head, chest, abdomen, back, limbs, and paired eyes/ears).
      #
      # @see #add_injury
      # @see #amputate?
      BODY_PARTS = %w[abdomen back chest head leftArm leftEye leftFoot leftHand leftLeg neck nerves rightArm rightEye rightFoot rightHand rightLeg]

      UCS_TTL = 120        # UCS data expires after 2 minutes
      UCS_SMITE_TTL = 15   # Smite effect expires after 15 seconds

      # Seconds per stun round. Critical tables express stun in *rounds*
      # (a rank-5 crit's `stunned: 5` means five rounds), while their
      # `roundtime` field is already in seconds - the two units live side by
      # side in the same CritRanks hash, so never mix them.
      STUN_ROUND_SECONDS = 5

      # Initializes a CreatureInstance from server data.
      #
      # Sets up runtime tracking for a single creature: a unique id, display name
      # and noun, empty injury/status maps, zero damage, and nil placeholders for
      # health, UCS (Unarmed Combat System) state, and stun estimates. All mutable
      # collections are instance copies, not shared.
      #
      # @param id [Integer, String] the server creature id (converted to Integer)
      # @param noun [String, nil] the creature noun from the game
      # @param name [String] the creature name from the game
      # @return [void]
      def initialize(id, noun, name)
        @id = id.to_i
        @noun = noun
        @name = name
        initialize_status_tracking
        @injuries = Hash.new(0)
        @health = nil
        @damage_taken = 0
        @created_at = Time.now
        @fatal_crit = false
        @ucs_position = nil
        @ucs_tierup = nil
        @ucs_smote = nil
        @ucs_updated = nil
        @amputated = []
        @stun_rounds = nil
        @stun_estimated_until = nil
      end

      # Get the template for this creature. Sentinel-cached so a creature with
      # no template doesn't redo the name lookup (downcase + boon regex) on
      # every call the way `||=` would.
      def template
        return @template if defined?(@template_looked_up)

        @template_looked_up = true
        @template = CreatureTemplate[@name]
      end

      # Check if creature has template data
      def has_template?
        !template.nil?
      end

      # UCS (Unarmed Combat System) tracking methods

      # Convert position string/number to tier (1-3)
      def position_to_tier(pos)
        case pos
        when "decent", 1, "1" then 1
        when "good", 2, "2" then 2
        when "excellent", 3, "3" then 3
        else nil
        end
      end

      # Set UCS position tier
      def set_ucs_position(position)
        new_tier = position_to_tier(position)
        return unless new_tier

        # Clear tierup if tier changed
        @ucs_tierup = nil if new_tier != @ucs_position

        @ucs_position = new_tier
        @ucs_updated = Time.now
        debug_log("UCS: position=#{new_tier}")
      end

      # Set UCS tierup vulnerability
      def set_ucs_tierup(attack_type)
        @ucs_tierup = attack_type
        @ucs_updated = Time.now
        debug_log("UCS: tierup=#{attack_type}")
      end

      # Mark creature as smote (crimson mist applied)
      def smite!
        @ucs_smote = Time.now
        @ucs_updated = Time.now
        debug_log("UCS: smote!")
      end

      # Check if creature is currently smote
      def smote?
        return false unless @ucs_smote

        # Check if smite effect has expired
        if Time.now - @ucs_smote > UCS_SMITE_TTL
          @ucs_smote = nil
          return false
        end

        true
      end

      # Clear smote status
      def clear_smote
        @ucs_smote = nil
        @ucs_updated = Time.now
        debug_log("UCS: smote cleared")
      end

      # Check if UCS data has expired
      def ucs_expired?
        return true unless @ucs_updated
        (Time.now - @ucs_updated) > UCS_TTL
      end

      # Get UCS position tier (1-3, or nil if expired)
      def ucs_position
        return nil if ucs_expired?
        @ucs_position
      end

      # Get UCS tierup vulnerability (or nil if expired)
      def ucs_tierup
        return nil if ucs_expired?
        @ucs_tierup
      end

      # Records a crit-table stun estimate, in rounds.
      #
      # This is deliberately *not* stored as a timed entry in @status. The
      # authoritative stun boolean is owned by <crtrStatus> and the combat
      # message parser (see STATUS_DURATIONS, where 'stunned' is nil on
      # purpose); expiring it on a table-derived timer would clear stun while
      # a resisted-or-stacked creature is still stunned, and report
      # `muckled?` false when acting is still unsafe. So the estimate lives
      # alongside the boolean and is advisory only.
      #
      # Stun does not cleanly stack, so a new estimate extends but never
      # shortens an existing one.
      #
      # @param rounds [Integer] stun rounds from the critical table.
      # @param at [Time] when the game applied the crit (prompt time, not
      #   parse time - the async parser can lag the server).
      # @return [void]
      def add_stun_estimate(rounds, at: Time.now)
        rounds = rounds.to_i
        return if rounds <= 0

        expires_at = at + (rounds * STUN_ROUND_SECONDS)
        return if @stun_estimated_until && @stun_estimated_until >= expires_at

        @stun_rounds = rounds
        @stun_estimated_until = expires_at
        debug_log("+stun estimate: #{rounds} round#{'s' unless rounds == 1} (~#{rounds * STUN_ROUND_SECONDS}s)")
      end

      # Estimated stun rounds from the last crit, or nil when the estimate has
      # lapsed or stun is no longer active.
      #
      # @return [Integer, nil]
      def stun_rounds
        return nil unless stun_estimate_active?
        @stun_rounds
      end

      # Estimated seconds of stun remaining.
      #
      # Advisory: derived from the critical table, not observed. Returns 0.0
      # when no estimate is active. Callers deciding whether it is safe to act
      # should gate on `muckled?`/`has_status?('stunned')` and use this only to
      # size the window.
      #
      # @return [Float]
      def stunned_for
        return 0.0 unless stun_estimate_active?
        [@stun_estimated_until - Time.now, 0.0].max.round(1)
      end

      # Clears any crit-derived stun estimate (creature shook off the stun).
      #
      # @return [void]
      def clear_stun_estimate
        @stun_rounds = nil
        @stun_estimated_until = nil
      end

      # Marks a body part as amputated.
      #
      # Distinct from @injuries, which accumulates rank: an amputated limb is
      # gone rather than wounded, cannot be wounded further, and stays gone.
      #
      # @param body_part [String, Symbol] one of BODY_PARTS.
      # @return [void]
      def amputate!(body_part)
        unless BODY_PARTS.include?(body_part.to_s)
          raise ArgumentError, "Invalid body part: #{body_part}"
        end
        return if @amputated.include?(body_part.to_s)

        @amputated << body_part.to_s
        debug_log("+amputated: #{body_part}")
      end

      # @return [Boolean] whether a body part has been amputated.
      def amputated?(body_part)
        @amputated.include?(body_part.to_s)
      end

      # @return [Array<String>] every amputated body part.
      def amputated_parts
        @amputated.dup
      end

      # Add injury to body part
      def add_injury(body_part, amount = 1)
        unless BODY_PARTS.include?(body_part.to_s)
          raise ArgumentError, "Invalid body part: #{body_part}"
        end
        # An amputated limb cannot accrue further wound rank - it is gone.
        return if amputated?(body_part)

        @injuries[body_part.to_sym] += amount
      end

      # Check if injured at location
      def injured?(location, threshold = 1)
        @injuries[location.to_sym] >= threshold
      end

      # Mark creature as killed by fatal critical hit
      def mark_fatal_crit!
        @fatal_crit = true
      end

      # Check if creature died from fatal crit
      def fatal_crit?
        @fatal_crit
      end

      # Get all injured locations
      def injured_locations(threshold = 1)
        @injuries.select { |_, value| value >= threshold }.keys
      end

      # Add damage to creature
      def add_damage(amount)
        @damage_taken += amount.to_i
      end

      # Get maximum HP, preferring a usable value from the latest crtrStatus
      # snapshot and otherwise using the established inferred fallback.
      def max_hp
        return @max_health if authoritative_health?

        inferred_max_hp
      end

      # Calculate current HP, preserving overkill as a negative value from
      # either the server or the inferred damage model.
      def current_hp
        return @health if authoritative_health?

        inferred_max_hp - @damage_taken
      end

      # Calculate HP percentage, preserving negative overkill.
      def hp_percent
        maximum = max_hp
        return nil unless maximum && maximum > 0

        ((current_hp.to_f / maximum) * 100).round(1)
      end

      # Check if creature is below HP threshold
      def low_hp?(threshold = 25)
        return false unless hp_percent
        hp_percent <= threshold
      end

      # Statuses that satisfy Coup de Grace's "incapacitated in some way"
      # requirement, unlocking the (rank * 10)% threshold instead of
      # (rank * 5)%. Positional states (prone/kneeling/sitting) are
      # deliberately excluded.
      COUP_INCAP_STATUSES = %w[stunned immobilized webbed sleeping bound].freeze

      # Check if creature currently qualifies for Coup de Grace at the given
      # trained rank: at or below (rank * 10)% of max HP when incapacitated,
      # (rank * 5)% otherwise, hard-capped at 200 HP either way. The cap is
      # what binds on large creatures, so this compares raw HP, not percent.
      def coup_eligible?(rank)
        return false unless rank.to_i > 0
        return false unless current_hp && max_hp && max_hp > 0
        incap = COUP_INCAP_STATUSES.any? { |s| has_status?(s) }
        threshold = [(max_hp * rank.to_i * (incap ? 10 : 5)) / 100.0, 200].min
        current_hp <= threshold
      end

      # Check if creature is dead (zero or negative HP)
      def dead?
        current_hp <= 0
      end

      # Checks whether this creature should be considered attackable.
      #
      # Uses the same decoy and appendage exclusions as `GameObj.targets`, but
      # uses structured death data from <crtrStatus> and HP tracking instead of
      # regex-matching a status string.
      #
      # @return [Boolean]
      def valid_target?
        return false if crtr_flag?(:dead) || dead?
        return false if @name =~ /^animated\b/i && @name !~ /^animated slush/i
        return false if @noun =~ /^(?:arm|appendage|claw|limb|pincer|tentacle)s?$|^(?:palpus|palpi)$/i &&
                        @name !~ /(?:amaranthine|ghostly|grizzled|ancient) kraken tentacle/i

        true
      end

      # Creature-side analog of Lich::Gemstone::Status.muckled? (the player's
      # own "can't act right now" check). Deliberately narrower than
      # everything tracked in @status: excludes penalty-only conditions
      # (disoriented), positional ones (prone/kneeling/sitting/flying/
      # hovering), and calm (the player version excludes that too, tracking
      # it separately) - this is only the statuses that actually prevent
      # acting, not ones that merely penalize or reposition.
      def muckled?
        has_status?('webbed') || crtr_flag?(:dead) || dead? || has_status?('stunned') ||
          has_status?('sleeping') || has_status?('immobilized') || has_status?('rooted')
      end

      # Reset damage (creature healed or respawned)
      def reset_damage
        @damage_taken = 0
      end

      # Essential data for this instance
      def essential_data
        {
          id: @id,
          noun: @noun,
          name: @name,
          status: @status,
          injuries: @injuries,
          health: @health,
          max_health: max_health,
          damage_taken: @damage_taken,
          max_hp: max_hp,
          current_hp: current_hp,
          hp_percent: hp_percent,
          has_template: has_template?,
          created_at: @created_at,
          ucs_position: ucs_position,
          ucs_tierup: ucs_tierup,
          ucs_smote: smote?,
          amputated: amputated_parts,
          stun_rounds: stun_rounds,
          stunned_for: stunned_for
        }
      end

      private

      # A positive maximum distinguishes combat health from legitimate 0/0
      # values emitted for noncombat entities. Both values must be present so a
      # malformed or partial snapshot falls back cleanly.
      def authoritative_health?
        @health.is_a?(Integer) && @max_health.is_a?(Integer) && @max_health.positive?
      end

      # Original template/damage-model maximum. This remains live underneath
      # the server-backed API so an omitted, invalid, or 0/0 snapshot can fall
      # back without retaining stale server data.
      def inferred_max_hp
        # Try template first
        hp = template&.max_hp
        return hp if hp && hp > 0

        # Fall back to combat tracker setting if available
        begin
          if defined?(Lich::Gemstone::Combat::Tracker) &&
             Lich::Gemstone::Combat::Tracker.respond_to?(:fallback_hp)
            fallback = Lich::Gemstone::Combat::Tracker.fallback_hp
            return fallback if fallback && fallback > 0
          end
        rescue
          # Ignore errors accessing tracker
        end

        # Last resort: hardcoded fallback
        400
      end

      # Whether a crit-derived stun estimate is still meaningful.
      #
      # Gated on the authoritative status as well as the clock: once the feed
      # or a removal message says the creature is no longer stunned, the
      # estimate is stale regardless of remaining time.
      def stun_estimate_active?
        return false unless @stun_estimated_until
        return false if @stun_estimated_until <= Time.now
        has_status?('stunned')
      end
    end

    # Public Creature API for GemStone runtime creature tracking.
    #
    # A thin facade: the surface shared with `Lich::DragonRealms::Creature`
    # comes from {Lich::Common::CreatureFacade}, delegating to {CreatureInstance},
    # which mixes in the shared id-keyed registry, room roster and
    # `targets`/`in_room` query methods from {Lich::Common::CreatureBase}.
    # GemStone adds recycled-id handling on register and template counts in
    # stats.
    module Creature
      extend Lich::Common::CreatureFacade

      # @return [Class] the registry class the shared facade delegates to.
      def self.instance_class = CreatureInstance
      private_class_method :instance_class

      # Register a new creature
      #
      # A known id arriving under a different name is a recycled id: start a
      # fresh instance so the previous creature's reported or inferred flags,
      # statuses and damage don't carry over to it. Skipped when
      # auto-registration is off, since no replacement would be created.
      #
      # @param name [String, nil] creature name from the room-objs link.
      # @param id [Integer, String] server creature id.
      # @param noun [String, nil] creature noun.
      # @return [CreatureInstance, nil] the registered instance, or nil when
      #   auto-registration is disabled or the registry is full.
      def self.register(name, id, noun = nil)
        existing = CreatureInstance[id]
        if existing && name && existing.name && existing.name != name && CreatureInstance.auto_register?
          CreatureInstance.forget(id)
        end
        super
      end

      # Get registry stats (the shared stats plus the bestiary template count).
      def self.stats
        { instances: CreatureInstance.size, templates: CreatureTemplate.all.size }.merge(super)
      end
    end

    # Keep the supporting classes from the original system
    class SpecialAbility
      attr_accessor :name, :note

      def initialize(data)
        @name = data[:name]
        @note = data[:note]
      end
    end

    # Treasure drop configuration for a creature template.
    #
    # Wraps creature-specific drop data: coin/gem drops, container boxes,
    # harvestable skin, magic item drops, and weapon/armor transmog availability.
    # Exposes boolean queries for script convenience.
    class Treasure
      # Initializes Treasure with drop configuration.
      #
      # Stores merged data with defaults: false for coins/gems/boxes/blunt_required,
      # nil for harvestable and magic attributes, empty for transmogs/armaments.
      #
      # @param data [Hash] creature treasure data (optional)
      # @return [void]
      def initialize(data = {})
        @data = {
          coins: false,
          gems: false,
          boxes: false,
          skin: nil,
          magic_items: nil,
          other: nil,
          armaments: nil,
          transmogs: nil,
          blunt_required: false
        }.merge(data)
      end

      # Returns whether the creature can drop coins.
      #
      # @return [Boolean]
      def has_coins? = !!@data[:coins]
      # Returns whether the creature can drop gems.
      #
      # @return [Boolean]
      def has_gems? = !!@data[:gems]
      # Returns whether the creature can drop containers.
      #
      # @return [Boolean]
      def has_boxes? = !!@data[:boxes]
      # Returns whether the creature has harvestable skin.
      #
      # @return [Boolean]
      def has_skin? = !!@data[:skin]
      # Returns whether the creature can drop weapons or armor.
      #
      # @return [Boolean]
      def has_armaments? = !!(@data[:armaments] && !Array(@data[:armaments]).empty?)
      # Returns whether the creature has weapon/armor transmog drops.
      #
      # @return [Boolean]
      def has_transmogs? = !!(@data[:transmogs] && !Array(@data[:transmogs]).empty?)
      # Returns whether the creature requires blunt damage to harvest.
      #
      # @return [Boolean]
      def blunt_required? = !!@data[:blunt_required]

      # Returns the underlying treasure data hash.
      #
      # @return [Hash]
      def to_h = @data
    end

    # Combat and encounter messaging for a creature template.
    #
    # Stores game lines for creature actions (attacks, spells, flight, death, etc.),
    # with support for templated text and placeholders. Creature messages can be
    # rendered with specific values (e.g., different pronouns or directions) or
    # matched against game output to recognize actions.
    class Messaging
      attr_accessor :description, :arrival, :flee, :death,
                    :decay, :search, :spell_prep, :frenzy,
                    :sympathy, :bite, :claw, :attack,
                    :attacks, :enrage, :mstrike, :stand,
                    :stun_break, :ambient, :triggers, :info

      # Every form a placeholder can take in a real game line. The lists
      # are alternatives in the generated regex, so a form that is missing
      # here makes an otherwise-correct message unmatchable - "its" and
      # "their" (possessives) and "out" (a flee direction) were absent.
      PLACEHOLDER_MAP = {
        Pronoun: %w[He She It His Her Its Their Him Them Himself Herself Itself Themselves],
        pronoun: %w[he she it his her its their him them himself herself itself themselves],
        Reflexive: %w[Himself Herself Itself Themselves],
        reflexive: %w[himself herself itself themselves],
        direction: %w[north south east west up down out northeast northwest southeast southwest],
        weapon: %w[RAW:.+?]
      }

      def initialize(data)
        data.each do |key, value|
          instance_variable_set("@#{key}", normalize(value))
        end
      end

      # Converts raw message data into displayable and matchable objects.
      #
      # Recursively processes hashes (transforms values), arrays (maps over elements),
      # and strings. Any string containing {placeholders} is wrapped in a
      # PlaceholderTemplate with extracted placeholder names and their allowed values
      # from PLACEHOLDER_MAP. Strings without placeholders and other types pass through
      # unchanged.
      #
      # @param value [Hash, Array, String, Object] message data to normalize
      # @return [Hash, Array, PlaceholderTemplate, Object] normalized value
      # @api private
      def normalize(value)
        if value.is_a?(Hash)
          # attacks: and triggers: are keyed hashes of message lists. Without
          # this branch their strings stayed raw, so a {pronoun} in an attack
          # or trigger line never became a matchable PlaceholderTemplate the
          # way the flat fields' did.
          value.transform_values { |v| normalize(v) }
        elsif value.is_a?(Array)
          value.map { |v| normalize(v) }
        elsif value.is_a?(String) && value.match?(/\{[a-zA-Z_]+\}/)
          phs = value.scan(/\{([a-zA-Z_]+)\}/).flatten.map(&:to_sym)
          placeholders = phs.map { |ph| [ph, PLACEHOLDER_MAP[ph] || []] }.to_h
          PlaceholderTemplate.new(value, placeholders)
        else
          value
        end
      end

      # Renders a message field with optional placeholder substitutions.
      #
      # Looks up the named messaging field and renders any PlaceholderTemplates
      # it contains with the provided substitutions (e.g., pronouns, directions).
      # For array fields, renders each variant and joins with newlines. Falls back
      # to sampling from PLACEHOLDER_MAP if a substitution is not provided.
      #
      # @param field [Symbol, String] the messaging field name (e.g., :arrival, :death)
      # @param subs [Hash] optional placeholder values (e.g., {pronoun: 'he'})
      # @return [String] the rendered message
      # @example
      #   messaging.display(:arrival, {pronoun: 'she', direction: 'north'})
      def display(field, subs = {})
        msg = send(field)
        if msg.is_a?(Array)
          msg.map { |m| m.is_a?(PlaceholderTemplate) ? m.to_display(subs) : m }.join("\n")
        elsif msg.is_a?(PlaceholderTemplate)
          msg.to_display(subs)
        else
          msg
        end
      end

      # Returns the placeholder captures ({} for a literal hit) when +str+
      # is one of the field's messages, else nil. Arrays are the common
      # case - most creatures have several variants of a message - so a
      # match against any variant counts.
      def match(field, str)
        Array(send(field)).each do |msg|
          hit = msg.is_a?(PlaceholderTemplate) ? msg.match(str) : (msg == str ? {} : nil)
          return hit if hit
        end
        nil
      end
    end

    # Combat defense properties for a creature template.
    #
    # Wraps all defensive metrics: armor skill group (ASG), armor graduate
    # defense (AGD) against melee/ranged/bolt, per-circle threat defense (TD)
    # values, undodgeable defense factor (UDF), immunities, defensive spells,
    # and special defenses. Defense values can be parsed ranges (e.g., "10..15"
    # becomes 10..15) or direct integers.
    class DefenseAttributes
      attr_accessor :asg, :melee, :ranged, :bolt, :udf,
                    :bar_td, :cle_td, :emp_td, :pal_td,
                    :ran_td, :sor_td, :wiz_td, :mje_td, :mne_td,
                    :mjs_td, :mns_td, :mnm_td, :immunities,
                    :defensive_spells, :defensive_abilities, :special_defenses

      # Initializes DefenseAttributes from template data.
      #
      # Sets ASG directly, parses defense values (melee/ranged/bolt/udf and all
      # threat defense fields) via #parse_td to handle ranges and strings, and
      # defaults array fields (immunities, spells, abilities, special defenses)
      # to [].
      #
      # @param data [Hash] defense data with keys like :asg, :melee, :bar_td, etc.
      # @return [void]
      def initialize(data)
        @asg = data[:asg]
        @melee = parse_td(data[:melee])
        @ranged = parse_td(data[:ranged])
        @bolt = parse_td(data[:bolt])
        @udf = parse_td(data[:udf])

        %i[bar_td cle_td emp_td pal_td ran_td sor_td wiz_td mje_td mne_td mjs_td mns_td mnm_td].each do |key|
          instance_variable_set("@#{key}", parse_td(data[key]))
        end

        @immunities = data[:immunities] || []
        @defensive_spells = data[:defensive_spells] || []
        @defensive_abilities = data[:defensive_abilities] || []
        @special_defenses = data[:special_defenses] || []
      end

      private

      def parse_td(val)
        return nil if val.nil?
        return val if val.is_a?(Range)

        # Parse range strings without eval (safer)
        if val.is_a?(String) && val.match?(/\A(\d+)\.\.(\d+)\z/)
          start_val, end_val = val.split('..').map(&:to_i)
          return start_val..end_val
        end

        val
      end
    end

    # Templated message with {placeholders} for dynamic game output matching
    # and rendering.
    #
    # Stores a message template and the allowed values for each placeholder
    # (e.g., {pronoun} can be he/she/it/etc.). Supports rendering a display
    # string by substituting placeholders with specific values (or random
    # samples), and matching game output by building a regex from the template
    # and capturing placeholder values.
    class PlaceholderTemplate
      # Initializes a PlaceholderTemplate.
      #
      # Stores the template string and placeholder options (allowed values for each
      # placeholder). Initializes an empty regex cache for to_regex optimization.
      #
      # @param template [String] the message template with {placeholder} markers
      # @param placeholders [Hash] placeholder names => allowed values, e.g.
      #   {pronoun: ['he', 'she', 'it']}
      # @return [void]
      def initialize(template, placeholders = {})
        @template = template
        @placeholders = placeholders
        @regex_cache = {}
      end

      # Returns the original message template.
      #
      # @return [String]
      def template
        @template
      end

      # Returns the placeholder definitions.
      #
      # @return [Hash] placeholder names => allowed values
      def placeholders
        @placeholders
      end

      # Renders the template to a display string by substituting placeholders.
      #
      # Replaces each {placeholder} with the value from subs if provided, otherwise
      # picks a random value from the placeholder's allowed list (or empty string if
      # the list is empty). Returns the fully-rendered line.
      #
      # @param subs [Hash] placeholder substitutions, e.g. {pronoun: 'she'}
      # @return [String] the rendered message
      # @example
      #   template.to_display({pronoun: 'he'}) #=> "He stands up."
      def to_display(subs = {})
        line = @template.dup
        @placeholders.each do |key, options|
          value = subs[key] || options.sample || ""
          line.gsub!("{#{key}}", value.to_s)
        end
        line
      end

      # Builds or retrieves a cached regex that matches the template.
      #
      # Converts {placeholders} into regex alternation groups, with literals and
      # RAW: (raw regex) patterns handled specially. Results are memoized by
      # literals hash to avoid rebuilding on repeated calls with the same
      # substitutions. For templates containing arrays, builds a union of regexes
      # for each element.
      #
      # @param literals [Hash] optional placeholder values for matching, e.g.
      #   {pronoun: 'he'} (uses Messaging#PLACEHOLDER_MAP values by default)
      # @return [Regexp] regex that matches the template
      # @example
      #   template.to_regex({pronoun: 'he'}) #=> matches "He stands up."
      def to_regex(literals = {})
        # Use cache to avoid rebuilding regex on every call
        cache_key = literals.hash
        return @regex_cache[cache_key] if @regex_cache[cache_key]

        regex = if @template.is_a?(Array)
                  regexes = @template.map { |t| self.class.new(t, @placeholders).to_regex(literals) }
                  Regexp.union(*regexes)
                else
                  build_regex(literals)
                end

        @regex_cache[cache_key] = regex
      end

      # Public: Messaging#match calls this on the template it holds. It
      # sat below the `private` keyword, so every templated message
      # raised NoMethodError on match - the placeholder machinery could
      # render a line but never recognize one.
      def match(str, literals = {})
        regex = to_regex(literals)
        m = regex.match(str)
        return nil unless m

        m.names.any? ? m.named_captures.transform_keys(&:to_sym) : m.captures
      end

      private

      def build_regex(literals)
        pattern = Regexp.escape(@template)
        @placeholders.each do |key, options|
          if options == [:wildcard] || options.first&.start_with?('RAW:')
            raw = options.first.start_with?('RAW:') ? options.first[4..-1] : options.first
            pattern.gsub!(/\\\{#{key}\\\}/, raw)
          else
            regex_group = "(?<#{key}>#{(literals[key] || options).map { |opt| Regexp.escape(opt) }.join('|')})"
            pattern.gsub!(/\\\{#{key}\\\}/, regex_group)
          end
        end
        Regexp.new("#{pattern}")
      end
    end
  end
end
