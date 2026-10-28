# handles instances of modules that are game dependent

# Namespace for Lich 5, a Ruby scripting engine for text-based games.
module Lich
  # Namespace for common, game-agnostic utilities shared across Lich 5.
  module Common
    # Loader for game-dependent modules and features.
    #
    # Handles conditional loading of GemStone IV and DragonRealms-specific code,
    # along with shared initialization that applies to both games.
    module GameLoader
      # Loads common modules required before any game-specific initialization.
      #
      # @return [void]
      # @api private
      def self.common_before
        require File.join(LIB_DIR, 'common', 'account.rb')
        require File.join(LIB_DIR, 'common', 'log.rb')
        require File.join(LIB_DIR, 'common', 'spell.rb')
        require File.join(LIB_DIR, 'util', 'util.rb')
        require File.join(LIB_DIR, 'util', 'textstripper.rb')
        require File.join(LIB_DIR, 'common', 'hmr.rb')
      end

      # Loads GemStone IV-specific modules and initializes watchers.
      #
      # Requires all GemStone-specific game mechanics including skills, spells, combat,
      # infomon state tracking, and client detachability support. Registers `ActiveSpell`
      # and `Infomon` watchers to track real-time state changes.
      #
      # @return [void]
      # @api private
      def self.gemstone
        self.common_before
        require File.join(LIB_DIR, 'gemstone', 'sk.rb')
        require File.join(LIB_DIR, 'common', 'map', 'map_gs.rb')
        require File.join(LIB_DIR, 'gemstone', 'xml_delta.rb')
        require File.join(LIB_DIR, 'gemstone', 'effects.rb')
        require File.join(LIB_DIR, 'gemstone', 'bounty.rb')
        require File.join(LIB_DIR, 'gemstone', 'claim.rb')
        require File.join(LIB_DIR, 'gemstone', 'overwatch.rb')
        require File.join(LIB_DIR, 'gemstone', 'infomon.rb')
        require File.join(LIB_DIR, 'attributes', 'resources.rb')
        require File.join(LIB_DIR, 'attributes', 'stats.rb')
        require File.join(LIB_DIR, 'attributes', 'spells.rb')
        require File.join(LIB_DIR, 'attributes', 'skills.rb')
        require File.join(LIB_DIR, 'attributes', 'enhancive.rb')
        require File.join(LIB_DIR, 'gemstone', 'society.rb')
        require File.join(LIB_DIR, 'gemstone', 'fog.rb')
        require File.join(LIB_DIR, 'gemstone', 'infomon', 'status.rb')
        require File.join(LIB_DIR, 'gemstone', 'stance.rb')
        require File.join(LIB_DIR, 'gemstone', 'mana.rb')
        require File.join(LIB_DIR, 'gemstone', 'experience.rb')
        require File.join(LIB_DIR, 'attributes', 'spellsong.rb')
        require File.join(LIB_DIR, 'gemstone', 'infomon', 'activespell.rb')
        require File.join(LIB_DIR, 'gemstone', 'psms.rb')
        require File.join(LIB_DIR, 'attributes', 'char.rb')
        require File.join(LIB_DIR, 'gemstone', 'currency.rb')
        require File.join(LIB_DIR, 'gemstone', 'bank.rb')
        # require File.join(LIB_DIR, 'gemstone', 'character', 'disk.rb') # dup
        require File.join(LIB_DIR, 'gemstone', 'group.rb')
        require File.join(LIB_DIR, 'gemstone', 'critranks')
        require File.join(LIB_DIR, 'gemstone', 'injured')
        require File.join(LIB_DIR, 'gemstone', 'wounds.rb')
        require File.join(LIB_DIR, 'gemstone', 'scars.rb')
        require File.join(LIB_DIR, 'gemstone', 'gift.rb')
        # require File.join(LIB_DIR, 'gemstone', 'creature.rb') # combat tracker below loads this so not needed to preload
        require File.join(LIB_DIR, 'gemstone', 'combat', 'tracker.rb')
        require File.join(LIB_DIR, 'gemstone', 'readylist.rb')
        require File.join(LIB_DIR, 'gemstone', 'stowlist.rb')
        require File.join(LIB_DIR, 'gemstone', 'armaments.rb')
        require File.join(LIB_DIR, 'gemstone', 'detachable_client_init.rb')
        ActiveSpell.watch!
        Infomon.watch!
        self.common_after
      end

      # Loads DragonRealms-specific modules and initializes watchers.
      #
      # Requires all DragonRealms-specific game mechanics including XML delta parsing,
      # settings configuration, creature tracking, and client detachability support.
      # Registers `DRInfomon` watcher to track real-time state changes.
      #
      # @return [void]
      # @api private
      def self.dragon_realms
        self.common_before
        require File.join(LIB_DIR, 'common', 'map', 'map_dr.rb')
        require File.join(LIB_DIR, 'dragonrealms', 'xml_delta.rb')
        require File.join(LIB_DIR, 'attributes', 'char.rb')
        require File.join(LIB_DIR, 'dragonrealms', 'dependency', 'settings_config.rb')
        require File.join(LIB_DIR, 'dragonrealms', 'drinfomon.rb')
        require File.join(LIB_DIR, 'dragonrealms', 'commons.rb')
        require File.join(LIB_DIR, 'dragonrealms', 'creature.rb')
        require File.join(LIB_DIR, 'dragonrealms', 'detachable_client_init.rb')
        DRInfomon.watch!
        self.common_after
      end

      # Performs post-load initialization common to both games.
      #
      # Registers a `PostLoad` hook to handle malformed settingsInfo XML from the game
      # server. If the server sends invalid XML (indicating the character has never logged
      # in with the Wrayth client), sends a dummy `<db>` command to seed a valid client
      # record so future connections receive properly formatted settingsInfo.
      #
      # @return [void]
      # @api private
      def self.common_after
        require File.join(LIB_DIR, 'common', 'postload.rb')
        PostLoad.register("settings_init") do
          # When the game server sends malformed <settingsInfo  space not found ...> XML,
          # it means this character has never logged in with the Wrayth client.
          # Game.fix_invalid_settings_info patches the XML and sets the flag.
          # Here we send a dummy <db> command to seed a valid client record so
          # the server sends properly formatted settingsInfo on future connects.
          if GameBase::Game.settings_init_needed?
            Game._puts("<db><settings client='1.0.1.28'></settings>")
          end
        end
        PostLoad.watch!
      end

      # Detects the current game and loads its game-specific modules.
      #
      # Blocks until XMLData.game is populated by the game server, then loads either
      # GemStone IV or DragonRealms code based on the game identifier. Echoes a warning
      # to the console if the game identifier does not match either game.
      #
      # @return [void]
      # @api private
      def self.load!
        sleep 0.1 while XMLData.game.nil? or XMLData.game.empty?
        return self.dragon_realms if XMLData.game =~ /DR/
        return self.gemstone if XMLData.game =~ /GS/
        echo "could not load game specifics for %s" % XMLData.game
      end
    end
  end
end
