# handles instances of modules that are game dependent

# Namespace for the Lich scripting engine.
module Lich
  # Namespace for shared code across all supported games.
  module Common
    # Loads game-specific and common modules based on the running game.
    #
    # Call .load! to initialize the Lich runtime with all required dependencies
    # for GemStone IV or DragonRealms.
    module GameLoader
      # Loads shared modules required by all games.
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

      # Loads all modules and dependencies for GemStone IV.
      #
      # Initializes character attributes, game-specific features (bounties, society,
      # combat tracking, etc.), and enables active spell and infomon watchers.
      #
      # @return [void]
      # @api private
      def self.gemstone
        self.common_before
        require File.join(LIB_DIR, 'gemstone', 'sk.rb')
        require File.join(LIB_DIR, 'common', 'map', 'map_gs.rb')
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
        require File.join(LIB_DIR, 'gemstone', 'infomon', 'status.rb')
        require File.join(LIB_DIR, 'gemstone', 'experience.rb')
        require File.join(LIB_DIR, 'attributes', 'spellsong.rb')
        require File.join(LIB_DIR, 'gemstone', 'infomon', 'activespell.rb')
        require File.join(LIB_DIR, 'gemstone', 'psms.rb')
        require File.join(LIB_DIR, 'attributes', 'char.rb')
        require File.join(LIB_DIR, 'gemstone', 'currency.rb')
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
        ActiveSpell.watch!
        Infomon.watch!
        self.common_after
      end

      # Loads all modules and dependencies for DragonRealms.
      #
      # Initializes character attributes, game-specific features (infomon, creatures,
      # settings), and enables the infomon watcher.
      #
      # @return [void]
      # @api private
      def self.dragon_realms
        self.common_before
        require File.join(LIB_DIR, 'common', 'map', 'map_dr.rb')
        require File.join(LIB_DIR, 'attributes', 'char.rb')
        require File.join(LIB_DIR, 'dragonrealms', 'dependency', 'settings_config.rb')
        require File.join(LIB_DIR, 'dragonrealms', 'drinfomon.rb')
        require File.join(LIB_DIR, 'dragonrealms', 'commons.rb')
        require File.join(LIB_DIR, 'dragonrealms', 'creature.rb')
        DRInfomon.watch!
        self.common_after
      end

      # Registers post-load hooks to initialize game settings.
      #
      # Seeds a valid client record on the game server when the character has never
      # logged in with the Wrayth client, ensuring properly formatted settingsInfo
      # on future connections.
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

      # Loads game-specific modules and initializes the Lich runtime.
      #
      # Blocks until the game is identified from the XML data stream, then delegates
      # to either .gemstone or .dragon_realms.
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
