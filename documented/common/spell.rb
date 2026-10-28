=begin
spell.rb: Core lich file for spell management and for spell related scripts.
=end

require 'open-uri'
require 'ox'

# Namespace for all Lich5 scripting engine classes and modules.
module Lich
  # Namespace for shared Lich5 core classes.
  module Common
    # Represents a spell from the game, parsed from the effect-list.xml data file.
    #
    # Spells are loaded once and cached in the class-level @@list; they track active
    # effects on the character and provide methods to cast spells and calculate costs,
    # durations, and bonuses. A Spell object reads spell metadata from XML including
    # number, name, type, availability (self-cast, group, or all), costs (mana, spirit,
    # stamina), duration formulas, and modifier bonuses. Instance state tracks whether
    # the spell is currently active, how much time remains, and when it was last cast.
    #
    # @example Retrieve and cast a spell
    #   spell = Spell[1701] # Major Heal
    #   spell.cast(target)
    # @example Check if a spell is known
    #   Spell[9610].known? #=> true or false
    # @see .load
    # @see .active
    # @see #cast
    class Spell
      @@list ||= Array.new
      @@loaded ||= false
      @@cast_lock ||= Array.new
      @@bonus_list ||= Array.new
      @@cost_list ||= Array.new
      @@load_mutex = Mutex.new
      @@after_stance = nil
      attr_reader :num, :name, :timestamp, :msgup, :msgdn, :circle, :active, :type, :cast_proc, :real_time, :persist_on_death, :availability, :no_incant, :last_cast, :group_cooldown, :target_cooldown, :target_msgup
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

      # Parses an XML spell element and initializes a Spell object.
      #
      # Called internally by {.load} when parsing effect-list.xml. Extracts spell number,
      # name, type, incantation requirement, availability, bonus modifiers, start/end
      # messages, costs, durations, cast procedures, and cooldown information from the XML.
      # Automatically appends the new Spell to the class-level @@list if not already
      # present.
      #
      # @param xml_spell [Ox::Element] an XML spell element from the parsed effect-list
      # @return [void]
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
        # Seconds a character is locked out of this spell, by kind. A 'group'
        # cooldown covers another group (EVOKE) casting of it; a 'target'
        # cooldown covers the spell landing on them from any caster, paired
        # with the third-person message that names them. Both are nil when the
        # spell declares no cooldown of that kind. See Group.spell_cooldown and
        # Group.spell_cooldown_ready?.
        xml_spell.locate('cooldown').each { |xml_cooldown|
          case xml_cooldown['type'].to_s.downcase
          when 'group'
            @group_cooldown = xml_cooldown.text.to_i
          when 'target'
            @target_cooldown = xml_cooldown.text.to_i
          end
        }
        @target_msgup = xml_spell.locate('message')
                                 .select { |e| e['type'].to_s.downcase == 'target-start' }
                                 .collect { |e| e.text }.join('$|^')
        @target_msgup = nil if @target_msgup.empty?
        @last_cast = Time.at(0)
        @timestamp = Time.now
        @timeleft = 0
        @active = false
        @circle = (num.to_s.length == 3 ? num.to_s[0..0] : num.to_s[0..1])
        @@list.push(self) unless @@list.find { |spell| spell.num == @num }
        # self # rubocop Lint/Void: self used in void context
      end

      # Every line that answers a cast: the regex {#cast} waits on, exposed
      # so a caller that sends and confirms on its own terms can wait on
      # the same lines instead of copying them.
      #
      # @param results_of_interest [Regexp, nil] extra lines to match, as {#cast} takes
      # @return [Regexp]
      def Spell.results_regex(results_of_interest: nil)
        return @@results_regex unless results_of_interest.is_a?(Regexp)
        Regexp.union(@@results_regex, results_of_interest)
      end

      # Sets the stance to restore after a stance spell finishes casting.
      #
      # When a spell with @stance = true completes, {#restore_stance_after_cast}
      # restores the character to this stance. Used by scripts to control post-cast
      # stance recovery.
      #
      # @param val [String, nil] the stance name (e.g. "offensive", "defensive", "guarded")
      #   or nil to let the game pick the safest stance
      # @return [String, nil]
      def Spell.after_stance=(val)
        @@after_stance = val
      end

      # Returns the stance to restore after a stance spell finishes casting.
      #
      # @return [String, nil] the stance name, or nil if not set
      def Spell.after_stance
        @@after_stance
      end

      # Loads the spell database from effect-list.xml and parses all spells.
      #
      # Called automatically on first access to the spell list if not already loaded.
      # If no file exists at DATA_DIR/effect-list.xml, attempts to download it from
      # the Elanthia-Online scripts GitHub repository. Falls back to the ;repository
      # script if GitHub retrieval fails.
      #
      # Thread-safe via @@load_mutex. Loading preserves active spell tracking across
      # reloads by storing and restoring timeleft for each active spell.
      #
      # @param filename [String, nil] path to effect-list.xml; if nil, uses the
      #   default DATA_DIR/effect-list.xml
      # @return [Boolean] true if load succeeds, false otherwise
      # @example
      #   Spell.load #=> true
      # @example Load from a custom path
      #   Spell.load('/custom/path/effect-list.xml') #=> true
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

      # Looks up a spell by number, name, or pattern.
      #
      # Automatically loads the spell database on first call. Looks up by:
      # - A Spell object: returns it as-is
      # - An integer or numeric string: finds spell by number
      # - A string: exact case-insensitive name match, then prefix match,
      #   then pattern match against start/end messages
      #
      # @param val [Spell, Integer, String] the lookup key
      # @return [Spell, nil] the matching spell, or nil if not found
      # @example Lookup by number
      #   Spell[1701] #=> #<Spell:... @num=1701 @name="Major Heal">
      # @example Lookup by exact name
      #   Spell["Major Heal"] #=> #<Spell:... @num=1701>
      # @example Lookup by prefix
      #   Spell["Major"] #=> #<Spell:... @num=1701>
      # @example Lookup by message pattern
      #   Spell["heals"] #=> #<Spell:... @num=1701>
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

      # Returns all currently active spells.
      #
      # @return [Array<Spell>] array of spell objects with {#active?} == true
      # @example
      #   Spell.active #=> [#<Spell... Haste>, #<Spell... Spirit Defense>]
      def Spell.active
        Spell.load unless @@loaded
        active = Array.new
        @@list.each { |spell| active.push(spell) if spell.active? }
        active
      end

      # Checks if a spell is currently active.
      #
      # @param val [Spell, Integer, String] spell lookup key (see {.[]})
      # @return [Boolean] true if the spell is active, false otherwise
      # @example
      #   Spell.active?(1701) #=> true
      def Spell.active?(val)
        Spell.load unless @@loaded
        Spell[val].active?
      end

      # Returns the complete cached list of all loaded spells.
      #
      # @return [Array<Spell>] all spell objects
      # @example
      #   Spell.list.count #=> 1043
      def Spell.list
        Spell.load unless @@loaded
        @@list
      end

      # Returns all spell start messages for matching active spells.
      #
      # Used to detect when a spell has landed. Each spell can have multiple start
      # messages separated by $|^ (join of multiple message elements with type="start").
      #
      # @return [Array<String>] start messages from all spells
      # @see #msgup
      # @see .dnmsgs
      def Spell.upmsgs
        Spell.load unless @@loaded
        @@list.collect { |spell| spell.msgup }.compact
      end

      # Third-person start messages, for spells that name the character they
      # land on. Empty until the effect list carries target-start messages.
      def Spell.target_upmsgs
        Spell.load unless @@loaded
        @@list.collect { |spell| spell.target_msgup }.compact
      end

      # Returns all spell end messages for detecting when spells wear off.
      #
      # Used to detect when a spell has expired. Each spell can have multiple end
      # messages separated by $|^ (join of multiple message elements with type="end").
      #
      # @return [Array<String>] end messages from all spells
      # @see #msgdn
      # @see .upmsgs
      def Spell.dnmsgs
        Spell.load unless @@loaded
        @@list.collect { |spell| spell.msgdn }.compact
      end

      # Returns the duration formula for this spell as a string.
      #
      # The formula can reference spell ranks, skill ranks, and character level.
      # Formulas differ by cast-type (self vs. target) and by whether the spell is
      # cast by the current character or another caster. When :caster or :target
      # options are provided and name a different character, the target cast-type
      # formula is used if available.
      #
      # @param options [Hash] lookup options
      # @option options [String] :caster name of the caster (defaults to self)
      # @option options [String] :target name of the spell target (defaults to self)
      # @option options [String] :activator spell activation method ("tap", "rub",
      #   "wave", "raise", "invoke", "scroll", etc.) for adjusting skill references
      # @return [String] a Ruby expression that evaluates to spell duration in minutes
      # @example
      #   Spell[1701].time_per_formula #=> "(Spells.majorspiritual + 5) / 2.0"
      # @see #time_per
      # @see #timeleft
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

      # Calculates the duration of this spell in minutes given the current character's skills.
      #
      # Evaluates the duration formula with the character's current spell ranks and
      # skills. Returns a minimum of 10 minutes for spells in the Lich Gemstone Keeper
      # database that evaluate to less than 10 minutes.
      #
      # @param options [Hash] lookup options (see {#time_per_formula})
      # @option options [String] :caster name of the caster
      # @option options [String] :target name of the spell target
      # @option options [String] :activator spell activation method
      # @return [Float] spell duration in minutes
      # @example
      #   Spell[1701].time_per #=> 42.5
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

      # Sets the remaining time on this spell and updates the timestamp.
      #
      # @param val [Float, Integer] remaining time in minutes
      # @return [Float, Integer] the value assigned
      def timeleft=(val)
        @timeleft = val
        @timestamp = Time.now
      end

      # Returns the remaining time on this spell in minutes.
      #
      # Decrements the stored time by elapsed real time since the last update.
      # Automatically calls {#putdown} and returns 0.0 when time expires. Updates
      # the internal timestamp to now.
      #
      # For spellsongs, delegates to the Spellsong object to get live remaining time.
      #
      # @return [Float] remaining time in minutes, or 0.0 if expired
      # @see #minsleft
      # @see #secsleft
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

      # Returns the remaining time on this spell in minutes (alias for {#timeleft}).
      #
      # @return [Float] remaining time in minutes
      def minsleft
        self.timeleft
      end

      # Returns the remaining time on this spell in seconds.
      #
      # @return [Float] remaining time converted to seconds from {#timeleft}
      # @see #timeleft
      def secsleft
        self.timeleft * 60
      end

      # Sets the active state of this spell.
      #
      # @param val [Boolean] true to mark active, false to mark inactive
      # @return [Boolean] the value assigned
      def active=(val)
        @active = val
      end

      # Checks if this spell is currently active.
      #
      # Returns true only if {#timeleft} > 0 and the @active flag is set.
      #
      # @return [Boolean] true if the spell is active and has time remaining
      def active?
        (self.timeleft > 0) and @active
      end

      # The cast-type predicates below (stackable?, refreshable?, multicastable?)
      # and the duration formulas resolve against the 'self' cast-type unless a
      # :caster or :target naming someone else is supplied. A bare call therefore
      # answers for a self-cast only, which is not the same answer for spells
      # whose target cast-type differs: in the current effect list 14 group buffs
      # (Bravery 211 and Heroism 215 among them) are stackable when self-cast but
      # refreshable when cast on someone else. Pass :caster/:target whenever the
      # spell may have come from another character.
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

      # Checks if casting this spell again refreshes (replaces) an active cast instead of stacking.
      #
      # Whether a spell is refreshable depends on its cast-type (self vs. target) and
      # the caster/target relationship. Defaults to the 'self' cast-type interpretation
      # unless a :caster or :target option names someone else.
      #
      # @param options [Hash] cast context options
      # @option options [String] :caster name of the caster (defaults to self)
      # @option options [String] :target name of the spell target (defaults to self)
      # @return [Boolean] true if refreshing the spell replaces the prior cast
      # @note In the current effect list, 14 group buffs (e.g. Bravery 211, Heroism 215)
      #   are refreshable when cast on another character but stackable when self-cast.
      # @see #stackable?
      # @see #multicastable?
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

      # Checks if multiple instances of this spell can be cast at the same time.
      #
      # Whether a spell is multicastable depends on its cast-type (self vs. target) and
      # the caster/target relationship. Defaults to the 'self' cast-type interpretation
      # unless a :caster or :target option names someone else.
      #
      # @param options [Hash] cast context options
      # @option options [String] :caster name of the caster (defaults to self)
      # @option options [String] :target name of the spell target (defaults to self)
      # @return [Boolean] true if the spell can be multicast
      # @see #stackable?
      # @see #refreshable?
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

      # Checks if the character currently knows this spell.
      #
      # Spell knowledge is determined by spell circle and minimum spell ranks in the
      # appropriate school. Delegates to Lich::Gemstone::SK if available for more
      # accurate tracking. Special cases: spell 1700 (Elemental Channels) is only known
      # to Wizards, Clerics, Empaths, Sorcerers, and Savants; circles 97-99 require
      # society membership and rank; circle 96 (Custom Man) is never known here.
      #
      # @return [Boolean] true if the character knows this spell
      # @example
      #   Spell[1701].known? #=> true if character has Major Spiritual ranks
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

      # Checks if this spell is available to cast given a caster and target.
      #
      # A spell is available if it is {#known?} and the availability allows the
      # caster/target combination. Availability modes from the effect-list:
      # - "all": can be cast on any character
      # - "group": can only be cast on self or groupmates
      # - "self-cast": can only be cast on self
      #
      # @param options [Hash] cast context options
      # @option options [String] :caster name of the caster (defaults to self)
      # @option options [String] :target name of the spell target (defaults to self)
      # @return [Boolean] true if the spell is known and availability permits the cast
      # @see #known?
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

      # Checks if this spell requires an incantation to cast.
      #
      # @return [Boolean] true if the spell must be incanted, false if it has no-incant
      def incant?
        !@no_incant
      end

      # Sets whether this spell requires an incantation.
      #
      # @param val [Boolean] true to require incantation, false for no-incant
      # @return [Boolean] the value assigned
      def incant=(val)
        @no_incant = !val
      end

      # Returns the spell name.
      #
      # @return [String] the spell name
      def to_s
        @name.to_s
      end

      # Returns the maximum allowed duration for this spell in minutes.
      #
      # Maximum duration defaults to 250.0 minutes if not specified in the XML.
      # Different cast-types (self vs. target) can have different max durations.
      #
      # @param options [Hash] cast context options
      # @option options [String] :caster name of the caster (defaults to self)
      # @option options [String] :target name of the spell target (defaults to self)
      # @return [Float] the maximum duration in minutes
      # @see #time_per
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

      # Marks this spell as active and sets its remaining time.
      #
      # If the spell is stackable, adds the new duration to the existing time (capped
      # at max duration). Otherwise, replaces the time with the new duration. Sets the
      # @active flag to true.
      #
      # @param options [Hash] cast context options (see {#time_per})
      # @return [void]
      # @see #putdown
      # @see #stackable?
      def putup(options = {})
        if stackable?(options)
          self.timeleft = [self.timeleft + self.time_per(options), self.max_duration(options)].min
        else
          self.timeleft = [self.time_per(options), self.max_duration(options)].min
        end
        @active = true
      end

      # Marks this spell as no longer active.
      #
      # Sets remaining time to 0.0 and clears the @active flag.
      #
      # @return [void]
      # @see #putup
      def putdown
        self.timeleft = 0
        @active = false
      end

      # Returns the remaining time on this spell formatted as a human-readable string.
      #
      # @return [String] formatted time (e.g. "42 minutes 30 seconds")
      # @see #timeleft
      def remaining
        self.timeleft.as_time
      end

      # Checks if the character can currently afford to cast this spell.
      #
      # Verifies that the character has sufficient mana, spirit, and stamina for the
      # spell's costs. Special handling for monks (Feat.mental_acuity) who pay mana
      # costs in stamina; spirit spells account for active spirit modifiers; stamina
      # costs fail if Overexerted or if a stamina drain is active.
      #
      # @param options [Hash] cast context options (see {#mana_cost})
      # @return [Boolean] true if all cost requirements are met
      # @see #mana_cost
      # @see #spirit_cost
      # @see #stamina_cost
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

      # Acquires an exclusive lock preventing other scripts from casting simultaneously.
      #
      # Blocks until the current script is first in the cast lock queue. Used internally
      # by {#cast} to ensure only one script casts at a time and to serialize prepare/cast
      # sequences. Sleeps 0.1 seconds between checks and allows paused scripts to release
      # their place in line.
      #
      # @return [void]
      # @see .unlock_cast
      def Spell.lock_cast
        script = Script.current
        @@cast_lock.push(script)
        until (@@cast_lock.first == script) or @@cast_lock.empty?
          sleep 0.1
          Script.current # allows this loop to be paused
          @@cast_lock.delete_if { |s| s.paused or not Script.list.include?(s) }
        end
      end

      # Releases the exclusive cast lock acquired by {.lock_cast}.
      #
      # Called automatically by {#cast} in an ensure block. Scripts should not call this
      # directly unless they have called {.lock_cast} outside of a normal cast.
      #
      # @return [void]
      # @see .lock_cast
      def Spell.unlock_cast
        @@cast_lock.delete(Script.current)
      end

      # Casts this spell and waits for the cast to complete.
      #
      # Handles the full spell casting sequence: checks energy/resources, acquires the
      # cast lock, prepares the spell (unless using incant), issues the cast/channel/evoke
      # command, and waits for a game response. Handles target resolution (GameObj, ID,
      # or name string), stance changes before casting and restoration after, and
      # retries for certain failures. Returns the final game output line or result message.
      #
      # Logs the cast time to @last_cast; updates @active and @timeleft when the spell
      # lands. Returns early if energy checks fail.
      #
      # @param target [String, Integer, GameObj, nil] spell target; nil for self-cast
      # @param results_of_interest [Regexp, nil] additional result patterns to match beyond
      #   the built-in {.results_regex} patterns
      # @param arg_options [String, nil] optional arguments and cast method override
      #   (e.g. "cast target", "channel left hand", "evoke")
      # @param force_stance [Boolean, nil] true to force stance change before cast
      #   (overrides spell's @stance setting), false to skip stance change, nil for default
      # @return [String] the game output line that matched the results regex, or a failure
      #   reason (e.g. "You can't think clearly enough to prepare a spell!")
      # @example Cast Major Heal on target
      #   Spell[1701].cast(target) #=> "Cast Roundtime 2 Seconds."
      # @example Cast with no incantation
      #   Spell[1701].cast(target, nil, "cast target")
      # @example Cast and capture custom results
      #   result = Spell[1721].cast(nil, /Your skin hardens/)
      #
      # @note Acquires {.lock_cast} for the duration. Restores character stance after
      #   casting if the spell has @stance set and force_stance is not false. Failed
      #   prepare attempts return the error message instead of retrying indefinitely.
      # @raise [ArgumentError] if restored stance is invalid (from restore_stance_after_cast)
      # @see #force_cast
      # @see #force_channel
      # @see #force_incant
      # @see .results_regex
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
                restore_stance_after_cast
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

      # After a stance spell is cast, put the character back into the stance
      # they asked for (Spell.after_stance), or the safest one the game allows.
      # Stance.change no-ops when already there and waits out roundtime itself.
      #
      # @return [void]
      def restore_stance_after_cast
        # after_stance can be a blank string when a script captured Char.stance
        # before the first pbarStance update arrived. Treat that as "no
        # preference" rather than letting it raise, which is what the old
        # inline regex check did.
        after = @@after_stance.to_s.strip
        if !after.empty?
          Lich::Gemstone::Stance.change(after)
        elsif Char.stance !~ /^guarded$|^defensive$/
          Lich::Gemstone::Stance.change(Lich::Gemstone::Stance.safest)
        end
      rescue ArgumentError => e
        echo "cast: #{e.message}"
      end
      private :restore_stance_after_cast

      # Casts this spell using the "cast" command (default cast method).
      #
      # Convenience method that wraps {#cast} and forces the cast command, overriding
      # any channel/evoke/incant preference in the spell definition.
      #
      # @param target [String, Integer, GameObj, nil] spell target
      # @param arg_options [String, nil] optional arguments (e.g. "target", "left hand")
      # @param results_of_interest [Regexp, nil] additional result patterns to match
      # @param force_stance [Boolean, nil] true to force offensive stance before cast,
      #   false to skip stance change
      # @return [String] the game output line or failure reason (see {#cast})
      # @example
      #   Spell[1701].force_cast(target) #=> "Cast Roundtime 2 Seconds."
      # @see #cast
      def force_cast(target = nil, arg_options = nil, results_of_interest = nil, force_stance: nil)
        unless arg_options.nil? || arg_options.empty?
          arg_options = "cast #{arg_options}"
        else
          arg_options = "cast"
        end
        cast(target, results_of_interest, arg_options, force_stance: force_stance)
      end

      # Casts this spell using the "channel" command.
      #
      # Convenience method that wraps {#cast} and forces the channel command, overriding
      # the spell's default cast method.
      #
      # @param target [String, Integer, GameObj, nil] spell target
      # @param arg_options [String, nil] optional arguments (e.g. "left hand")
      # @param results_of_interest [Regexp, nil] additional result patterns to match
      # @param force_stance [Boolean, nil] true to force offensive stance before cast,
      #   false to skip stance change
      # @return [String] the game output line or failure reason (see {#cast})
      # @example
      #   Spell[1721].force_channel(target) #=> "Channel Roundtime 3 Seconds."
      # @see #cast
      def force_channel(target = nil, arg_options = nil, results_of_interest = nil, force_stance: nil)
        unless arg_options.nil? || arg_options.empty?
          arg_options = "channel #{arg_options}"
        else
          arg_options = "channel"
        end
        cast(target, results_of_interest, arg_options, force_stance: force_stance)
      end

      # Casts this spell using the "evoke" command.
      #
      # Convenience method that wraps {#cast} and forces the evoke command, typically
      # used for wands and other evokable items.
      #
      # @param target [String, Integer, GameObj, nil] spell target
      # @param arg_options [String, nil] optional arguments (e.g. "target", "at orc")
      # @param results_of_interest [Regexp, nil] additional result patterns to match
      # @param force_stance [Boolean, nil] true to force offensive stance before cast,
      #   false to skip stance change
      # @return [String] the game output line or failure reason (see {#cast})
      # @example
      #   Spell[1721].force_evoke(target) #=> "Evoke Roundtime 3 Seconds."
      # @see #cast
      def force_evoke(target = nil, arg_options = nil, results_of_interest = nil, force_stance: nil)
        unless arg_options.nil? || arg_options.empty?
          arg_options = "evoke #{arg_options}"
        else
          arg_options = "evoke"
        end
        cast(target, results_of_interest, arg_options, force_stance: force_stance)
      end

      # Casts this spell using the "incant" command (quick-cast without prepare).
      #
      # Convenience method that wraps {#cast} and forces the incant command, skipping
      # the normal prepare/cast sequence. Incantation is instantaneous if the spell
      # supports it.
      #
      # @param arg_options [String, nil] optional arguments (e.g. additional targeting)
      # @param results_of_interest [Regexp, nil] additional result patterns to match
      # @param force_stance [Boolean, nil] true to force offensive stance before cast,
      #   false to skip stance change
      # @return [String] the game output line or failure reason (see {#cast})
      # @example
      #   Spell[1701].force_incant #=> "Incant Roundtime 1 Seconds."
      # @see #cast
      def force_incant(arg_options = nil, results_of_interest = nil, force_stance: nil)
        unless arg_options.nil? || arg_options.empty?
          arg_options = "incant #{arg_options}"
        else
          arg_options = "incant"
        end
        cast(nil, results_of_interest, arg_options, force_stance: force_stance)
      end

      # Returns a copy of the spell's bonus modifier hash.
      #
      # Bonus modifiers are spell-specific effects stored in the XML (e.g., bolt AS,
      # elemental CS). The hash keys are modifier types (as strings with dashes, e.g.
      # "bolt-as", "elemental-cs") and values are formulas as strings that reference
      # character skills and attributes.
      #
      # @return [Hash] a copy of the @bonus hash
      # @api private
      def _bonus
        @bonus.dup
      end

      # Returns a copy of the spell's cost hash.
      #
      # Cost hash structure: {cost_type => {'self' => formula, 'target' => formula}}.
      # Cost types include "mana", "spirit", and "stamina". Some spells have separate
      # costs for self-cast vs. target cast; missing target costs default to self costs.
      #
      # @return [Hash] a copy of the @cost hash
      # @api private
      def _cost
        @cost.dup
      end

      # Dynamically delegates spell bonus and cost lookups to the bonus/cost hashes.
      #
      # Handles method calls of the form:
      # - `spell.bonus_type` → evaluates the bonus formula for bonus_type
      # - `spell.bonus_type_formula` → returns the bonus formula as a string
      # - `spell.cost_type_cost(options)` → evaluates the cost formula
      # - `spell.cost_type_cost_formula(options)` → returns the cost formula string
      #
      # Bonus/cost types use underscores in method names but dashes in the XML
      # (e.g., `bolt_as` maps to "bolt-as" key). Raises NoMethodError if the method
      # name does not match a known bonus or cost type.
      #
      # @param args [Array] method name and optional arguments
      # @return [Integer] evaluated cost or bonus value, or [String] if _formula variant
      # @example
      #   Spell[1701].mana_cost #=> 11
      #   Spell[1701].mana_cost_formula #=> "9 + (Spells.majorspiritual / 2)"
      #   Spell[1721].bolt_as #=> 42
      # @raise [NoMethodError] if method name does not match a bonus or cost type
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
      # @return [String] circle name (e.g. "Minor Spiritual", "Major Elemental", "Wizard")
      # @example
      #   Spell[1701].circle_name #=> "Major Spiritual"
      # @see Spells.get_circle_name
      def circle_name
        Spells.get_circle_name(@circle)
      end

      # Checks if this spell is cleared when the character dies.
      #
      # Returns the opposite of @persist_on_death: spells that do not persist through
      # death are cleared on death.
      #
      # @return [Boolean] true if the spell should be cleared on death
      def clear_on_death
        !@persist_on_death
      end

      # for backwards compatiblity
      def duration; self.time_per_formula; end
      # Returns the mana cost formula (backward-compatible alias for {#mana_cost_formula}).
      #
      # @return [String] the mana cost formula, or '0' if not defined
      # @deprecated Use {#mana_cost} or {#mana_cost_formula} instead
      def cost; self.mana_cost_formula || '0'; end
      # Returns the mana cost formula (backward-compatible camelCase alias).
      #
      # @return [String] the mana cost formula, or '0' if not defined
      # @deprecated Use {#mana_cost} or {#mana_cost_formula} instead
      def manaCost; self.mana_cost_formula || '0'; end
      # Returns the spirit cost formula (backward-compatible camelCase alias).
      #
      # @return [String] the spirit cost formula, or '0' if not defined
      # @deprecated Use {#spirit_cost} or {#spirit_cost_formula} instead
      def spiritCost; self.spirit_cost_formula || '0'; end
      # Returns the stamina cost formula (backward-compatible camelCase alias).
      #
      # @return [String] the stamina cost formula, or '0' if not defined
      # @deprecated Use {#stamina_cost} or {#stamina_cost_formula} instead
      def staminaCost; self.stamina_cost_formula || '0'; end
      # Returns the spell's bolt attack strength bonus formula (backward-compatible alias).
      #
      # @return [String] the bolt AS formula
      # @deprecated Use {#bolt_as} or {#bolt_as_formula} instead
      def boltAS; self.bolt_as_formula; end
      # Returns the spell's physical attack strength bonus formula (backward-compatible alias).
      #
      # @return [String] the physical AS formula
      # @deprecated Use {#physical_as} or {#physical_as_formula} instead
      def physicalAS; self.physical_as_formula; end
      # Returns the spell's bolt defense strength bonus formula (backward-compatible alias).
      #
      # @return [String] the bolt DS formula
      # @deprecated Use {#bolt_ds} or {#bolt_ds_formula} instead
      def boltDS; self.bolt_ds_formula; end
      # Returns the spell's physical defense strength bonus formula (backward-compatible alias).
      #
      # @return [String] the physical DS formula
      # @deprecated Use {#physical_ds} or {#physical_ds_formula} instead
      def physicalDS; self.physical_ds_formula; end
      # Returns the spell's elemental cast strength bonus formula (backward-compatible alias).
      #
      # @return [String] the elemental CS formula
      # @deprecated Use {#elemental_cs} or {#elemental_cs_formula} instead
      def elementalCS; self.elemental_cs_formula; end
      # Returns the spell's mental cast strength bonus formula (backward-compatible alias).
      #
      # @return [String] the mental CS formula
      # @deprecated Use {#mental_cs} or {#mental_cs_formula} instead
      def mentalCS; self.mental_cs_formula; end
      # Returns the spell's spirit cast strength bonus formula (backward-compatible alias).
      #
      # @return [String] the spirit CS formula
      # @deprecated Use {#spirit_cs} or {#spirit_cs_formula} instead
      def spiritCS; self.spirit_cs_formula; end
      # Returns the spell's sorcerer cast strength bonus formula (backward-compatible alias).
      #
      # @return [String] the sorcerer CS formula
      # @deprecated Use {#sorcerer_cs} or {#sorcerer_cs_formula} instead
      def sorcererCS; self.sorcerer_cs_formula; end
      # Returns the spell's elemental target defense formula (backward-compatible alias).
      #
      # @return [String] the elemental TD formula
      # @deprecated Use {#elemental_td} or {#elemental_td_formula} instead
      def elementalTD; self.elemental_td_formula; end
      # Returns the spell's mental target defense formula (backward-compatible alias).
      #
      # @return [String] the mental TD formula
      # @deprecated Use {#mental_td} or {#mental_td_formula} instead
      def mentalTD; self.mental_td_formula; end
      # Returns the spell's spirit target defense formula (backward-compatible alias).
      #
      # @return [String] the spirit TD formula
      # @deprecated Use {#spirit_td} or {#spirit_td_formula} instead
      def spiritTD; self.spirit_td_formula; end
      # Returns the spell's sorcerer target defense formula (backward-compatible alias).
      #
      # @return [String] the sorcerer TD formula
      # @deprecated Use {#sorcerer_td} or {#sorcerer_td_formula} instead
      def sorcererTD; self.sorcerer_td_formula; end
      # Returns the spell's custom cast procedure (backward-compatible alias).
      #
      # @return [String, nil] the cast-proc code block, or nil if not defined
      # @deprecated Use {#cast_proc} instead
      def castProc; @cast_proc; end
      # Checks if this spell stacks (backward-compatible alias for {#stackable?}).
      #
      # @return [Boolean] true if the spell is stackable
      # @deprecated Use {#stackable?} instead
      def stacks; self.stackable? end
      # Returns nil (deprecated method, included for backward compatibility).
      #
      # @return [nil]
      # @deprecated This method is not used in Lich5
      def command; nil; end
      # Returns the human-readable name of this spell's circle (backward-compatible alias).
      #
      # @return [String] circle name (e.g. "Minor Spiritual", "Major Elemental")
      # @deprecated Use {#circle_name} instead
      def circlename; self.circle_name; end
      # Checks if this spell is self-only or restricted (not available to all).
      #
      # @return [Boolean] true if availability is not 'all'
      # @deprecated Use {#available?} instead
      def selfonly; @availability != 'all'; end
    end # class
  end # mod
end # mod
