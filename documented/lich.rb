require 'time'
# Namespace for Lich 5 scripting engine functionality, providing database access,
# configuration management, logging, and frontend integration for GemStone IV and DragonRealms.
module Lich
  # Default timeout in milliseconds for SQLite3 busy waits when the database is locked.
  #
  # @return [Integer] 5000 milliseconds
  DEFAULT_SQLITE_BUSY_TIMEOUT_MS = 5000 unless const_defined?(:DEFAULT_SQLITE_BUSY_TIMEOUT_MS)

  # Returns the configured SQLite busy timeout in milliseconds.
  #
  # @return [Integer] the busy timeout value (5000 by default)
  def Lich.sqlite_busy_timeout_ms
    DEFAULT_SQLITE_BUSY_TIMEOUT_MS
  end

  # Configures an SQLite3 database connection with the busy timeout setting.
  #
  # @param db [SQLite3::Database] an SQLite database connection object
  # @return [SQLite3::Database] the configured database object
  # @note If the database object does not respond to `busy_timeout`, it is returned unchanged
  def Lich.configure_sqlite_connection(db)
    db.busy_timeout(sqlite_busy_timeout_ms) if db.respond_to?(:busy_timeout)
    db
  end

  # Opens or creates an SQLite3 database at the specified path and applies busy timeout configuration.
  #
  # @param path [String] the file path to the database
  # @return [SQLite3::Database] the configured database connection
  # @example
  #   db = Lich.open_sqlite_db("#{Lich::DATA_DIR}/lich.db3")
  def Lich.open_sqlite_db(path)
    configure_sqlite_connection(SQLite3::Database.new(path))
  end

  # Opens an SQLite database via the Sequel ORM and sets the busy timeout via PRAGMA.
  #
  # @param path [String] the file path to the database
  # @return [Sequel::Database] the configured Sequel database object
  # @note Sequel does not expose SQLite3's busy_timeout API directly; the PRAGMA is used instead
  def Lich.open_sequel_sqlite(path)
    db = Sequel.sqlite(path)
    # Sequel does not expose sqlite3's busy_timeout API on its database wrapper.
    db.run("PRAGMA busy_timeout = #{sqlite_busy_timeout_ms.to_i}")
    db
  end

  # --- Minimal DB maintenance helpers (simple + safe) ---
  # Stores last maintenance timestamp and summary in lich_settings.
  # Uses an advisory OS file lock so only one Lich instance attempts VACUUM.
  def Lich.db_maint_lock_path
    File.join(DATA_DIR, 'lich.db3.maint.lock')
  end

  # Retrieves the timestamp of the last database maintenance operation from lich_settings.
  #
  # @return [String, nil] ISO 8601 UTC timestamp string of the last maintenance, or nil if never run
  # @note Retries on SQLite3::BusyException; returns nil on other errors
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

  # Records a database maintenance completion timestamp and optional note in lich_settings.
  #
  # @param iso_utc [String] ISO 8601 UTC timestamp of maintenance completion
  # @param note [String] optional summary of maintenance activity (e.g., "VACUUM ok pages 100->80")
  # @return [void]
  # @note Retries on SQLite3::BusyException; creates lich_settings table if needed
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

  # Checks whether database maintenance is due based on elapsed time since last run.
  #
  # @param months [Integer] the interval in months; maintenance is due if last run was more than this long ago
  # @return [Boolean] true if maintenance has never run, the timestamp is empty/invalid, or the interval has elapsed
  # @note Returns true on parsing errors to allow maintenance to attempt
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

  @@db_mutex             ||= Mutex.new

  # settings
  @@display_lichid       = nil # boolean
  @@display_uid          = nil # boolean
  @@display_exits        = nil # boolean
  @@display_stringprocs  = nil # boolean
  @@display_room_links   = nil # boolean
  @@display_room_mono    = nil # boolean
  @@display_expgains     = nil # boolean (DragonRealms only)
  @@display_roomid_location = nil # string (DragonRealms only): "title" | "line" | "both"
  @@hide_uid_flag        = nil # boolean
  @@track_autosort_state = nil # boolean
  @@track_dark_mode      = nil # boolean
  @@track_layout_state   = nil # boolean
  @@track_persistent_launcher_mode = nil # boolean
  @@debug_messaging = nil # boolean
  @@max_debug_logs  = nil # integer

  # Returns the module-level mutex used to serialize database access.
  #
  # @return [Mutex] the database access mutex
  # @api private
  def self.db_mutex
    @@db_mutex
  end

  # Acquires the database mutex lock if not already held by the current thread.
  #
  # @return [void]
  # @note Logs and responds to user on lock errors; safe to call multiple times
  # @api private
  def self.mutex_lock
    begin
      self.db_mutex.lock unless self.db_mutex.owned?
    rescue StandardError
      respond "--- Lich: error: Lich.mutex_lock: #{$!}"
      Lich.log "error: Lich.mutex_lock: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
    end
  end

  # Releases the database mutex lock if currently held by the current thread.
  #
  # @return [void]
  # @note Logs and responds to user on unlock errors; safe to call when not locked
  # @api private
  def self.mutex_unlock
    begin
      self.db_mutex.unlock if self.db_mutex.owned?
    rescue StandardError
      respond "--- Lich: error: Lich.mutex_unlock: #{$!}"
      Lich.log "error: Lich.mutex_unlock: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
    end
  end

  # Deprecated delegation to Vars.method_missing for legacy Lich.* variable access.
  #
  # @param arg1 [String] the variable name
  # @param arg2 [String] optional value for assignment
  # @return [Object] delegated result from Vars.method_missing
  # @note Emits a deprecation warning (throttled to once per 5 minutes); scripts should use Vars.* instead
  # @deprecated Use {Vars} class instead
  def Lich.method_missing(arg1, arg2 = '')
    if (Time.now.to_i - @@last_warn_deprecated) > 300
      respond "--- warning: Lich.* variables will stop working in a future version of Lich.  Use Vars.* (offending script: #{Script.current.name || 'unknown'})"
      @@last_warn_deprecated = Time.now.to_i
    end
    Vars.method_missing(arg1, arg2)
  end

  # Locates the installation directory of a frontend by name.
  #
  # @param fe [String] the frontend identifier (e.g., "wizard", "stormfront")
  # @return [String, nil] the frontend installation path, or nil if not found
  # @note Prefers Lich::Common::FrontendLocator if available; falls back to legacy global variables
  def Lich.seek(fe)
    if defined?(Lich::Common::FrontendLocator)
      return Lich::Common::FrontendLocator.compatibility_location(fe)
    end

    return $wiz_fe_loc if fe =~ /wizard/
    return $sf_fe_loc if fe =~ /stormfront/

    nil
  end

  # Returns the primary SQLite3 database connection, creating it on first access.
  #
  # @return [SQLite3::Database] the lazily-initialized database object at #{DATA_DIR}/lich.db3
  # @note Connection is cached in @@lich_db; the database file is created if it does not exist
  def Lich.db
    @@lich_db ||= open_sqlite_db("#{DATA_DIR}/lich.db3")
  end

  # Initializes the Lich database schema, creating all required tables and indices.
  #
  # @return [void]
  # @note Creates: script_setting, script_auto_settings, lich_settings, uservars, session_summary_state, session_summary_state indices, trusted_scripts (Ruby 2.0-2.2 only), simu_game_entry, enable_inventory_boxes
  # @note Safely handles SQLite3::BusyException and idempotently tolerates duplicate-column errors from migrations
  # @api private
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

  # Stub implementation that prevents access to class variables.
  #
  # @return [nil] always nil
  # @api private
  def Lich.class_variable_get(*_a); nil; end

  # Stub implementation that prevents dynamic class evaluation.
  #
  # @return [nil] always nil
  # @api private
  def Lich.class_eval(*_a);         nil; end

  # Stub implementation that prevents dynamic module evaluation.
  #
  # @return [nil] always nil
  # @api private
  def Lich.module_eval(*_a);        nil; end

  # Writes a timestamped message to stderr (the debug log).
  #
  # @param msg [String] the message to log
  # @return [void]
  # @note Format: "YYYY-MM-DD HH:MM:SS: {msg}"
  def Lich.log(msg)
    $stderr.puts "#{Time.now.strftime("%Y-%m-%d %H:%M:%S")}: #{msg}"
  end

  # Records a deprecation notice for an old API call and optionally logs it.
  #
  # @param old_object [String] the deprecated call or object name
  # @param new_object [String] the recommended replacement
  # @param script_location [String] the script name or location using the deprecated API
  # @param debug_log [Boolean] whether to log to stderr (default true)
  # @param fe_log [Boolean] whether to send to frontend via messaging (default false)
  # @param limit_log [Boolean] whether to deduplicate messages in the log (default true)
  # @return [void]
  # @note Deduplication tracks messages in @@deprecated_log; use {.show_deprecated_log} to display accumulated notices
  def Lich.deprecated(old_object = '', new_object = '', script_location = "#{Script.current.name || 'unknown'}", debug_log: true, fe_log: false, limit_log: true)
    msg = "Deprecated call to #{old_object} used in #{script_location}. Please change to #{new_object} instead!"
    return if limit_log && @@deprecated_log.include?(msg)
    Lich.log(msg) if debug_log
    Lich::Messaging.msg("bold", msg) if fe_log
    @@deprecated_log.push(msg) unless @@deprecated_log.include?(msg)
  end

  # Displays all recorded deprecation notices to the user via respond().
  #
  # @return [void]
  # @see .deprecated
  def Lich.show_deprecated_log
    @@deprecated_log.each do |msg|
      respond(msg)
    end
  end

  # Displays a modal message box dialog using the native platform GUI or terminal fallback.
  #
  # @param args [Hash] dialog configuration
  # @option args :message [String] the message body (required)
  # @option args :title [String] the window title (default: "Lich v{LICH_VERSION}")
  # @option args :buttons [Symbol] :ok (default), :ok_cancel, or :yes_no
  # @option args :icon [Symbol] :error, :question, :warning, or nil (default)
  # @return [Symbol, nil] :ok, :cancel, :yes, :no, or nil if closed without selection
  # @note Uses Win32 API on Windows, Gtk on Linux/Mac with Gtk, or stdout.puts on text terminals
  # @api private
  def Lich.msgbox(args)
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

  # Retrieves the path or command of the Simutronics Game Entry (SGE) launcher from the system registry.
  #
  # @return [String, nil] the launcher command, or nil if not found
  # @note Reads from Windows HKEY_LOCAL_MACHINE on Windows; Wine registry on Wine; returns nil on other platforms
  # @api private
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

  # Integrates Lich into the Simutronics Game Entry launcher by modifying the registry.
  #
  # @return [Boolean, nil] true if successful or already linked, false on error, nil on unsupported platform
  # @note On Windows non-admin: elevates to admin and re-runs self via ShellExecuteEx
  # @note On Wine: modifies the Wine registry for Simutronics launcher integration
  # @note Saves the original launcher directory for later restoration
  # @api private
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

  # Removes Lich integration from the Simutronics Game Entry launcher by restoring the original registry.
  #
  # @return [Boolean, nil] true if successful or not linked, false on error, nil on unsupported platform
  # @note On Windows non-admin: elevates to admin and re-runs self via ShellExecuteEx
  # @note On Wine: restores the Wine registry for Simutronics launcher
  # @api private
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

  # Integrates Lich into Simutronics AutoLaunch (browser launcher) by modifying the registry.
  #
  # @return [Boolean, nil] true if successful or already linked, false on error, nil on unsupported platform
  # @note On Windows non-admin: elevates to admin and re-runs self via ShellExecuteEx
  # @note On Wine: modifies the Wine registry for AutoLaunch integration
  # @note Saves the original launcher command for later restoration
  # @api private
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

  # Removes Lich integration from Simutronics AutoLaunch by restoring the original registry.
  #
  # @return [Boolean, nil] true if successful or not linked, false on error, nil on unsupported platform
  # @note On Windows non-admin: elevates to admin and re-runs self via ShellExecuteEx
  # @note On Wine: restores the Wine registry for AutoLaunch
  # @api private
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

  # Returns the path to the system hosts file, locating it on first access.
  #
  # @return [String, false] the hosts file path, or false if not found
  # @note Caches the result in @@hosts_file for subsequent calls
  def Lich.hosts_file
    Lich.find_hosts_file if @@hosts_file.nil?
    return @@hosts_file
  end

  # Searches the system for the hosts file and caches its path.
  #
  # @return [String, false] the hosts file path, or false if not found
  # @note On Windows: queries registry, checks default paths, and searches all drives
  # @note On Linux/Mac: checks /etc/hosts and /private/etc/hosts
  # @note Stores result in @@hosts_file
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
        hosts_path.gsub('%SystemRoot%', windir)
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

  # Adds a hosts file entry redirecting a game hostname to 127.0.0.1 for local testing.
  #
  # @param game_host [String] the hostname to redirect (e.g., "gs4.simutronics.net")
  # @return [Boolean] true if successful, false if the hosts file does not exist or backup creation fails
  # @note Backs up the original hosts file to {hosts_file}.bak and registers an at_exit handler to restore it
  # @api private
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

  # Restores the hosts file from its backup if present.
  #
  # @return [void]
  # @note Exits the process with code 1 on restoration error
  # @api private
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

  # Checks whether inventory boxes are enabled for a given player.
  #
  # @param player_id [Integer] the player ID
  # @return [Boolean] true if inventory boxes are enabled for this player, false otherwise
  # @note Retries on SQLite3::BusyException
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

  # Enables or disables inventory boxes for a given player.
  #
  # @param player_id [Integer] the player ID
  # @param enabled [Boolean] true to enable, false to disable
  # @return [void]
  # @note Retries on SQLite3::BusyException
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

  # Retrieves the stored Windows launch method preference from lich_settings.
  #
  # @return [String, nil] the launch method value, or nil if not set
  # @note Retries on SQLite3::BusyException
  # @api private
  def Lich.win32_launch_method
    begin
      val = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='win32_launch_method';")
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
    val
  end

  # Stores a Windows launch method preference in lich_settings.
  #
  # @param val [String] the launch method value
  # @return [void]
  # @note Retries on SQLite3::BusyException
  # @api private
  def Lich.win32_launch_method=(val)
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('win32_launch_method',?);", [val.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end

  # Normalizes deprecated game server hostnames and ports to current values.
  #
  # @param gamehost [String] the game hostname
  # @param gameport [Integer] the game port
  # @return [Array<(String, Integer)>] the normalized [hostname, port] pair
  # @note Maps: gs-plat.simutronics.net:10121 and gs3.simutronics.net:4900 and gs4.simutronics.net:10321 and prime.dr.game.play.net:4901 to current endpoints
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

  # Converts current game server hostnames and ports back to their deprecated equivalents (inverse of {.fix_game_host_port}).
  #
  # @param gamehost [String] the game hostname
  # @param gameport [Integer] the game port
  # @return [Array<(String, Integer)>] the legacy [hostname, port] pair
  # @note Maps: storm.gs4.game.play.net:10124 and storm.gs4.game.play.net:10024 and dr.simutronics.net:11024 to their original aliases
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

  # Returns the debug messaging toggle state, lazily loaded from lich_settings.
  #
  # @return [Boolean] true if debug messaging is enabled, false otherwise
  # @note Lazily evaluates from database on first call and caches in @@debug_messaging
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

  # Sets and persists the debug messaging toggle state.
  #
  # @param val [String, Boolean] truthy values are "on", "true", or "yes" (case-insensitive)
  # @return [void]
  # @note Retries on SQLite3::BusyException
  def Lich.debug_messaging=(val)
    @@debug_messaging = (val.to_s =~ /on|true|yes/ ? true : false)
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('debug_messaging',?);", [@@debug_messaging.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end

  # Returns the room ID display toggle, defaulting based on game type.
  #
  # @return [Boolean, nil] true if room IDs should be displayed, nil until a game is identified
  # @note Default: true for GemStone, false for DragonRealms
  # @note Lazily loaded from lich_settings and cached
  def Lich.display_lichid
    if @@display_lichid.nil?
      begin
        val = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='display_lichid';")
      rescue SQLite3::BusyException
        sleep 0.1
        retry
      end
      val = (XMLData.game =~ /^GS/ ? true : false) if val.nil? and XMLData.game != ""; # default false if DR, otherwise default true
      @@display_lichid = (val.to_s =~ /on|true|yes/ ? true : false) if !val.nil?;
    end
    return @@display_lichid
  end

  # Sets and persists the room ID display toggle.
  #
  # @param val [String, Boolean] truthy values are "on", "true", or "yes" (case-insensitive)
  # @return [void]
  # @note Retries on SQLite3::BusyException
  def Lich.display_lichid=(val)
    @@display_lichid = (val.to_s =~ /on|true|yes/ ? true : false)
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('display_lichid',?);", [@@display_lichid.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end

  # Returns the UID hiding toggle state.
  #
  # @return [Boolean, nil] true if UIDs should be hidden, nil until a game is identified
  # @note Default: false
  # @note Lazily loaded from lich_settings and cached
  def Lich.hide_uid_flag
    if @@hide_uid_flag.nil?
      begin
        val = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='hide_uid_flag';")
      rescue SQLite3::BusyException
        sleep 0.1
        retry
      end
      val = false if val.nil? and XMLData.game != ""; # default false
      @@hide_uid_flag = (val.to_s =~ /on|true|yes/ ? true : false) if !val.nil?;
    end
    return @@hide_uid_flag
  end

  # Sets and persists the UID hiding toggle state.
  #
  # @param val [String, Boolean] truthy values are "on", "true", or "yes" (case-insensitive)
  # @return [void]
  # @note Retries on SQLite3::BusyException
  def Lich.hide_uid_flag=(val)
    @@hide_uid_flag = (val.to_s =~ /on|true|yes/ ? true : false)
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('hide_uid_flag',?);", [@@hide_uid_flag.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end

  # Retrieves the Lich version string recorded at the last core update.
  #
  # @return [String] the version string, or empty string if not set
  # @note Retries on SQLite3::BusyException
  # @api private
  def Lich.core_updated_with_lich_version
    begin
      val = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='core_updated_with_lich_version';")
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
    return val.to_s
  end

  # Records the Lich version at core update time.
  #
  # @param val [String] the version string to store
  # @return [void]
  # @note Retries on SQLite3::BusyException
  # @api private
  def Lich.core_updated_with_lich_version=(val)
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('core_updated_with_lich_version',?);", [val.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end

  # Returns the UID (unique ID) display toggle, defaulting based on game type.
  #
  # @return [Boolean, nil] true if UIDs should be displayed, nil until a game is identified
  # @note Default: true for GemStone, false for DragonRealms
  # @note Lazily loaded from lich_settings and cached
  def Lich.display_uid
    if @@display_uid.nil?
      begin
        val = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='display_uid';")
      rescue SQLite3::BusyException
        sleep 0.1
        retry
      end
      val = (XMLData.game =~ /^GS/ ? true : false) if val.nil? and XMLData.game != ""; # default false if DR, otherwise default true
      @@display_uid = (val.to_s =~ /on|true|yes/ ? true : false) if !val.nil?;
    end
    return @@display_uid
  end

  # Sets and persists the UID display toggle.
  #
  # @param val [String, Boolean] truthy values are "on", "true", or "yes" (case-insensitive)
  # @return [void]
  # @note Retries on SQLite3::BusyException
  def Lich.display_uid=(val)
    @@display_uid = (val.to_s =~ /on|true|yes/ ? true : false)
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('display_uid',?);", [@@display_uid.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
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
    if @@display_roomid_location.nil?
      begin
        val = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='display_roomid_location';")
      rescue SQLite3::BusyException
        sleep 0.1
        retry
      end
      # Default to the historical below-room line once a game is known; leave unresolved
      # (nil) until then, matching the other display_* getters.
      val = "line" if val.nil? && XMLData.game != ""
      @@display_roomid_location = (ROOMID_LOCATIONS.include?(val) ? val : "line") unless val.nil?
    end
    return @@display_roomid_location
  end

  # Sets the DragonRealms room-id display placement and persists it. An unrecognized value is
  # ignored (the current setting is retained) so a typo can never blank the display or feed the
  # renderer an invalid placement.
  # @param val [String, Symbol] one of ROOMID_LOCATIONS ("title", "line", or "both"); case-insensitive
  # @return [void]
  def Lich.display_roomid_location=(val)
    normalized = val.to_s.downcase
    return unless ROOMID_LOCATIONS.include?(normalized)

    @@display_roomid_location = normalized
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('display_roomid_location',?);", [normalized.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end

  # Returns the room exits display toggle.
  #
  # @return [Boolean, nil] true if room exits should be displayed, nil until a game is identified
  # @note Default: false
  # @note Lazily loaded from lich_settings and cached
  def Lich.display_exits
    if @@display_exits.nil?
      begin
        val = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='display_exits';")
      rescue SQLite3::BusyException
        sleep 0.1
        retry
      end
      val = false if val.nil? and XMLData.game != ""; # default false
      @@display_exits = (val.to_s =~ /on|true|yes/ ? true : false) if !val.nil?;
    end
    return @@display_exits
  end

  # Sets and persists the room exits display toggle.
  #
  # @param val [String, Boolean] truthy values are "on", "true", or "yes" (case-insensitive)
  # @return [void]
  # @note Retries on SQLite3::BusyException
  def Lich.display_exits=(val)
    @@display_exits = (val.to_s =~ /on|true|yes/ ? true : false)
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('display_exits',?);", [@@display_exits.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end

  # Returns the StringProcs display toggle.
  #
  # @return [Boolean, nil] true if StringProcs should be displayed, nil until a game is identified
  # @note Default: false
  # @note Lazily loaded from lich_settings and cached
  def Lich.display_stringprocs
    if @@display_stringprocs.nil?
      begin
        val = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='display_stringprocs';")
      rescue SQLite3::BusyException
        sleep 0.1
        retry
      end
      val = false if val.nil? and XMLData.game != ""; # default false
      @@display_stringprocs = (val.to_s =~ /on|true|yes/ ? true : false) if !val.nil?;
    end
    return @@display_stringprocs
  end

  # Sets and persists the StringProcs display toggle.
  #
  # @param val [String, Boolean] truthy values are "on", "true", or "yes" (case-insensitive)
  # @return [void]
  # @note Retries on SQLite3::BusyException
  def Lich.display_stringprocs=(val)
    @@display_stringprocs = (val.to_s =~ /on|true|yes/ ? true : false)
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('display_stringprocs',?);", [@@display_stringprocs.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
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
    if @@display_room_links.nil?
      begin
        val = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='display_room_links';")
      rescue SQLite3::BusyException
        sleep 0.1
        retry
      end
      val = (XMLData.game =~ /^DR/ ? false : true) if val.nil? and XMLData.game != ""; # default: DR off, others on
      @@display_room_links = (val.to_s =~ /on|true|yes/ ? true : false) if !val.nil?;
    end
    return @@display_room_links
  end

  # Sets and persists the room-exit link toggle.
  # @param val [Boolean, String] truthy values are any of on/true/yes
  # @return [Boolean, String] the value passed in - Ruby assignment methods
  #   always return their argument, not the method body's result
  def Lich.display_room_links=(val)
    @@display_room_links = (val.to_s =~ /on|true|yes/ ? true : false)
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('display_room_links',?);", [@@display_room_links.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
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
    if @@display_room_mono.nil?
      begin
        val = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='display_room_mono';")
      rescue SQLite3::BusyException
        sleep 0.1
        retry
      end
      val = (XMLData.game =~ /^DR/ ? true : false) if val.nil? and XMLData.game != ""; # default: DR on, others off
      @@display_room_mono = (val.to_s =~ /on|true|yes/ ? true : false) if !val.nil?;
    end
    return @@display_room_mono
  end

  # Sets and persists the room-line mono-font toggle.
  # @param val [Boolean, String] truthy values are any of on/true/yes
  # @return [Boolean, String] the value passed in - Ruby assignment methods
  #   always return their argument, not the method body's result
  def Lich.display_room_mono=(val)
    @@display_room_mono = (val.to_s =~ /on|true|yes/ ? true : false)
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('display_room_mono',?);", [@@display_room_mono.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end

  # Returns the experience gains display toggle.
  #
  # @return [Boolean, nil] true if experience gains should be displayed, nil until a game is identified
  # @note Default: true for non-Genie frontends, false for Genie (which has built-in exp tracking)
  # @note Lazily loaded from lich_settings and cached
  def Lich.display_expgains
    if @@display_expgains.nil?
      begin
        val = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='display_expgains';")
      rescue SQLite3::BusyException
        sleep 0.1
        retry
      end
      # Default to true for non-Genie frontends (Genie has built-in exp tracking)
      # Once explicitly set, the persisted value takes precedence
      if val.nil? && XMLData.game != ""
        val = ($frontend == 'genie') ? 'false' : 'true'
      end
      @@display_expgains = (val.to_s =~ /on|true|yes/ ? true : false) if !val.nil?
    end
    @@display_expgains
  end

  # Sets and persists the experience gains display toggle.
  #
  # @param val [String, Boolean] truthy values are "on", "true", or "yes" (case-insensitive)
  # @return [void]
  # @note Retries on SQLite3::BusyException
  def Lich.display_expgains=(val)
    @@display_expgains = (val.to_s =~ /on|true|yes/ ? true : false)
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('display_expgains',?);", [@@display_expgains.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end

  # Returns the autosort state tracking toggle.
  #
  # @return [Boolean] true if autosort state should be tracked, false otherwise
  # @note Lazily loaded from lich_settings and cached
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

  # Sets and persists the autosort state tracking toggle.
  #
  # @param val [String, Boolean] truthy values are "on", "true", or "yes" (case-insensitive)
  # @return [void]
  # @note Retries on SQLite3::BusyException
  def Lich.track_autosort_state=(val)
    @@track_autosort_state = (val.to_s =~ /on|true|yes/ ? true : false)
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('track_autosort_state',?);", [@@track_autosort_state.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end

  # Returns the dark mode state tracking toggle.
  #
  # @return [Boolean] true if dark mode state should be tracked, false otherwise
  # @note Lazily loaded from lich_settings and cached
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

  # Sets and persists the dark mode state tracking toggle.
  #
  # @param val [String, Boolean] truthy values are "on", "true", or "yes" (case-insensitive)
  # @return [void]
  # @note Retries on SQLite3::BusyException
  def Lich.track_dark_mode=(val)
    @@track_dark_mode = (val.to_s =~ /on|true|yes/ ? true : false)
    begin
      Lich.db.execute("INSERT OR REPLACE INTO lich_settings(name,value) values('track_dark_mode',?);", [@@track_dark_mode.to_s.encode('UTF-8')])
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end

  # Returns the layout state tracking toggle.
  #
  # @return [Boolean] true if layout state should be tracked, false otherwise
  # @note Lazily loaded from lich_settings and cached
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

  # Sets and persists the layout state tracking toggle.
  #
  # @param val [String, Boolean] truthy values are "on", "true", or "yes" (case-insensitive)
  # @return [void]
  # @note Retries on SQLite3::BusyException
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
