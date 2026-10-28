## hot module reloading
require 'rbconfig'

# Namespace for the Lich 5 scripting engine.
module Lich
  # Namespace for utilities common to Lich scripts.
  module Common
    # Hot Module Reloading: utilities to safely reload script files without restarting the engine.
    #
    # Reloading a file that belongs to Ruby's standard library or an installed gem is skipped
    # because those libraries are not written to be re-executed and doing so can corrupt their
    # state (e.g., stack overflow with REXML). User .lic scripts and Lich's own modules are
    # safe to reload and will be reloaded on demand, with error reporting to the game client.
    module HMR
      # What a reload of one file may raise and still leave Lich running.
      # StandardError alone misses the common failures: a typo in the edited
      # file is a SyntaxError (a ScriptError), and a file whose body is not
      # safe to re-run can overflow the stack (SystemStackError). Either one
      # used to escape into the client thread and stop it reading input.
      RELOAD_ERRORS = [StandardError, ScriptError, SystemStackError].freeze

      # Most backtrace lines printed for a failed reload. A stack overflow's
      # backtrace repeats one frame about 10,000 times; printing it all would
      # flood the frontend.
      BACKTRACE_LINES = 25

      # Most skipped file names printed; the rest are counted. `;hmr xml`
      # alone skips about 34 rexml files.
      SKIPPED_NAMES = 5

      # RbConfig keys for Ruby's own library directories.
      RUBY_LIB_DIR_KEYS = %w[rubylibdir rubyarchdir sitelibdir sitearchdir vendorlibdir vendorarchdir].freeze

      # Clears cached gem paths to ensure the next reload picks up newly installed gems.
      #
      # @return [void]
      # @api private
      def self.clear_cache
        Gem.clear_paths
      end

      # Sends a message to the game client with visual formatting.
      #
      # Uses the client's high-fidelity `_respond` method if available and the message contains
      # HTML tags; falls back to `respond` for plain text; outputs to stdout if neither method
      # is defined.
      #
      # @param message [String] the text to send; may contain HTML markup like "<b>" and "</b>"
      # @return [void]
      # @api private
      def self.msg(message)
        return _respond message if defined?(:_respond) && message.include?("<b>")
        return respond message if defined?(:respond)
        puts message
      end

      # Returns all currently loaded Ruby files.
      #
      # @return [Array<String>] file paths from $LOADED_FEATURES that end with .rb
      # @api private
      def self.loaded
        $LOADED_FEATURES.select { |path| path.end_with?(".rb") }
      end

      # Directories holding Ruby's standard library and installed gems,
      # resolved through symlinks so they compare with resolved file paths.
      # Returned as bytes (BINARY): RbConfig's strings are BINARY and feature
      # paths are UTF-8. Once both hold a non-ASCII character (Ruby and Lich
      # both under a home directory whose name is not ASCII),
      # String#start_with? raises Encoding::CompatibilityError instead of
      # comparing them.
      #
      # @return [Array<String>] each ending in a path separator
      def self.foreign_roots
        dirs = RUBY_LIB_DIR_KEYS.map { |key| RbConfig::CONFIG[key] }
        dirs.concat(Gem.path)
        dirs.concat(Gem.loaded_specs.values.map(&:full_gem_path))
        dirs.compact.reject(&:empty?).filter_map do |dir|
          File.join(File.realpath(dir), '').b
        rescue SystemCallError
          nil
        end.uniq
      end

      # True for a loaded file that is not Lich's to reload: part of Ruby
      # itself or of an installed gem. Their bodies are not written to be
      # re-run; reloading rexml (which `;hmr xml` matches) overflows the stack
      # and leaves REXML broken for the rest of the session.
      #
      # @param path [String] a $LOADED_FEATURES entry
      # @param roots [Array<String>] from {foreign_roots}
      # @return [Boolean]
      def self.foreign?(path, roots)
        # Ruby records some built-in features (thread.rb, set.rb) without a
        # path; load would resolve them against $LOAD_PATH.
        return true unless File.absolute_path?(path)

        real = begin
          File.realpath(path)
        rescue SystemCallError
          path
        end.b
        roots.any? { |root| real.start_with?(root) }
      end

      # @param backtrace [Array<String>, nil]
      # @return [String] at most {BACKTRACE_LINES} lines, then a count of the rest
      def self.format_backtrace(backtrace)
        lines = Array(backtrace)
        shown = lines.first(BACKTRACE_LINES)
        hidden = lines.size - shown.size
        shown << "... #{hidden} more backtrace lines" if hidden.positive?
        shown.join("\n")
      end

      # @param skipped [Array<String>] the matched files that were not reloaded
      # @return [String] the count, the first {SKIPPED_NAMES} basenames, and
      #   how many more were left out
      def self.skipped_message(skipped)
        names = skipped.first(SKIPPED_NAMES).map { |file| File.basename(file) }.join(", ")
        more = skipped.size - SKIPPED_NAMES
        names += " and #{more} more" if more.positive?
        "<b>[lich.hmr] skipped %d file(s) that belong to Ruby or an installed gem: %s</b>" % [skipped.size, names]
      end

      # Reloads all loaded script files matching a regex pattern, excluding Ruby standard library and gem files.
      #
      # Clears the gem cache, then finds all .rb files in $LOADED_FEATURES that match the pattern.
      # Files belonging to Ruby's standard library or installed gems are skipped with a message
      # listing the first few skipped names. For each user script or Lich module that is reloaded,
      # a success message is printed; if reloading raises StandardError, ScriptError, or
      # SystemStackError, the exception message and backtrace (capped at 25 lines) are printed
      # and execution continues to the next file.
      #
      # @param pattern [Regexp] a regular expression to match against $LOADED_FEATURES paths
      # @return [void]
      # @example Reload all scripts matching 'hunt'
      #   Lich::Common::HMR.reload(/hunt/)
      # @api private
      def self.reload(pattern)
        self.clear_cache
        matched = self.loaded.grep(pattern)
        roots = self.foreign_roots unless matched.empty?
        skipped, loaded_paths = matched.partition { |file| self.foreign?(file, roots) }
        unless skipped.empty?
          self.msg self.skipped_message(skipped)
        end
        unless loaded_paths.empty?
          loaded_paths.each { |file|
            begin
              load(file)
              self.msg "<b>[lich.hmr] reloaded %s</b>" % file
            rescue *RELOAD_ERRORS => exception
              self.msg exception.message
              self.msg self.format_backtrace(exception.backtrace)
            end
          }
        else
          self.msg "<b>[lich.hmr] nothing matching regex pattern: %s</b>" % pattern.source if skipped.empty?
        end
      end
    end
  end
end
