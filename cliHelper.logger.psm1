#!/usr/bin/env pwsh

using namespace System.IO
using namespace System.Text
using namespace System.Threading
using namespace System.Collections.Generic
using namespace System.Collections.Concurrent # Added for potential future async

#region Enums and Interfaces

enum LogEventType {
  # Ordered from least to most severe
  Debug = 0       # Detailed diagnostic information
  Information = 1 # General operational information (Info)
  Warning = 2     # Indicates a potential problem
  Error = 3       # A recoverable error occurred
  Fatal = 4       # Critical conditions, system may be unusable (Critical/Alert/Emergency mapped here)
}

# Interface for log entry data
class ILoggerEntry {
  [LogEventType]$Severity
  [string]$Message
  [Exception]$Exception
  [datetime]$Timestamp # Set by the factory method
}

# Interface for log appenders (consumers)
class ILoggerAppender {
  # Method to be implemented by appenders to process a log entry
  [void] Log([ILoggerEntry]$entry) { Write-Warning "Log method not implemented in $($this.GetType().Name)" }
}

#endregion

#region Logger Core Classes

# Default implementation of a log entry
class LoggerEntry : ILoggerEntry {
  # Factory method to create a new entry
  static [ILoggerEntry] NewEntry([LogEventType]$severity, [string]$message, [System.Exception]$exception) {
    return [LoggerEntry]@{
      Severity  = $severity
      Message   = $message
      Exception = $exception
      Timestamp = [datetime]::UtcNow
    }
  }
}

# Main Logger class - manages appenders and processes log entries
class Logger : IDisposable {
  hidden [LogEventType]$_minimumLevel = [LogEventType]::Information
  hidden [Type]$_entryType = [LoggerEntry]
  hidden [bool]$_isDisposed = $false
  hidden [object]$_disposeLock = [object]::new()

  # Public properties
  [string]$LogDirectory # Optional: Primarily for reference or default file appender location
  [List[ILoggerAppender]]$Appenders
  # [Type]$EntryType {
  #   get { return $this._entryType }
  #   Set-Variable {
  #     if ($value -is [Type] -and $value.GetInterfaces().Name -contains 'ILoggerEntry') {
  #       $this._entryType = $value
  #     } else {
  #       throw "EntryType must be a Type that implements ILoggerEntry"
  #     }
  #   }
  # }
  # [LogEventType]$MinimumLevel {
  #   get { return $this._minimumLevel }
  #   Set-Variable { $this._minimumLevel = $value }
  # }

  # Static default directory (initialized below class definition)
  static [string]$DefaultLogDirectory

  # Constructors
  Logger([string]$logDirectory = $null) {
    $this.Appenders = [List[ILoggerAppender]]::new()
    # Use provided directory or the static default if null/empty
    $this.LogDirectory = if ([string]::IsNullOrWhiteSpace($logDirectory)) { [Logger]::DefaultLogDirectory } else { $logDirectory }

    # Ensure the target directory exists if specified and non-null
    if (![string]::IsNullOrWhiteSpace($this.LogDirectory)) {
      if (!(Test-Path $this.LogDirectory)) {
        try {
          New-Item -Path $this.LogDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
        } catch {
          Write-Error "Failed to create log directory '$($this.LogDirectory)': $_"
          # Decide if this should be fatal or just prevent file logging later
        }
      }
    }
  }

  [bool] IsEnabled([LogEventType]$level) {
    return (!$this._isDisposed) -and ($level -ge $this.MinimumLevel)
  }

  [void] Log([LogEventType]$severity, [string]$message, [Exception]$exception = $null) {
    if (!$this.IsEnabled($severity)) {
      return
    }

    $entry = $this.CreateEntry($severity, $message, $exception)
    $this.ProcessEntry($entry)
  }

  [ILoggerEntry] CreateEntry([LogEventType]$severity, [string]$message, [Exception]$exception) {
    # Use the configured EntryType's static factory method
    return $this.EntryType::NewEntry($severity, $message, $exception)
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
  [void] Debug([string]$message) { $this.Log([LogEventType]::Debug, $message) }
  [void] Information([string]$message) { $this.Log([LogEventType]::Information, $message) }
  [void] Warning([string]$message) { $this.Log([LogEventType]::Warning, $message) }
  [void] Error([string]$message, [Exception]$exception = $null) { $this.Log([LogEventType]::Error, $message, $exception) }
  [void] Fatal([string]$message, [Exception]$exception = $null) { $this.Log([LogEventType]::Fatal, $message, $exception) }

  [void] Dispose() {
    lock ($this._disposeLock) {
      if ($this._isDisposed) { return }

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

      $this._isDisposed = $true
    }
    # Suppress finalization if this class had a finalizer (it doesn't)
    # [System.GC]::SuppressFinalize($this)
  }
}

# Initialize static property after class definition
[Logger]::DefaultLogDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'Logs'

#endregion

#region Appender Implementations

# Appender that writes to the PowerShell console with colors
class ConsoleAppender : ILoggerAppender {
  static [hashtable]$ColorMap = @{
    Debug       = [ConsoleColor]::DarkGray
    Information = [ConsoleColor]::Green # Use Green for Info for better visibility than default
    Warning     = [ConsoleColor]::Yellow
    Error       = [ConsoleColor]::Red
    Fatal       = [ConsoleColor]::Magenta
  }

  [void] Log([ILoggerEntry]$entry) {
    # Check if host supports colors - might be unnecessary in modern PS
    $color = [ConsoleAppender]::ColorMap[$entry.Severity.ToString()]
    $timestamp = $entry.Timestamp.ToString('HH:mm:ss') # Concise timestamp for console
    $message = "[$timestamp] [$($entry.Severity.ToString().ToUpper())] $($entry.Message)"

    # Write message
    Write-Host $message -ForegroundColor $color

    # Write exception details if present, using Write-Error for visibility
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
  hidden [bool]$_isDisposed = $false

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
    if ($this._isDisposed) { return }

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
      if ($this._isDisposed -or $null -eq $this._writer) { return }
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
      if ($this._isDisposed) { return }
      if ($null -ne $this._writer) {
        try {
          $this._writer.Flush() # Final flush
          $this._writer.Dispose()
        } catch {
          Write-Error "JsonAppender error during dispose for file '$($this.FilePath)': $_"
        }
        $this._writer = $null
      }
      $this._isDisposed = $true
    }
  }
}

# Appender that writes formatted text logs to a file
class FileAppender : ILoggerAppender, IDisposable {
  [string]$FilePath
  hidden [StreamWriter]$_writer
  hidden [ReaderWriterLockSlim]$_lock = [ReaderWriterLockSlim]::new()
  hidden [bool]$_isDisposed = $false

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
    if ($this._isDisposed) { return }

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
      if ($this._isDisposed -or $null -eq $this._writer) { return }
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
    $this._isDisposed = $true

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

#endregion

#region Null Logger (for disabling logging easily)

# A logger that does nothing. Useful as a default or for disabling logging.
class NullLogger : Logger {
  hidden static [NullLogger]$_instance = [NullLogger]::new()
  # static [NullLogger] Instance { get { return [NullLogger]::_instance } }

  # Implement required methods/properties from Logger concept (or ILogger if defined)
  [List[ILoggerAppender]]$Appenders = [List[ILoggerAppender]]::new() # Empty list
  [Type]$EntryType = [LoggerEntry] # Can be default
  [LogEventType]$MinimumLevel = [LogEventType]::Fatal + 1 # Set above highest level to disable all
  [void] Log([LogEventType]$severity, [string]$message, [Exception]$exception = $null) { } # No-op
  [void] Debug([string]$message) { }
  [void] Information([string]$message) { }
  [void] Warning([string]$message) { }
  [void] Error([string]$message, [Exception]$exception = $null) { }
  [void] Fatal([string]$message, [Exception]$exception = $null) { }
  [bool] IsEnabled([LogEventType]$level) { return $false }
}

#endregion

#region Module Export Logic

$typestoExport = @(
  [Logger], [ILoggerEntry], [LogEventType], [ConsoleAppender],
  [JsonAppender], [FileAppender], [NullLogger], [LoggerEntry]
)
# Register Type Accelerators
$TypeAcceleratorsClass = [PsObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
$ExistingAccelerators = $TypeAcceleratorsClass::Get.Keys
$SkippedAccelerators = [System.Collections.Generic.List[string]]::new()

foreach ($Type in $typestoExport) {
  $typeName = $Type.Name # Use short name for accelerator if possible/desired
  # Or use FullName: $typeName = $Type.FullName
  if ($ExistingAccelerators.Contains($typeName)) {
    $SkippedAccelerators.Add($typeName)
  } else {
    try {
      $TypeAcceleratorsClass::Add($typeName, $Type)
    } catch {
      Write-Debug "Failed to add type accelerator '$typeName': $_"
      $SkippedAccelerators.Add($typeName)
    }
  }
}

if ($SkippedAccelerators.Count -gt 0) {
  Write-Debug "Skipped adding existing or problematic type accelerators: $($SkippedAccelerators -join ', ')"
}

# Define cleanup script block for OnRemove
$cleanupScript = {
  param($typestoExport, $SkippedAccelerators)

  $TypeAcceleratorsClass = [PsObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
  foreach ($Type in $typestoExport) {
    $typeName = $Type.Name # Use the same name used for adding
    # Or use FullName: $typeName = $Type.FullName
    if (!($SkippedAccelerators.Contains($typeName))) {
      # Only remove accelerators we successfully added
      try {
        if ($TypeAcceleratorsClass::Get.Keys.Contains($typeName)) {
          $TypeAcceleratorsClass::Remove($typeName)
        }
      } catch {
        Write-Warning "Failed to remove type accelerator '$typeName': $_"
      }
    }
  }
}.GetNewClosure() # Close over the current scope variables

# Assign to OnRemove, passing the necessary variables
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = [ScriptBlock]::Create(". $cleanupScript -typestoExport $using:typestoExport -SkippedAccelerators $using:SkippedAccelerators")


# Import functions from Public/Private directories
$scripts = @()
$Public = Get-ChildItem "$PSScriptRoot/Public" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$Private = Get-ChildItem "$PSScriptRoot/Private" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += $Private # Import private first if they contain helpers
$scripts += $Public

foreach ($file in $scripts) {
  Try {
    # Dot-source the script into the module's scope
    . "$($file.FullName)"
  } Catch {
    Write-Warning "Failed to source script '$($file.FullName)': $_"
  }
}

# Export public functions and the explicitly defined types
Export-ModuleMember -Function $Public.BaseName -Class $typestoExport.Name

#endregion