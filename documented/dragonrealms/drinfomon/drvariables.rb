# frozen_string_literal: true

# Lich scripting engine for GemStone IV and DragonRealms.
module Lich
  # DragonRealms-specific constants and configuration data.
  module DragonRealms
    # Learning rates for skills in DragonRealms, ordered from slowest to fastest.
    #
    # @return [Array<String>] skill learning rate names, from 'clear' through 'mind lock'
    # @example
    #   DR_LEARNING_RATES[0]  #=> "clear"
    #   DR_LEARNING_RATES[-1] #=> "mind lock"
    # @see DR_LONGEST_LEARNING_RATE_LENGTH
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

    # Balance quality descriptors used in combat positioning.
    #
    # @return [Array<String>] balance descriptors ordered from worst to best
    # @see DR_POSITION_VALUES
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

    # Skill tree structure and guild-specific skill aliases for DragonRealms.
    #
    # Contains two sections:
    # - `skillsets`: Maps skill category names ('Armor', 'Lore', 'Weapon', 'Magic',
    #   'Survival') to arrays of individual skills within that category.
    # - `guild_skill_aliases`: Maps guild names to hashes of skill name substitutions.
    #   For example, Clerics use 'Holy Magic' where the base skill is 'Primary Magic'.
    #
    # @return [Hash] skill tree with :skillsets and :guild_skill_aliases keys
    # @example
    #   DR_SKILLS_DATA[:skillsets]["Magic"]        #=> ["Primary Magic", "Arcana", ...]
    #   DR_SKILLS_DATA[:guild_skill_aliases]["Cleric"] #=> {"Primary Magic"=>"Holy Magic"}
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

    # Towns with banks that accept Kronar currency.
    #
    # @return [Array<String>] bank location names
    KRONAR_BANKS = ['Crossings', 'Dirge', 'Ilaya Taipa', 'Leth Deriel'].freeze
    # Towns with banks that accept Lirum currency.
    #
    # @return [Array<String>] bank location names
    LIRUM_BANKS = ["Aesry Surlaenis'a", "Hara'jaal", "Mer'Kresh", "Muspar'i", 'Ratha', 'Riverhaven', "Rossman's Landing", 'Therenborough', 'Throne City'].freeze
    # Towns with banks that accept Dokora currency.
    #
    # @return [Array<String>] bank location names
    DOKORA_BANKS = ['Ain Ghazal', 'Boar Clan', "Chyolvea Tayeu'a", 'Hibarnhvidar', 'Fang Cove', "Raven's Point", 'Shard'].freeze

    # In-game room titles for bank deposit and teller windows by location.
    #
    # Keys are town names; values are arrays of room titles where banking transactions
    # can occur. Rooms are specified in the Lich room reference format [[location, descriptor]].
    #
    # @return [Hash{String => Array<String>}] mapping town names to room title arrays
    # @example
    #   BANK_TITLES["Leth Deriel"] #=> ["[[Imperial Depository, Domestic Branch]]"]
    # @see VAULT_TITLES
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

    # In-game room titles for vault carousel chambers by location.
    #
    # Keys are town names; values are arrays of room titles where vault storage can
    # be accessed. Not all towns with banks have vaults.
    #
    # @return [Hash{String => Array<String>}] mapping town names to vault room title arrays
    # @example
    #   VAULT_TITLES["Crossing"] #=> ["[[Crossing, Carousel Chamber]]"]
    # @see BANK_TITLES
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

    # Regular expressions that match player-input abbreviations and variations for each town.
    #
    # Keys are canonical town names; values are case-insensitive regexes that accept
    # common abbreviations and alternate spellings. Used to normalize user input.
    #
    # @return [Hash{String => Regexp}] mapping canonical names to abbreviation patterns
    # @example
    #   HOMETOWN_REGEX_MAP["Therenborough"].match?("theren")  #=> true
    #   HOMETOWN_REGEX_MAP["Langenfirth"].match?("lang")      #=> true
    # @see HOMETOWN_LIST, HOMETOWN_REGEX
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

    # English ordinal words from first to twentieth.
    #
    # @return [Array<String>] ordinal number names
    ORDINALS = %w[first second third fourth fifth sixth seventh eighth ninth tenth eleventh twelfth thirteenth fourteenth fifteenth sixteenth seventeenth eighteenth nineteenth twentieth].freeze

    # Currency types recognized in DragonRealms.
    #
    # @return [Array<String>] currency names
    CURRENCIES = %w[Kronars Lirums Dokoras].freeze

    # Character encumbrance levels and their numeric indices.
    #
    # Keys are encumbrance descriptors from game output (e.g., "You are carrying
    # a light burden"); values are numeric severity levels from 0 (no burden) to 11
    # (extreme burden).
    #
    # @return [Hash{String => Integer}] mapping encumbrance descriptions to levels
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

    # English number words mapped to their integer equivalents.
    #
    # Covers zero through twenty and tens (thirty, forty, etc. up to ninety).
    #
    # @return [Hash{String => Integer}] mapping number words to integers
    # @example
    #   NUM_MAP["five"]  #=> 5
    #   NUM_MAP["twenty"] #=> 20
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

    # Mana level descriptors grouped by skill training stage.
    #
    # Each key represents a training phase; values are arrays of adjectives that
    # describe the character's mana reserves at that stage. Used to assess spell
    # readiness and casting potential.
    #
    # @return [Hash{String => Array<String>}] mapping skill stage names to mana descriptors
    # @example
    #   MANA_MAP["good"] #=> ["faint", "dim", "hazy", ...] (13 descriptors)
    MANA_MAP = {
      'weak'       => %w[dim glowing bright].freeze,
      'developing' => %w[faint muted glowing luminous bright].freeze,
      'improving'  => %w[faint hazy flickering shimmering glowing lambent shining fulgent glaring].freeze,
      'good'       => %w[faint dim hazy dull muted dusky pale flickering shimmering pulsating glowing lambent shining luminous radiant fulgent brilliant flaring glaring blazing blinding].freeze
    }.freeze

    # Pattern matching primary sigil types in spell or ability names.
    #
    # Matches word boundaries around sigil names: abolition, congruence, induction,
    # permutation, or rarefaction.
    #
    # @return [Regexp] pattern for primary sigils
    # @example
    #   "congruence sigil" =~ PRIMARY_SIGILS_PATTERN #=> 0
    #   "abolition sigil"  =~ PRIMARY_SIGILS_PATTERN #=> 0
    # @see SECONDARY_SIGILS_PATTERN
    PRIMARY_SIGILS_PATTERN = /\b(?:abolition|congruence|induction|permutation|rarefaction) sigil\b/.freeze
    # Pattern matching secondary sigil types in spell or ability names.
    #
    # Matches word boundaries around sigil names: antipode, ascension, clarification,
    # decay, evolution, integration, metamorphosis, nurture, paradox, or unity.
    #
    # @return [Regexp] pattern for secondary sigils
    # @example
    #   "decay sigil"       =~ SECONDARY_SIGILS_PATTERN #=> 0
    #   "unity sigil"       =~ SECONDARY_SIGILS_PATTERN #=> 0
    # @see PRIMARY_SIGILS_PATTERN
    SECONDARY_SIGILS_PATTERN = /\b(?:antipode|ascension|clarification|decay|evolution|integration|metamorphosis|nurture|paradox|unity) sigil\b/.freeze

    # Object volume descriptors mapped to approximate container sizes.
    #
    # Keys are size adjectives; values are numeric volume estimates used to estimate
    # container capacity and item bulk.
    #
    # @return [Hash{String => Integer}] mapping size descriptors to volume units
    # @example
    #   VOL_MAP["large"]   #=> 4
    #   VOL_MAP["colossal"] #=> 200
    VOL_MAP = {
      'colossal' => 200,
      'gigantic' => 100,
      'immense'  => 50,
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
