#!/usr/bin/env pwsh
using namespace System.IO
using namespace System.Text
using namespace System.Threading
using namespace System.Collections.Generic
using namespace System.Management.Automation
using namespace System.Collections.Concurrent

#Requires -Modules PsModuleBase

# Enums
enum LogLevel {
  DEBUG = 0    # Detailed diagnostic Info
  INFO = 1     # General operational information
  WARN = 2     # Indicates a potential problem
  ERROR = 3    # A recoverable error occurred
  FATAL = 4    # Critical conditions, system may be unusable (same as Critical/Alert/Emergency)
}

enum LogAppenderType {
  CONSOLE = 0  # writes to console
  JSON = 1     # writes to a .json file
  FILE = 2     # writes to a .log file
  XML = 3      # writes to a .xml file
}


# .EXAMPLE
# New-Object LogEntry
class LogEntry {
  [string]$Message
  [Exception]$Exception
  [LogLevel]$Severity
  [datetime]$Timestamp = [datetime]::UtcNow

  static [LogEntry] Create([LogLevel]$severity, [string]$message, [System.Exception]$exception) {
    return [LogEntry]@{
      Severity  = $severity
      Message   = $message
      Exception = $exception
      Timestamp = [datetime]::UtcNow
    }
  }
  [Hashtable] ToHashtable() {
    return @{
      timestamp = $this.Timestamp.ToString('o') # ISO 8601 format
      severity  = $this.Severity.ToString()
      message   = $this.Message
      exception = ($null -ne $this.Exception) ? $this.Exception.ToString() : [string]::Empty
    }
  }
}

class LogAppender : IDisposable {
  hidden [ValidateNotNullOrWhiteSpace()][string]$_name = $this.PsObject.TypeNames[0]
  hidden [ValidateNotNullOrEmpty()][LogAppenderType]$_type = "File"

  [void] Log([LogEntry]$entry) {
    [ValidateNotNull()][LogEntry]$entry = $entry
    throw [System.NotImplementedException]::new("Log method not implemented in $($this.GetType().Name)")
  }
  [string] GetlogLine([LogEntry]$entry) {
    [ValidateNotNull()][LogEntry]$entry = $entry
    $logb = $entry.ToHashtable()
    $line = switch ($true) {
      ($this._type -eq "JSON") { ($logb | ConvertTo-Json -Compress -Depth 5) + ','; break }
      ($this._type -in ("CONSOLE", "FILE")) { "[{0:u}] [{1,-5}] {2}" -f $logb.Timestamp, $logb.Severity.ToString().Trim().ToUpper(), $logb.Message; break }
      ($this._type -eq "XML") { $logb | ConvertTo-CliXml -Depth 5; break }
      Default {
        throw [System.InvalidOperationException]::new("BUG: LogAppenderType of value '$($this._type)' was not expected!")
      }
    }
    return $line
  }
  [void] Dispose() {
    if ($this.IsDisposed) { return }
    $this.PsObject.Properties.Add([PSScriptProperty]::new('IsDisposed', { return $true }, { throw [SetValueException]::new("IsDisposed is a read-only Property") }))
  }
  [string] ToString() {
    return "[{0}]" -f $this._name
  }
}

# Appender that writes to the PowerShell console with colors
class ConsoleAppender : LogAppender {
  hidden [ValidateNotNullOrEmpty()][LogAppenderType]$_type = "CONSOLE"
  static [hashtable]$ColorMap = @{
    Debug = [ConsoleColor]::DarkGray
    Info  = [ConsoleColor]::Green
    Warn  = [ConsoleColor]::Yellow
    Error = [ConsoleColor]::Red
    Fatal = [ConsoleColor]::Magenta
  }
  [void] Log([LogEntry]$entry) {
    Write-Host $this.GetlogLine($entry) -f ([ConsoleAppender]::ColorMap[$entry.Severity.ToString()])
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

# Appender that writes formatted text logs to a file
class FileAppender : LogAppender {
  hidden [StreamWriter]$_writer
  hidden [ValidateNotNullOrWhiteSpace()][string]$FilePath
  hidden [ReaderWriterLockSlim]$_lock = [ReaderWriterLockSlim]::new()

  FileAppender([string]$Path) {
    $this.FilePath = [Logger]::GetUnResolvedPath($Path)
    if (![IO.File]::Exists($this.FilePath)) { throw [FileNotFoundException]::new("File '$Path'. Logging to this file may not work.") }
    # Ensure directory exists
    $dir = Split-Path $this.FilePath -Parent
    if (!(Test-Path $dir)) {
      try {
        New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop | Out-Null
      } catch {
        throw [RuntimeException]::new("Failed to create directory '$dir'", $_.Exception)
      }
    }
    try {
      # Open file for appending with UTF8 encoding
      $this._writer = [StreamWriter]::new($this.FilePath, $true, [Encoding]::UTF8)
      $this._writer.AutoFlush = $true # Flush after every write
    } catch {
      throw [RuntimeException]::new("Failed to open file '$($this.FilePath)'", $_.Exception)
    }
  }
  [void] Log([LogEntry]$entry) {
    if ($this.IsDisposed) { return }
    $logLine = $this.GetlogLine($entry)
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
      if ($this.IsDisposed -or $null -eq $this._writer) { return }
      $this._writer.WriteLine($logLine)
      # AutoFlush is true
    } catch {
      throw [RuntimeException]::new("FileAppender failed to write to '$($this.FilePath)'", $_.Exception)
    } finally {
      $this._lock.ExitWriteLock()
    }
  }
  [void] Dispose() {
    if ($this.IsDisposed) { return }
    if ($null -ne $this._writer) {
      try {
        # Prevent new logs trying to acquire lock while disposing
        $this._lock.EnterWriteLock() # Acquire lock to ensure no writes are happening
        $this._writer.Flush() # Final flush
        $this._writer.Dispose()
      } catch {
        throw [RuntimeException]::new("error during dispose of file '$($this.FilePath)'", $_.Exception)
      } finally {
        $this._lock.ExitWriteLock()
      }
    }
    $this.PsObject.Properties.Add([PSScriptProperty]::new('IsDisposed', { return $true }, { throw [SetValueException]::new("IsDisposed is a read-only Property") }))
    $this._lock.Dispose()
  }
}

# Appender that writes log entries as JSON objects to a file
class JsonAppender : FileAppender {
  JsonAppender([string]$Path) : base($Path) {}
  [void] Log([LogEntry]$entry) {
    if ($this.IsDisposed) { throw [System.InvalidOperationException]::new("$($this.GetType().Name) is already disposed") }
    try {
      $this._writer.WriteLine($this.GetlogLine($entry))
      # AutoFlush is true, manual flush shouldn't be needed unless guaranteeing write before potential crash
    } catch {
      throw [RuntimeException]::new("JsonAppender failed to write to '$($this.FilePath)'", $_.Exception)
    }
  }
}

class XMLAppender : FileAppender {
  XMLAppender([string]$Path) : base($Path) {}
}

class Logger : PsModuleBase, IDisposable {
  [LogLevel] $MinLevel = [LogLevel]::Info
  hidden [ValidateNotNull()][LogAppender[]] $Appenders = @()
  hidden [object] $_disposeLock = [object]::new()
  hidden [Type] $_logBaseType = [LogEntry]
  hidden [ValidateNotNull()] $_logdirectory
  Logger() {
    [void][Logger]::From(
      [IO.Path]::Combine([IO.Path]::GetTempPath(), [guid]::newguid().guid, 'Logs'),
      [ref]$this
    )
  }
  Logger([string]$Logdirectory) {
    [void][Logger]::From($Logdirectory, [ref]$this)
  }
  static hidden [Logger] From([string]$Logdirectory, [ref]$o) {
    $o.Value.PsObject.Properties.Add([PSScriptProperty]::new('Logdirectory', [scriptblock]::Create("return [IO.DirectoryInfo]`$this._logdirectory.ToString()"), {
          param($value)
          $Ld = [Logger]::GetUnResolvedPath($value)
          if (![IO.Directory]::Exists($Ld)) {
            try {
              PsModuleBase\New-Directory $Ld
              Write-Debug "[Logger] Created new Logdirectory: '$Ld'."
            } catch {
              throw [SetValueException]::new(($_.Exception | Format-List * -Force | Out-String))
            }
          }
          $this._logdirectory = [IO.DirectoryInfo]::new($Ld)
        }
      )
    )
    $o.Value.PsObject.Properties.Add([PSScriptProperty]::new('LogBaseType', { return $this._logBaseType }, {
          param($value)
          if ($value -is [Type] -and $value.BaseType.Name -eq 'LogEntry') {
            $this._logBaseType = $value
          } else {
            throw [SetValueException]::new("LogBaseType must be a Type that implements LogEntry")
          }
        }
      )
    )
    $o.Value.Logdirectory = $Logdirectory
    return $o.Value
  }
  [bool] IsEnabled([LogLevel]$level) {
    return (!$this.IsDisposed) -and ($level -ge $this.MinLevel)
  }
  [IO.FileInfo[]] GetlogFiles() {
    return $this.Appenders.FilePath
  }
  [void] DeleteLogFiles() {
    $this.GetlogFiles().Delete()
  }
  [void] Log([LogEntry]$entry) {
    foreach ($appender in $this.Appenders) {
      try {
        $appender.Log($entry)
      } catch {
        throw $_.Exception
      }
    }
  }
  [void] Log([LogLevel]$severity, [string]$message) {
    $this.Log($severity, $message, $null)
  }
  [void] Log([LogLevel]$severity, [string]$message, [Exception]$exception) {
    if ($this.IsEnabled($severity)) {
      $this.Log($this.CreateEntry($severity, $message, $exception))
    } else {
      Write-Debug "[Logger] [$severity] is disabled. Skipped log message : $message"
    }
  }
  [void] AddLogAppender() {
    $this.AddLogAppender([ConsoleAppender]::new())
  }
  [void] AddLogAppender([LogAppender]$LogAppender) {
    if ($null -ne $this.Appenders) {
      if ($this.Appenders._name.Contains($LogAppender._name)) {
        Write-Warning "$LogAppender is already added"
        return
      }
    }
    $this.Appenders += $LogAppender
  }
  [LogEntry] CreateEntry([LogLevel]$severity, [string]$message) {
    return $this.CreateEntry($severity, $message, $null)
  }
  [LogEntry] CreateEntry([LogLevel]$severity, [string]$message, [Exception]$exception) {
    if ($null -ne ($this.LogBaseType | Get-Member -MemberType Method -Static -Name Create)) {
      return $this.LogBaseType::Create($severity, $message, $exception)
    }
    return $this.LogBaseType::New($severity, $message, $exception)
  }
  # --- Convenience Methods ---
  [void] Info([string]$message) { $this.Log([LogLevel]::Info, $message) }
  [void] Debug([string]$message) { $this.Log([LogLevel]::Debug, $message) }

  [void] Warn([string]$message) { $this.Log([LogLevel]::Warning, $message) }

  [void] Error([string]$message) { $this.Error($message, $null) }
  [void] Error([string]$message, [Exception]$exception) { $this.Log([LogLevel]::Error, $message, $exception) }

  [void] Fatal([string]$message) { $this.Fatal($message, $null) }
  [void] Fatal([string]$message, [Exception]$exception = $null) { $this.Log([LogLevel]::Fatal, $message, $exception) }

  [string] ToString() {
    return @{
      LogBaseType  = $this.LogBaseType
      MinLevel     = $this.MinLevel
      Logdirectory = $this.Logdirectory
      Appenders    = $this.Appenders ? ([IO.FileInfo[]]($this.Appenders.FilePath)).Name :@()
    } | ConvertTo-Json
  }
  [void] ClearLogdirectory() {
    $this.Logdirectory.EnumerateFiles().ForEach({ Remove-Item $_.FullName -Force })
  }
  [void] Dispose() {
    if ($this.IsDisposed) { return }
    [void][System.GC]::SuppressFinalize($this)
    # Dispose appenders that implement IDisposable
    foreach ($appender in $this.Appenders) {
      if ($appender -is [IDisposable]) {
        try {
          $appender.Dispose()
        } catch {
          throw [RuntimeException]::new("Error disposing appender '$($appender.GetType().Name)'", $_.Exception)
        }
      }
    }
    # Clear the list to prevent further use and release references
    $this.Appenders.Clear()
    $this.PsObject.Properties.Add([PSScriptProperty]::new('IsDisposed', { return $true }, { throw [SetValueException]::new("Its a read-only Property") }))
  }
}

# A logger that does nothing. Useful as a default or for disabling logging.
class NullLogger : Logger {
  [LogLevel]$MinLevel = [LogLevel]::Fatal + 1 # Set above highest level to disable all
  hidden static [NullLogger]$Instance = [NullLogger]::new()
  NullLogger() {}
  [void] Log([LogLevel]$severity, [string]$message, [Exception]$exception = $null) { } # No-op
  [void] Debug([string]$message) { }
  [void] Info([string]$message) { }
  [void] Warn([string]$message) { }
  [void] Error([string]$message, [Exception]$exception) { }
  [void] Fatal([string]$message, [Exception]$exception) { }
  [bool] IsEnabled([LogLevel]$level) { return $false }
}

$typestoExport = @(
  [Logger], [LogEntry], [LogAppender], [LogLevel], [ConsoleAppender],
  [JsonAppender], [XMLAppender], [LogAppenderType], [FileAppender], [NullLogger]
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