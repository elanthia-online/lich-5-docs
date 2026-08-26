=begin
spell.rb: Core lich file for spell management and for spell related scripts.
=end

require 'open-uri'
require 'ox'

# Namespace for the Lich 5 scripting engine and its associated utilities.
module Lich
  # Namespace for common game-related classes and utilities shared across Lich scripts.
  module Common
    # Represents a spell from the game's spell database, loaded from effect-list.xml.
    #
    # Provides spell metadata (name, circle, type, duration, costs), active tracking,
    # casting methods, and convenience accessors for calculated values like duration formulas
    # and spell bonuses. Spells are globally indexed by number and name for fast lookup.
    #
    # @see Spell.load
    # @see Spell.[]
    class Spell
      @@list ||= Array.new
      @@loaded ||= false
      @@cast_lock ||= Array.new
      @@bonus_list ||= Array.new
      @@cost_list ||= Array.new
      @@load_mutex = Mutex.new
      @@after_stance = nil
      attr_reader :num, :name, :timestamp, :msgup, :msgdn, :circle, :active, :type, :cast_proc, :real_time, :persist_on_death, :availability, :no_incant, :last_cast
      attr_accessor :stance, :channel

      @@prepare_regex = Regexp.union(
        /^You already have a spell readied!  You must RELEASE it if you wish to prepare another!$/,
        /^Your spell(?:song)? is ready\./,
        /^You can't think clearly enough to prepare a spell!$/,
        /^You are concentrating too intently .*?to prepare a spell\.$/,
        /^You are too injured to make that dextrous of a movement/,
        /^The searing pain in your throat makes that impossible/,
        /^But you don't have any mana!\.$/,
        /^You can't make that dextrous of a move!$/,
        /^As you begin to prepare the spell the wind blows small objects at you thwarting your attempt\.$/,
        /^You do not know that spell!$/,
        /^All you manage to do is cough up some blood\.$/,
        /^The incantations of countless spells swirl through your mind as a golden light flashes before your eyes\./
      )
      @@results_regex = Regexp.union(
        /^(?:Cast|Sing) Roundtime [0-9]+ Seconds?\.$/,
        /^Cast at what\?$/,
        /^But you don't have any mana!$/,
        /^You don't have a spell prepared!$/,
        /keeps? the spell from working\./,
        /^Be at peace my child, there is no need for spells of war in here\.$/,
        /Spells of War cannot be cast/,
        /^As you focus on your magic, your vision swims with a swirling haze of crimson\.$/,
        /^Your magic fizzles ineffectually\.$/,
        /^All you manage to do is cough up some blood\.$/,
        /^And give yourself away!  Never!$/,
        /^You are unable to do that right now\.$/,
        /^You feel a sudden rush of power as you absorb [0-9]+ mana!$/,
        /^You are unable to drain it!$/,
        /leaving you casting at nothing but thin air!$/,
        /^You don't seem to be able to move to do that\.$/,
        /^Provoking a GameMaster is not such a good idea\.$/,
        /^You can't think clearly enough to prepare a spell!$/,
        /^You do not currently have a target\.$/,
        /The incantations of countless spells swirl through your mind as a golden light flashes before your eyes\./,
        /You can only evoke certain spells\./,
        /You can only channel certain spells for extra power\./,
        /That is not something you can prepare\./,
        /^\[Spell preparation time: \d seconds?\]$/,
        /^You are too injured to make that dextrous of a movement/,
        /^You can't make that dextrous of a move!$/
      )

      # Initializes a Spell from an XML element (from effect-list.xml).
      #
      # Parses spell metadata including number, name, type, duration formulas, cost formulas,
      # bonus formulas, and caster requirements from the XML node. Sets default duration to
      # 250 seconds per self-cast unless specified. Registers this spell in the global list
      # unless a spell with the same number already exists.
      #
      # @param xml_spell [Ox::Element] an XML element with attributes and child elements
      #   describing the spell (e.g., number, name, type, channel, stance) and optional
      #   children (bonus, message, cost, duration, cast-proc)
      # @return [void]
      # @api private
      def initialize(xml_spell)
        @num = xml_spell['number'].to_i
        @name = xml_spell['name']
        @type = xml_spell['type']
        @no_incant = ((xml_spell['incant'] == 'no') ? true : false)
        if xml_spell['availability'] == 'all'
          @availability = 'all'
        elsif xml_spell['availability'] == 'group'
          @availability = 'group'
        else
          @availability = 'self-cast'
        end
        @bonus = Hash.new
        xml_spell.locate('bonus').each { |e|
          bonus_type = e['type']
          next unless bonus_type # skip malformed bonus elements

          @bonus[bonus_type] = e.text
        }
        @msgup = xml_spell.locate('message').select { |e| e['type'].downcase == 'start' }.collect { |e| e.text }.join('$|^')
        @msgup = nil if @msgup.empty?
        @msgdn = xml_spell.locate('message').select { |e| e['type'].downcase == 'end' }.collect { |e| e.text }.join('$|^')
        @msgdn = nil if @msgdn.empty?
        @stance = ((xml_spell['stance'] =~ /^(yes|true)$/i) ? true : false)
        @channel = ((xml_spell['channel'] =~ /^(yes|true)$/i) ? true : false)
        @cost = Hash.new
        xml_spell.locate('cost').each { |xml_cost|
          cost_type = xml_cost['type']&.downcase
          next unless cost_type # skip malformed cost elements

          @cost[cost_type] ||= Hash.new
          # cast-type defaults to 'self' if not specified (most cost elements omit it)
          if xml_cost['cast-type']&.downcase == 'target'
            @cost[cost_type]['target'] = xml_cost.text
          else
            @cost[cost_type]['self'] = xml_cost.text
          end
        }
        @duration = Hash.new
        xml_spell.locate('duration').each { |xml_duration|
          # cast-type defaults to 'self' if not specified
          if xml_duration['cast-type']&.downcase == 'target'
            cast_type = 'target'
          else
            cast_type = 'self'
            if xml_duration['real-time'] =~ /^(yes|true)$/i
              @real_time = true
            else
              @real_time = false
            end
          end
          @duration[cast_type] = Hash.new
          @duration[cast_type][:duration] = xml_duration.text
          span = xml_duration['span']&.downcase
          @duration[cast_type][:stackable] = (span == 'stackable')
          @duration[cast_type][:refreshable] = (span == 'refreshable')
          if xml_duration['multicastable'] =~ /^(yes|true)$/i
            @duration[cast_type][:multicastable] = true
          else
            @duration[cast_type][:multicastable] = false
          end
          if xml_duration['persist-on-death'] =~ /^(yes|true)$/i
            @persist_on_death = true
          else
            @persist_on_death = false
          end
          if xml_duration['max']
            @duration[cast_type][:max_duration] = xml_duration['max'].to_f
          else
            @duration[cast_type][:max_duration] = 250.0
          end
        }
        @cast_proc = xml_spell.locate('cast-proc').first&.text
        @last_cast = Time.at(0)
        @timestamp = Time.now
        @timeleft = 0
        @active = false
        @circle = (num.to_s.length == 3 ? num.to_s[0..0] : num.to_s[0..1])
        @@list.push(self) unless @@list.find { |spell| spell.num == @num }
        # self # rubocop Lint/Void: self used in void context
      end

      # Sets the global default stance to adopt after spell casting completes.
      #
      # When set, spells cast with {#cast} will return to this stance after the spell
      # is cast (e.g., 'offensive', 'guarded', 'defensive') instead of the default
      # guarded/defensive choice.
      #
      # @param val [String, nil] the stance name to adopt post-cast, or nil to clear
      # @return [String, nil] the value assigned
      # @see Spell.after_stance
      def Spell.after_stance=(val)
        @@after_stance = val
      end

      # Returns the global default stance set for after spell casting.
      #
      # @return [String, nil] the stance name, or nil if not set
      # @see Spell.after_stance=
      def Spell.after_stance
        @@after_stance
      end

      # Loads and parses the spell database from an XML file (effect-list.xml).
      #
      # If no filename is given, looks for the file in the DATA directory. If not found,
      # attempts to download from the Elanthia-Online scripts GitHub repository. Falls back
      # to the ;repository script if GitHub download fails. Thread-safe via mutex.
      #
      # Preserves active spell tracking across reloads: spells marked active before the reload
      # are restored to their active state with their remaining duration preserved.
      #
      # Caches bonus and cost keys across all spells for method_missing dispatch.
      #
      # @param filename [String, nil] path to the spell XML file, or nil for default DATA_DIR location
      # @return [Boolean] true on successful load, false on error
      # @example
      #   Spell.load  # Loads from DATA_DIR/effect-list.xml
      # @note This method is called automatically by most Spell class methods if needed.
      def Spell.load(filename = nil)
        if filename.nil?
          filename = File.join(DATA_DIR, 'effect-list.xml')
          unless File.exist?(filename)
            begin
              File.write(filename, URI.open('https://raw.githubusercontent.com/elanthia-online/scripts/master/scripts/effect-list.xml').read)
              Lich.log('effect-list.xml missing from DATA dir. Downloaded effect-list.xml from EO\Scripts GitHub complete.')
            rescue StandardError
              respond "--- Lich: error: Spell.load: #{$!}"
              Lich.log "error: Spell.load: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
              Lich.log('Github retrieval of effect-list.xml failed, trying ;repository instead.')
              Script.run('repository', 'download effect-list.xml --game=gs')
              return false unless File.exist?(filename)
            end
          end
        end
        # script = Script.current #rubocop useless assignment to variable - script
        Script.current
        @@load_mutex.synchronize {
          return true if @loaded
          begin
            spell_times = Hash.new
            # reloading spell data should not reset spell tracking...
            unless @@list.empty?
              @@list.each { |spell| spell_times[spell.num] = spell.timeleft if spell.active? }
              @@list.clear
            end
            # skip: :skip_none preserves whitespace verbatim -- spell up/down
            # messages are stored as regexes, and Ox's default whitespace
            # collapsing would turn the double spaces after periods into single
            # spaces and stop those patterns matching the real game lines.
            # Ox.load returns an Ox::Document when the file has an XML prolog
            # (effect-list.xml does) and the bare root Ox::Element otherwise.
            parsed = Ox.load(File.read(filename), mode: :generic, skip: :skip_none)
            xml_root = parsed.is_a?(Ox::Document) ? parsed.root : parsed
            xml_root.locate('spell').each { |xml_spell| Spell.new(xml_spell) }
            @@list.each { |spell|
              if spell_times[spell.num]
                spell.timeleft = spell_times[spell.num]
                spell.active = true
              end
            }
            @@bonus_list = @@list.collect { |spell| spell._bonus.keys }.flatten
            # @@bonus_list = @@bonus_list # | @@bonus_list #rubocop Binary operator | has identical operands.
            @@cost_list = @@list.collect { |spell| spell._cost.keys }.flatten
            # @@cost_list = @@cost_list # | @@cost_list #rubocop Binary operator | has identical operands.
            @@loaded = true
            return true
          rescue
            respond "--- Lich: error: Spell.load: #{$!}"
            Lich.log "error: Spell.load: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
            @@loaded = false
            return false
          end
        }
      end

      # Looks up a spell by number, numeric ID, or name.
      #
      # If val is already a Spell object, returns it directly. If it's an integer or
      # numeric string, finds the spell by number. Otherwise, escapes the value as a
      # regex pattern and searches by name (exact match first, then prefix match, then
      # a fuzzy match against up/down messages).
      #
      # Automatically loads spell data if not yet loaded.
      #
      # @param val [Spell, Integer, String] a spell object, spell number, or spell name
      # @return [Spell, nil] the matching spell, or nil if not found
      # @example
      #   Spell[505]                    #=> Spell for number 505
      # @example
      #   Spell["Minor Heal"]           #=> spell by name
      # @example
      #   s = Spell[505]
      #   Spell[s]                      #=> s (passthrough)
      # @see Spell.load
      def Spell.[](val)
        Spell.load unless @@loaded
        if val.is_a?(Spell)
          val
        elsif (val.is_a?(Integer)) or (val.is_a?(String) and val =~ /^[0-9]+$/)
          @@list.find { |spell| spell.num == val.to_i }
        else
          val = Regexp.escape(val)
          (@@list.find { |s| s.name =~ /^#{val}$/i } || @@list.find { |s| s.name =~ /^#{val}/i } || @@list.find { |s| s.msgup =~ /#{val}/i or s.msgdn =~ /#{val}/i })
        end
      end

      # Returns an array of all currently active spells.
      #
      # A spell is active if its {#active?} predicate returns true (remaining duration > 0).
      # The returned array is a fresh copy; modifications do not affect the spell list.
      #
      # Automatically loads spell data if not yet loaded.
      #
      # @return [Array<Spell>] all spells with remaining duration > 0
      # @example
      #   Spell.active.map(&:name)  #=> ["Minor Heal", "Strength"]
      def Spell.active
        Spell.load unless @@loaded
        active = Array.new
        @@list.each { |spell| active.push(spell) if spell.active? }
        active
      end

      # Tests whether a given spell is currently active.
      #
      # @param val [Spell, Integer, String] a spell object, number, or name
      # @return [Boolean] true if the spell's remaining duration > 0 and it is marked active
      # @example
      #   Spell.active?(505)  #=> true
      def Spell.active?(val)
        Spell.load unless @@loaded
        Spell[val].active?
      end

      # Returns the global list of all known spells.
      #
      # Automatically loads spell data if not yet loaded.
      #
      # @return [Array<Spell>] all spells loaded from effect-list.xml
      # @example
      #   Spell.list.count  #=> 1700+
      def Spell.list
        Spell.load unless @@loaded
        @@list
      end

      # Returns all unique spell "up" (cast start) messages from the spell database.
      #
      # Messages are concatenated with the pattern $|^ to form a union regex.
      # Nil messages (spells with no start message) are excluded.
      #
      # Automatically loads spell data if not yet loaded.
      #
      # @return [Array<String>] all non-nil msgup values
      # @see Spell#msgup
      def Spell.upmsgs
        Spell.load unless @@loaded
        @@list.collect { |spell| spell.msgup }.compact
      end

      # Returns all unique spell "down" (cast end) messages from the spell database.
      #
      # Messages are concatenated with the pattern $|^ to form a union regex.
      # Nil messages (spells with no end message) are excluded.
      #
      # Automatically loads spell data if not yet loaded.
      #
      # @return [Array<String>] all non-nil msgdn values
      # @see Spell#msgdn
      def Spell.dnmsgs
        Spell.load unless @@loaded
        @@list.collect { |spell| spell.msgdn }.compact
      end

      # Returns the duration formula for this spell, with skill references substituted.
      #
      # Retrieves the appropriate duration formula (self-cast or target-cast) and rewrites
      # skill references (e.g., Spells.minorelemental, Skills.magicitemuse) to concrete
      # expressions. The substitution depends on the :caster, :target, and :activator options.
      #
      # Activators (tap, rub, wave, raise, drink, etc.) get scaled multipliers applied to
      # skill values. Invocation methods (invoke, scroll) use arcanesymbols instead. Caster
      # and target names are case-insensitive; a caster other than self receives lookups via
      # SpellRanks['name'] instead of global Skills.
      #
      # @param options [Hash] optional parameters for skill substitution
      # @option options [String] :caster the name of the caster, defaults to player character
      # @option options [String] :target the name of the spell target
      # @option options [String] :activator the activation method (tap, rub, wave, raise, invoke, scroll, etc.)
      # @option options [String] :line reserved for internal use
      # @return [String] the duration formula with skill references replaced
      # @example
      #   spell = Spell[505]
      #   spell.time_per_formula                #=> "(Spells.minorspiritual * 2) + 20"
      # @see Spell#time_per
      def time_per_formula(options = {})
        activator_modifier = { 'tap' => 0.5, 'rub' => 1, 'wave' => 1, 'raise' => 1.33, 'drink' => 0, 'bite' => 0, 'eat' => 0, 'gobble' => 0 }
        can_haz_spell_ranks = /Spells\.(?:minorelemental|majorelemental|minorspiritual|majorspiritual|wizard|sorcerer|ranger|paladin|empath|cleric|bard|minormental)/
        skills = ['Spells.minorelemental', 'Spells.majorelemental', 'Spells.minorspiritual', 'Spells.majorspiritual', 'Spells.wizard', 'Spells.sorcerer', 'Spells.ranger', 'Spells.paladin', 'Spells.empath', 'Spells.cleric', 'Spells.bard', 'Spells.minormental', 'Skills.magicitemuse', 'Skills.arcanesymbols']
        if options[:caster] and (options[:caster] !~ /^(?:self|#{XMLData.name})$/i)
          if options[:target] and (options[:target].downcase == options[:caster].downcase)
            formula = @duration['self'][:duration].to_s.dup
          else
            formula = @duration['target'][:duration].dup || @duration['self'][:duration].to_s.dup
          end
          if options[:activator] =~ /^(#{activator_modifier.keys.join('|')})$/i
            if formula =~ can_haz_spell_ranks
              skills.each { |skill_name| formula.gsub!(skill_name, "(SpellRanks['#{options[:caster]}'].magicitemuse * #{activator_modifier[options[:activator]]}).to_i") }
              formula = "(#{formula})/2.0"
            elsif formula =~ /Skills\.(?:magicitemuse|arcanesymbols)/
              skills.each { |skill_name| formula.gsub!(skill_name, "(SpellRanks['#{options[:caster]}'].magicitemuse * #{activator_modifier[options[:activator]]}).to_i") }
            end
          elsif options[:activator] =~ /^(invoke|scroll)$/i
            if formula =~ can_haz_spell_ranks
              skills.each { |skill_name| formula.gsub!(skill_name, "SpellRanks['#{options[:caster]}'].arcanesymbols.to_i") }
              formula = "(#{formula})/2.0"
            elsif formula =~ /Skills\.(?:magicitemuse|arcanesymbols)/
              skills.each { |skill_name| formula.gsub!(skill_name, "SpellRanks['#{options[:caster]}'].arcanesymbols.to_i") }
            end
          else
            skills.each { |skill_name| formula.gsub!(skill_name, "SpellRanks[#{options[:caster].to_s.inspect}].#{skill_name.sub(/^(?:Spells|Skills)\./, '')}.to_i") }
          end
        else
          if options[:target] and (options[:target] !~ /^(?:self|#{XMLData.name})$/i)
            formula = @duration['target'][:duration].dup || @duration['self'][:duration].to_s.dup
          else
            formula = @duration['self'][:duration].to_s.dup
          end
          if options[:activator] =~ /^(#{activator_modifier.keys.join('|')})$/i
            if formula =~ can_haz_spell_ranks
              skills.each { |skill_name| formula.gsub!(skill_name, "(Skills.magicitemuse * #{activator_modifier[options[:activator]]}).to_i") }
              formula = "(#{formula})/2.0"
            elsif formula =~ /Skills\.(?:magicitemuse|arcanesymbols)/
              skills.each { |skill_name| formula.gsub!(skill_name, "(Skills.magicitemuse * #{activator_modifier[options[:activator]]}).to_i") }
            end
          elsif options[:activator] =~ /^(invoke|scroll)$/i
            if formula =~ can_haz_spell_ranks
              skills.each { |skill_name| formula.gsub!(skill_name, "Skills.arcanesymbols.to_i") }
              formula = "(#{formula})/2.0"
            elsif formula =~ /Skills\.(?:magicitemuse|arcanesymbols)/
              skills.each { |skill_name| formula.gsub!(skill_name, "Skills.arcanesymbols.to_i") }
            end
          end
        end
        formula
      end

      # Evaluates the duration formula and returns the calculated spell duration in minutes.
      #
      # Computes the duration by evaluating {#time_per_formula} with the game's current
      # skill values and bonuses. For spells with spell knowledge (SK) integration, enforces
      # a 10-minute minimum duration.
      #
      # @param options [Hash] optional parameters (see {#time_per_formula})
      # @option options [String] :caster the caster's name
      # @option options [String] :target the target's name
      # @option options [String] :activator the activation method
      # @option options [String] :line reserved for internal use
      # @return [Float] the duration in minutes, with a minimum of 10.0 for known spells
      # @example
      #   spell = Spell[505]
      #   spell.time_per  #=> 15.5
      # @see Spell#time_per_formula
      def time_per(options = {})
        formula = self.time_per_formula(options)
        if options[:line]
          # line = options[:line] rubocop useless assignment to line
          options[:line]
        end
        result = proc { eval(formula) }.call.to_f
        return 10.0 if defined?(Lich::Gemstone::SK) && Lich::Gemstone::SK.known?(self) && (result.nil? || result < 10)
        return result
      end

      # Sets the remaining duration for this spell and updates the timestamp.
      #
      # Used internally to track spell duration across duration checks. Setting a new
      # value resets the base timestamp to now.
      #
      # @param val [Numeric] the remaining duration in minutes
      # @return [Numeric] the value assigned
      # @api private
      def timeleft=(val)
        @timeleft = val
        @timestamp = Time.now
      end

      # Returns the remaining duration of this spell in minutes.
      #
      # Subtracts elapsed time since the last {#timeleft=} or {#timeleft} call from the
      # tracked duration. If the spell's duration formula is a Spellsong reference, queries
      # Spellsong.timeleft directly instead. When remaining time drops to 0 or below, calls
      # {#putdown} and returns 0.0.
      #
      # Updates the timestamp on each call.
      #
      # @return [Float] remaining duration in minutes, or 0.0 if expired
      # @see Spell#minsleft
      # @see Spell#secsleft
      def timeleft
        if self.time_per_formula.to_s == 'Spellsong.timeleft'
          @timeleft = Spellsong.timeleft
        else
          @timeleft = @timeleft - ((Time.now - @timestamp) / 60.to_f)
          if @timeleft <= 0
            self.putdown
            return 0.to_f
          end
        end
        @timestamp = Time.now
        @timeleft
      end

      # Returns the remaining duration of this spell in minutes.
      #
      # Alias for {#timeleft}.
      #
      # @return [Float] remaining duration in minutes
      def minsleft
        self.timeleft
      end

      # Returns the remaining duration of this spell in seconds.
      #
      # Multiplies {#timeleft} by 60.
      #
      # @return [Float] remaining duration in seconds
      def secsleft
        self.timeleft * 60
      end

      # Sets the active status of this spell.
      #
      # @param val [Boolean] true to mark the spell as active, false otherwise
      # @return [Boolean] the value assigned
      # @api private
      def active=(val)
        @active = val
      end

      # Tests whether this spell is currently active.
      #
      # A spell is active when both the remaining duration is greater than 0 AND the
      # internal active flag is set to true (via {#putup} or {#active=}).
      #
      # @return [Boolean] true if duration > 0 and the spell is marked active
      # @see Spell#timeleft
      # @see Spell#putup
      def active?
        (self.timeleft > 0) and @active
      end

      # Tests whether this spell's duration stacks when recast before expiration.
      #
      # Duration stacking behavior depends on the spell's duration XML metadata (span="stackable")
      # and can differ for self-cast vs. target-cast variants. When a :caster option is provided,
      # uses the caster's spell data if it differs from the player. When a :target is specified
      # that differs from the caster, uses target-cast metadata; otherwise uses self-cast.
      #
      # @param options [Hash] optional parameters for determining cast type
      # @option options [String] :caster the caster's name
      # @option options [String] :target the target's name
      # @return [Boolean] true if the spell stacks with itself on recast
      # @see Spell#refreshable?
      # @see Spell#multicastable?
      def stackable?(options = {})
        if options[:caster] and (options[:caster] !~ /^(?:self|#{XMLData.name})$/i)
          if options[:target] and (options[:target].downcase == options[:caster].downcase)
            @duration['self'][:stackable]
          else
            if @duration['target'][:stackable].nil?
              @duration['self'][:stackable]
            else
              @duration['target'][:stackable]
            end
          end
        else
          if options[:target] and (options[:target] !~ /^(?:self|#{XMLData.name})$/i)
            if @duration['target'][:stackable].nil?
              @duration['self'][:stackable]
            else
              @duration['target'][:stackable]
            end
          else
            @duration['self'][:stackable]
          end
        end
      end

      # Tests whether recasting this spell before expiration refreshes its duration.
      #
      # Duration refresh behavior depends on the spell's duration XML metadata (span="refreshable")
      # and can differ for self-cast vs. target-cast variants. When a :caster option is provided,
      # uses the caster's spell data if it differs from the player. When a :target is specified
      # that differs from the caster, uses target-cast metadata; otherwise uses self-cast.
      #
      # @param options [Hash] optional parameters for determining cast type
      # @option options [String] :caster the caster's name
      # @option options [String] :target the target's name
      # @return [Boolean] true if the spell refreshes (restarts duration) on recast
      # @see Spell#stackable?
      # @see Spell#multicastable?
      def refreshable?(options = {})
        if options[:caster] and (options[:caster] !~ /^(?:self|#{XMLData.name})$/i)
          if options[:target] and (options[:target].downcase == options[:caster].downcase)
            @duration['self'][:refreshable]
          else
            if @duration['target'][:refreshable].nil?
              @duration['self'][:refreshable]
            else
              @duration['target'][:refreshable]
            end
          end
        else
          if options[:target] and (options[:target] !~ /^(?:self|#{XMLData.name})$/i)
            if @duration['target'][:refreshable].nil?
              @duration['self'][:refreshable]
            else
              @duration['target'][:refreshable]
            end
          else
            @duration['self'][:refreshable]
          end
        end
      end

      # Tests whether this spell can be multicast (cast multiple times in rapid succession).
      #
      # Duration multicast behavior depends on the spell's duration XML metadata (multicastable="yes")
      # and can differ for self-cast vs. target-cast variants. When a :caster option is provided,
      # uses the caster's spell data if it differs from the player. When a :target is specified
      # that differs from the caster, uses target-cast metadata; otherwise uses self-cast.
      #
      # @param options [Hash] optional parameters for determining cast type
      # @option options [String] :caster the caster's name
      # @option options [String] :target the target's name
      # @return [Boolean] true if the spell can be multicast
      # @see Spell#stackable?
      # @see Spell#refreshable?
      def multicastable?(options = {})
        if options[:caster] and (options[:caster] !~ /^(?:self|#{XMLData.name})$/i)
          if options[:target] and (options[:target].downcase == options[:caster].downcase)
            @duration['self'][:multicastable]
          else
            if @duration['target'][:multicastable].nil?
              @duration['self'][:multicastable]
            else
              @duration['target'][:multicastable]
            end
          end
        else
          if options[:target] and (options[:target] !~ /^(?:self|#{XMLData.name})$/i)
            if @duration['target'][:multicastable].nil?
              @duration['self'][:multicastable]
            else
              @duration['target'][:multicastable]
            end
          else
            @duration['self'][:multicastable]
          end
        end
      end

      # Tests whether the player character knows this spell.
      #
      # Checks if the spell number falls within the player's trained circle ranks for the
      # appropriate spell school (e.g., minorspiritual for circle 1, majorelemental for circle 5).
      # Circle 17 spells (1700) are available only to Wizard, Cleric, Empath, Sorcerer, or Savant.
      # Circles 96-99 (society/custom magic) are handled specially via Society status and rank.
      #
      # If Lich::Gemstone::SK (spell knowledge system) is available, uses that directly.
      #
      # @return [Boolean] true if the spell is trained and the character meets circle/level requirements
      # @example
      #   Spell[505].known?  #=> true (if trained in minorspiritual and within circle)
      # @see Spell#available?
      def known?
        return true if defined?(Lich::Gemstone::SK) && Lich::Gemstone::SK.known?(self)
        if @num.to_s.length == 3
          circle_num = @num.to_s[0..0].to_i
        elsif @num.to_s.length == 4
          circle_num = @num.to_s[0..1].to_i
        else
          return false
        end
        if circle_num == 1
          ranks = [Spells.minorspiritual, XMLData.level].min
        elsif circle_num == 2
          ranks = [Spells.majorspiritual, XMLData.level].min
        elsif circle_num == 3
          ranks = [Spells.cleric, XMLData.level].min
        elsif circle_num == 4
          ranks = [Spells.minorelemental, XMLData.level].min
        elsif circle_num == 5
          ranks = [Spells.majorelemental, XMLData.level].min
        elsif circle_num == 6
          ranks = [Spells.ranger, XMLData.level].min
        elsif circle_num == 7
          ranks = [Spells.sorcerer, XMLData.level].min
        elsif circle_num == 9
          ranks = [Spells.wizard, XMLData.level].min
        elsif circle_num == 10
          ranks = [Spells.bard, XMLData.level].min
        elsif circle_num == 11
          ranks = [Spells.empath, XMLData.level].min
        elsif circle_num == 12
          ranks = [Spells.minormental, XMLData.level].min
        elsif circle_num == 16
          ranks = [Spells.paladin, XMLData.level].min
        elsif circle_num == 17
          if (@num == 1700) and (Stats.prof =~ /^(?:Wizard|Cleric|Empath|Sorcerer|Savant)$/)
            return true
          else
            return false
          end
        elsif (circle_num == 97) and (Society.status == 'Guardians of Sunfist')
          ranks = Society.rank
        elsif (circle_num == 98) and (Society.status == 'Order of Voln')
          ranks = Society.rank
        elsif (circle_num == 99) and (Society.status == 'Council of Light')
          ranks = Society.rank
        elsif (circle_num == 96)
          return false

        #          deprecate CMan from Spell class .known?
        #          See CMan, CMan.known? and CMan.available? methods in CMan class

        else
          return false
        end
        if (@num % 100) <= ranks.to_i
          return true
        else
          return false
        end
      end

      # Tests whether this spell can be cast by a given caster on a given target.
      #
      # A spell is available if it is {#known?} by the relevant caster AND the spell's
      # availability allows casting on the target. Availability is either 'all' (group/other),
      # 'group', or 'self-cast' (self only). When a :caster other than self is provided,
      # availability is checked as 'all' for other targets. When a :target other than self
      # is provided, availability is checked as 'all'.
      #
      # @param options [Hash] optional parameters for determining availability
      # @option options [String] :caster the caster's name
      # @option options [String] :target the target's name
      # @return [Boolean] true if {#known?} and availability requirements are met
      # @example
      #   Spell[505].available?                      #=> true (if known and can self-cast)
      # @example
      #   Spell[505].available?(target: "Zeke")      #=> true (if known and 'all' availability)
      # @see Spell#known?
      def available?(options = {})
        if self.known?
          if options[:caster] and (options[:caster] !~ /^(?:self|#{XMLData.name})$/i)
            if options[:target] and (options[:target].downcase == options[:caster].downcase)
              true
            else
              @availability == 'all'
            end
          else
            if options[:target] and (options[:target] !~ /^(?:self|#{XMLData.name})$/i)
              @availability == 'all'
            else
              true
            end
          end
        else
          false
        end
      end

      # Tests whether this spell requires an incantation.
      #
      # @return [Boolean] true if the spell requires spoken incantation, false if it is a no-incant spell
      def incant?
        !@no_incant
      end

      # Sets whether this spell requires an incantation.
      #
      # @param val [Boolean] true to require incant, false to mark as no-incant
      # @return [Boolean] the value assigned
      # @api private
      def incant=(val)
        @no_incant = !val
      end

      # Returns the spell's name as a string.
      #
      # @return [String] the spell name
      def to_s
        @name.to_s
      end

      # Returns the maximum allowed duration for this spell in minutes.
      #
      # Duration maxima depend on the spell's XML metadata and can differ for self-cast vs.
      # target-cast variants. Defaults to 250 minutes per cast type if not specified in XML.
      # When a :caster option is provided, uses the caster's spell data. When a :target is
      # specified that differs from the caster, uses target-cast metadata; otherwise uses self-cast.
      #
      # @param options [Hash] optional parameters for determining cast type
      # @option options [String] :caster the caster's name
      # @option options [String] :target the target's name
      # @return [Float] the maximum duration in minutes
      # @see Spell#time_per
      def max_duration(options = {})
        if options[:caster] and (options[:caster] !~ /^(?:self|#{XMLData.name})$/i)
          if options[:target] and (options[:target].downcase == options[:caster].downcase)
            @duration['self'][:max_duration]
          else
            @duration['target'][:max_duration] || @duration['self'][:max_duration]
          end
        else
          if options[:target] and (options[:target] !~ /^(?:self|#{XMLData.name})$/i)
            @duration['target'][:max_duration] || @duration['self'][:max_duration]
          else
            @duration['self'][:max_duration]
          end
        end
      end

      # Marks this spell as active and sets its duration.
      #
      # Calculates the spell's duration using {#time_per} and applies stacking rules:
      # if {#stackable?} is true, adds the new duration to the current remaining duration;
      # otherwise replaces the duration. Clamps the result to {#max_duration}.
      # Sets the active flag to true.
      #
      # @param options [Hash] optional parameters for duration calculation (see {#time_per})
      # @option options [String] :caster the caster's name
      # @option options [String] :target the target's name
      # @return [void]
      # @see Spell#putdown
      # @see Spell#stackable?
      def putup(options = {})
        if stackable?(options)
          self.timeleft = [self.timeleft + self.time_per(options), self.max_duration(options)].min
        else
          self.timeleft = [self.time_per(options), self.max_duration(options)].min
        end
        @active = true
      end

      # Marks this spell as inactive and clears its remaining duration.
      #
      # Sets timeleft to 0 and active flag to false.
      #
      # @return [void]
      # @see Spell#putup
      def putdown
        self.timeleft = 0
        @active = false
      end

      # Returns a human-readable string of the remaining spell duration.
      #
      # @return [String] the formatted duration (e.g., "2 hours 30 minutes")
      # @see Spell#timeleft
      # @see Spell#secsleft
      def remaining
        self.timeleft.as_time
      end

      # Tests whether the player can currently cast this spell given resource constraints.
      #
      # Checks if the player has sufficient mana, spirit, and stamina to cast the spell.
      # For monks with the mental_acuity feat (circle 12 spells), uses stamina instead of
      # mana for cost calculations. Accounts for active debuffs like Overexerted. For
      # mana-costing spells with the mental_acuity feat, doubles the mana cost and checks
      # stamina instead.
      #
      # @param options [Hash] optional parameters (reserved for future use)
      # @return [Boolean] true if all required resources are available, false otherwise
      # @example
      #   Spell[505].affordable?  #=> true (if mana/spirit/stamina sufficient)
      # @see Spell#cast
      def affordable?(options = {})
        # fixme: deal with them dirty bards!
        release_options = options.dup
        release_options[:multicast] = nil
        if (self.stamina_cost(options) > 0) and (Spell[9699].active? or not Char.stamina >= self.stamina_cost(options) or Effects::Debuffs.active?("Overexerted"))
          false
        elsif (self.spirit_cost(options) > 0) and not (Char.spirit >= (self.spirit_cost(options) + 1 + [9912, 9913, 9914, 9916, 9916, 9916].delete_if { |num| !Spell[num].active? }.length))
          false
        elsif (self.mana_cost(options) > 0)
          ## convert Spell[9699].active? to Effects::Debuffs test (if Debuffs is where it shows)
          if (Feat.known?(:mental_acuity) and self.num.between?(1201, 1220)) and (Spell[9699].active? or not Char.stamina >= (self.mana_cost(options) * 2) or Effects::Debuffs.active?("Overexerted"))
            false
          elsif (!(Feat.known?(:mental_acuity) and self.num.between?(1201, 1220))) and !(Char.mana >= self.mana_cost(options))
            false
          else
            true
          end
        else
          true
        end
      end

      # Acquires the global spell casting lock, blocking until it is the first in queue.
      #
      # Used internally by {#cast} to serialize spell casting across multiple concurrent
      # scripts. The lock queue is checked periodically; paused scripts and those no longer
      # in Script.list are automatically removed. This method blocks the calling script until
      # its lock acquire completes.
      #
      # @return [void]
      # @see Spell.unlock_cast
      # @api private
      def Spell.lock_cast
        script = Script.current
        @@cast_lock.push(script)
        until (@@cast_lock.first == script) or @@cast_lock.empty?
          sleep 0.1
          Script.current # allows this loop to be paused
          @@cast_lock.delete_if { |s| s.paused or not Script.list.include?(s) }
        end
      end

      # Releases the global spell casting lock for the current script.
      #
      # Removes the current script from the lock queue, allowing the next waiting script
      # to acquire the lock and proceed with casting.
      #
      # @return [void]
      # @see Spell.lock_cast
      # @api private
      def Spell.unlock_cast
        @@cast_lock.delete(Script.current)
      end

      # Casts this spell, handling preparation, casting, and stance management.
      #
      # A comprehensive casting method that handles spell preparation (if not incant),
      # resource checks, target validation, the actual cast/incant/channel/evoke command,
      # and post-cast stance restoration. Acquires the global cast lock to serialize
      # casting across scripts.
      #
      # Returns the final cast result string (e.g., "Cast Roundtime 5 Seconds.") or a
      # status message if preparation or casting fails (e.g., "You don't have a spell prepared!").
      #
      # Supports custom cast commands (incant, cast, channel, evoke) via arg_options.
      # Handles stance enforcement: if spell.stance is true and force_stance is not false,
      # moves to offensive stance before casting and returns to Spell.after_stance (if set)
      # or guarded/defensive after casting.
      #
      # For spells with a cast_proc (custom cast logic), evaluates that proc instead of
      # generating a standard command.
      #
      # Checks spell affordability (mana, spirit, stamina) before and during preparation.
      # Automatically releases a prepared spell if a different spell is needed.
      #
      # @param target [GameObj, Integer, String, nil] the target, as object ID, object, or name
      # @param results_of_interest [Regexp, nil] a custom regex of additional successful cast outcomes
      # @param arg_options [String, nil] space-separated cast command and arguments (e.g., "cast at ground")
      # @param force_stance [Boolean, nil] true to enforce stance, false to skip, nil for default
      # @return [String] the cast result message from the game
      # @example
      #   result = Spell[505].cast("Lich")  # Cast on target
      # @example
      #   result = Spell[505].cast         # Self-cast
      # @see Spell#force_cast
      # @see Spell#force_channel
      # @see Spell.lock_cast
      def cast(target = nil, results_of_interest = nil, arg_options = nil, force_stance: nil)
        # fixme: find multicast in target and check mana for it
        check_energy = proc {
          if Feat.known?(:mental_acuity)
            unless (self.mana_cost <= 0) or Char.stamina >= (self.mana_cost * 2)
              echo 'cast: not enough stamina there, Monk!'
              sleep 0.1
              return false
            end
          else
            unless (self.mana_cost <= 0) or Char.mana >= self.mana_cost
              echo 'cast: not enough mana'
              sleep 0.1
              return false
            end
          end
          unless (self.spirit_cost <= 0) or Char.spirit >= (self.spirit_cost + 1 + [9912, 9913, 9914, 9916, 9916, 9916].delete_if { |num| !Spell[num].active? }.length)
            echo 'cast: not enough spirit'
            sleep 0.1
            return false
          end
          unless (self.stamina_cost <= 0) or Char.stamina >= self.stamina_cost
            echo 'cast: not enough stamina'
            sleep 0.1
            return false
          end
        }
        script = Script.current
        if @type.nil?
          echo "cast: spell missing type (#{@name})"
          sleep 0.1
          return false
        end
        check_energy.call
        begin
          save_want_downstream = script.want_downstream
          save_want_downstream_xml = script.want_downstream_xml
          script.want_downstream = true
          script.want_downstream_xml = false
          @@cast_lock.push(script)
          until (@@cast_lock.first == script) or @@cast_lock.empty?
            sleep 0.1
            Script.current # allows this loop to be paused
            @@cast_lock.delete_if { |s| s.paused or not Script.list.include?(s) }
          end
          check_energy.call
          if @cast_proc
            waitrt?
            waitcastrt?
            check_energy.call
            begin
              proc { eval(@cast_proc) }.call
            rescue
              echo "cast: error: #{$!}"
              respond $!.backtrace[0..2]
              return false
            end
          else
            if @channel
              cast_cmd = 'channel'
            else
              cast_cmd = 'cast'
            end
            unless (arg_options.nil? || arg_options.empty?)
              if arg_options.split(" ")[0] =~ /incant|channel|evoke|cast/
                cast_cmd = arg_options.split(" ")[0]
                arg_options = arg_options.split(" ").drop(1)
                arg_options = arg_options.join(" ") unless arg_options.empty?
              end
            end

            if (((target.nil? || target.to_s.empty?) && !(@no_incant)) && (cast_cmd == "cast" && arg_options.nil?) || cast_cmd == "incant") && cast_cmd !~ /^(?:channel|evoke)/
              cast_cmd = "incant #{@num}"
            elsif (target.nil? or target.to_s.empty?) and (@type =~ /attack/i) and not [410, 435, 525, 912, 909, 609].include?(@num)
              cast_cmd += ' target'
            elsif target.is_a?(GameObj)
              cast_cmd += " ##{target.id}"
            elsif target.is_a?(Integer)
              cast_cmd += " ##{target}"
            elsif cast_cmd !~ /^incant/
              cast_cmd += " #{target}"
            end

            unless (arg_options.nil? || arg_options.empty?)
              cast_cmd += " #{arg_options}"
            end

            cast_result = nil
            loop {
              waitrt?
              if cast_cmd =~ /^incant/
                if (checkprep != @name) and (checkprep != 'None')
                  dothistimeout 'release', 5, /^You feel the magic of your spell rush away from you\.$|^You don't have a prepared spell to release!$/
                end
              else
                unless checkprep == @name
                  unless checkprep == 'None'
                    dothistimeout 'release', 5, /^You feel the magic of your spell rush away from you\.$|^You don't have a prepared spell to release!$/
                    unless (self.mana_cost <= 0) or Char.mana >= self.mana_cost
                      echo 'cast: not enough mana'
                      sleep 0.1
                      return false
                    end
                    unless (self.spirit_cost <= 0) or Char.spirit >= (self.spirit_cost + 1 + (if checkspell(9912) then 1 else 0 end) + (if checkspell(9913) then 1 else 0 end) + (if checkspell(9914) then 1 else 0 end) + (if checkspell(9916) then 5 else 0 end))
                      echo 'cast: not enough spirit'
                      sleep 0.1
                      return false
                    end
                    unless (self.stamina_cost <= 0) or Char.stamina >= self.stamina_cost
                      echo 'cast: not enough stamina'
                      sleep 0.1
                      return false
                    end
                  end
                  loop {
                    waitrt?
                    waitcastrt?
                    prepare_result = dothistimeout "prepare #{@num}", 8, @@prepare_regex
                    if prepare_result =~ /^Your spell(?:song)? is ready\./
                      break
                    elsif prepare_result == 'You already have a spell readied!  You must RELEASE it if you wish to prepare another!'
                      dothistimeout 'release', 5, /^You feel the magic of your spell rush away from you\.$|^You don't have a prepared spell to release!$/
                      unless (self.mana_cost <= 0) or Char.mana >= self.mana_cost
                        echo 'cast: not enough mana'
                        sleep 0.1
                        return false
                      end
                    elsif prepare_result =~ /^You can't think clearly enough to prepare a spell!$|^You are concentrating too intently .*?to prepare a spell\.$|^You are too injured to make that dextrous of a movement|^The searing pain in your throat makes that impossible|^But you don't have any mana!\.$|^You can't make that dextrous of a move!$|^As you begin to prepare the spell the wind blows small objects at you thwarting your attempt\.$|^You do not know that spell!$|^All you manage to do is cough up some blood\.$|The incantations of countless spells swirl through your mind as a golden light flashes before your eyes\./
                      sleep 0.1
                      return prepare_result
                    end
                  }
                end
              end
              waitcastrt?
              if ((@stance && force_stance != false) || force_stance == true) && Char.stance != 'offensive'
                put 'stance offensive'
                # dothistimeout 'stance offensive', 5, /^You (?:are now in|move into) an? offensive stance|^You are unable to change your stance\.$/
              end
              if results_of_interest.is_a?(Regexp)
                merged_results_regex = Regexp.union(@@results_regex, results_of_interest)
              else
                merged_results_regex = @@results_regex
              end

              if Effects::Spells.active?("Armored Casting")
                merged_results_regex = Regexp.union(/^Roundtime: \d+ sec.$/, merged_results_regex)
              else
                merged_results_regex = Regexp.union(/^\[Spell Hindrance for/, merged_results_regex)
              end
              cast_result = dothistimeout cast_cmd, 5, merged_results_regex
              if cast_result == "You don't seem to be able to move to do that."
                100.times { break if clear.any? { |line| line =~ /^You regain control of your senses!$/ }; sleep 0.1 }
                cast_result = dothistimeout cast_cmd, 5, merged_results_regex
              end
              if cast_cmd =~ /^incant/i && cast_result =~ /^\[Spell preparation time: (\d) seconds?\]$/
                sleep(Regexp.last_match(1).to_i + 0.5)
                cast_result = dothistimeout cast_cmd, 5, merged_results_regex
              end
              if ((@stance && force_stance != false) || force_stance == true)
                if @@after_stance
                  if Char.stance !~ /#{@@after_stance}/
                    waitrt?
                    dothistimeout "stance #{@@after_stance}", 3, /^You (?:are now in|move into) an? \w+ stance|^You are unable to change your stance\.$/
                  end
                elsif Char.stance !~ /^guarded$|^defensive$/
                  waitrt?
                  if checkcastrt > 0
                    dothistimeout 'stance guarded', 3, /^You (?:are now in|move into) an? \w+ stance|^You are unable to change your stance\.$/
                  else
                    dothistimeout 'stance defensive', 3, /^You (?:are now in|move into) an? \w+ stance|^You are unable to change your stance\.$/
                  end
                end
              end
              if cast_result =~ /^Cast at what\?$|^Be at peace my child, there is no need for spells of war in here\.$|^Provoking a GameMaster is not such a good idea\.$/
                dothistimeout 'release', 5, /^You feel the magic of your spell rush away from you\.$|^You don't have a prepared spell to release!$/
              end
              if cast_result =~ /You can only evoke certain spells\.|You can only channel certain spells for extra power\./
                echo "cast: can't evoke/channel #{@num}"
                cast_cmd = cast_cmd.gsub(/^(?:evoke|channel)/, "cast")
                next
              end
              break unless ((@circle.to_i == 10) && (cast_result =~ /^\[Spell Hindrance for/))
            }
            cast_result
          end
        ensure
          @last_cast = Time.now
          script.want_downstream = save_want_downstream
          script.want_downstream_xml = save_want_downstream_xml
          @@cast_lock.delete(script)
        end
      end

      # Casts this spell using the standard "cast" command, bypassing incant.
      #
      # Wrapper around {#cast} that prepends "cast" to arg_options, forcing the spell
      # to use the cast command even if it would normally incant.
      #
      # @param target [GameObj, Integer, String, nil] the spell target
      # @param arg_options [String, nil] additional command arguments (appended after "cast")
      # @param results_of_interest [Regexp, nil] custom successful cast outcomes
      # @param force_stance [Boolean, nil] true to enforce stance, false to skip, nil for default
      # @return [String] the cast result message
      # @example
      #   Spell[505].force_cast("Lich")  #=> "Cast Roundtime 5 Seconds."
      # @see Spell#cast
      def force_cast(target = nil, arg_options = nil, results_of_interest = nil, force_stance: nil)
        unless arg_options.nil? || arg_options.empty?
          arg_options = "cast #{arg_options}"
        else
          arg_options = "cast"
        end
        cast(target, results_of_interest, arg_options, force_stance: force_stance)
      end

      # Casts this spell using the "channel" command, for spells that support channeling.
      #
      # Wrapper around {#cast} that prepends "channel" to arg_options, forcing the spell
      # to use the channel command. Returns an error string if the spell does not support channeling.
      #
      # @param target [GameObj, Integer, String, nil] the spell target
      # @param arg_options [String, nil] additional command arguments (appended after "channel")
      # @param results_of_interest [Regexp, nil] custom successful cast outcomes
      # @param force_stance [Boolean, nil] true to enforce stance, false to skip, nil for default
      # @return [String] the cast result message, or error if channeling not supported
      # @example
      #   Spell[505].force_channel("Lich")  #=> "Cast Roundtime 5 Seconds."
      # @see Spell#cast
      def force_channel(target = nil, arg_options = nil, results_of_interest = nil, force_stance: nil)
        unless arg_options.nil? || arg_options.empty?
          arg_options = "channel #{arg_options}"
        else
          arg_options = "channel"
        end
        cast(target, results_of_interest, arg_options, force_stance: force_stance)
      end

      # Casts this spell using the "evoke" command, for spells that support evoking.
      #
      # Wrapper around {#cast} that prepends "evoke" to arg_options, forcing the spell
      # to use the evoke command. Returns an error string if the spell does not support evoking.
      #
      # @param target [GameObj, Integer, String, nil] the spell target
      # @param arg_options [String, nil] additional command arguments (appended after "evoke")
      # @param results_of_interest [Regexp, nil] custom successful cast outcomes
      # @param force_stance [Boolean, nil] true to enforce stance, false to skip, nil for default
      # @return [String] the cast result message, or error if evoking not supported
      # @example
      #   Spell[505].force_evoke("Lich")  #=> "Cast Roundtime 5 Seconds."
      # @see Spell#cast
      def force_evoke(target = nil, arg_options = nil, results_of_interest = nil, force_stance: nil)
        unless arg_options.nil? || arg_options.empty?
          arg_options = "evoke #{arg_options}"
        else
          arg_options = "evoke"
        end
        cast(target, results_of_interest, arg_options, force_stance: force_stance)
      end

      # Casts this spell using the "incant" command (verbal incantation).
      #
      # Wrapper around {#cast} that prepends "incant" to arg_options, forcing the spell
      # to use verbal incantation. No target parameter; incanting is always self-initiated.
      #
      # @param arg_options [String, nil] additional command arguments (appended after "incant")
      # @param results_of_interest [Regexp, nil] custom successful cast outcomes
      # @param force_stance [Boolean, nil] true to enforce stance, false to skip, nil for default
      # @return [String] the cast result message
      # @example
      #   Spell[505].force_incant  #=> "Cast Roundtime 5 Seconds."
      # @see Spell#cast
      def force_incant(arg_options = nil, results_of_interest = nil, force_stance: nil)
        unless arg_options.nil? || arg_options.empty?
          arg_options = "incant #{arg_options}"
        else
          arg_options = "incant"
        end
        cast(nil, results_of_interest, arg_options, force_stance: force_stance)
      end

      # Returns a copy of the spell's bonus formulas hash.
      #
      # Bonus keys are spell attribute types (e.g., 'bolt-as', 'physical-ds', 'elemental-cs').
      # Values are formula strings evaluated at runtime. Used by method_missing for dynamic
      # bonus accessors like {#bolt_as} and {#physical_ds}.
      #
      # @return [Hash{String => String}] a copy of the bonus formulas
      # @api private
      def _bonus
        @bonus.dup
      end

      # Returns a copy of the spell's cost formulas hash.
      #
      # Cost keys are resource types (e.g., 'mana', 'spirit', 'stamina'). Values are hashes
      # mapping cast-type ('self', 'target') to formula strings. Used by method_missing for
      # dynamic cost accessors like {#mana_cost} and {#mana_cost_formula}.
      #
      # @return [Hash{String => Hash{String => String}}] a copy of the cost formulas
      # @api private
      def _cost
        @cost.dup
      end

      # Provides dynamic accessors for spell bonuses and costs based on XML data.
      #
      # Supports three categories of dynamic methods:
      #
      # 1. **Bonus accessors** (e.g., `bolt_as`, `physical_ds`):
      #    - Method name keys map to hyphens (e.g., `bolt_as` → `bolt-as`).
      #    - Without `_formula` suffix: evaluates the formula and returns integer result.
      #    - With `_formula` suffix: returns the formula string as-is.
      #    - Returns 0 if the bonus key is not found.
      #
      # 2. **Cost accessors** (e.g., `mana_cost`, `spirit_cost`):
      #    - Method name keys map to cost type with hyphens removed (e.g., `mana_cost` → `mana`).
      #    - Without `_formula` suffix: evaluates the formula with options and returns integer.
      #    - With `_formula` suffix: returns the formula string.
      #    - Handles :caster, :target, and :multicast options to select and rewrite formulas.
      #    - For mana costs, adds 5 if spell 597 (Rapid Fire Penalty) is active.
      #    - Returns 0 if the cost key is not found or formula is nil.
      #
      # 3. **Unknown methods** raise NoMethodError with the method name.
      #
      # Formula evaluation substitutes skill references (Spells.minorelemental, Skills.magicitemuse)
      # with runtime values, including SpellRanks lookups for non-self casters.
      #
      # @param args [Array] method name and arguments; args[0] is the method name, args[1] is options hash (for costs)
      # @return [Integer, String, nil] evaluated result (integer or formula string) or 0 if key not found
      # @example
      #   spell.bolt_as           #=> 10 (evaluated)
      # @example
      #   spell.bolt_as_formula   #=> "Spells.wizard + 5"
      # @example
      #   spell.mana_cost(caster: "Bob")  #=> 50 (evaluated for Bob's skills)
      # @api private
      def method_missing(*args)
        if @@bonus_list.include?(args[0].to_s.gsub('_', '-'))
          if @bonus[args[0].to_s.gsub('_', '-')]
            proc { eval(@bonus[args[0].to_s.gsub('_', '-')]) }.call.to_i
          else
            0
          end
        elsif @@bonus_list.include?(args[0].to_s.sub(/_formula$/, '').gsub('_', '-'))
          @bonus[args[0].to_s.sub(/_formula$/, '').gsub('_', '-')].dup
        elsif (args[0].to_s =~ /_cost(?:_formula)?$/) and @@cost_list.include?(args[0].to_s.sub(/_formula$/, '').sub(/_cost$/, ''))
          options = args[1].to_hash
          if options[:caster] and (options[:caster] !~ /^(?:self|#{XMLData.name})$/i)
            if options[:target] and (options[:target].downcase == options[:caster].downcase)
              formula = @cost[args[0].to_s.sub(/_formula$/, '').sub(/_cost$/, '')]['self'].dup
            else
              formula = @cost[args[0].to_s.sub(/_formula$/, '').sub(/_cost$/, '')]['target'].dup || @cost[args[0].to_s.gsub('_', '-')]['self'].dup
            end
            skills = { 'Spells.minorelemental' => "SpellRanks['#{options[:caster]}'].minorelemental.to_i", 'Spells.majorelemental' => "SpellRanks['#{options[:caster]}'].majorelemental.to_i", 'Spells.minorspiritual' => "SpellRanks['#{options[:caster]}'].minorspiritual.to_i", 'Spells.majorspiritual' => "SpellRanks['#{options[:caster]}'].majorspiritual.to_i", 'Spells.wizard' => "SpellRanks['#{options[:caster]}'].wizard.to_i", 'Spells.sorcerer' => "SpellRanks['#{options[:caster]}'].sorcerer.to_i", 'Spells.ranger' => "SpellRanks['#{options[:caster]}'].ranger.to_i", 'Spells.paladin' => "SpellRanks['#{options[:caster]}'].paladin.to_i", 'Spells.empath' => "SpellRanks['#{options[:caster]}'].empath.to_i", 'Spells.cleric' => "SpellRanks['#{options[:caster]}'].cleric.to_i", 'Spells.bard' => "SpellRanks['#{options[:caster]}'].bard.to_i", 'Stats.level' => '100' }
            skills.each_pair { |a, b| formula.gsub!(a, b) }
          else
            if options[:target] and (options[:target] !~ /^(?:self|#{XMLData.name})$/i)
              formula = @cost[args[0].to_s.sub(/_formula$/, '').sub(/_cost$/, '')]['target'].dup || @cost[args[0].to_s.gsub('_', '-')]['self'].dup
            else
              formula = @cost[args[0].to_s.sub(/_formula$/, '').sub(/_cost$/, '')]['self'].dup
            end
          end
          if args[0].to_s =~ /mana/ and Spell[597].active? # Rapid Fire Penalty
            formula = "#{formula}+5"
          end
          if options[:multicast].to_i > 1
            formula = "(#{formula})*#{options[:multicast].to_i}"
          end
          if args[0].to_s =~ /_formula$/
            formula.dup
          else
            if formula
              proc { eval(formula) }.call.to_i
            else
              0
            end
          end
        else
          respond 'missing method: ' + args.inspect.to_s
          raise NoMethodError
        end
      end

      # Returns the human-readable name of this spell's circle.
      #
      # @return [String] the circle name (e.g., "Minor Spiritual", "Major Elemental", "Wizard")
      # @example
      #   Spell[505].circle_name  #=> "Minor Spiritual"
      # @see Spells.get_circle_name
      def circle_name
        Spells.get_circle_name(@circle)
      end

      # Tests whether this spell is cleared (removed) when the character dies.
      #
      # The inverse of {#persist_on_death}; returns true if the spell does NOT persist across death.
      #
      # @return [Boolean] true if the spell is cleared on death, false if it persists
      # @see Spell#persist_on_death
      def clear_on_death
        !@persist_on_death
      end

      # for backwards compatiblity
      def duration;      self.time_per_formula;            end
      # Returns the mana cost formula for this spell (backward compatibility alias).
      #
      # @return [String] the mana cost formula, or '0' if not defined
      # @deprecated Use {#mana_cost_formula} instead
      def cost;          self.mana_cost_formula    || '0'; end
      # Returns the mana cost formula for this spell (backward compatibility alias).
      #
      # @return [String] the mana cost formula, or '0' if not defined
      # @deprecated Use {#mana_cost_formula} instead
      def manaCost;      self.mana_cost_formula    || '0'; end
      # Returns the spirit cost formula for this spell (backward compatibility alias).
      #
      # @return [String] the spirit cost formula, or '0' if not defined
      # @deprecated Use {#spirit_cost_formula} instead
      def spiritCost;    self.spirit_cost_formula  || '0'; end
      # Returns the stamina cost formula for this spell (backward compatibility alias).
      #
      # @return [String] the stamina cost formula, or '0' if not defined
      # @deprecated Use {#stamina_cost_formula} instead
      def staminaCost;   self.stamina_cost_formula || '0'; end
      # Returns the spell's bolt attack strength formula (backward compatibility alias).
      #
      # @return [String] the formula, or nil if not defined
      # @deprecated Use {#bolt_as_formula} instead
      def boltAS;        self.bolt_as_formula;             end
      # Returns the spell's physical attack strength formula (backward compatibility alias).
      #
      # @return [String] the formula, or nil if not defined
      # @deprecated Use {#physical_as_formula} instead
      def physicalAS;    self.physical_as_formula;         end
      # Returns the spell's bolt defense strength formula (backward compatibility alias).
      #
      # @return [String] the formula, or nil if not defined
      # @deprecated Use {#bolt_ds_formula} instead
      def boltDS;        self.bolt_ds_formula;             end
      # Returns the spell's physical defense strength formula (backward compatibility alias).
      #
      # @return [String] the formula, or nil if not defined
      # @deprecated Use {#physical_ds_formula} instead
      def physicalDS;    self.physical_ds_formula;         end
      # Returns the spell's elemental cast strength formula (backward compatibility alias).
      #
      # @return [String] the formula, or nil if not defined
      # @deprecated Use {#elemental_cs_formula} instead
      def elementalCS;   self.elemental_cs_formula;        end
      # Returns the spell's mental cast strength formula (backward compatibility alias).
      #
      # @return [String] the formula, or nil if not defined
      # @deprecated Use {#mental_cs_formula} instead
      def mentalCS;      self.mental_cs_formula;           end
      # Returns the spell's spirit cast strength formula (backward compatibility alias).
      #
      # @return [String] the formula, or nil if not defined
      # @deprecated Use {#spirit_cs_formula} instead
      def spiritCS;      self.spirit_cs_formula;           end
      # Returns the spell's sorcerer cast strength formula (backward compatibility alias).
      #
      # @return [String] the formula, or nil if not defined
      # @deprecated Use {#sorcerer_cs_formula} instead
      def sorcererCS;    self.sorcerer_cs_formula;         end
      # Returns the spell's elemental trivial difficulty formula (backward compatibility alias).
      #
      # @return [String] the formula, or nil if not defined
      # @deprecated Use {#elemental_td_formula} instead
      def elementalTD;   self.elemental_td_formula;        end
      # Returns the spell's mental trivial difficulty formula (backward compatibility alias).
      #
      # @return [String] the formula, or nil if not defined
      # @deprecated Use {#mental_td_formula} instead
      def mentalTD;      self.mental_td_formula;           end
      # Returns the spell's spirit trivial difficulty formula (backward compatibility alias).
      #
      # @return [String] the formula, or nil if not defined
      # @deprecated Use {#spirit_td_formula} instead
      def spiritTD;      self.spirit_td_formula;           end
      # Returns the spell's sorcerer trivial difficulty formula (backward compatibility alias).
      #
      # @return [String] the formula, or nil if not defined
      # @deprecated Use {#sorcerer_td_formula} instead
      def sorcererTD;    self.sorcerer_td_formula;         end
      # Returns this spell's custom cast procedure (backward compatibility alias).
      #
      # @return [String, nil] the cast-proc XML text, or nil if not defined
      # @deprecated Use the {#cast_proc} reader instead
      def castProc;      @cast_proc;                       end
      # Tests whether this spell stacks when recast (backward compatibility alias).
      #
      # @return [Boolean] true if the spell stacks
      # @deprecated Use {#stackable?} instead
      def stacks;        self.stackable?                   end
      # Returns the command string to cast this spell (backward compatibility alias).
      #
      # Always returns nil; cast commands are generated dynamically by {#cast}.
      #
      # @return [nil]
      # @deprecated Legacy API; use {#cast} directly instead
      def command;       nil;                              end
      # Returns the human-readable circle name (backward compatibility alias).
      #
      # @return [String] the circle name
      # @deprecated Use {#circle_name} instead
      def circlename;    self.circle_name;                 end
      # Tests whether this spell is self-cast only (backward compatibility alias).
      #
      # @return [Boolean] true if spell availability is not 'all'
      # @deprecated Use {#available?} instead
      def selfonly;      @availability != 'all';           end
    end # class
  end # mod
end # mod
