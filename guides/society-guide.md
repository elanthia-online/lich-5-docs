# Society Guide

This guide covers working with the three societies (Order of Voln, Council of Light, Guardians of Sunfist) in Lich scripts for GemStone IV.

## Overview

The `Society` class and its subclasses provide access to your character's society membership, rank, tasks, and abilities.

## Basic Society Information

```ruby
# Get your society membership
Society.membership    # "Order of Voln", "Council of Light", "Guardians of Sunfist", or nil
Society.status        # Alias for membership

# Get your rank
Society.rank          # 0-26 for Voln, 0-20 for others

# Get current society task
Society.task          # Task description or status message
```

### Checking Membership

```ruby
# Check if member of specific society
def voln_member?
  Society.membership == "Order of Voln"
end

def col_member?
  Society.membership == "Council of Light"
end

def sunfist_member?
  Society.membership == "Guardians of Sunfist"
end

# Check if in any society
def in_society?
  !Society.membership.nil? && Society.membership != "None"
end
```

## Order of Voln

The Order of Voln is dedicated to releasing undead from their suffering.

### Accessing Voln Data

```ruby
# Quick access
Societies.voln              # Returns OrderOfVoln class

# Or full path
Lich::Gemstone::Societies::OrderOfVoln
```

### Voln Favor

```ruby
# Get current favor
Societies::OrderOfVoln.favor

# Check favor level
favor = Societies::OrderOfVoln.favor
if favor > 1000
  echo "Plenty of favor"
elsif favor < 100
  echo "Low on favor!"
end
```

### Voln Symbols (Abilities)

Voln members gain Symbols as they progress through ranks:

| Rank | Symbol |
|------|--------|
| 1 | Symbol of Recognition |
| 2 | Symbol of Blessing |
| 3 | Symbol of Thought |
| 4 | Symbol of Diminishment |
| 5 | Symbol of Courage |
| 6 | Symbol of Protection |
| 7 | Symbol of Submission |
| 8 | Kai's Strike |
| 9 | Symbol of Holiness |
| 10 | Symbol of Recall |
| 11 | Symbol of Sleep |
| 12 | Symbol of Transcendence |
| 13 | Symbol of Mana |
| 14 | Symbol of Sight |
| 15 | Symbol of Retribution |
| 16 | Symbol of Supremacy |
| 17 | Symbol of Restoration |
| 18 | Symbol of Need |
| 19 | Symbol of Renewal |
| 20 | Symbol of Disruption |
| 21 | Kai's Smite |
| 22 | Symbol of Turning |
| 23 | Symbol of Preservation |
| 24 | Symbol of Dreams |
| 25 | Symbol of Return |
| 26 | Symbol of Seeking |

### Using Voln Symbols

```ruby
# Check if you know a symbol
if Society.rank >= 22
  echo "You know Symbol of Turning"
end

# Symbol costs vary - check favor before using
if Societies::OrderOfVoln.favor >= 50
  fput "symbol of turning"
end
```

## Council of Light

The Council of Light is a secretive society whose members employ Signs - short-duration magical abilities that cost small amounts of spirit (or nothing).

### Accessing CoL Data

```ruby
# Quick access
Societies.col               # Returns CouncilOfLight class

# Or full path
Lich::Gemstone::Societies::CouncilOfLight
```

### CoL Signs

Council of Light members gain Signs as they progress through ranks:

| Rank | Sign |
|------|------|
| 1 | Sign of Recognition |
| 2 | Sign of Signal |
| 3 | Sign of Warding |
| 4 | Sign of Striking |
| 5 | Sign of Clotting |
| 6 | Sign of Thought |
| 7 | Sign of Defending |
| 8 | Sign of Smiting |
| 9 | Sign of Staunching |
| 10 | Sign of Deflection |
| 11 | Sign of Hypnosis |
| 12 | Sign of Swords |
| 13 | Sign of Shields |
| 14 | Sign of Dissipation |
| 15 | Sign of Healing |
| 16 | Sign of Madness |
| 17 | Sign of Possession |
| 18 | Sign of Wracking |
| 19 | Sign of Darkness |
| 20 | Sign of Hopelessness |

## Guardians of Sunfist

The Guardians of Sunfist are a militant society; members employ Sigils - combat-oriented abilities fueled primarily by stamina.

### Accessing Sunfist Data

```ruby
# Quick access
Societies.sunfist           # Returns GuardiansOfSunfist class

# Or full path
Lich::Gemstone::Societies::GuardiansOfSunfist
```

### Sunfist Sigils

Sunfist members gain Sigils as they progress through ranks:

| Rank | Sigil |
|------|-------|
| 1 | Sigil of Recognition |
| 2 | Sigil of Location |
| 3 | Sigil of Contact |
| 4 | Sigil of Resolve |
| 5 | Sigil of Minor Bane |
| 6 | Sigil of Bandages |
| 7 | Sigil of Defense |
| 8 | Sigil of Offense |
| 9 | Sigil of Distraction |
| 10 | Sigil of Minor Protection |
| 11 | Sigil of Focus |
| 12 | Sigil of Intimidation |
| 13 | Sigil of Mending |
| 14 | Sigil of Concentration |
| 15 | Sigil of Major Bane |
| 16 | Sigil of Determination |
| 17 | Sigil of Health |
| 18 | Sigil of Power |
| 19 | Sigil of Major Protection |
| 20 | Sigil of Escape |

## Common Patterns

### Society-Based Script Behavior

```ruby
def use_society_ability
  case Society.membership
  when "Order of Voln"
    if Societies::OrderOfVoln.favor >= 100
      fput "symbol of courage"
    end
  when "Council of Light"
    fput "sign of striking"  # Example
  when "Guardians of Sunfist"
    fput "sigil of defense"  # Example
  else
    echo "Not in a society"
  end
end
```

### Checking for Undead (Voln)

```ruby
def should_use_symbol?
  return false unless voln_member?
  return false if Societies::OrderOfVoln.favor < 50

  # Check for undead targets
  GameObj.npcs.any? { |npc| npc.type?("undead") }
end
```

### Society Task Handling

```ruby
def check_society_task
  task = Society.task

  if task =~ /release.*undead/i
    echo "Voln eternal duty - release undead"
  elsif task =~ /not currently in a society/i
    echo "Not in a society"
  else
    echo "Current task: #{task}"
  end
end
```

### Rank-Based Features

```ruby
def available_abilities
  rank = Society.rank
  abilities = []

  case Society.membership
  when "Order of Voln"
    abilities << "Recognition" if rank >= 1
    abilities << "Blessing" if rank >= 2
    abilities << "Supremacy" if rank >= 16
    abilities << "Turning" if rank >= 22
  end

  abilities
end

# Check if specific ability is available
def has_voln_turning?
  voln_member? && Society.rank >= 22
end
```

### Resource Management

```ruby
# Voln favor management
def conserve_favor?
  return false unless voln_member?
  Societies::OrderOfVoln.favor < 200
end

def use_expensive_symbol?
  return false unless voln_member?
  Societies::OrderOfVoln.favor >= 500
end
```

## Society Serialization

```ruby
# Get society status as array
Society.serialize
# Returns: [membership, rank]
# Example: ["Order of Voln", 15]
```

## Deprecated Methods

These methods still work but are deprecated:

```ruby
# Old                    # New
Society.member           # Use Society.membership
Society.step             # Use Society.rank
Society.favor            # Use Societies::OrderOfVoln.favor
```

## See Also

- {Lich::Gemstone::Society} - Society class reference
- {Lich::Gemstone::Societies::OrderOfVoln} - Voln reference
- {Lich::Gemstone::Societies::CouncilOfLight} - CoL reference
- {Lich::Gemstone::Societies::GuardiansOfSunfist} - Sunfist reference
- {file:guides/scripting-basics.md Scripting Basics} - Core scripting concepts
- {file:guides/spells-guide.md Spells Guide} - Working with spells
