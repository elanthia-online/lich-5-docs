require 'time'
require_relative 'common/sqlite_connection'
# Namespace for Lich 5 scripting engine core functionality, including database
# management, display settings, host configuration, and deprecated legacy accessors.
#
# Most user scripts interact with Lich through {Vars}, {Script}, and other specific
# modules rather than directly calling Lich.* methods. See individual method
# documentation for their public contracts.
module Lich
  # --- Minimal DB maintenance helpers (simple + safe) ---
  # Stores last maintenance timestamp and summary in lich_settings.
  # Uses an advisory OS file lock so only one Lich instance attempts VACUUM.
  def Lich.db_maint_lock_path
    File.join(DATA_DIR, 'lich.db3.maint.lock')
  end

  # Retrieves the timestamp of the last database maintenance operation.
  #
  # Reads from the lich_settings table and retries on SQLite3::BusyException.
  # Returns nil if the setting does not exist or if a read error occurs (other than
  # busy contention).
  #
  # @return [String, nil] ISO 8601 UTC timestamp, or nil if no maintenance has been recorded
  def Lich.db_maint_last_at
    ts = nil
    begin
      ts = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='db_maint_last_at';")
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    rescue => e
      Lich.log "db_maint_last_at error: #{e}"
    end
    ts
  end

  # Records a database maintenance operation with timestamp and optional summary.
  #
  # Creates the lich_settings table if it does not exist, then writes the
  # db_maint_last_at and db_maint_last_note settings via INSERT OR REPLACE.
  # The note is UTF-8 encoded before storage. Retries on SQLite3::BusyException.
  #
  # @param iso_utc [String] ISO 8601 UTC timestamp (e.g., from Time.now.utc.iso8601)
  # @param note [String] optional summary of the maintenance operation (default '')
  # @return [void]
  def Lich.db_maint_set!(iso_utc, note = '')
    begin
      Lich.db.execute("CREATE TABLE IF NOT EXISTS lich_settings (name TEXT NOT NULL, value TEXT, PRIMARY KEY(name));")
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name, value) VALUES('db_maint_last_at', ?);", [iso_utc])
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name, value) VALUES('db_maint_last_note', ?);", [note.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    rescue => e
      Lich.log "db_maint_set! error: #{e}"
    end
  end

  # Determines whether database maintenance is due based on elapsed time.
  #
  # Returns true if no maintenance timestamp is recorded, or if the last recorded
  # time is older than the specified number of months. Treats the timestamp as
  # ISO 8601 and compares against the current UTC time. Returns true on parse errors
  # or if last_at is nil.
  #
  # @param months [Integer] interval in months between maintenance operations (default 6)
  # @return [Boolean] true if VACUUM should be attempted, false otherwise
  def Lich.db_maint_due?(months = 6)
    last = Lich.db_maint_last_at
    return true if last.nil? || last.empty?
    begin
      cutoff = Time.now.utc - (months * 30 * 24 * 60 * 60)
      last_t = Time.parse(last) rescue nil
      return true if last_t.nil?
      last_t < cutoff
    rescue => e
      Lich.log "db_maint_due? parse error: #{e}"
      true
    end
  end

  # Try VACUUM if due. If the DB is busy (another process), skip and try next run.
  def Lich.db_vacuum_if_due!(months: 6, lock_timeout_s: 0.5)
    return :skipped_recent unless Lich.db_maint_due?(months)

    lock_path = Lich.db_maint_lock_path
    File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |f|
      start = Time.now
      got = false
      begin
        got = f.flock(File::LOCK_EX | File::LOCK_NB)
      rescue => e
        Lich.log "db_maint flock error: #{e}"
      end
      unless got
        while (Time.now - start) < lock_timeout_s && !got
          sleep 0.1
          begin
            got = f.flock(File::LOCK_EX | File::LOCK_NB)
          rescue SystemCallError, IOError
            # Transient error acquiring lock on some filesystems; back off and retry.
            sleep 0.05
          end
        end
      end
      return :skipped_lock_held unless got

      begin
        page_count_before     = Lich.db.get_first_value('PRAGMA page_count;').to_i
        freelist_count_before = Lich.db.get_first_value('PRAGMA freelist_count;').to_i
      rescue SQLite3::BusyException
        Lich.log "db_maint: busy reading stats; skipping"
        return :skipped_busy
      end

      begin
        mode = Lich.db.get_first_value('PRAGMA journal_mode;')
        if mode && mode.to_s.strip.upcase == 'WAL'
          Lich.db.execute('PRAGMA wal_checkpoint(TRUNCATE);')
        end
      rescue SQLite3::SQLException => e
        Lich.log "db_maint: checkpoint skipped (#{e.class}: #{e.message})"
      end

      begin
        Lich.db.execute('VACUUM;')
      rescue SQLite3::BusyException => e
        Lich.log "db_maint: VACUUM busy; skipping (#{e.message})"
        return :skipped_busy
      rescue => e
        Lich.log "db_maint: VACUUM error: #{e}"
        return :error
      end

      page_count_after     = Lich.db.get_first_value('PRAGMA page_count;').to_i rescue 0
      freelist_count_after = Lich.db.get_first_value('PRAGMA freelist_count;').to_i rescue 0
      note = "VACUUM ok pages #{page_count_before}->#{page_count_after}, free #{freelist_count_before}->#{freelist_count_after}"
      Lich.db_maint_set!(Time.now.utc.iso8601, note)
      :vacuum_ok
    end
  end

  @@hosts_file           = nil
  @@lich_db              = nil
  @@last_warn_deprecated = 0
  @@deprecated_log       = []

  @@db_mutex ||= Mutex.new
  @display_settings_mutex ||= Mutex.new

  # Display caches are reset on reload, like the former individual fields.
  @display_settings_cache = {}
  @display_read_retry_at = nil
  @display_uid_retry_at = nil

  # settings
  @@keep_fe_string       = nil # boolean
  @@track_autosort_state = nil # boolean
  @@track_dark_mode      = nil # boolean
  @@track_layout_state   = nil # boolean
  @@track_persistent_launcher_mode = nil # boolean
  @@debug_messaging = nil # boolean
  @@max_debug_logs  = nil # integer

  # Returns the Mutex protecting access to Lich.db.
  #
  # @return [Mutex] the shared database mutex
  def self.db_mutex
    @@db_mutex
  end

  # Acquires the database mutex if not already owned by the current thread.
  #
  # Logs errors to stderr and sends a respond message on acquisition failure.
  # Does nothing if the mutex is already held by this thread.
  #
  # @return [void]
  def self.mutex_lock
    begin
      self.db_mutex.lock unless self.db_mutex.owned?
    rescue StandardError
      respond "--- Lich: error: Lich.mutex_lock: #{$!}"
      Lich.log "error: Lich.mutex_lock: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
    end
  end

  # Releases the database mutex if currently owned by the calling thread.
  #
  # Logs errors to stderr and sends a respond message on release failure.
  # Does nothing if the mutex is not currently owned by this thread.
  #
  # @return [void]
  def self.mutex_unlock
    begin
      self.db_mutex.unlock if self.db_mutex.owned?
    rescue StandardError
      respond "--- Lich: error: Lich.mutex_unlock: #{$!}"
      Lich.log "error: Lich.mutex_unlock: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
    end
  end

  # Delegates deprecated Lich.* variable access to Vars.*.
  #
  # Emits a deprecation warning (at most once per 5 minutes) directing script authors
  # to use Vars instead. Calls are delegated transparently to Vars.method_missing.
  #
  # @param arg1 [Object] the variable name or method call
  # @param arg2 [String] optional secondary argument (default '')
  # @return [Object] the result of delegating to Vars
  # @api private
  def Lich.method_missing(arg1, arg2 = '')
    if (Time.now.to_i - @@last_warn_deprecated) > 300
      respond "--- warning: Lich.* variables will stop working in a future version of Lich.  Use Vars.* (offending script: #{Script.current.name || 'unknown'})"
      @@last_warn_deprecated = Time.now.to_i
    end
    Vars.method_missing(arg1, arg2)
  end

  # Locates the installation path for a game front-end by name.
  #
  # Uses Lich::Common::FrontendLocator if available; falls back to legacy global
  # variables ($wiz_fe_loc, $sf_fe_loc) for Wizard and Stormfront respectively.
  #
  # @param fe [String] front-end identifier (e.g., "wizard", "stormfront")
  # @return [String, nil] the front-end installation path, or nil if not found
  def Lich.seek(fe)
    if defined?(Lich::Common::FrontendLocator)
      return Lich::Common::FrontendLocator.compatibility_location(fe)
    end

    return $wiz_fe_loc if fe =~ /wizard/
    return $sf_fe_loc if fe =~ /stormfront/

    nil
  end

  # WARNING: do not call Lich.db.transaction { } (or run BEGIN/COMMIT by hand
  # on Lich.db) without handling a failed or interrupted COMMIT. If the thread
  # is killed while COMMIT waits for the lock, the transaction stays open on
  # this shared connection and holds the write lock until Lich exits. Nothing
  # calls Lich.db.transaction today. Databases opened with
  # Lich.open_sequel_sqlite roll back a failed or interrupted COMMIT; see
  # SQLiteBusyWait::Transactions.
  def Lich.db
    @@lich_db ||= open_sqlite_db("#{DATA_DIR}/lich.db3")
  end

  # Initializes the Lich database schema on first run.
  #
  # Creates all core tables if they do not exist: script_setting, script_auto_settings,
  # lich_settings, uservars, session_summary_state, and indexes. Applies idempotent
  # ALTER TABLE statements for backward-compatible migration (tolerating duplicate
  # column errors). Retries on SQLite3::BusyException.
  #
  # Called once at Lich startup to ensure the database structure is ready.
  #
  # @return [void]
  def Lich.init_db
    begin
      Lich.db.execute("CREATE TABLE IF NOT EXISTS script_setting (script TEXT NOT NULL, name TEXT NOT NULL, value BLOB, PRIMARY KEY(script, name));")
      Lich.db.execute("CREATE TABLE IF NOT EXISTS script_auto_settings (script TEXT NOT NULL, scope TEXT, hash BLOB, PRIMARY KEY(script, scope));")
      Lich.db.execute("CREATE TABLE IF NOT EXISTS lich_settings (name TEXT NOT NULL, value TEXT, PRIMARY KEY(name));")
      Lich.db.execute("CREATE TABLE IF NOT EXISTS uservars (scope TEXT NOT NULL, hash BLOB, PRIMARY KEY(scope));")
      # Session summary reporting table for process-level heartbeat metadata.
      # This schema is initialized with the rest of core DB setup to avoid
      # runtime DDL lock contention on first adapter access.
      Lich.db.execute("CREATE TABLE IF NOT EXISTS session_summary_state (pid INTEGER PRIMARY KEY, session_name TEXT, role TEXT, state TEXT, frontend TEXT, game_code TEXT, hidden INTEGER DEFAULT 0, started_at INTEGER, last_heartbeat_at INTEGER, os_seen_at INTEGER, os_seen INTEGER, os_name INTEGER, last_utilization_at INTEGER, metadata_json TEXT);")
      Lich.db.execute("CREATE INDEX IF NOT EXISTS idx_session_summary_state_session_name ON session_summary_state(session_name);")
      Lich.db.execute("CREATE INDEX IF NOT EXISTS idx_session_summary_state_heartbeat ON session_summary_state(last_heartbeat_at);")
      # Backward-compatible migration guards:
      # In dev/test transitions, older local tables may be missing newer columns.
      # We keep these ALTER blocks idempotent by tolerating duplicate-column errors.
      begin
        Lich.db.execute("ALTER TABLE session_summary_state ADD COLUMN os_seen_at INTEGER;")
      rescue SQLite3::SQLException => e
        raise unless e.message.include?('duplicate column name')
      end
      begin
        Lich.db.execute("ALTER TABLE session_summary_state ADD COLUMN os_seen INTEGER;")
      rescue SQLite3::SQLException => e
        raise unless e.message.include?('duplicate column name')
      end
      begin
        Lich.db.execute("ALTER TABLE session_summary_state ADD COLUMN os_name INTEGER;")
      rescue SQLite3::SQLException => e
        raise unless e.message.include?('duplicate column name')
      end
      if (RUBY_VERSION =~ /^2\.[012]\./)
        Lich.db.execute("CREATE TABLE IF NOT EXISTS trusted_scripts (name TEXT NOT NULL);")
      end
      Lich.db.execute("CREATE TABLE IF NOT EXISTS simu_game_entry (character TEXT NOT NULL, game_code TEXT NOT NULL, data BLOB, PRIMARY KEY(character, game_code));")
      Lich.db.execute("CREATE TABLE IF NOT EXISTS enable_inventory_boxes (player_id INTEGER NOT NULL, PRIMARY KEY(player_id));")
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end

  # Disabled stub for class variable access.
  #
  # Always returns nil. Prevents scripts from calling Lich.class_variable_get.
  #
  # @return [nil]
  # @api private
  def Lich.class_variable_get(*_a); nil; end

  # Disabled stub for class evaluation.
  #
  # Always returns nil. Prevents scripts from calling Lich.class_eval.
  #
  # @return [nil]
  # @api private
  def Lich.class_eval(*_a); nil; end

  # Disabled stub for module evaluation.
  #
  # Always returns nil. Prevents scripts from calling Lich.module_eval.
  #
  # @return [nil]
  # @api private
  def Lich.module_eval(*_a); nil; end

  # Writes a timestamped message to stderr.
  #
  # Used internally by Lich to log debug, error, and informational messages.
  # The timestamp is in YYYY-MM-DD HH:MM:SS format (UTC).
  #
  # @param msg [String] the message to log
  # @return [void]
  def Lich.log(msg)
    $stderr.puts "#{Time.now.strftime("%Y-%m-%d %H:%M:%S")}: #{msg}"
  end

  # Records a deprecation warning for outdated script API usage.
  #
  # Logs the warning to stderr (if debug_log is true) and optionally displays it in-game
  # via Lich::Messaging (if fe_log is true). By default, each unique message is logged
  # only once (limit_log: true) to avoid spam. The warning includes the calling script name.
  #
  # @param old_object [String] the deprecated method or variable name (default '')
  # @param new_object [String] the recommended replacement (default '')
  # @param script_location [String] the script calling the deprecated code (default current script name or 'unknown')
  # @param debug_log [Boolean] whether to log to stderr (default true)
  # @param fe_log [Boolean] whether to display in-game (default false)
  # @param limit_log [Boolean] whether to suppress duplicate messages (default true)
  # @return [void]
  def Lich.deprecated(old_object = '', new_object = '', script_location = "#{Script.current.name || 'unknown'}", debug_log: true, fe_log: false, limit_log: true)
    msg = "Deprecated call to #{old_object} used in #{script_location}. Please change to #{new_object} instead!"
    return if limit_log && @@deprecated_log.include?(msg)
    Lich.log(msg) if debug_log
    Lich::Messaging.msg("bold", msg) if fe_log
    @@deprecated_log.push(msg) unless @@deprecated_log.include?(msg)
  end

  # Displays all recorded deprecation warnings to the game window.
  #
  # Iterates over the internal deprecation log and responds with each message.
  #
  # @return [void]
  def Lich.show_deprecated_log
    @@deprecated_log.each do |msg|
      respond(msg)
    end
  end

  # Displays a modal message box with optional buttons and icon.
  #
  # On Windows (Win32), uses native MessageBox; on Linux/Mac with Gtk, uses a Gtk dialog;
  # otherwise writes to stdout. Accepts a String (converted to message) or a Hash with keys:
  # :message, :buttons, :icon, :title.
  #
  # :buttons may be :ok, :ok_cancel, or :yes_no; :icon may be :error, :question, :warning,
  # or omitted. The title defaults to "Lich vVERSION".
  #
  # @param args [String, Hash] either a message string or options hash
  # @return [Symbol, nil] :ok, :cancel, :yes, :no, or nil (if dismissed or unsupported platform)
  # @example Show a simple message
  #   Lich.msgbox("Script finished.")
  # @example Show a yes/no dialog
  #   response = Lich.msgbox(message: "Continue?", buttons: :yes_no, icon: :question, title: "Confirm")
  #   respond response.to_s
  def Lich.msgbox(args)
    args = { message: args.to_s } unless args.is_a?(Hash)
    if defined?(Win32)
      if args[:buttons] == :ok_cancel
        buttons = Win32::MB_OKCANCEL
      elsif args[:buttons] == :yes_no
        buttons = Win32::MB_YESNO
      else
        buttons = Win32::MB_OK
      end
      if args[:icon] == :error
        icon = Win32::MB_ICONERROR
      elsif args[:icon] == :question
        icon = Win32::MB_ICONQUESTION
      elsif args[:icon] == :warning
        icon = Win32::MB_ICONWARNING
      else
        icon = 0
      end
      args[:title] ||= "Lich v#{LICH_VERSION}"
      r = Win32.MessageBox(:lpText => args[:message], :lpCaption => args[:title], :uType => (buttons | icon))
      if r == Win32::IDIOK
        return :ok
      elsif r == Win32::IDICANCEL
        return :cancel
      elsif r == Win32::IDIYES
        return :yes
      elsif r == Win32::IDINO
        return :no
      else
        return nil
      end
    elsif defined?(Gtk)
      if args[:buttons] == :ok_cancel
        buttons = :ok_cancel
      elsif args[:buttons] == :yes_no
        buttons = :yes_no
      else
        buttons = :ok
      end
      if args[:icon] == :error
        type = :error
      elsif args[:icon] == :question
        type = :question
      elsif args[:icon] == :warning
        type = :warning
      else
        type = :info
      end
      dialog = Gtk::MessageDialog.new(parent: nil, flags: :modal, type: type, buttons: buttons, message: args[:message])
      args[:title] ||= "Lich v#{LICH_VERSION}"
      dialog.title = args[:title]
      begin
        # GTK3 returns the response; it does not yield to a block passed to run.
        response = dialog.run
      ensure
        dialog.destroy
      end
      if response == Gtk::ResponseType::OK
        return :ok
      elsif response == Gtk::ResponseType::CANCEL
        return :cancel
      elsif response == Gtk::ResponseType::YES
        return :yes
      elsif response == Gtk::ResponseType::NO
        return :no
      else
        return nil
      end
    elsif $stdout.isatty
      $stdout.puts(args[:message])
      return nil
    end
  end

  # Retrieves the Simutronics launcher command from the system registry.
  #
  # On Windows, queries HKEY_LOCAL_MACHINE\\Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command.
  # On Linux/Mac with Wine, queries the equivalent Wine registry key.
  # Returns nil on unsupported platforms or if the registry key is not found.
  #
  # @return [String, nil] the launcher command path, or nil if not available
  def Lich.get_simu_launcher
    if defined?(Win32)
      begin
        launcher_key = Win32.RegOpenKeyEx(:hKey => Win32::HKEY_LOCAL_MACHINE, :lpSubKey => 'Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command', :samDesired => (Win32::KEY_ALL_ACCESS | Win32::KEY_WOW64_32KEY))[:phkResult]
        launcher_cmd = Win32.RegQueryValueEx(:hKey => launcher_key, :lpValueName => 'RealCommand')[:lpData]
        if launcher_cmd.nil? or launcher_cmd.empty?
          launcher_cmd = Win32.RegQueryValueEx(:hKey => launcher_key)[:lpData]
        end
        return launcher_cmd
      ensure
        Win32.RegCloseKey(:hKey => launcher_key) rescue nil
      end
    elsif defined?(Wine)
      launcher_cmd = Wine.registry_gets('HKEY_LOCAL_MACHINE\\Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command\\RealCommand')
      unless launcher_cmd and not launcher_cmd.empty?
        launcher_cmd = Wine.registry_gets('HKEY_LOCAL_MACHINE\\Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command\\')
      end
      return launcher_cmd
    else
      return nil
    end
  end

  # Integrates Lich into the Simutronics Game Entry (SGE) launcher on Windows.
  #
  # Requires administrator privileges. Modifies the registry to redirect the SGE launcher
  # to launch Lich, then Lich launches the game. Returns false if already linked or if the
  # operation fails (insufficient privileges, registry errors, etc.).
  #
  # On Windows without admin, attempts elevation via ShellExecuteEx with 'runas' verb.
  # On Wine/Linux, updates the Wine registry equivalently.
  #
  # @return [Boolean] true if successfully linked or already linked, false on error
  def Lich.link_to_sge
    if defined?(Win32)
      if Win32.admin?
        begin
          launcher_key = Win32.RegOpenKeyEx(:hKey => Win32::HKEY_LOCAL_MACHINE, :lpSubKey => 'Software\\Simutronics\\Launcher', :samDesired => (Win32::KEY_ALL_ACCESS | Win32::KEY_WOW64_32KEY))[:phkResult]
          r = Win32.RegQueryValueEx(:hKey => launcher_key, :lpValueName => 'RealDirectory')
          if (r[:return] == 0) and not r[:lpData].empty?
            # already linked
            return true
          end

          r = Win32.GetModuleFileName
          unless r[:return] > 0
            # fixme
            return false
          end

          new_launcher_dir = "\"#{r[:lpFilename]}\" \"#{File.expand_path($PROGRAM_NAME)}\" "
          r = Win32.RegQueryValueEx(:hKey => launcher_key, :lpValueName => 'Directory')
          launcher_dir = r[:lpData]
          r = Win32.RegSetValueEx(:hKey => launcher_key, :lpValueName => 'RealDirectory', :dwType => Win32::REG_SZ, :lpData => launcher_dir)
          return false unless (r == 0)

          r = Win32.RegSetValueEx(:hKey => launcher_key, :lpValueName => 'Directory', :dwType => Win32::REG_SZ, :lpData => new_launcher_dir)
          return (r == 0)
        ensure
          Win32.RegCloseKey(:hKey => launcher_key) rescue nil
        end
      else
        begin
          r = Win32.GetModuleFileName
          file = ((r[:return] > 0) ? r[:lpFilename] : 'rubyw.exe')
          params = "#{$PROGRAM_NAME.split(/\/|\\/).last} --link-to-sge"
          r = Win32.ShellExecuteEx(:lpVerb => 'runas', :lpFile => file, :lpDirectory => LICH_DIR.tr("/", "\\"), :lpParameters => params, :fMask => Win32::SEE_MASK_NOCLOSEPROCESS)
          if r[:return] > 0
            process_id = r[:hProcess]
            sleep 0.2 while Win32.GetExitCodeProcess(:hProcess => process_id)[:lpExitCode] == Win32::STILL_ACTIVE
            sleep 3
          else
            Win32.ShellExecute(:lpOperation => 'runas', :lpFile => file, :lpDirectory => LICH_DIR.tr("/", "\\"), :lpParameters => params)
            sleep 6
          end
        rescue
          Lich.msgbox(:message => $!)
        end
      end
    elsif defined?(Wine)
      launch_dir = Wine.registry_gets('HKEY_LOCAL_MACHINE\\Software\\Simutronics\\Launcher\\Directory')
      return false unless launch_dir

      lich_launch_dir = "#{File.expand_path($PROGRAM_NAME)} --wine=#{Wine::BIN} --wine-prefix=#{Wine::PREFIX}  "
      result = true
      if launch_dir
        if launch_dir =~ /lich/i
          $stdout.puts "--- warning: Lich appears to already be installed to the registry"
          Lich.log "warning: Lich appears to already be installed to the registry"
          Lich.log 'info: launch_dir: ' + launch_dir
        else
          result = result && Wine.registry_puts('HKEY_LOCAL_MACHINE\\Software\\Simutronics\\Launcher\\RealDirectory', launch_dir)
          result = result && Wine.registry_puts('HKEY_LOCAL_MACHINE\\Software\\Simutronics\\Launcher\\Directory', lich_launch_dir)
        end
      end
      return result
    else
      return false
    end
  end

  # Removes Lich from the Simutronics Game Entry (SGE) launcher on Windows.
  #
  # Reverses a previous link_to_sge operation by restoring the original launcher
  # command in the registry. Requires administrator privileges; attempts elevation
  # via ShellExecuteEx if run without admin.
  #
  # @return [Boolean] true if successfully unlinked or was never linked, false on error
  def Lich.unlink_from_sge
    if defined?(Win32)
      if Win32.admin?
        begin
          launcher_key = Win32.RegOpenKeyEx(:hKey => Win32::HKEY_LOCAL_MACHINE, :lpSubKey => 'Software\\Simutronics\\Launcher', :samDesired => (Win32::KEY_ALL_ACCESS | Win32::KEY_WOW64_32KEY))[:phkResult]
          real_directory = Win32.RegQueryValueEx(:hKey => launcher_key, :lpValueName => 'RealDirectory')[:lpData]
          if real_directory.nil? or real_directory.empty?
            # not linked
            return true
          end

          r = Win32.RegSetValueEx(:hKey => launcher_key, :lpValueName => 'Directory', :dwType => Win32::REG_SZ, :lpData => real_directory)
          return false unless (r == 0)

          r = Win32.RegDeleteValue(:hKey => launcher_key, :lpValueName => 'RealDirectory')
          return (r == 0)
        ensure
          Win32.RegCloseKey(:hKey => launcher_key) rescue nil
        end
      else
        begin
          r = Win32.GetModuleFileName
          file = ((r[:return] > 0) ? r[:lpFilename] : 'rubyw.exe')
          params = "#{$PROGRAM_NAME.split(/\/|\\/).last} --unlink-from-sge"
          r = Win32.ShellExecuteEx(:lpVerb => 'runas', :lpFile => file, :lpDirectory => LICH_DIR.tr("/", "\\"), :lpParameters => params, :fMask => Win32::SEE_MASK_NOCLOSEPROCESS)
          if r[:return] > 0
            process_id = r[:hProcess]
            sleep 0.2 while Win32.GetExitCodeProcess(:hProcess => process_id)[:lpExitCode] == Win32::STILL_ACTIVE
            sleep 3
          else
            Win32.ShellExecute(:lpOperation => 'runas', :lpFile => file, :lpDirectory => LICH_DIR.tr("/", "\\"), :lpParameters => params)
            sleep 6
          end
        rescue
          Lich.msgbox(:message => $!)
        end
      end
    elsif defined?(Wine)
      real_launch_dir = Wine.registry_gets('HKEY_LOCAL_MACHINE\\Software\\Simutronics\\Launcher\\RealDirectory')
      result = true
      if real_launch_dir and not real_launch_dir.empty?
        result = result && Wine.registry_puts('HKEY_LOCAL_MACHINE\\Software\\Simutronics\\Launcher\\Directory', real_launch_dir)
        result = result && Wine.registry_puts('HKEY_LOCAL_MACHINE\\Software\\Simutronics\\Launcher\\RealDirectory', '')
      end
      return result
    else
      return false
    end
  end

  # Integrates Lich into the Simutronics Autolaunch (SAL) protocol on Windows.
  #
  # Modifies the registry to handle Simutronics.Autolaunch URIs (SAL links) by routing
  # them through Lich before launching the game. Requires administrator privileges;
  # attempts elevation via ShellExecuteEx if run without admin.
  #
  # @return [Boolean] true if successfully linked or already linked, false on error
  def Lich.link_to_sal
    if defined?(Win32)
      if Win32.admin?
        begin
          # fixme: 64 bit browsers?
          launcher_key = Win32.RegOpenKeyEx(:hKey => Win32::HKEY_LOCAL_MACHINE, :lpSubKey => 'Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command', :samDesired => (Win32::KEY_ALL_ACCESS | Win32::KEY_WOW64_32KEY))[:phkResult]
          r = Win32.RegQueryValueEx(:hKey => launcher_key, :lpValueName => 'RealCommand')
          if (r[:return] == 0) and not r[:lpData].empty?
            # already linked
            return true
          end

          r = Win32.GetModuleFileName
          unless r[:return] > 0
            # fixme
            return false
          end

          new_launcher_cmd = "\"#{r[:lpFilename]}\" \"#{File.expand_path($PROGRAM_NAME)}\" %1"
          r = Win32.RegQueryValueEx(:hKey => launcher_key)
          launcher_cmd = r[:lpData]
          r = Win32.RegSetValueEx(:hKey => launcher_key, :lpValueName => 'RealCommand', :dwType => Win32::REG_SZ, :lpData => launcher_cmd)
          return false unless (r == 0)

          r = Win32.RegSetValueEx(:hKey => launcher_key, :dwType => Win32::REG_SZ, :lpData => new_launcher_cmd)
          return (r == 0)
        ensure
          Win32.RegCloseKey(:hKey => launcher_key) rescue nil
        end
      else
        begin
          r = Win32.GetModuleFileName
          file = ((r[:return] > 0) ? r[:lpFilename] : 'rubyw.exe')
          params = "#{$PROGRAM_NAME.split(/\/|\\/).last} --link-to-sal"
          r = Win32.ShellExecuteEx(:lpVerb => 'runas', :lpFile => file, :lpDirectory => LICH_DIR.tr("/", "\\"), :lpParameters => params, :fMask => Win32::SEE_MASK_NOCLOSEPROCESS)
          if r[:return] > 0
            process_id = r[:hProcess]
            sleep 0.2 while Win32.GetExitCodeProcess(:hProcess => process_id)[:lpExitCode] == Win32::STILL_ACTIVE
            sleep 3
          else
            Win32.ShellExecute(:lpOperation => 'runas', :lpFile => file, :lpDirectory => LICH_DIR.tr("/", "\\"), :lpParameters => params)
            sleep 6
          end
        rescue
          Lich.msgbox(:message => $!)
        end
      end
    elsif defined?(Wine)
      launch_cmd = Wine.registry_gets('HKEY_LOCAL_MACHINE\\Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command\\')
      return false unless launch_cmd

      new_launch_cmd = "#{File.expand_path($PROGRAM_NAME)} --wine=#{Wine::BIN} --wine-prefix=#{Wine::PREFIX} %1"
      result = true
      if launch_cmd
        if launch_cmd =~ /lich/i
          $stdout.puts "--- warning: Lich appears to already be installed to the registry"
          Lich.log "warning: Lich appears to already be installed to the registry"
          Lich.log 'info: launch_cmd: ' + launch_cmd
        else
          result = result && Wine.registry_puts('HKEY_LOCAL_MACHINE\\Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command\\RealCommand', launch_cmd)
          result = result && Wine.registry_puts('HKEY_LOCAL_MACHINE\\Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command\\', new_launch_cmd)
        end
      end
      return result
    else
      return false
    end
  end

  # Removes Lich from the Simutronics Autolaunch (SAL) protocol on Windows.
  #
  # Reverses a previous link_to_sal operation by restoring the original SAL handler
  # command in the registry. Requires administrator privileges; attempts elevation
  # via ShellExecuteEx if run without admin.
  #
  # @return [Boolean] true if successfully unlinked or was never linked, false on error
  def Lich.unlink_from_sal
    if defined?(Win32)
      if Win32.admin?
        begin
          launcher_key = Win32.RegOpenKeyEx(:hKey => Win32::HKEY_LOCAL_MACHINE, :lpSubKey => 'Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command', :samDesired => (Win32::KEY_ALL_ACCESS | Win32::KEY_WOW64_32KEY))[:phkResult]
          real_directory = Win32.RegQueryValueEx(:hKey => launcher_key, :lpValueName => 'RealCommand')[:lpData]
          if real_directory.nil? or real_directory.empty?
            # not linked
            return true
          end

          r = Win32.RegSetValueEx(:hKey => launcher_key, :dwType => Win32::REG_SZ, :lpData => real_directory)
          return false unless (r == 0)

          r = Win32.RegDeleteValue(:hKey => launcher_key, :lpValueName => 'RealCommand')
          return (r == 0)
        ensure
          Win32.RegCloseKey(:hKey => launcher_key) rescue nil
        end
      else
        begin
          r = Win32.GetModuleFileName
          file = ((r[:return] > 0) ? r[:lpFilename] : 'rubyw.exe')
          params = "#{$PROGRAM_NAME.split(/\/|\\/).last} --unlink-from-sal"
          r = Win32.ShellExecuteEx(:lpVerb => 'runas', :lpFile => file, :lpDirectory => LICH_DIR.tr("/", "\\"), :lpParameters => params, :fMask => Win32::SEE_MASK_NOCLOSEPROCESS)
          if r[:return] > 0
            process_id = r[:hProcess]
            sleep 0.2 while Win32.GetExitCodeProcess(:hProcess => process_id)[:lpExitCode] == Win32::STILL_ACTIVE
            sleep 3
          else
            Win32.ShellExecute(:lpOperation => 'runas', :lpFile => file, :lpDirectory => LICH_DIR.tr("/", "\\"), :lpParameters => params)
            sleep 6
          end
        rescue
          Lich.msgbox(:message => $!)
        end
      end
    elsif defined?(Wine)
      real_launch_cmd = Wine.registry_gets('HKEY_LOCAL_MACHINE\\Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command\\RealCommand')
      result = true
      if real_launch_cmd and not real_launch_cmd.empty?
        result = result && Wine.registry_puts('HKEY_LOCAL_MACHINE\\Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command\\', real_launch_cmd)
        result = result && Wine.registry_puts('HKEY_LOCAL_MACHINE\\Software\\Classes\\Simutronics.Autolaunch\\Shell\\Open\\command\\RealCommand', '')
      end
      return result
    else
      return false
    end
  end

  # Returns the path to the system hosts file.
  #
  # Caches the result after the first lookup. Calls find_hosts_file to locate it if
  # not already cached.
  #
  # @return [String, Boolean] the hosts file path, or false if not found
  def Lich.hosts_file
    Lich.find_hosts_file if @@hosts_file.nil?
    return @@hosts_file
  end

  # Locates the hosts file on the current system.
  #
  # On Windows, queries the registry for the TCP/IP database path or searches standard
  # Windows locations (C:\\windows\\system32\\drivers\\etc\\hosts, etc.). On macOS/Linux,
  # checks /etc/hosts and /private/etc/hosts. Caches and returns the result, or false
  # if not found.
  #
  # @return [String, Boolean] the hosts file path, or false if not found
  def Lich.find_hosts_file
    if defined?(Win32)
      begin
        key = Win32.RegOpenKeyEx(:hKey => Win32::HKEY_LOCAL_MACHINE, :lpSubKey => 'System\\CurrentControlSet\\Services\\Tcpip\\Parameters', :samDesired => Win32::KEY_READ)[:phkResult]
        hosts_path = Win32.RegQueryValueEx(:hKey => key, :lpValueName => 'DataBasePath')[:lpData]
      ensure
        Win32.RegCloseKey(:hKey => key) rescue nil
      end
      if hosts_path
        windir = (ENV['windir'] || ENV['SYSTEMROOT'] || 'c:\windows')
        hosts_path = hosts_path.gsub(/%SystemRoot%/i, windir)
        hosts_file = "#{hosts_path}\\hosts"
        if File.exist?(hosts_file)
          return (@@hosts_file = hosts_file)
        end
      end
      if (windir = (ENV['windir'] || ENV['SYSTEMROOT'])) and File.exist?("#{windir}\\system32\\drivers\\etc\\hosts")
        return (@@hosts_file = "#{windir}\\system32\\drivers\\etc\\hosts")
      end

      for drive in ['C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z']
        for windir in ['winnt', 'windows']
          if File.exist?("#{drive}:\\#{windir}\\system32\\drivers\\etc\\hosts")
            return (@@hosts_file = "#{drive}:\\#{windir}\\system32\\drivers\\etc\\hosts")
          end
        end
      end
    else # Linux/Mac
      if File.exist?('/etc/hosts')
        return (@@hosts_file = '/etc/hosts')
      elsif File.exist?('/private/etc/hosts')
        return (@@hosts_file = '/private/etc/hosts')
      end
    end
    return (@@hosts_file = false)
  end

  # Adds a localhost entry to the hosts file for testing purposes.
  #
  # Backs up the current hosts file to hosts.bak, then appends a line mapping
  # game_host to 127.0.0.1. Restores the backup on exit. Returns false if the
  # hosts file does not exist or if a backup already exists.
  #
  # @param game_host [String] the game hostname to redirect to localhost
  # @return [Boolean] true on success, false if hosts file not found or backup exists
  def Lich.modify_hosts(game_host)
    if Lich.hosts_file and File.exist?(Lich.hosts_file)
      at_exit { Lich.restore_hosts }
      Lich.restore_hosts
      if File.exist?("#{Lich.hosts_file}.bak")
        return false
      end

      begin
        # copy hosts to hosts.bak
        File.open("#{Lich.hosts_file}.bak", 'w') { |hb| File.open(Lich.hosts_file) { |h| hb.write(h.read) } }
      rescue
        File.unlink("#{Lich.hosts_file}.bak") if File.exist?("#{Lich.hosts_file}.bak")
        return false
      end
      File.open(Lich.hosts_file, 'a') { |f| f.write "\r\n127.0.0.1\t\t#{game_host}" }
      return true
    else
      return false
    end
  end

  # Restores the hosts file from backup (hosts.bak).
  #
  # Called automatically on exit if modify_hosts was used. Replaces the current
  # hosts file with the backed-up version and removes the .bak file. Exits with
  # code 1 and logs the error if restoration fails.
  #
  # @return [void]
  def Lich.restore_hosts
    if Lich.hosts_file and File.exist?(Lich.hosts_file)
      begin
        # fixme: use rename instead?  test rename on windows
        if File.exist?("#{Lich.hosts_file}.bak")
          File.open("#{Lich.hosts_file}.bak") { |infile|
            File.open(Lich.hosts_file, 'w') { |outfile|
              outfile.write(infile.read)
            }
          }
          File.unlink "#{Lich.hosts_file}.bak"
        end
      rescue
        $stdout.puts "--- error: restore_hosts: #{$!}"
        Lich.log "error: restore_hosts: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
        exit(1)
      end
    end
  end

  # Checks whether inventory boxes are enabled for a player.
  #
  # Queries the enable_inventory_boxes table and retries on SQLite3::BusyException.
  #
  # @param player_id [Integer, #to_i] the player ID
  # @return [Boolean] true if inventory boxes are enabled for this player, false otherwise
  def Lich.inventory_boxes(player_id)
    begin
      v = Lich.db.get_first_value('SELECT player_id FROM enable_inventory_boxes WHERE player_id=?;', [player_id.to_i])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
    if v
      true
    else
      false
    end
  end

  # Enables or disables inventory boxes for a player.
  #
  # Inserts a row into enable_inventory_boxes if enabled is true, or deletes the row
  # if false. Retries on SQLite3::BusyException.
  #
  # @param player_id [Integer, #to_i] the player ID
  # @param enabled [Boolean] true to enable, false to disable
  # @return [nil]
  def Lich.set_inventory_boxes(player_id, enabled)
    if enabled
      begin
        Lich.db.execute('INSERT OR REPLACE INTO enable_inventory_boxes values(?);', [player_id.to_i])
      rescue SQLite3::BusyException
        sleep 0.1
        retry
      end
    else
      begin
        Lich.db.execute('DELETE FROM enable_inventory_boxes where player_id=?;', [player_id.to_i])
      rescue SQLite3::BusyException
        sleep 0.1
        retry
      end
    end
    nil
  end

  # Retrieves the Windows game launch method preference.
  #
  # Reads from lich_settings and retries on SQLite3::BusyException.
  #
  # @return [String, nil] the stored launch method, or nil if not set
  def Lich.win32_launch_method
    begin
      val = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='win32_launch_method';")
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
    val
  end

  # Stores the Windows game launch method preference.
  #
  # Writes to lich_settings as UTF-8 encoded string via INSERT OR REPLACE.
  # Retries on SQLite3::BusyException.
  #
  # @param val [#to_s] the launch method to store
  # @return [void]
  def Lich.win32_launch_method=(val)
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('win32_launch_method',?);", [val.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end

  # Normalizes game server host and port for known redirects.
  #
  # Maps legacy game server addresses to their current Storm endpoints:
  # gs-plat.simutronics.net:10121 → storm.gs4.game.play.net:10124 (Platinum)
  # gs3.simutronics.net:4900 → storm.gs4.game.play.net:10024 (Prime)
  # gs4.simutronics.net:10321 → storm.gs4.game.play.net:10324 (Shattered)
  # prime.dr.game.play.net:4901 → dr.simutronics.net:11024 (DragonRealms Prime)
  #
  # @param gamehost [String] the game server hostname
  # @param gameport [Integer, #to_i] the game server port
  # @return [Array(String, Integer)] the normalized [gamehost, gameport] pair
  def Lich.fix_game_host_port(gamehost, gameport)
    if (gamehost == 'gs-plat.simutronics.net') and (gameport.to_i == 10121)
      gamehost = 'storm.gs4.game.play.net'
      gameport = 10124
    elsif (gamehost == 'gs3.simutronics.net') and (gameport.to_i == 4900)
      gamehost = 'storm.gs4.game.play.net'
      gameport = 10024
    elsif (gamehost == 'gs4.simutronics.net') and (gameport.to_i == 10321)
      gamehost = 'storm.gs4.game.play.net'
      gameport = 10324
    elsif (gamehost == 'prime.dr.game.play.net') and (gameport.to_i == 4901)
      gamehost = 'dr.simutronics.net'
      gameport = 11024
    end
    [gamehost, gameport]
  end

  # Reverses game server normalization, converting Storm endpoints back to legacy addresses.
  #
  # Inverse of fix_game_host_port: maps Storm consolidated servers back to their
  # original pre-consolidation hostnames and ports (for launcher registry restoration).
  #
  # @param gamehost [String] the game server hostname
  # @param gameport [Integer, #to_i] the game server port
  # @return [Array(String, Integer)] the original [gamehost, gameport] pair
  def Lich.break_game_host_port(gamehost, gameport)
    if (gamehost == 'storm.gs4.game.play.net') and (gameport.to_i == 10324)
      gamehost = 'gs4.simutronics.net'
      gameport = 10321
    elsif (gamehost == 'storm.gs4.game.play.net') and (gameport.to_i == 10124)
      gamehost = 'gs-plat.simutronics.net'
      gameport = 10121
    elsif (gamehost == 'storm.gs4.game.play.net') and (gameport.to_i == 10024)
      gamehost = 'gs3.simutronics.net'
      gameport = 4900
    elsif (gamehost == 'dr.simutronics.net') and (gameport.to_i == 11024)
      gamehost = 'prime.dr.game.play.net'
      gameport = 4901
    end
    [gamehost, gameport]
  end

  # new feature GUI / internal settings states

  # Returns the debug messaging setting (cached).
  #
  # Reads from lich_settings on first call and caches the result as a Boolean.
  # Retries on SQLite3::BusyException.
  #
  # @return [Boolean] true if debug messaging is enabled, false otherwise
  def Lich.debug_messaging
    if @@debug_messaging.nil?
      begin
        val = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='debug_messaging';")
      rescue SQLite3::BusyException
        sleep 0.1
        retry
      end
      @@debug_messaging = (val.to_s =~ /on|true|yes/ ? true : false)
      Lich.debug_messaging = @@debug_messaging
    end
    return @@debug_messaging
  end

  # Enables or disables debug messaging.
  #
  # Normalizes the value to Boolean (on/true/yes → true, else false) and persists
  # to lich_settings as UTF-8 encoded string. Updates the cache immediately.
  # Retries on SQLite3::BusyException.
  #
  # @param val [#to_s] any value; truthy strings: on, true, yes
  # @return [void]
  def Lich.debug_messaging=(val)
    @@debug_messaging = (val.to_s =~ /on|true|yes/ ? true : false)
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('debug_messaging',?);", [@@debug_messaging.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end

  # Shared Lich.db uses a Ruby busy handler that releases the GVL while
  # waiting (5000 ms per attempt by default). The calling thread still waits.
  # Two attempts plus one 100 ms pause bound each operation's default lock
  # waiting to about 10.1 seconds plus execution overhead. Failed writes raise;
  # hot-path reads use an uncached default unless a command requests strict reads.
  DISPLAY_SETTINGS_MAX_ATTEMPTS = 2
  DISPLAY_SETTINGS_RETRY_DELAY = 0.1
  DISPLAY_SETTINGS_RETRY_COOLDOWN = 30.0

  # Commands and one-shot startup actions must not act on a busy-read default.
  # Nested callers retain the outer strict scope, even when a read raises.
  # @yield reads display settings through their public accessors
  # @return [Object] the block result
  def self.with_strict_display_reads
    previous = Thread.current[:lich_strict_display_reads]
    Thread.current[:lich_strict_display_reads] = true
    yield
  ensure
    Thread.current[:lich_strict_display_reads] = previous
  end

  # Checks whether display-setting reads are in cooldown due to contention.
  #
  # Returns true if a previous read attempt encountered database contention
  # (SQLite3::BusyException) and the cooldown interval has not yet expired.
  # Allows hot-path rendering reads to use the last published cached value
  # instead of retrying the busy database during the cooldown.
  #
  # @return [Boolean] true if in cooldown, false otherwise
  # @api private
  def self.display_read_cooling_down?
    retry_at = @display_read_retry_at
    !Thread.current[:lich_strict_display_reads] && retry_at &&
      Process.clock_gettime(Process::CLOCK_MONOTONIC) < retry_at
  end

  # Retries one display-setting read or write after transient contention.
  # @yield performs one DB operation
  # @return [Object] the operation's result
  # @raise [SQLite3::BusyException] when the final attempt remains busy
  def self.with_display_settings_retry
    attempts = 0
    begin
      attempts += 1
      yield
    rescue SQLite3::BusyException
      raise if attempts >= DISPLAY_SETTINGS_MAX_ATTEMPTS

      sleep DISPLAY_SETTINGS_RETRY_DELAY
      retry
    end
  end

  # Loads and normalizes an unresolved display value under the same lock as
  # writes, so a concurrent cold read cannot overwrite a successful update.
  # @param name [Symbol] the internal display setting name
  # @yieldparam value [String, nil] the stored value, or nil for no row
  # @return [Boolean, String, nil] cached value, or an uncached default while busy
  def self.read_display_setting(name)
    # Warm rendering reads may use the last published value during a write.
    cached = @display_settings_cache[name]
    return cached unless cached.nil?
    return yield(nil) if display_read_cooling_down?

    @display_settings_mutex.synchronize do
      cached = @display_settings_cache[name]
      return cached unless cached.nil?
      return yield(nil) if display_read_cooling_down?

      stored = begin
        with_display_settings_retry do
          Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='#{name}';")
        end
      rescue SQLite3::BusyException
        raise if Thread.current[:lich_strict_display_reads]

        # A rendering/hook read must not remove the hook or abort the parser.
        # Share the cooldown across cold settings in this render/session.
        # Defaults remain uncached, so expiry can load the saved choice.
        @display_read_retry_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + DISPLAY_SETTINGS_RETRY_COOLDOWN
        return yield(nil)
      end
      @display_settings_cache[name] = yield(stored)
    end
  end

  # Persists first, then publishes the cache while still holding the display
  # lock. Competing writes therefore leave the cache at the last saved value.
  # Defer raised exceptions through publication. A thread kill invalidates an
  # unfinished publication so the next read reloads the saved value. Explicit
  # writes propagate synchronous DB failures and retain the previous cache.
  # @param name [Symbol] the internal display setting name
  # @param value [Boolean, String] the normalized value to save
  # @param automatic [Boolean] cooldown and log optional subtitle UID writes
  # @return [Boolean, String, nil] saved value, or nil for a skipped automatic write
  def self.write_display_setting(name, value, automatic: false)
    @display_settings_mutex.synchronize do
      publication_pending = false
      if automatic
        return if @display_settings_cache[name] == true
        return if @display_uid_retry_at && Process.clock_gettime(Process::CLOCK_MONOTONIC) < @display_uid_retry_at
      end

      Thread.handle_interrupt(Exception => :never) do
        publication_pending = true
        with_display_settings_retry do
          Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('#{name}',?);",
                          [value.to_s.encode('UTF-8')])
        end
        @display_settings_cache[name] = value
        publication_pending = false
        @display_read_retry_at = nil
        @display_uid_retry_at = nil if name == :display_uid
        value
      end
    rescue SQLite3::Exception => e
      publication_pending = false
      raise unless automatic

      # Optional subtitle persistence must not abort parsing or retry every room.
      # Retain the prior value; the next numbered subtitle after expiry retries.
      @display_uid_retry_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + DISPLAY_SETTINGS_RETRY_COOLDOWN
      Lich.log "warning: could not persist automatic display_uid: #{e.message}"
      nil
    ensure
      if publication_pending
        @display_settings_cache.delete(name)
        @display_read_retry_at = nil
      end
    end
  end
  private_class_method :with_display_settings_retry, :read_display_setting, :write_display_setting,
                       :display_read_cooling_down?

  # Explicit setters bypass this cooldown and clear it after a successful save.
  def self.enable_display_uid_automatically
    write_display_setting(:display_uid, true, automatic: true)
  end

  # Returns whether Lich IDs should be displayed in output.
  #
  # Reads from lich_settings on first access and caches the result. Defaults to
  # true for GemStone games, false for others, when no value is stored. Returns nil
  # before any game is identified.
  #
  # @return [Boolean, nil] true to display Lich IDs, false to hide them, or nil if no game identified
  def Lich.display_lichid
    read_display_setting(:display_lichid) do |val|
      val = (XMLData.game =~ /^GS/ ? true : false) if val.nil? && XMLData.game != ""
      val.nil? ? nil : val.to_s.match?(/on|true|yes/)
    end
  end

  # Sets whether Lich IDs should be displayed in output.
  #
  # Normalizes the value to Boolean (on/true/yes → true, else false) and persists
  # to lich_settings. Clears the display cache and retry cooldown on save.
  #
  # @param val [#to_s] any value; truthy strings: on, true, yes
  # @return [Boolean, String] the normalized value passed in
  def Lich.display_lichid=(val)
    write_display_setting(:display_lichid, val.to_s.match?(/on|true|yes/))
  end

  # Returns whether the UID flag should be hidden from output.
  #
  # Reads from lich_settings on first access and caches the result. Defaults to
  # false when no value is stored and a game is identified. Returns nil before
  # any game is identified.
  #
  # @return [Boolean, nil] true to hide the UID flag, false to show it, or nil if no game identified
  def Lich.hide_uid_flag
    read_display_setting(:hide_uid_flag) do |val|
      val = false if val.nil? && XMLData.game != ""
      val.nil? ? nil : val.to_s.match?(/on|true|yes/)
    end
  end

  # Sets whether the UID flag should be hidden from output.
  #
  # Normalizes the value to Boolean (on/true/yes → true, else false) and persists
  # to lich_settings. Clears the display cache and retry cooldown on save.
  #
  # @param val [#to_s] any value; truthy strings: on, true, yes
  # @return [Boolean, String] the normalized value passed in
  def Lich.hide_uid_flag=(val)
    write_display_setting(:hide_uid_flag, val.to_s.match?(/on|true|yes/))
  end

  # Whether the client gets the character's room view without its
  # description while DragonRealms' FLAG DESCRIPTION is OFF (";display
  # descflag"). Works around the Saga-identity stream ignoring the flag; see
  # Lich::Common::RoomDescriptionFilter. Off by default.
  # @return [Boolean, nil] nil until a game is identified and no value is stored
  def Lich.follow_description_flag
    read_display_setting(:follow_description_flag) do |val|
      val = false if val.nil? && XMLData.game != ""
      val.nil? ? nil : val.to_s.match?(/on|true|yes/)
    end
  end

  # Sets and persists the room description filter toggle.
  # @param val [Boolean, String] truthy values are any of on/true/yes
  def Lich.follow_description_flag=(val)
    write_display_setting(:follow_description_flag, val.to_s.match?(/on|true|yes/))
  end

  # Whether Lich's proxy forwards a front end's own /FE: handshake instead of
  # replacing it with Lich's client string (Frontend.proxy_handshake). The
  # kill switch for that replacement; the --keep-fe-string flag does the same
  # for one launch. Persisted in the lich_settings table, shared across
  # characters, read at the handshake. Default false, also when the read fails.
  # @return [Boolean]
  def Lich.keep_fe_string
    if @@keep_fe_string.nil?
      begin
        val = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='keep_fe_string';")
      rescue SQLite3::BusyException
        sleep 0.1
        retry
      end
      @@keep_fe_string = val.to_s.strip.match?(/\A(?:on|true|yes)\z/i)
    end
    @@keep_fe_string
  rescue StandardError => e
    # Read on the login path: a settings failure must not stop the handshake.
    Lich.log "warning: could not read keep_fe_string, replacing the client string: #{e}"
    false
  end

  # Sets and persists the handshake kill switch; takes effect at the next login.
  # @param val [Boolean, String] true, or any of on/true/yes
  def Lich.keep_fe_string=(val)
    @@keep_fe_string = val.to_s.strip.match?(/\A(?:on|true|yes)\z/i)
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('keep_fe_string',?);", [@@keep_fe_string.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end

  # Retrieves the Lich version that last updated the core scripts.
  #
  # Reads from lich_settings and retries on SQLite3::BusyException.
  #
  # @return [String] the version string, or empty string if not set
  def Lich.core_updated_with_lich_version
    begin
      val = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='core_updated_with_lich_version';")
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
    return val.to_s
  end

  # Records the Lich version that last updated the core scripts.
  #
  # Writes to lich_settings as UTF-8 encoded string via INSERT OR REPLACE.
  # Retries on SQLite3::BusyException.
  #
  # @param val [#to_s] the Lich version string
  # @return [void]
  def Lich.core_updated_with_lich_version=(val)
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('core_updated_with_lich_version',?);", [val.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end

  # Returns whether UIDs (unique identifiers) should be displayed in output.
  #
  # Reads from lich_settings on first access and caches the result. Defaults to
  # true for GemStone games, false for others, when no value is stored. Returns nil
  # before any game is identified.
  #
  # @return [Boolean, nil] true to display UIDs, false to hide them, or nil if no game identified
  def Lich.display_uid
    read_display_setting(:display_uid) do |val|
      val = (XMLData.game =~ /^GS/ ? true : false) if val.nil? && XMLData.game != ""
      val.nil? ? nil : val.to_s.match?(/on|true|yes/)
    end
  end

  # Sets whether UIDs should be displayed in output.
  #
  # Normalizes the value to Boolean (on/true/yes → true, else false) and persists
  # to lich_settings. Clears the display cache and triggers automatic subtitle UID
  # cooldown on save.
  #
  # @param val [#to_s] any value; truthy strings: on, true, yes
  # @return [Boolean, String] the normalized value passed in
  def Lich.display_uid=(val)
    write_display_setting(:display_uid, val.to_s.match?(/on|true|yes/))
  end

  # The valid values for Lich.display_roomid_location.
  ROOMID_LOCATIONS = %w[title line both].freeze

  # Where DragonRealms renders the optional room id / UID chosen via ;display lichid and
  # ;display uid: "title" injects into the room-name line (visible on every front-end),
  # "line" is the historical "Room Number:" line below the room, and "both" does both.
  # GemStone ignores this setting (it always injects into the title line). The value is
  # read fresh from the lich_settings table on first access and then memoized.
  # @return [String, nil] one of ROOMID_LOCATIONS, or nil before a game has been identified
  def Lich.display_roomid_location
    read_display_setting(:display_roomid_location) do |val|
      val = "line" if val.nil? && XMLData.game != ""
      val.nil? ? nil : (ROOMID_LOCATIONS.include?(val) ? val : "line")
    end
  end

  # Sets the DragonRealms room-id display placement and persists it. An unrecognized value is
  # ignored (the current setting is retained) so a typo can never blank the display or feed the
  # renderer an invalid placement.
  # @param val [String, Symbol] one of ROOMID_LOCATIONS ("title", "line", or "both"); case-insensitive
  # @return [void]
  def Lich.display_roomid_location=(val)
    normalized = val.to_s.downcase
    return unless ROOMID_LOCATIONS.include?(normalized)

    write_display_setting(:display_roomid_location, normalized)
  end

  # Returns whether room exits should be displayed in output.
  #
  # Reads from lich_settings on first access and caches the result. Defaults to
  # false when no value is stored and a game is identified. Returns nil before
  # any game is identified.
  #
  # @return [Boolean, nil] true to display exits, false to hide them, or nil if no game identified
  def Lich.display_exits
    read_display_setting(:display_exits) do |val|
      val = false if val.nil? && XMLData.game != ""
      val.nil? ? nil : val.to_s.match?(/on|true|yes/)
    end
  end

  # Sets whether room exits should be displayed in output.
  #
  # Normalizes the value to Boolean (on/true/yes → true, else false) and persists
  # to lich_settings. Clears the display cache and retry cooldown on save.
  #
  # @param val [#to_s] any value; truthy strings: on, true, yes
  # @return [Boolean, String] the normalized value passed in
  def Lich.display_exits=(val)
    write_display_setting(:display_exits, val.to_s.match?(/on|true|yes/))
  end

  # Returns whether StringProcs should be displayed in output.
  #
  # Reads from lich_settings on first access and caches the result. Defaults to
  # false when no value is stored and a game is identified. Returns nil before
  # any game is identified.
  #
  # @return [Boolean, nil] true to display StringProcs, false to hide them, or nil if no game identified
  def Lich.display_stringprocs
    read_display_setting(:display_stringprocs) do |val|
      val = false if val.nil? && XMLData.game != ""
      val.nil? ? nil : val.to_s.match?(/on|true|yes/)
    end
  end

  # Sets whether StringProcs should be displayed in output.
  #
  # Normalizes the value to Boolean (on/true/yes → true, else false) and persists
  # to lich_settings. Clears the display cache and retry cooldown on save.
  #
  # @param val [#to_s] any value; truthy strings: on, true, yes
  # @return [Boolean, String] the normalized value passed in
  def Lich.display_stringprocs=(val)
    write_display_setting(:display_stringprocs, val.to_s.match?(/on|true|yes/))
  end

  # Whether room exits are rendered as clickable command links (a <d> tag) or as
  # plain text in room-display output. Persisted in the lich_settings table and
  # shared across characters. When no value has been saved yet, the default is
  # game-aware: DragonRealms defaults to off (plain text, matching the retired
  # roomnumbers.lic look) while GemStone and any other game default to on
  # (clickable links, the pre-existing core behavior).
  # @return [Boolean, nil] true when exits should be clickable links; nil until
  #   the game is identified (XMLData.game still blank), matching the pre-existing
  #   display_* getters. Callers treat nil as falsy.
  def Lich.display_room_links
    read_display_setting(:display_room_links) do |val|
      val = (XMLData.game =~ /^DR/ ? false : true) if val.nil? && XMLData.game != ""
      val.nil? ? nil : val.to_s.match?(/on|true|yes/)
    end
  end

  # Sets and persists the room-exit link toggle.
  # @param val [Boolean, String] truthy values are any of on/true/yes
  # @return [Boolean, String] the value passed in - Ruby assignment methods
  #   always return their argument, not the method body's result
  def Lich.display_room_links=(val)
    write_display_setting(:display_room_links, val.to_s.match?(/on|true|yes/))
  end

  # Whether the Lich-injected room lines (Room Number, Room Exits, StringProcs)
  # are wrapped in the fixed-width mono style. Persisted in the lich_settings
  # table and shared across characters. When no value has been saved yet, the
  # default is game-aware: DragonRealms defaults to on (mono, matching the
  # retired roomnumbers.lic look) while GemStone and any other game default to
  # off (the proportional game font, the pre-existing core behavior). The mono
  # wrapper is only emitted on mono-capable frontends (see Frontend.supports_mono?).
  # @return [Boolean, nil] true when the lines should render in the mono style;
  #   nil until the game is identified (XMLData.game still blank), matching the
  #   pre-existing display_* getters. Callers treat nil as falsy.
  def Lich.display_room_mono
    read_display_setting(:display_room_mono) do |val|
      val = (XMLData.game =~ /^DR/ ? true : false) if val.nil? && XMLData.game != ""
      val.nil? ? nil : val.to_s.match?(/on|true|yes/)
    end
  end

  # Sets and persists the room-line mono-font toggle.
  # @param val [Boolean, String] truthy values are any of on/true/yes
  # @return [Boolean, String] the value passed in - Ruby assignment methods
  #   always return their argument, not the method body's result
  def Lich.display_room_mono=(val)
    write_display_setting(:display_room_mono, val.to_s.match?(/on|true|yes/))
  end

  # Returns whether experience gains should be displayed in output.
  #
  # Reads from lich_settings on first access and caches the result. Defaults based
  # on frontend: Genie defaults to false (off), others default to true (on). Returns nil
  # before any game is identified.
  #
  # @return [Boolean, nil] true to display exp gains, false to hide them, or nil if no game identified
  def Lich.display_expgains
    read_display_setting(:display_expgains) do |val|
      val = ($frontend == 'genie' ? 'false' : 'true') if val.nil? && XMLData.game != ""
      val.nil? ? nil : val.to_s.match?(/on|true|yes/)
    end
  end

  # Sets whether experience gains should be displayed in output.
  #
  # Normalizes the value to Boolean (on/true/yes → true, else false) and persists
  # to lich_settings. Clears the display cache and retry cooldown on save.
  #
  # @param val [#to_s] any value; truthy strings: on, true, yes
  # @return [Boolean, String] the normalized value passed in
  def Lich.display_expgains=(val)
    write_display_setting(:display_expgains, val.to_s.match?(/on|true|yes/))
  end

  # Returns the autosort state tracking preference (cached).
  #
  # Reads from lich_settings on first call and caches the result as a Boolean.
  # Retries on SQLite3::BusyException.
  #
  # @return [Boolean] true if autosort state tracking is enabled, false otherwise
  def Lich.track_autosort_state
    if @@track_autosort_state.nil?
      begin
        val = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='track_autosort_state';")
      rescue SQLite3::BusyException
        sleep 0.1
        retry
      end
      @@track_autosort_state = (val.to_s =~ /on|true|yes/ ? true : false)
    end
    return @@track_autosort_state
  end

  # Enables or disables autosort state tracking.
  #
  # Normalizes the value to Boolean (on/true/yes → true, else false) and persists
  # to lich_settings as UTF-8 encoded string. Updates the cache immediately.
  # Retries on SQLite3::BusyException.
  #
  # @param val [#to_s] any value; truthy strings: on, true, yes
  # @return [void]
  def Lich.track_autosort_state=(val)
    @@track_autosort_state = (val.to_s =~ /on|true|yes/ ? true : false)
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('track_autosort_state',?);", [@@track_autosort_state.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end

  # Returns the dark mode tracking preference (cached).
  #
  # Reads from lich_settings on first call and caches the result as a Boolean.
  # Retries on SQLite3::BusyException.
  #
  # @return [Boolean] true if dark mode tracking is enabled, false otherwise
  def Lich.track_dark_mode
    if @@track_dark_mode.nil?
      begin
        val = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='track_dark_mode';")
      rescue SQLite3::BusyException
        sleep 0.1
        retry
      end
      @@track_dark_mode = (val.to_s =~ /on|true|yes/ ? true : false)
    end
    return @@track_dark_mode
  end

  # Enables or disables dark mode tracking.
  #
  # Normalizes the value to Boolean (on/true/yes → true, else false) and persists
  # to lich_settings as UTF-8 encoded string. Updates the cache immediately.
  # Retries on SQLite3::BusyException.
  #
  # @param val [#to_s] any value; truthy strings: on, true, yes
  # @return [void]
  def Lich.track_dark_mode=(val)
    @@track_dark_mode = (val.to_s =~ /on|true|yes/ ? true : false)
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('track_dark_mode',?);", [@@track_dark_mode.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end

  # Returns the layout state tracking preference (cached).
  #
  # Reads from lich_settings on first call and caches the result as a Boolean.
  # Retries on SQLite3::BusyException.
  #
  # @return [Boolean] true if layout state tracking is enabled, false otherwise
  def Lich.track_layout_state
    if @@track_layout_state.nil?
      begin
        val = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='track_layout_state';")
      rescue SQLite3::BusyException
        sleep 0.1
        retry
      end
      @@track_layout_state = (val.to_s =~ /on|true|yes/ ? true : false)
    end
    return @@track_layout_state
  end

  # Enables or disables layout state tracking.
  #
  # Normalizes the value to Boolean (on/true/yes → true, else false) and persists
  # to lich_settings as UTF-8 encoded string. Updates the cache immediately.
  # Retries on SQLite3::BusyException.
  #
  # @param val [#to_s] any value; truthy strings: on, true, yes
  # @return [void]
  def Lich.track_layout_state=(val)
    @@track_layout_state = (val.to_s =~ /on|true|yes/ ? true : false)
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('track_layout_state',?);", [@@track_layout_state.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end

  # Returns persisted launcher mode state for GUI login flow.
  #
  # @return [Boolean] true when persistent multi-launch mode is enabled
  def Lich.track_persistent_launcher_mode
    if @@track_persistent_launcher_mode.nil?
      begin
        val = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='track_persistent_launcher_mode';")
      rescue SQLite3::BusyException
        sleep 0.1
        retry
      end
      @@track_persistent_launcher_mode = (val.to_s =~ /on|true|yes/ ? true : false)
    end
    return @@track_persistent_launcher_mode
  end

  # Persists launcher mode state for GUI login flow.
  #
  # @param val [Object] truthy/falsey value parsed to Boolean
  # @return [void]
  def Lich.track_persistent_launcher_mode=(val)
    @@track_persistent_launcher_mode = (val.to_s =~ /on|true|yes/ ? true : false)
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('track_persistent_launcher_mode',?);", [@@track_persistent_launcher_mode.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end

  # Default number of debug log files to retain when no user preference is set.
  #
  # @return [Integer] the built-in retention limit
  MAX_DEBUG_LOGS_DEFAULT = 20

  # Minimum allowed value for max_debug_logs to prevent accidental deletion
  # of all log files.
  #
  # @return [Integer] the floor value enforced by the setter
  MAX_DEBUG_LOGS_MINIMUM = 1

  # Returns the maximum number of debug log files to retain in the temp
  # directory. The value is lazily loaded from the +lich_settings+ database
  # table on first access, then cached in a class variable for subsequent
  # calls. When no persisted value exists, falls back to
  # {MAX_DEBUG_LOGS_DEFAULT}.
  #
  # @return [Integer] the configured retention limit (>= {MAX_DEBUG_LOGS_MINIMUM})
  #
  # @example Query the current setting in-game
  #   ;e respond Lich.max_debug_logs
  #
  # @see Lich.max_debug_logs=
  # @see Lich.cleanup_debug_logs
  def Lich.max_debug_logs
    if @@max_debug_logs.nil?
      begin
        val = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='max_debug_logs';")
      rescue SQLite3::BusyException
        sleep 0.1
        retry
      end
      @@max_debug_logs = val.nil? ? MAX_DEBUG_LOGS_DEFAULT : [val.to_i, MAX_DEBUG_LOGS_MINIMUM].max
    end
    @@max_debug_logs
  end

  # Persists the maximum number of debug log files to retain. Values below
  # {MAX_DEBUG_LOGS_MINIMUM} are clamped to prevent accidental deletion of
  # all logs.
  #
  # @param val [#to_i] the desired retention limit
  # @return [void]
  #
  # @example Set retention to 50 files in-game
  #   ;e Lich.max_debug_logs = 50
  #
  # @see Lich.max_debug_logs
  # @see Lich.cleanup_debug_logs
  def Lich.max_debug_logs=(val)
    @@max_debug_logs = [val.to_i, MAX_DEBUG_LOGS_MINIMUM].max
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('max_debug_logs',?);", [@@max_debug_logs.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end

  # Removes old debug log files from +temp_dir+, keeping at most
  # {Lich.max_debug_logs} files. Files are sorted lexicographically by name
  # (which encodes a timestamp), so the most recent files are retained.
  #
  # This method is called once during Lich startup (in +init.rb+) after the
  # database has been initialized.
  #
  # @param temp_dir [String] the directory containing debug log files
  # @return [void]
  #
  # @see Lich.max_debug_logs
  def Lich.cleanup_debug_logs(temp_dir)
    pattern = /^debug(?:-\d+)+\.log$/
    candidates = Dir.entries(temp_dir).select { |fn| fn.match?(pattern) }
    limit = Lich.max_debug_logs
    return if candidates.length <= limit

    candidates.sort.reverse[limit..-1].each do |old_file|
      begin
        File.delete(File.join(temp_dir, old_file))
      rescue
        Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
      end
    end
  end
end
