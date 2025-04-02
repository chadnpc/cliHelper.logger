#!/usr/bin/env pwsh
using namespace System.IO
using namespace System.Text
using namespace System.Threading
using namespace System.Collections.Generic
using namespace System.Management.Automation
using namespace System.Collections.Concurrent

#Requires -Modules PsModuleBase

# Enums
enum LogEventType {
  Debug = 0       # Detailed diagnostic Info
  Info = 1        # General operational information
  Warning = 2     # Indicates a potential problem
  Error = 3       # A recoverable error occurred
  Fatal = 4       # Critical conditions, system may be unusable (same as Critical/Alert/Emergency)
}

# marker classes for log entry data
class ILoggerEntry {
  [string]$Message
  [LogEventType]$Severity
  [Exception]$Exception
  [datetime]$Timestamp = [datetime]::UtcNow
}

class ILoggerAppender {
  [void] Log([ILoggerEntry]$entry) {
    Write-Warning "Log method not implemented in $($this.GetType().Name)"
  }
}

# .EXAMPLE
# [LoggerEntry]::new()
class LoggerEntry : ILoggerEntry {
  static [LoggerEntry] Create([LogEventType]$severity, [string]$message, [System.Exception]$exception) {
    return [LoggerEntry]@{
      Severity  = $severity
      Message   = $message
      Exception = $exception
      Timestamp = [datetime]::UtcNow
    }
  }
}

class Logger : PsModuleBase, IDisposable {
  [LogEventType] $MinimumLevel = [LogEventType]::Info
  [ValidateNotNullOrEmpty()][IO.DirectoryInfo] $LogDirectory
  [ValidateNotNullOrEmpty()][List[ILoggerAppender]] $Appenders
  hidden [Type] $_entryType = [LoggerEntry]
  hidden [bool] $_IsDisposed = $false
  hidden [object] $_disposeLock = [object]::new()
  Logger() {
    [void][Logger]::From(
      [IO.Path]::Combine([IO.Path]::GetTempPath(), [guid]::newguid().guid, 'Logs'),
      [ref]$this
    )
  }
  Logger([string]$LogDirectory) {
    [void][Logger]::From($LogDirectory, [ref]$this)
  }
  static [Logger] From([string]$LogDirectory, [ref]$o) {
    if (![IO.Directory]::Exists($LogDirectory)) {
      try {
        PsModuleBase\New-Directory $LogDirectory
        $o.Value.LogDirectory = [IO.DirectoryInfo]::new($LogDirectory)
      } catch {
        Write-Error "Failed to create log directory '$($o.Value.LogDirectory)':`n$_"
        # Decide if this should be fatal or just prevent file logging later
      }
    }
    $o.Value.Appenders = [List[ILoggerAppender]]::new()
    $o.Value.PsObject.Properties.Add([PsScriptProperty]::new('EntryType', { return $this._entryType }, {
          param($value)
          if ($value -is [Type] -and $value.GetInterfaces().Name -contains 'ILoggerEntry') {
            $this._entryType = $value
          } else {
            throw [SetValueException]::new("EntryType must be a Type that implements ILoggerEntry")
          }
        }
      )
    )
    return $o.Value
  }
  [bool] IsEnabled([LogEventType]$level) {
    return (!$this._IsDisposed) -and ($level -ge $this.MinimumLevel)
  }

  [void] Log([LogEventType]$severity, [string]$message, [Exception]$exception = $null) {
    if (!$this.IsEnabled($severity)) {
      return
    }
    $entry = $this.CreateEntry($severity, $message, $exception)
    $this.ProcessEntry($entry)
  }
  [ILoggerEntry] CreateEntry([LogEventType]$severity, [string]$message) {
    return $this.CreateEntry($severity, $message, $null)
  }
  [ILoggerEntry] CreateEntry([LogEventType]$severity, [string]$message, [Exception]$exception) {
    return $this.EntryType::Create($severity, $message, $exception)
  }

  [void] ProcessEntry([ILoggerEntry]$entry) {
    # Iterate through a copy in case appenders list is modified during enumeration (less likely without async)
    $appendersCopy = $this.Appenders.ToArray()
    foreach ($appender in $appendersCopy) {
      try {
        $appender.Log($entry)
      } catch {
        # Consider logging this error to the console/debug stream, or a fallback logger
        Write-Error "Logger failed processing appender '$($appender.GetType().Name)': $_"
      }
    }
  }

  # --- Convenience Methods ---
  [void] Info([string]$message) { $this.Log([LogEventType]::Info, $message) }
  [void] Debug([string]$message) { $this.Log([LogEventType]::Debug, $message) }

  [void] Warning([string]$message) { $this.Log([LogEventType]::Warning, $message) }

  [void] Error([string]$message) { $this.Error($message, $null) }
  [void] Error([string]$message, [Exception]$exception) { $this.Log([LogEventType]::Error, $message, $exception) }

  [void] Fatal([string]$message) { $this.Fatal($message, $null) }
  [void] Fatal([string]$message, [Exception]$exception = $null) { $this.Log([LogEventType]::Fatal, $message, $exception) }

  [void] Dispose() {
    lock ($this._disposeLock) {
      if ($this._IsDisposed) { return }

      # Dispose appenders that implement IDisposable
      foreach ($appender in $this.Appenders) {
        if ($appender -is [IDisposable]) {
          try {
            $appender.Dispose()
          } catch {
            Write-Error "Error disposing appender '$($appender.GetType().Name)': $_"
          }
        }
      }
      # Clear the list to prevent further use and release references
      $this.Appenders.Clear()
      $this._IsDisposed = $true
    }
    [void][System.GC]::SuppressFinalize($this)
  }
}

# Appender that writes to the PowerShell console with colors
class ConsoleAppender : ILoggerAppender {
  static [hashtable]$ColorMap = @{
    Debug   = [ConsoleColor]::DarkGray
    Info    = [ConsoleColor]::Green
    Warning = [ConsoleColor]::Yellow
    Error   = [ConsoleColor]::Red
    Fatal   = [ConsoleColor]::Magenta
  }

  [void] Log([ILoggerEntry]$entry) {
    # Check if host supports colors - might be unnecessary in modern PS
    $color = [ConsoleAppender]::ColorMap[$entry.Severity.ToString()]
    $timestamp = $entry.Timestamp.ToString('HH:mm:ss') # Concise timestamp for console
    $message = "[$timestamp] [$($entry.Severity.ToString().ToUpper())] $($entry.Message)"

    # Write message
    Write-Host $message -ForegroundColor $color

    # Write exception details if present, use Write-Error for visibility
    if ($null -ne $entry.Exception) {
      # Format exception concisely for console
      $exceptionMessage = "  Exception: $($entry.Exception.GetType().Name): $($entry.Exception.Message)"
      # Optionally include stack trace snippet if needed, but can be verbose
      # $stack = ($entry.Exception.StackTrace -split '\r?\n' | Select-Object -First 3) -join "`n  "
      # $exceptionMessage += "`n  Stack Trace (partial):`n  $stack"
      Write-Error $exceptionMessage # Write-Error uses stderr and default error color
    }
  }
}

# Appender that writes log entries as JSON objects to a file
class JsonAppender : ILoggerAppender, IDisposable {
  [string]$FilePath
  hidden [StreamWriter]$_writer
  hidden [object]$_lock = [object]::new()
  hidden [bool]$_IsDisposed = $false

  JsonAppender([string]$Path) {
    $this.FilePath = Convert-Path $Path # Resolve path
    # Ensure directory exists
    $dir = Split-Path $this.FilePath -Parent
    if (!(Test-Path $dir)) {
      try {
        New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop | Out-Null
      } catch {
        throw "Failed to create directory for JSON appender '$dir': $_"
      }
    }
    try {
      # Open file for appending with UTF8 encoding
      $this._writer = [StreamWriter]::new($this.FilePath, $true, [Encoding]::UTF8)
      $this._writer.AutoFlush = $true # Flush after every write
    } catch {
      throw "Failed to open file for JSON appender '$($this.FilePath)': $_"
    }
  }

  [void] Log([ILoggerEntry]$entry) {
    if ($this._IsDisposed) { return }

    # Create the object to serialize
    $logObject = [ordered]@{
      timestamp = $entry.Timestamp.ToString('o') # ISO 8601 format
      severity  = $entry.Severity.ToString()
      message   = $entry.Message
      # Include full exception string if present
      exception = if ($null -ne $entry.Exception) { $entry.Exception.ToString() } else { $null }
    }

    # Convert to JSON
    $jsonLine = $logObject | ConvertTo-Json -Compress -Depth 5 # Depth important for exceptions

    # Lock and write
    lock ($this._lock) {
      # Re-check disposal after acquiring lock
      if ($this._IsDisposed -or $null -eq $this._writer) { return }
      try {
        $this._writer.WriteLine($jsonLine)
        # AutoFlush is true, manual flush shouldn't be needed unless guaranteeing write before potential crash
      } catch {
        Write-Error "JsonAppender failed to write to '$($this.FilePath)': $_"
        # Consider fallback or temporary disable mechanism here
      }
    }
  }

  [void] Dispose() {
    lock ($this._lock) {
      if ($this._IsDisposed) { return }
      if ($null -ne $this._writer) {
        try {
          $this._writer.Flush() # Final flush
          $this._writer.Dispose()
        } catch {
          Write-Error "JsonAppender error during dispose for file '$($this.FilePath)': $_"
        }
        $this._writer = $null
      }
      $this._IsDisposed = $true
    }
  }
}

# Appender that writes formatted text logs to a file
class FileAppender : ILoggerAppender, IDisposable {
  [string]$FilePath
  hidden [StreamWriter]$_writer
  hidden [ReaderWriterLockSlim]$_lock = [ReaderWriterLockSlim]::new()
  hidden [bool]$_IsDisposed = $false

  FileAppender([string]$Path) {
    $this.FilePath = Convert-Path $Path # Resolve path
    # Ensure directory exists
    $dir = Split-Path $this.FilePath -Parent
    if (!(Test-Path $dir)) {
      try {
        New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop | Out-Null
      } catch {
        throw "Failed to create directory for File appender '$dir': $_"
      }
    }
    try {
      # Open file for appending with UTF8 encoding
      $this._writer = [StreamWriter]::new($this.FilePath, $true, [Encoding]::UTF8)
      $this._writer.AutoFlush = $true # Flush after every write
    } catch {
      throw "Failed to open file for File appender '$($this.FilePath)': $_"
    }
  }

  [void] Log([ILoggerEntry]$entry) {
    if ($this._IsDisposed) { return }

    # Format the log line
    $logLine = "[{0:u}] [{1,-11}] {2}" -f $entry.Timestamp, $entry.Severity.ToString().ToUpper(), $entry.Message
    # Add exception info if present
    if ($null -ne $entry.Exception) {
      # Append exception on new lines, indented for readability
      $exceptionText = ($entry.Exception.ToString() -split '\r?\n' | ForEach-Object { "  $_" }) -join "`n"
      $logLine += "`n$($exceptionText)"
    }

    # Acquire write lock
    $this._lock.EnterWriteLock()
    try {
      # Re-check disposal after acquiring lock
      if ($this._IsDisposed -or $null -eq $this._writer) { return }
      $this._writer.WriteLine($logLine)
      # AutoFlush is true
    } catch {
      Write-Error "FileAppender failed to write to '$($this.FilePath)': $_"
    } finally {
      $this._lock.ExitWriteLock()
    }
  }

  [void] Dispose() {
    # Prevent new logs trying to acquire lock while disposing
    $this._IsDisposed = $true

    $this._lock.EnterWriteLock() # Acquire lock to ensure no writes are happening
    try {
      if ($null -ne $this._writer) {
        try {
          $this._writer.Flush()
          $this._writer.Dispose()
        } catch {
          Write-Error "FileAppender error during dispose for file '$($this.FilePath)': $_"
        }
        $this._writer = $null
      }
    } finally {
      $this._lock.ExitWriteLock()
    }
    # Dispose the lock itself
    $this._lock.Dispose()
  }
}



# A logger that does nothing. Useful as a default or for disabling logging.
class NullLogger : Logger {
  [Type]$EntryType = [LoggerEntry]
  [List[ILoggerAppender]]$Appenders = [List[ILoggerAppender]]::new()
  [LogEventType]$MinimumLevel = [LogEventType]::Fatal + 1 # Set above highest level to disable all
  hidden static [NullLogger]$Instance = [NullLogger]::new()
  NullLogger() {}
  [void] Log([LogEventType]$severity, [string]$message, [Exception]$exception = $null) { } # No-op
  [void] Debug([string]$message) { }
  [void] Info([string]$message) { }
  [void] Warning([string]$message) { }
  [void] Error([string]$message, [Exception]$exception) { }
  [void] Fatal([string]$message, [Exception]$exception) { }
  [bool] IsEnabled([LogEventType]$level) { return $false }
}

$typestoExport = @(
  [Logger], [ILoggerEntry], [ILoggerAppender], [LogEventType], [ConsoleAppender],
  [JsonAppender], [FileAppender], [NullLogger], [LoggerEntry]
)
# Register Type Accelerators
$TypeAcceleratorsClass = [PsObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
foreach ($Type in $typestoExport) {
  if ($Type.FullName -in $TypeAcceleratorsClass::Get.Keys) {
    $Message = @(
      "Unable to register type accelerator '$($Type.FullName)'"
      'Accelerator already exists.'
    ) -join ' - '
    "TypeAcceleratorAlreadyExists $Message" | Write-Debug
  }
}
# Add type accelerators for every exportable type.
foreach ($Type in $typestoExport) {
  $TypeAcceleratorsClass::Add($Type.FullName, $Type)
}
# Remove type accelerators when the module is removed.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
  foreach ($Type in $typestoExport) {
    $TypeAcceleratorsClass::Remove($Type.FullName)
  }
}.GetNewClosure();

$scripts = @();
$Public = Get-ChildItem "$PSScriptRoot/Public" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += Get-ChildItem "$PSScriptRoot/Private" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += $Public

foreach ($file in $scripts) {
  Try {
    if ([string]::IsNullOrWhiteSpace($file.fullname)) { continue }
    . "$($file.fullname)"
  } Catch {
    Write-Warning "Failed to import function $($file.BaseName): $_"
    $host.UI.WriteErrorLine($_)
  }
}

$Param = @{
  Function = $Public.BaseName
  Cmdlet   = '*'
  Alias    = '*'
  Verbose  = $false
}
Export-ModuleMember @Param