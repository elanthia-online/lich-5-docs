# frozen_string_literal: true

# Namespace for the Lich scripting engine and its game-specific extensions.
module Lich
  # Namespace for DragonRealms-specific constants, data structures, and utilities.
  module DragonRealms
    # Learning rate progression levels in DragonRealms, from slowest to fastest.
    #
    # These levels are used to interpret the "learning" component of skill experience
    # displays and are ordered from "clear" (no experience gain) to "mind lock" (maximum
    # learning rate).
    #
    # @return [Array<String>] immutable array of learning rate names
    DR_LEARNING_RATES = [
      'clear',
      'dabbling',
      'perusing',
      'learning',
      'thoughtful',
      'thinking',
      'considering',
      'pondering',
      'ruminating',
      'concentrating',
      'attentive',
      'deliberative',
      'interested',
      'examining',
      'understanding',
      'absorbing',
      'intrigued',
      'scrutinizing',
      'analyzing',
      'studious',
      'focused',
      'very focused',
      'engaged',
      'very engaged',
      'cogitating',
      'fascinated',
      'captivated',
      'engrossed',
      'riveted',
      'very riveted',
      'rapt',
      'very rapt',
      'enthralled',
      'nearly locked',
      'mind lock'
    ].freeze

    # Length of the longest learning rate name, used for padding in exp display
    DR_LONGEST_LEARNING_RATE_LENGTH = DR_LEARNING_RATES.max_by(&:length).length

    # Combat balance modifiers in DragonRealms, reflecting body control and stance.
    #
    # These values describe how well-balanced a combatant is, independent of positional
    # advantage against an opponent. Used to interpret combat status messages.
    #
    # @return [Array<String>] immutable array of balance descriptions
    DR_BALANCE_VALUES = [
      'completely',
      'hopelessly',
      'extremely',
      'very badly',
      'badly',
      'somewhat off',
      'off',
      'slightly off',
      'solidly',
      'nimbly',
      'adeptly',
      'incredibly'
    ].freeze

    # Combat positioning relative to your opponent, captured from the balance
    # status line (e.g. "[You're solidly balanced and in good position.]").
    # Stored as a signed magnitude: positive means you hold the advantage,
    # negative means your opponent does, and 0 is an even contest. The scale is
    # symmetric, and the two "overwhelming opponent" phrasings map to the same
    # value.
    DR_POSITION_VALUES = {
      'opponent overwhelming you'        => -9,
      'opponent dominating'              => -8,
      'opponent in excellent position'   => -7,
      'opponent in superior position'    => -6,
      'opponent in very strong position' => -5,
      'opponent in strong position'      => -4,
      'opponent in good position'        => -3,
      'opponent in better position'      => -2,
      'opponent has slight advantage'    => -1,
      'no advantage'                     => 0,
      'have slight advantage'            => 1,
      'in better position'               => 2,
      'in good position'                 => 3,
      'in strong position'               => 4,
      'in very strong position'          => 5,
      'in superior position'             => 6,
      'in excellent position'            => 7,
      'in dominating position'           => 8,
      'overwhelming opponent'            => 9,
      'overwhelming your opponent'       => 9
    }.freeze

    # Canonical skill hierarchy and guild-specific skill aliases for DragonRealms.
    #
    # Contains two top-level keys:
    # - `skillsets`: a [Hash] mapping skill categories ("Armor", "Lore", "Weapon", "Magic", "Survival") to arrays of individual skill names
    # - `guild_skill_aliases`: a [Hash] mapping guild names to their primary magic overrides (e.g., "Cleric" maps "Primary Magic" to "Holy Magic")
    #
    # @return [Hash] immutable nested structure with symbolized and stringified keys
    DR_SKILLS_DATA = {
      skillsets: {
        'Armor'    => [
          'Shield Usage',
          'Light Armor',
          'Chain Armor',
          'Brigandine',
          'Plate Armor',
          'Defending',
          'Conviction'
        ].freeze,
        'Lore'     => [
          'Alchemy',
          'Appraisal',
          'Enchanting',
          'Engineering',
          'Forging',
          'Outfitting',
          'Performance',
          'Scholarship',
          'Tactics',
          'Empathy',
          'Bardic Lore',
          'Trading',
          'Mechanical Lore'
        ].freeze,
        'Weapon'   => [
          'Parry Ability',
          'Small Edged',
          'Large Edged',
          'Twohanded Edged',
          'Small Blunt',
          'Large Blunt',
          'Twohanded Blunt',
          'Slings',
          'Bow',
          'Crossbow',
          'Staves',
          'Polearms',
          'Light Thrown',
          'Heavy Thrown',
          'Brawling',
          'Offhand Weapon',
          'Melee Mastery',
          'Missile Mastery',
          'Expertise'
        ].freeze,
        'Magic'    => [
          'Primary Magic',
          'Arcana',
          'Attunement',
          'Augmentation',
          'Debilitation',
          'Targeted Magic',
          'Utility',
          'Warding',
          'Sorcery',
          'Astrology',
          'Summoning',
          'Theurgy',
          'Inner Magic',
          'Inner Fire',
          'Lunar Magic',
          'Elemental Magic',
          'Holy Magic',
          'Life Magic',
          'Arcane Magic'
        ].freeze,
        'Survival' => [
          'Evasion',
          'Athletics',
          'Perception',
          'Stealth',
          'Locksmithing',
          'Thievery',
          'First Aid',
          'Outdoorsmanship',
          'Skinning',
          'Instinct',
          'Backstab',
          'Thanatology'
        ].freeze
      }.freeze,
      guild_skill_aliases: {
        'Cleric'       => { 'Primary Magic' => 'Holy Magic' }.freeze,
        'Necromancer'  => { 'Primary Magic' => 'Arcane Magic' }.freeze,
        'Warrior Mage' => { 'Primary Magic' => 'Elemental Magic' }.freeze,
        'Thief'        => { 'Primary Magic' => 'Inner Magic' }.freeze,
        'Barbarian'    => { 'Primary Magic' => 'Inner Fire' }.freeze,
        'Ranger'       => { 'Primary Magic' => 'Life Magic' }.freeze,
        'Bard'         => { 'Primary Magic' => 'Elemental Magic' }.freeze,
        'Paladin'      => { 'Primary Magic' => 'Holy Magic' }.freeze,
        'Empath'       => { 'Primary Magic' => 'Life Magic' }.freeze,
        'Trader'       => { 'Primary Magic' => 'Lunar Magic' }.freeze,
        'Moon Mage'    => { 'Primary Magic' => 'Lunar Magic' }.freeze
      }.freeze
    }.freeze

    # Towns in DragonRealms where Kronars (the primary currency) can be exchanged.
    #
    # @return [Array<String>] immutable array of town names
    KRONAR_BANKS = ['Crossings', 'Dirge', 'Ilaya Taipa', 'Leth Deriel'].freeze
    # Towns in DragonRealms where Lirums (the eastern currency) can be exchanged.
    #
    # @return [Array<String>] immutable array of town names
    LIRUM_BANKS = ["Aesry Surlaenis'a", "Hara'jaal", "Mer'Kresh", "Muspar'i", 'Ratha', 'Riverhaven', "Rossman's Landing", 'Therenborough', 'Throne City'].freeze
    # Towns in DragonRealms where Dokoras (the southern currency) can be exchanged.
    #
    # @return [Array<String>] immutable array of town names
    DOKORA_BANKS = ['Ain Ghazal', 'Boar Clan', "Chyolvea Tayeu'a", 'Hibarnhvidar', 'Fang Cove', "Raven's Point", 'Shard'].freeze

    # Room titles of bank deposit windows in DragonRealms towns, indexed by town name.
    #
    # Maps each town to an array of full room titles (e.g., "[[Provincial Bank, Teller]]").
    # Used to locate and identify bank deposit windows when depositing or checking balances.
    #
    # @return [Hash{String => Array<String>}] immutable mapping from town name to room title array
    BANK_TITLES = {
      "Aesry Surlaenis'a" => ['[[Tona Kertigen, Deposit Window]]'].freeze,
      'Ain Ghazal'        => ['[[Ain Ghazal, Private Depository]]'].freeze,
      'Boar Clan'         => ['[[Ranger Guild, Bank]]'].freeze,
      "Chyolvea Tayeu'a"  => ["[[Chyolvea Tayeu'a, Teller]]"].freeze,
      'Crossings'         => ['[[Provincial Bank, Teller]]'].freeze,
      'Dirge'             => ["[[Dirge, Traveller's Bank]]"].freeze,
      'Fang Cove'         => ['[[First Council Banking, Vault]]'].freeze,
      "Hara'jaal"         => ["[[Baron's Forset, Teller]]"].freeze,
      'Hibarnhvidar'      => ['[[Second Provincial Bank of Hibarnhvidar, Teller]]', '[[Hibarnhvidar, Teller Windows]]', '[[First Arachnid Bank, Lobby]]'].freeze,
      'Ilaya Taipa'       => ['[[Ilaya Taipa, Trader Outpost Bank]]'].freeze,
      'Leth Deriel'       => ['[[Imperial Depository, Domestic Branch]]'].freeze,
      "Mer'Kresh"         => ["[[Harti Clemois Bank, Teller's Window]]"].freeze,
      "Muspar'i"          => ["[[Old Lata'arna Keep, Teller Windows]]"].freeze,
      'Ratha'             => ['[[Lower Bank of Ratha, Cashier]]', '[[Sshoi-sson Palace, Grand Provincial Bank, Bursarium]]'].freeze,
      "Raven's Point"     => ["[[Bank of Raven's Point, Depository]]"].freeze,
      'Riverhaven'        => ['[[Bank of Riverhaven, Teller]]'].freeze,
      "Rossman's Landing" => ["[[Traders' Guild Outpost, Depository]]"].freeze,
      'Shard'             => ["[[First Bank of Ilithi, Teller's Windows]]"].freeze,
      'Therenborough'     => ['[[Bank of Therenborough, Teller]]'].freeze,
      'Throne City'       => ['[[Faldesu Exchequer, Teller]]'].freeze
    }.freeze

    # Room titles of vault carousel chambers in DragonRealms towns, indexed by town name.
    #
    # Maps each town with a vault carousel to its full room title
    # (e.g., "[[Crossing, Carousel Chamber]]"). Used to locate and identify vault chambers
    # when managing long-term item storage.
    #
    # @return [Hash{String => Array<String>}] immutable mapping from town name to room title array
    VAULT_TITLES = {
      'Crossings'     => ['[[Crossing, Carousel Chamber]]'].freeze,
      'Fang Cove'     => ['[[Fang Cove, Carousel Chamber]]'].freeze,
      'Leth Deriel'   => ['[[Leth Deriel, Carousel Chamber]]'].freeze,
      "Mer'Kresh"     => ["[[Mer'Kresh, Carousel Square]]"].freeze,
      "Muspar'i"      => ["[[Muspar'i, Carousel Square]]"].freeze,
      'Ratha'         => ['[[Ratha, Carousel Square]]'].freeze,
      'Riverhaven'    => ['[[Riverhaven, Carousel Chamber]]'].freeze,
      'Shard'         => ['[[Shard, Carousel Chamber]]'].freeze,
      'Therenborough' => ['[[Therenborough, Carousel Chamber]]'].freeze
    }.freeze

    # Some spells may last for an unknown duration,
    # such as cyclic spells that last as long as
    # the caster can harness mana for it.
    # Or, barbarian abilities when the character
    # doesn't have Power Monger mastery to see true
    # durations but only vague guestimates.
    # In those situations, we set use this value.
    UNKNOWN_DURATION = 1000 unless defined?(UNKNOWN_DURATION)

    # Case-insensitive regex patterns for matching DragonRealms hometown abbreviations and aliases.
    #
    # Maps each canonical hometown name to a pattern that matches common abbreviations and
    # full names. Patterns are anchored to word boundaries and support apostrophe/optional-character
    # variations in names. For example, 'Therenborough' matches /^(theren(borough)?)$/i to accept
    # both "theren" and "therenborough".
    #
    # @return [Hash{String => Regexp}] immutable mapping from canonical town name to regex pattern
    # @see HOMETOWN_LIST
    # @see HOMETOWN_REGEX
    HOMETOWN_REGEX_MAP = {
      'Arthe Dale'        => /^(arthe( dale)?)$/i,
      'Crossing'          => /^(cross(ing)?)$/i,
      'Darkling Wood'     => /^(darkling( wood)?)$/i,
      'Dirge'             => /^(dirge)$/i,
      "Fayrin's Rest"     => /^(fayrin'?s?( rest)?)$/i,
      'Leth Deriel'       => /^(leth( deriel)?)$/i,
      'Shard'             => /^(shard)$/i,
      'Steelclaw Clan'    => /^(steel( )?claw( clan)?|SCC)$/i,
      'Stone Clan'        => /^(stone( clan)?)$/i,
      'Tiger Clan'        => /^(tiger( clan)?)$/i,
      'Wolf Clan'         => /^(wolf( clan)?)$/i,
      'Riverhaven'        => /^(river|haven|riverhaven)$/i,
      "Rossman's Landing" => /^(rossman'?s?( landing)?)$/i,
      'Therenborough'     => /^(theren(borough)?)$/i,
      'Langenfirth'       => /^(lang(enfirth)?)$/i,
      'Fornsted'          => /^(fornsted)$/i,
      'Hvaral'            => /^(hvaral)$/i,
      'Ratha'             => /^(ratha)$/i,
      'Aesry'             => /^(aesry)$/i,
      "Mer'Kresh"         => /^(mer'?kresh)$/i,
      'Throne City'       => /^(throne( city)?)$/i,
      'Hibarnhvidar'      => /^(hib(arnhvidar)?)$/i,
      "Raven's Point"     => /^(raven'?s?( point)?)$/i,
      'Boar Clan'         => /^(boar( clan)?)$/i,
      'Fang Cove'         => /^(fang( cove)?)$/i,
      "Muspar'i"          => /^(muspar'?i)$/i,
      'Ain Ghazal'        => /^(ain( )?ghazal)$/i
    }.freeze

    # List of canonical town names, like 'Therenborough' and 'Langenfirth'.
    HOMETOWN_LIST = HOMETOWN_REGEX_MAP.keys.freeze

    # Union of regular expressions that match town names, like /^(theren(borough)?)$/i
    HOMETOWN_REGEX = Regexp.union(HOMETOWN_REGEX_MAP.values)

    # English ordinal words from "first" through "twentieth".
    #
    # Used to parse and convert written ordinal expressions ("first", "third", "tenth") in game text.
    #
    # @return [Array<String>] immutable array of ordinal words
    ORDINALS = %w[first second third fourth fifth sixth seventh eighth ninth tenth eleventh twelfth thirteenth fourteenth fifteenth sixteenth seventeenth eighteenth nineteenth twentieth].freeze

    # The three playable currencies in DragonRealms.
    #
    # Kronars are primary in western towns; Lirums in the east; Dokoras in the south.
    #
    # @return [Array<String>] immutable array of currency names
    CURRENCIES = %w[Kronars Lirums Dokoras].freeze

    # Encumbrance levels in DragonRealms, mapped to numeric burden values.
    #
    # Maps descriptive encumbrance states ("None", "Light Burden", "Overburdened", etc.)
    # to a numeric scale from 0 (no burden) to 11 (maximum burden). Used to interpret
    # encumbrance status messages and assess character mobility.
    #
    # @return [Hash{String => Integer}] immutable mapping from encumbrance description to numeric level
    ENC_MAP = {
      'None'                              => 0,
      'Light Burden'                      => 1,
      'Somewhat Burdened'                 => 2,
      'Burdened'                          => 3,
      'Heavy Burden'                      => 4,
      'Very Heavy Burden'                 => 5,
      'Overburdened'                      => 6,
      'Very Overburdened'                 => 7,
      'Extremely Overburdened'            => 8,
      'Tottering Under Burden'            => 9,
      'Are you even able to move?'        => 10,
      "It's amazing you aren't squashed!" => 11
    }.freeze

    # English number words mapped to their integer values.
    #
    # Covers cardinal numbers from "zero" through "ninety" (including teens and common tens).
    # Used to parse written numbers in game text and convert them to integers.
    #
    # @return [Hash{String => Integer}] immutable mapping from word to integer value
    NUM_MAP = {
      'zero'      => 0,
      'one'       => 1,
      'two'       => 2,
      'three'     => 3,
      'four'      => 4,
      'five'      => 5,
      'six'       => 6,
      'seven'     => 7,
      'eight'     => 8,
      'nine'      => 9,
      'ten'       => 10,
      'eleven'    => 11,
      'twelve'    => 12,
      'thirteen'  => 13,
      'fourteen'  => 14,
      'fifteen'   => 15,
      'sixteen'   => 16,
      'seventeen' => 17,
      'eighteen'  => 18,
      'nineteen'  => 19,
      'twenty'    => 20,
      'thirty'    => 30,
      'forty'     => 40,
      'fifty'     => 50,
      'sixty'     => 60,
      'seventy'   => 70,
      'eighty'    => 80,
      'ninety'    => 90
    }.freeze

    # Box wood/material adjectives recognized in rummaged box lists. Players
    # extend this via the +custom_box_woods+ setting; see
    # {Lich::DragonRealms::DRC.box_list_to_adj_and_noun}.
    BOX_WOODS = %w[brass copper deobar driftwood iron ironwood mahogany oaken pine steel wooden].freeze
    # Box container nouns recognized in rummaged box lists. Players extend this
    # via the +custom_box_containers+ setting.
    BOX_CONTAINERS = %w[box caddy casket chest coffer crate skippet strongbox trunk].freeze
    # Recognizes "<wood> <container>" box descriptions. Built from {BOX_WOODS}
    # and {BOX_CONTAINERS} so both remain a single source of truth; kept as a
    # global ($box_regex) for third-party scripts.
    BOX_REGEX = /((?:#{BOX_WOODS.join('|')}) (?:#{BOX_CONTAINERS.join('|')}))/.freeze

    # Mana adjectives grouped by mana development tier in DragonRealms.
    #
    # Maps each development level ("weak", "developing", "improving", "good") to an array
    # of adjectives that indicate mana at that tier (e.g., "weak" mana may appear "dim",
    # "glowing", or "bright"). Used to parse spell descriptions and estimate mana control.
    #
    # @return [Hash{String => Array<String>}] immutable mapping from tier to array of adjectives
    MANA_MAP = {
      'weak'       => %w[dim glowing bright].freeze,
      'developing' => %w[faint muted glowing luminous bright].freeze,
      'improving'  => %w[faint hazy flickering shimmering glowing lambent shining fulgent glaring].freeze,
      'good'       => %w[faint dim hazy dull muted dusky pale flickering shimmering pulsating glowing lambent shining luminous radiant fulgent brilliant flaring glaring blazing blinding].freeze
    }.freeze

    # Pattern matching primary (tier 1) sigil names in spell descriptions.
    #
    # Matches the five primary sigils: abolition, congruence, induction, permutation, rarefaction.
    #
    # @return [Regexp] immutable regex matching a primary sigil word
    # @example
    #   "abolition sigil" =~ PRIMARY_SIGILS_PATTERN #=> 0
    #   "congruence sigil" =~ PRIMARY_SIGILS_PATTERN #=> 0
    # @see SECONDARY_SIGILS_PATTERN
    PRIMARY_SIGILS_PATTERN = /\b(?:abolition|congruence|induction|permutation|rarefaction) sigil\b/.freeze
    # Pattern matching secondary (tier 2) sigil names in spell descriptions.
    #
    # Matches the ten secondary sigils: antipode, ascension, clarification, decay, evolution,
    # integration, metamorphosis, nurture, paradox, unity.
    #
    # @return [Regexp] immutable regex matching a secondary sigil word
    # @example
    #   "antipode sigil" =~ SECONDARY_SIGILS_PATTERN #=> 0
    #   "unity sigil" =~ SECONDARY_SIGILS_PATTERN #=> 0
    # @see PRIMARY_SIGILS_PATTERN
    SECONDARY_SIGILS_PATTERN = /\b(?:antipode|ascension|clarification|decay|evolution|integration|metamorphosis|nurture|paradox|unity) sigil\b/.freeze

    # Container volume categories in DragonRealms, mapped to numeric capacity values.
    #
    # Maps descriptive size adjectives ("enormous", "tiny", etc.) to numeric volume units.
    # Used to estimate storage capacity of containers based on their described size.
    #
    # @return [Hash{String => Integer}] immutable mapping from volume adjective to capacity value
    VOL_MAP = {
      'enormous' => 20,
      'massive'  => 10,
      'huge'     => 5,
      'large'    => 4,
      'medium'   => 3,
      'small'    => 2,
      'tiny'     => 1
    }.freeze

    # Backward compatibility aliases for global variables.
    # Third-party scripts may rely on these globals.
    $HOMETOWN_REGEX_MAP = HOMETOWN_REGEX_MAP
    $HOMETOWN_LIST = HOMETOWN_LIST
    $HOMETOWN_REGEX = HOMETOWN_REGEX
    $ORDINALS = ORDINALS
    $CURRENCIES = CURRENCIES
    $ENC_MAP = ENC_MAP
    $NUM_MAP = NUM_MAP
    $box_regex = BOX_REGEX
    $MANA_MAP = MANA_MAP
    $PRIMARY_SIGILS_PATTERN = PRIMARY_SIGILS_PATTERN
    $SECONDARY_SIGILS_PATTERN = SECONDARY_SIGILS_PATTERN
    $VOL_MAP = VOL_MAP
  end
end
