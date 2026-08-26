# Lich5 carveout for init_db

#
# Report an error if Lich 4.4 data is found
#
if File.exist?("#{DATA_DIR}/lich.sav")
  Lich.log "error: Archaic Lich 4.4 configuration found: Please remove #{DATA_DIR}/lich.sav"
  Lich.msgbox "error: Archaic Lich 4.4 configuration found: Please remove #{DATA_DIR}/lich.sav"
  exit
end

require_relative 'wine'

begin
  # stupid workaround for Windows
  # seems to avoid a 10 second lag when starting lnet, without adding a 10 second lag at startup
  require 'openssl'
  OpenSSL::PKey::RSA.new(512)
rescue LoadError
  nil # not required for basic Lich; however, lnet and repository scripts will fail without openssl
rescue
  nil
end

## The following should be deprecated with the direct-frontend-launch-method
## TODO: remove as part of chore/Remove unnecessary Win32 calls
## Temporarily reinstatated for DR

if (RUBY_PLATFORM =~ /mingw|win/i) and (RUBY_PLATFORM !~ /darwin/i)
  #
  # Windows API made slightly less annoying
  #
  require 'fiddle'
  require 'fiddle/import'
  # Namespace for Windows API bindings via Fiddle, providing access to kernel, user, shell, and registry operations.
  # Available only on Windows platforms (mingw/win without darwin).
  #
  # @api private
  module Win32
    # Size of a C char in bytes, delegated from Fiddle.
    #
    # @api private
    SIZEOF_CHAR = Fiddle::SIZEOF_CHAR
    # Size of a C long in bytes, delegated from Fiddle.
    #
    # @api private
    SIZEOF_LONG = Fiddle::SIZEOF_LONG
    # Windows API flag for ShellExecuteEx: do not close the process handle automatically.
    #
    # @api private
    SEE_MASK_NOCLOSEPROCESS = 0x00000040
    # Windows API message box button flag: OK button only.
    #
    # @api private
    MB_OK = 0x00000000
    # Windows API message box button flag: OK and Cancel buttons.
    #
    # @api private
    MB_OKCANCEL = 0x00000001
    # Windows API message box button flag: Yes and No buttons.
    #
    # @api private
    MB_YESNO = 0x00000004
    # Windows API message box icon flag: error icon.
    #
    # @api private
    MB_ICONERROR = 0x00000010
    # Windows API message box icon flag: question mark icon.
    #
    # @api private
    MB_ICONQUESTION = 0x00000020
    # Windows API message box icon flag: warning/exclamation icon.
    #
    # @api private
    MB_ICONWARNING = 0x00000030
    IDIOK = 1
    IDICANCEL = 2
    IDIYES = 6
    IDINO = 7
    # Windows registry access flag: all access permissions.
    #
    # @api private
    KEY_ALL_ACCESS = 0xF003F
    # Windows registry access flag: permission to create subkeys.
    #
    # @api private
    KEY_CREATE_SUB_KEY = 0x0004
    # Windows registry access flag: permission to enumerate subkeys.
    #
    # @api private
    KEY_ENUMERATE_SUB_KEYS = 0x0008
    # Windows registry access flag: permission to execute/read registry keys.
    #
    # @api private
    KEY_EXECUTE = 0x20019
    # Windows registry access flag: permission to request change notifications.
    #
    # @api private
    KEY_NOTIFY = 0x0010
    # Windows registry access flag: permission to query registry value data.
    #
    # @api private
    KEY_QUERY_VALUE = 0x0001
    # Windows registry access flag: read permissions for registry keys.
    #
    # @api private
    KEY_READ = 0x20019
    # Windows registry access flag: permission to set registry value data.
    #
    # @api private
    KEY_SET_VALUE = 0x0002
    # Windows registry access flag: access 32-bit registry view on 64-bit Windows.
    #
    # @api private
    KEY_WOW64_32KEY = 0x0200
    # Windows registry access flag: access 64-bit registry view on 64-bit Windows.
    #
    # @api private
    KEY_WOW64_64KEY = 0x0100
    # Windows registry access flag: write permissions for registry keys.
    #
    # @api private
    KEY_WRITE = 0x20006
    TokenElevation = 20
    TOKEN_QUERY = 8
    STILL_ACTIVE = 259
    SW_SHOWNORMAL = 1
    SW_SHOW = 5
    PROCESS_QUERY_INFORMATION = 1024
    PROCESS_VM_READ = 16
    HKEY_LOCAL_MACHINE = -2147483646
    REG_NONE = 0
    REG_SZ = 1
    REG_EXPAND_SZ = 2
    REG_BINARY = 3
    REG_DWORD = 4
    REG_DWORD_LITTLE_ENDIAN = 4
    REG_DWORD_BIG_ENDIAN = 5
    REG_LINK = 6
    REG_MULTI_SZ = 7
    REG_QWORD = 11
    REG_QWORD_LITTLE_ENDIAN = 11

    module Kernel32
      extend Fiddle::Importer
      dlload 'kernel32'
      extern 'int GetCurrentProcess()'
      extern 'int GetExitCodeProcess(int, int*)'
      extern 'int GetModuleFileName(int, void*, int)'
      extern 'int GetVersionEx(void*)'
      #         extern 'int OpenProcess(int, int, int)' # fixme
      extern 'int GetLastError()'
      extern 'int CreateProcess(void*, void*, void*, void*, int, int, void*, void*, void*, void*)'
    end

    # Retrieves the last error code from the Windows API.
    #
    # @return [Integer] the error code
    # @api private
    def Win32.GetLastError
      return Kernel32.GetLastError()
    end

    # Creates a new process on Windows.
    #
    # @param args [Hash] process creation parameters
    # @option args [String] :lpCommandLine command line string (will be duplicated internally)
    # @option args [Boolean, Integer] :bInheritHandles whether to inherit handles; true/false or 0/1
    # @option args [String, nil] :lpApplicationName application executable path
    # @option args [String, nil] :lpProcessAttributes process security attributes
    # @option args [String, nil] :lpThreadAttributes thread security attributes
    # @option args [Integer] :dwCreationFlags process creation flags
    # @option args [String, nil] :lpEnvironment environment block (Array not yet supported)
    # @option args [String, nil] :lpCurrentDirectory working directory
    # @option args [Integer] :dwX window X position
    # @option args [Integer] :dwY window Y position
    # @option args [Integer] :dwXSize window width
    # @option args [Integer] :dwYSize window height
    # @return [Hash] result hash with keys: :return (Boolean), :hProcess, :hThread, :dwProcessId, :dwThreadId
    # @api private
    def Win32.CreateProcess(args)
      if args[:lpCommandLine]
        lpCommandLine = args[:lpCommandLine].dup
      else
        lpCommandLine = nil
      end
      if args[:bInheritHandles] == false
        bInheritHandles = 0
      elsif args[:bInheritHandles] == true
        bInheritHandles = 1
      else
        bInheritHandles = args[:bInheritHandles].to_i
      end
      if args[:lpEnvironment].is_a?(Array)
        # fixme
      end
      lpStartupInfo = [68, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
      lpStartupInfo_index = { :lpDesktop => 2, :lpTitle => 3, :dwX => 4, :dwY => 5, :dwXSize => 6, :dwYSize => 7, :dwXCountChars => 8, :dwYCountChars => 9, :dwFillAttribute => 10, :dwFlags => 11, :wShowWindow => 12, :hStdInput => 15, :hStdOutput => 16, :hStdError => 17 }
      for sym in [:lpDesktop, :lpTitle]
        if args[sym]
          args[sym] = "#{args[sym]}\0" unless args[sym][-1, 1] == "\0"
          lpStartupInfo[lpStartupInfo_index[sym]] = Fiddle::Pointer.to_ptr(args[sym]).to_i
        end
      end
      for sym in [:dwX, :dwY, :dwXSize, :dwYSize, :dwXCountChars, :dwYCountChars, :dwFillAttribute, :dwFlags, :wShowWindow, :hStdInput, :hStdOutput, :hStdError]
        if args[sym]
          lpStartupInfo[lpStartupInfo_index[sym]] = args[sym]
        end
      end
      lpStartupInfo = lpStartupInfo.pack('LLLLLLLLLLLLSSLLLL')
      lpProcessInformation = [0, 0, 0, 0,].pack('LLLL')
      r = Kernel32.CreateProcess(args[:lpApplicationName], lpCommandLine, args[:lpProcessAttributes], args[:lpThreadAttributes], bInheritHandles, args[:dwCreationFlags].to_i, args[:lpEnvironment], args[:lpCurrentDirectory], lpStartupInfo, lpProcessInformation)
      lpProcessInformation = lpProcessInformation.unpack('LLLL')
      return :return => (r > 0 ? true : false), :hProcess => lpProcessInformation[0], :hThread => lpProcessInformation[1], :dwProcessId => lpProcessInformation[2], :dwThreadId => lpProcessInformation[3]
    end

    #      Win32.CreateProcess(:lpApplicationName => 'Launcher.exe', :lpCommandLine => 'lich2323.sal', :lpCurrentDirectory => 'C:\\PROGRA~1\\SIMU')
    #      def Win32.OpenProcess(args={})
    #         return Kernel32.OpenProcess(args[:dwDesiredAccess].to_i, args[:bInheritHandle].to_i, args[:dwProcessId].to_i)
    #      end
    def Win32.GetCurrentProcess
      return Kernel32.GetCurrentProcess
    end

    # Retrieves the exit code of a process.
    #
    # @param args [Hash] process handle parameters
    # @option args [Integer] :hProcess handle to the process
    # @return [Hash] result hash with keys: :return (Integer), :lpExitCode (Integer)
    # @api private
    def Win32.GetExitCodeProcess(args)
      lpExitCode = [0].pack('L')
      r = Kernel32.GetExitCodeProcess(args[:hProcess].to_i, lpExitCode)
      return :return => r, :lpExitCode => lpExitCode.unpack('L')[0]
    end

    # Retrieves the filename of a loaded module.
    #
    # @param args [Hash] module parameters
    # @option args [Integer] :hModule module handle (defaults to current process if omitted)
    # @option args [Integer] :nSize buffer size in bytes (default: 256)
    # @return [Hash] result hash with keys: :return (Integer), :lpFilename (String without null terminators)
    # @api private
    def Win32.GetModuleFileName(args = {})
      args[:nSize] ||= 256
      buffer = "\0" * args[:nSize].to_i
      r = Kernel32.GetModuleFileName(args[:hModule].to_i, buffer, args[:nSize].to_i)
      return :return => r, :lpFilename => buffer.gsub("\0", '')
    end

    # Retrieves Windows OS version information.
    #
    # @return [Hash] result hash with keys: :return (Integer), :dwOSVersionInfoSize, :dwMajorVersion, :dwMinorVersion, :dwBuildNumber, :dwPlatformId, :szCSDVersion (String), :wServicePackMajor, :wServicePackMinor, :wSuiteMask, :wProductType
    # @api private
    def Win32.GetVersionEx
      a = [156, 0, 0, 0, 0, ("\0" * 128), 0, 0, 0, 0, 0].pack('LLLLLa128SSSCC')
      r = Kernel32.GetVersionEx(a)
      a = a.unpack('LLLLLa128SSSCC')
      return :return => r, :dwOSVersionInfoSize => a[0], :dwMajorVersion => a[1], :dwMinorVersion => a[2], :dwBuildNumber => a[3], :dwPlatformId => a[4], :szCSDVersion => a[5].strip, :wServicePackMajor => a[6], :wServicePackMinor => a[7], :wSuiteMask => a[8], :wProductType => a[9]
    end

    # Fiddle binding to the Windows user32 library.
    #
    # @api private
    module User32
      extend Fiddle::Importer
      dlload 'user32'
      extern 'int MessageBox(int, char*, char*, int)'
    end

    # Displays a message box dialog on Windows.
    #
    # @param args [Hash] message box parameters
    # @option args [Integer] :hWnd parent window handle
    # @option args [String] :lpText message text
    # @option args [String] :lpCaption window title (default: "Lich v#{LICH_VERSION}")
    # @option args [Integer] :uType message box type flags (buttons and icons)
    # @return [Integer] dialog result code
    # @api private
    def Win32.MessageBox(args)
      args[:lpCaption] ||= "Lich v#{LICH_VERSION}"
      return User32.MessageBox(args[:hWnd].to_i, args[:lpText], args[:lpCaption], args[:uType].to_i)
    end

    # Fiddle binding to the Windows advapi32 library (Advanced Windows API).
    #
    # @api private
    module Advapi32
      extend Fiddle::Importer
      dlload 'advapi32'
      extern 'int GetTokenInformation(int, int, void*, int, void*)'
      extern 'int OpenProcessToken(int, int, void*)'
      extern 'int RegOpenKeyEx(int, char*, int, int, void*)'
      extern 'int RegQueryValueEx(int, char*, void*, void*, void*, void*)'
      extern 'int RegSetValueEx(int, char*, int, int, char*, int)'
      extern 'int RegDeleteValue(int, char*)'
      extern 'int RegCloseKey(int)'
    end

    # Retrieves information about an access token.
    #
    # @param args [Hash] token parameters
    # @option args [Integer] :TokenHandle handle to the access token
    # @option args [Integer] :TokenInformationClass information class (e.g., TokenElevation)
    # @return [Hash, nil] result hash with keys: :return (Integer), :TokenIsElevated (Integer); nil if TokenInformationClass is not TokenElevation
    # @api private
    def Win32.GetTokenInformation(args)
      if args[:TokenInformationClass] == TokenElevation
        token_information_length = SIZEOF_LONG
        token_information = [0].pack('L')
      else
        return nil
      end
      return_length = [0].pack('L')
      r = Advapi32.GetTokenInformation(args[:TokenHandle].to_i, args[:TokenInformationClass], token_information, token_information_length, return_length)
      if args[:TokenInformationClass] == TokenElevation
        return :return => r, :TokenIsElevated => token_information.unpack('L')[0]
      end
    end

    # Opens an access token associated with a process.
    #
    # @param args [Hash] process token parameters
    # @option args [Integer] :ProcessHandle process handle
    # @option args [Integer] :DesiredAccess desired access level (e.g., TOKEN_QUERY)
    # @return [Hash] result hash with keys: :return (Integer), :TokenHandle (Integer)
    # @api private
    def Win32.OpenProcessToken(args)
      token_handle = [0].pack('L')
      r = Advapi32.OpenProcessToken(args[:ProcessHandle].to_i, args[:DesiredAccess].to_i, token_handle)
      return :return => r, :TokenHandle => token_handle.unpack('L')[0]
    end

    # Opens a registry key with extended options.
    #
    # @param args [Hash] registry key parameters
    # @option args [Integer] :hKey parent registry key handle
    # @option args [String] :lpSubKey subkey path
    # @option args [Integer] :samDesired desired access level
    # @return [Hash] result hash with keys: :return (Integer), :phkResult (Integer, opened key handle)
    # @api private
    def Win32.RegOpenKeyEx(args)
      phkResult = [0].pack('L')
      r = Advapi32.RegOpenKeyEx(args[:hKey].to_i, args[:lpSubKey].to_s, 0, args[:samDesired].to_i, phkResult)
      return :return => r, :phkResult => phkResult.unpack('L')[0]
    end

    # Queries a registry value, automatically converting to the appropriate Ruby type.
    #
    # @param args [Hash] registry value parameters
    # @option args [Integer] :hKey registry key handle
    # @option args [String] :lpValueName value name (default: nil)
    # @return [Hash] result hash with keys: :return (Integer), :lpType (Integer, registry type), :lpcbData (Integer, size), :lpData (String, Integer, Array, or nil depending on type)
    # @note REG_SZ, REG_EXPAND_SZ, REG_LINK are returned as String; REG_MULTI_SZ as Array<String>; REG_DWORD as Integer; REG_QWORD as Integer; others are unparsed
    # @api private
    def Win32.RegQueryValueEx(args)
      args[:lpValueName] ||= 0
      lpcbData = [0].pack('L')
      r = Advapi32.RegQueryValueEx(args[:hKey].to_i, args[:lpValueName], 0, 0, 0, lpcbData)
      if r == 0
        lpcbData = lpcbData.unpack('L')[0]
        lpData = String.new.rjust(lpcbData, "\x00")
        lpcbData = [lpcbData].pack('L')
        lpType = [0].pack('L')
        r = Advapi32.RegQueryValueEx(args[:hKey].to_i, args[:lpValueName], 0, lpType, lpData, lpcbData)
        lpType = lpType.unpack('L')[0]
        lpcbData = lpcbData.unpack('L')[0]
        if [REG_EXPAND_SZ, REG_SZ, REG_LINK].include?(lpType)
          lpData.gsub!("\x00", '')
        elsif lpType == REG_MULTI_SZ
          lpData = lpData.gsub("\x00\x00", '').split("\x00")
        elsif lpType == REG_DWORD
          lpData = lpData.unpack('L')[0]
        elsif lpType == REG_QWORD
          lpData = lpData.unpack('Q')[0]
        elsif lpType == REG_BINARY
          # fixme
        elsif lpType == REG_DWORD_BIG_ENDIAN
          # fixme
        else
          # fixme
        end
        return :return => r, :lpType => lpType, :lpcbData => lpcbData, :lpData => lpData
      else
        return :return => r
      end
    end

    # Sets a registry value, converting from Ruby types to Windows registry format.
    #
    # @param args [Hash] registry value parameters
    # @option args [Integer] :hKey registry key handle
    # @option args [String] :lpValueName value name (default: nil)
    # @option args [Integer] :dwType registry data type (REG_SZ, REG_DWORD, REG_MULTI_SZ, REG_QWORD, etc.)
    # @option args [String, Integer, Array] :lpData data to store (must match dwType)
    # @return [Integer] Windows API result code; false if dwType is REG_BINARY or REG_DWORD_BIG_ENDIAN (not yet implemented)
    # @api private
    def Win32.RegSetValueEx(args)
      if [REG_EXPAND_SZ, REG_SZ, REG_LINK].include?(args[:dwType]) and (args[:lpData].is_a?(String))
        lpData = args[:lpData].dup
        lpData.concat("\x00")
        cbData = lpData.length
      elsif (args[:dwType] == REG_MULTI_SZ) and (args[:lpData].is_a?(Array))
        lpData = args[:lpData].join("\x00").concat("\x00\x00")
        cbData = lpData.length
      elsif (args[:dwType] == REG_DWORD) and (args[:lpData].is_a?(Integer))
        lpData = [args[:lpData]].pack('L')
        cbData = 4
      elsif (args[:dwType] == REG_QWORD) and (args[:lpData].is_a?(Integer))
        lpData = [args[:lpData]].pack('Q')
        cbData = 8
      elsif args[:dwType] == REG_BINARY
        # fixme
        return false
      elsif args[:dwType] == REG_DWORD_BIG_ENDIAN
        # fixme
        return false
      else
        # fixme
        return false
      end
      args[:lpValueName] ||= 0
      return Advapi32.RegSetValueEx(args[:hKey].to_i, args[:lpValueName], 0, args[:dwType], lpData, cbData)
    end

    # Deletes a registry value.
    #
    # @param args [Hash] registry value parameters
    # @option args [Integer] :hKey registry key handle
    # @option args [String] :lpValueName value name (default: nil)
    # @return [Integer] Windows API result code
    # @api private
    def Win32.RegDeleteValue(args)
      args[:lpValueName] ||= 0
      return Advapi32.RegDeleteValue(args[:hKey].to_i, args[:lpValueName])
    end

    # Closes a registry key handle.
    #
    # @param args [Hash] registry key parameters
    # @option args [Integer] :hKey registry key handle
    # @return [Integer] Windows API result code
    # @api private
    def Win32.RegCloseKey(args)
      return Advapi32.RegCloseKey(args[:hKey])
    end

    # Fiddle binding to the Windows shell32 library.
    #
    # @api private
    module Shell32
      extend Fiddle::Importer
      dlload 'shell32'
      extern 'int ShellExecuteEx(void*)'
      extern 'int ShellExecute(int, char*, char*, char*, char*, int)'
    end

    # Executes a file with extended shell options (includes UAC elevation support).
    #
    # @param args [Hash] shell execution parameters
    # @option args [String] :lpVerb verb to perform, e.g. 'open', 'edit', 'runas' (for elevation)
    # @option args [String] :lpFile file or URL to execute
    # @option args [String] :lpParameters command-line arguments
    # @option args [String] :lpDirectory working directory
    # @option args [Integer] :nShow window display flag (e.g., SW_SHOW, SW_SHOWNORMAL)
    # @option args [Integer] :fMask operation flags
    # @option args [Integer] :hwnd parent window handle
    # @option args [Integer] :hkeyClass registry key for file class
    # @option args [Integer] :dwHotKey hot key
    # @option args [Integer] :hIcon icon handle
    # @option args [Integer] :hMonitor monitor handle
    # @return [Hash] result hash with keys: :return (Integer), :hProcess (Integer), :hInstApp (Integer)
    # @api private
    def Win32.ShellExecuteEx(args)
      #         struct = [ (SIZEOF_LONG * 15), 0, 0, 0, 0, 0, 0, SW_SHOWNORMAL, 0, 0, 0, 0, 0, 0, 0 ]
      struct = [(SIZEOF_LONG * 15), 0, 0, 0, 0, 0, 0, SW_SHOW, 0, 0, 0, 0, 0, 0, 0]
      struct_index = { :cbSize => 0, :fMask => 1, :hwnd => 2, :lpVerb => 3, :lpFile => 4, :lpParameters => 5, :lpDirectory => 6, :nShow => 7, :hInstApp => 8, :lpIDList => 9, :lpClass => 10, :hkeyClass => 11, :dwHotKey => 12, :hIcon => 13, :hMonitor => 13, :hProcess => 14 }
      for sym in [:lpVerb, :lpFile, :lpParameters, :lpDirectory, :lpIDList, :lpClass]
        if args[sym]
          args[sym] = "#{args[sym]}\0" unless args[sym][-1, 1] == "\0"
          struct[struct_index[sym]] = Fiddle::Pointer.to_ptr(args[sym]).to_i
        end
      end
      for sym in [:fMask, :hwnd, :nShow, :hkeyClass, :dwHotKey, :hIcon, :hMonitor, :hProcess]
        if args[sym]
          struct[struct_index[sym]] = args[sym]
        end
      end
      struct = struct.pack('LLLLLLLLLLLLLLL')
      r = Shell32.ShellExecuteEx(struct)
      struct = struct.unpack('LLLLLLLLLLLLLLL')
      return :return => r, :hProcess => struct[struct_index[:hProcess]], :hInstApp => struct[struct_index[:hInstApp]]
    end

    # Executes a file with basic shell options.
    #
    # @param args [Hash] shell execution parameters
    # @option args [Integer] :hwnd parent window handle
    # @option args [String] :lpOperation verb ('open', 'edit', etc.; default: nil)
    # @option args [String] :lpFile file or URL to execute
    # @option args [String] :lpParameters command-line arguments (default: nil)
    # @option args [String] :lpDirectory working directory (default: nil)
    # @option args [Integer] :nShowCmd window display flag (default: 1)
    # @return [Integer] Windows API result code
    # @api private
    def Win32.ShellExecute(args)
      args[:lpOperation] ||= 0
      args[:lpParameters] ||= 0
      args[:lpDirectory] ||= 0
      args[:nShowCmd] ||= 1
      return Shell32.ShellExecute(args[:hwnd].to_i, args[:lpOperation], args[:lpFile], args[:lpParameters], args[:lpDirectory], args[:nShowCmd])
    end

    begin
      # Extended Fiddle binding to kernel32 for process enumeration.
      #
      # @api private
      module Kernel32
        extern 'int EnumProcesses(void*, int, void*)'
      end

      def Win32.EnumProcesses(args = {})
        args[:cb] ||= 400
        pProcessIds = Array.new((args[:cb] / SIZEOF_LONG), 0).pack(''.rjust((args[:cb] / SIZEOF_LONG), 'L'))
        pBytesReturned = [0].pack('L')
        r = Kernel32.EnumProcesses(pProcessIds, args[:cb], pBytesReturned)
        pBytesReturned = pBytesReturned.unpack('L')[0]
        return :return => r, :pProcessIds => pProcessIds.unpack(''.rjust((args[:cb] / SIZEOF_LONG), 'L'))[0...(pBytesReturned / SIZEOF_LONG)], :pBytesReturned => pBytesReturned
      end
    rescue
      # Fiddle binding to the Windows psapi library (fallback for process enumeration).
      #
      # @api private
      module Psapi
        extend Fiddle::Importer
        dlload 'psapi'
        extern 'int EnumProcesses(void*, int, void*)'
      end

      # Enumerates all running process IDs on Windows via psapi (fallback implementation).
      #
      # @param args [Hash] enumeration parameters
      # @option args [Integer] :cb buffer size in bytes (default: 400)
      # @return [Hash] result hash with keys: :return (Integer), :pProcessIds (Array<Integer>), :pBytesReturned (Integer, bytes actually populated)
      # @api private
      def Win32.EnumProcesses(args = {})
        args[:cb] ||= 400
        pProcessIds = Array.new((args[:cb] / SIZEOF_LONG), 0).pack(''.rjust((args[:cb] / SIZEOF_LONG), 'L'))
        pBytesReturned = [0].pack('L')
        r = Psapi.EnumProcesses(pProcessIds, args[:cb], pBytesReturned)
        pBytesReturned = pBytesReturned.unpack('L')[0]
        return :return => r, :pProcessIds => pProcessIds.unpack(''.rjust((args[:cb] / SIZEOF_LONG), 'L'))[0...(pBytesReturned / SIZEOF_LONG)], :pBytesReturned => pBytesReturned
      end
    end

    # Checks whether the operating system is Windows XP or earlier.
    #
    # @return [Boolean] true if OS major version is less than 6 (XP and below), false otherwise
    # @api private
    def Win32.isXP?
      return (Win32.GetVersionEx[:dwMajorVersion] < 6)
    end

    #      def Win32.isWin8?
    #         r = Win32.GetVersionEx
    #         return ((r[:dwMajorVersion] == 6) and (r[:dwMinorVersion] >= 2))
    #      end
    def Win32.admin?
      if Win32.isXP?
        return true
      else
        r = Win32.OpenProcessToken(:ProcessHandle => Win32.GetCurrentProcess, :DesiredAccess => TOKEN_QUERY)
        token_handle = r[:TokenHandle]
        r = Win32.GetTokenInformation(:TokenInformationClass => TokenElevation, :TokenHandle => token_handle)
        return (r[:TokenIsElevated] != 0)
      end
    end

    # Elevates the current Lich process via UAC and executes a shell command with admin privileges.
    #
    # @param args [Hash] shell execution parameters (see .Win32.ShellExecute)
    # @note Only executes if not already running in an eval/run context (to prevent infinite recursion)
    # @return [void]
    # @api private
    def Win32.AdminShellExecute(args)
      # open ruby/lich as admin and tell it to open something else
      if not caller.any? { |c| c =~ /eval|run/ }
        r = Win32.GetModuleFileName
        if r[:return] > 0
          if File.exist?(r[:lpFilename])
            Win32.ShellExecuteEx(:lpVerb => 'runas', :lpFile => r[:lpFilename], :lpParameters => "#{File.expand_path($PROGRAM_NAME)} shellexecute #{[Marshal.dump(args)].pack('m').gsub("\n", '')}")
          end
        end
      end
    end
  end
end

if ARGV[0] == 'shellexecute'
  args = Marshal.load(Marshal.dump(ARGV[1].unpack('m')[0]))
  Win32.ShellExecute(:lpOperation => args[:op], :lpFile => args[:file], :lpDirectory => args[:dir], :lpParameters => args[:params])
  exit
end

## End of TODO

begin
  require 'sqlite3'
rescue LoadError => sqlite_load_error
  # sqlite3 is a required dependency. It is restored only from an approved,
  # hash-verified Ruby4Lich5 manifest unit; this never falls back to `gem
  # install` or a user GEM_HOME.
  unless Lich::GemCheck.self_healing_supported?
    Lich::GemCheck.alert(missing: ['sqlite3'], groups: [:default], error: sqlite_load_error)
    exit 1
  end

  result = Lich::GemCheck.recover_with_consent!(['sqlite3'], force: true, groups: [:default])
  if result.nil?
    exit 1
  elsif result.restart_required
    exit 0
  elsif result.success?
    begin
      require 'sqlite3'
    rescue LoadError => e
      Lich::GemCheck.alert(missing: ['sqlite3'], groups: [:default], error: e)
      exit 1
    end
  else
    Lich::GemCheck.alert(
      missing: ['sqlite3'], groups: [:default], error: Lich::DependencyRecovery::Error.new(result.error)
    )
    exit 1
  end
end

unless ARGV.any? { |arg| arg.match?(/^--no-(?:gtk|gui)$/i) }
  begin
    require 'gtk3'
    HAVE_GTK = true
  rescue LoadError => gtk_load_error
    # gtk3 stands for the whole GTK runtime unit in the manifest. A missing
    # native dependency therefore restores the complete, ordered closure.
    if Lich::GemCheck.self_healing_supported?
      result = Lich::GemCheck.recover_with_consent!(['gtk3'], force: true, groups: [:gtk])
      if result.nil?
        exit 1
      elsif result.restart_required
        exit 0
      elsif result.success?
        begin
          require 'gtk3'
          HAVE_GTK = true
        rescue LoadError => recovered_error
          Lich::GemCheck.alert(missing: ['gtk3'], groups: [:gtk], error: recovered_error)
          exit 1
        end
      else
        Lich::GemCheck.alert(
          missing: ['gtk3'], groups: [:gtk], error: Lich::DependencyRecovery::Error.new(result.error)
        )
        exit 1
      end
    else
      # GTK is required unless the user explicitly selected a headless launch.
      # Do not infer that choice from DISPLAY, TTY, or cron environment state.
      Lich::GemCheck.alert(missing: ['gtk3'], groups: [:gtk], error: gtk_load_error)
      exit 1
    end
  end
else
  HAVE_GTK = false
  @early_gtk_error = 'info: GTK disabled by command-line option'
end

unless File.exist?(LICH_DIR)
  begin
    Dir.mkdir(LICH_DIR)
  rescue
    message = "An error occured while attempting to create directory #{LICH_DIR}\n\n"
    if not File.exist?(LICH_DIR.sub(/[\\\/]$/, '').slice(/^.+[\\\/]/).chop)
      message.concat "This was likely because the parent directory (#{LICH_DIR.sub(/[\\\/]$/, '').slice(/^.+[\\\/]/).chop}) doesn't exist."
    elsif defined?(Win32) and (Win32.GetVersionEx[:dwMajorVersion] >= 6) and (dir !~ /^[A-z]\:\\(Users|Documents and Settings)/)
      message.concat "This was likely because Lich doesn't have permission to create files and folders here.  It is recommended to put Lich in your Documents folder."
    else
      message.concat $!
    end
    Lich.msgbox(:message => message, :icon => :error)
    exit
  end
end

Dir.chdir(LICH_DIR)

unless File.exist?(TEMP_DIR)
  begin
    Dir.mkdir(TEMP_DIR)
  rescue
    message = "An error occured while attempting to create directory #{TEMP_DIR}\n\n"
    if not File.exist?(TEMP_DIR.sub(/[\\\/]$/, '').slice(/^.+[\\\/]/).chop)
      message.concat "This was likely because the parent directory (#{TEMP_DIR.sub(/[\\\/]$/, '').slice(/^.+[\\\/]/).chop}) doesn't exist."
    elsif defined?(Win32) and (Win32.GetVersionEx[:dwMajorVersion] >= 6) and (dir !~ /^[A-z]\:\\(Users|Documents and Settings)/)
      message.concat "This was likely because Lich doesn't have permission to create files and folders here.  It is recommended to put Lich in your Documents folder."
    else
      message.concat $!
    end
    Lich.msgbox(:message => message, :icon => :error)
    exit
  end
end

begin
  debug_filename = "#{TEMP_DIR}/debug-#{Time.now.strftime("%Y-%m-%d-%H-%M-%S-%L")}.log"
  $stderr = File.open(debug_filename, 'w')
rescue
  message = "An error occured while attempting to create file #{debug_filename}\n\n"
  if defined?(Win32) and (TEMP_DIR !~ /^[A-z]\:\\(Users|Documents and Settings)/) and not Win32.isXP?
    message.concat "This was likely because Lich doesn't have permission to create files and folders here.  It is recommended to put Lich in your Documents folder."
  else
    message.concat $!
  end
  Lich.msgbox(:message => message, :icon => :error)
  exit
end

$stderr.sync = true
Lich.log "info: Lich #{LICH_VERSION}"
Lich.log "info: Branch - #{LICH_BRANCH}" if defined?(LICH_BRANCH)
Lich.log "info: Repo - #{LICH_BRANCH_REPO}" if defined?(LICH_BRANCH_REPO)
Lich.log "info: Ruby #{RUBY_VERSION}"
Lich.log "info: #{RUBY_PLATFORM}"
Lich.log @early_gtk_error if @early_gtk_error
@early_gtk_error = nil

unless File.exist?(DATA_DIR)
  begin
    Dir.mkdir(DATA_DIR)
  rescue
    Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
    Lich.msgbox(:message => "An error occured while attempting to create directory #{DATA_DIR}\n\n#{$!}", :icon => :error)
    exit
  end
end
unless File.exist?(SCRIPT_DIR)
  begin
    Dir.mkdir(SCRIPT_DIR)
  rescue
    Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
    Lich.msgbox(:message => "An error occured while attempting to create directory #{SCRIPT_DIR}\n\n#{$!}", :icon => :error)
    exit
  end
end
unless File.exist?("#{SCRIPT_DIR}/custom")
  begin
    Dir.mkdir("#{SCRIPT_DIR}/custom")
  rescue
    Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
    Lich.msgbox(:message => "An error occured while attempting to create directory #{SCRIPT_DIR}/custom\n\n#{$!}", :icon => :error)
    exit
  end
end
unless File.exist?(MAP_DIR)
  begin
    Dir.mkdir(MAP_DIR)
  rescue
    Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
    Lich.msgbox(:message => "An error occured while attempting to create directory #{MAP_DIR}\n\n#{$!}", :icon => :error)
    exit
  end
end
unless File.exist?(LOG_DIR)
  begin
    Dir.mkdir(LOG_DIR)
  rescue
    Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
    Lich.msgbox(:message => "An error occured while attempting to create directory #{LOG_DIR}\n\n#{$!}", :icon => :error)
    exit
  end
end
unless File.exist?(BACKUP_DIR)
  begin
    Dir.mkdir(BACKUP_DIR)
  rescue
    Lich.log "error: #{$!}\n\t#{$!.backtrace.join("\n\t")}"
    Lich.msgbox(:message => "An error occured while attempting to create directory #{BACKUP_DIR}\n\n#{$!}", :icon => :error)
    exit
  end
end

Lich.init_db

Lich.cleanup_debug_logs(TEMP_DIR)

# todo: deprecate / remove for Ruby 3.2.1?
if (RUBY_VERSION =~ /^2\.[012]\./)
  begin
    did_trusted_defaults = Lich.db.get_first_value("SELECT value FROM lich_settings WHERE name='did_trusted_defaults';")
  rescue SQLite3::BusyException
    sleep 0.1
    retry
  end
  if did_trusted_defaults.nil?
    Script.trust('repository')
    Script.trust('lnet')
    Script.trust('narost')
    begin
      Lich.db.execute("INSERT INTO lich_settings(name,value) VALUES('did_trusted_defaults', 'yes');")
    rescue SQLite3::BusyException
      sleep 0.1
      retry
    end
  end
end
