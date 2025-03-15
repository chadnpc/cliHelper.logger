#!/usr/bin/env pwsh

using namespace System.IO
using namespace System.Text
using namespace System.Threading
using namespace System.Collections.Generic

enum LogEventType {
  Debug
  Information
  Warning
  Error
  Fatal
}

class ILoggerAppender {
  [void] Log([ILoggerEntry]$entry) { }
}

class ILoggerEntry {
  [LogEventType]$Severity
  [string]$Message
  [Exception]$Exception
  [datetime]$Timestamp = [datetime]::UtcNow

  static [ILoggerEntry] Yield([string]$message) { throw "Not implemented" }
}

class LoggerEntry : ILoggerEntry {
  static [ILoggerEntry] Yield([string]$message) {
    $caller = (Get-PSCallStack)[2].Command
    $severity = [LogEventType]::$caller
    return [LoggerEntry]@{
      Severity  = $severity
      Message   = $message
      Timestamp = [datetime]::UtcNow
    }
  }
}

class BaseLogger : IDisposable {
  [List[ILoggerAppender]]$Appenders = [List[ILoggerAppender]]::new()
  [Type]$EntryType = [LoggerEntry]
  [guid]$SessionId = [guid]::NewGuid()
  [string]$LogDirectory
  [StreamWriter]$StreamWriter
  static [Hashtable]$Sessions = [Hashtable]::Synchronized(@{})
  static [string]$DefaultLogDirectory = "$pwd\Logs"

  BaseLogger() { }

  BaseLogger([string]$logDirectory) {
    $this.LogDirectory = $logDirectory
    $this.Initialize()
  }

  [void] Initialize() {
    if (-not (Test-Path $this.LogDirectory)) {
      New-Item -Path $this.LogDirectory -ItemType Directory -Force | Out-Null
    }

    $logPath = Join-Path $this.LogDirectory "Log_$($this.SessionId).log"
    $this.StreamWriter = [StreamWriter]::new($logPath)
    [BaseLogger]::Sessions[$this.SessionId] = $this
  }

  [void] Log([LogEventType]$severity, [string]$message, [Exception]$exception) {
    $entry = $this.CreateEntry($severity, $message, $exception)
    $this.ProcessEntry($entry)
  }

  [ILoggerEntry] CreateEntry([LogEventType]$severity, [string]$message, [Exception]$exception) {
    return $this.EntryType::Yield($message, $exception)
  }

  [void] ProcessEntry([ILoggerEntry]$entry) {
    $this.StreamWriter.WriteLine("[{0:u}] [{1}] {2}" -f
      $entry.Timestamp, $entry.Severity, $entry.Message)

    foreach ($appender in $this.Appenders) {
      try {
        $appender.Log($entry)
      } catch {
        Write-Error "Appender error: $_"
      }
    }
  }

  [void] Dispose() {
    if ($this.StreamWriter) {
      $this.StreamWriter.Flush()
      $this.StreamWriter.Dispose()
    }
    [BaseLogger]::Sessions.Remove($this.SessionId)
  }
}

class Logger : BaseLogger {
  Logger() : base() { }
  Logger([string]$logDirectory) : base($logDirectory) { }

  [void] Debug([string]$message) { $this.Log([LogEventType]::Debug, $message, $null) }
  [void] Information([string]$message) { $this.Log([LogEventType]::Information, $message, $null) }
  [void] Warning([string]$message) { $this.Log([LogEventType]::Warning, $message, $null) }
  [void] Error([string]$message, [Exception]$ex) { $this.Log([LogEventType]::Error, $message, $ex) }
  [void] Fatal([string]$message, [Exception]$ex) { $this.Log([LogEventType]::Fatal, $message, $ex) }
}

class ConsoleAppender : ILoggerAppender {
  static [hashtable]$ColorMap = @{
    Debug       = [ConsoleColor]::DarkGray
    Information = [ConsoleColor]::Green
    Warning     = [ConsoleColor]::Yellow
    Error       = [ConsoleColor]::Red
    Fatal       = [ConsoleColor]::Magenta
  }

  [void] Log([ILoggerEntry]$entry) {
    $color = [ConsoleAppender]::ColorMap[$entry.Severity.ToString()]
    $message = "[{0}] {1}" -f $entry.Severity.ToString().ToUpper(), $entry.Message
    Write-Host $message -ForegroundColor $color
  }
}

class JsonAppender : ILoggerAppender {
  [string]$FilePath
  [System.IO.StreamWriter]$Writer

  JsonAppender([string]$Path) {
    $this.FilePath = $Path
    $this.Writer = [System.IO.StreamWriter]::new($Path)
  }

  [void] Log([ILoggerEntry]$entry) {
    $logObject = [ordered]@{
      timestamp = $entry.Timestamp.ToString('o')
      severity  = $entry.Severity.ToString()
      message   = $entry.Message
      exception = if ($entry.Exception) { $entry.Exception.ToString() }
    }

    $this.Writer.WriteLine(($logObject | ConvertTo-Json -Compress))
  }

  [void] Dispose() {
    if ($this.Writer) {
      $this.Writer.Dispose()
    }
  }
}
class FileAppender : ILoggerAppender {
  [StreamWriter]$Writer
  [ReaderWriterLockSlim]$Lock = [ReaderWriterLockSlim]::new()

  FileAppender([string]$path) {
    $this.Writer = [StreamWriter]::new($path, [Encoding]::UTF8)
  }

  [void] Log([ILoggerEntry]$entry) {
    $this.Lock.EnterWriteLock()
    try {
      $this.Writer.WriteLine("[{0:u}] [{1}] {2}" -f
        $entry.Timestamp, $entry.Severity, $entry.Message)
    } finally {
      $this.Lock.ExitWriteLock()
    }
  }
  [void] Dispose() {
    $this.Writer.Dispose()
    $this.Lock.Dispose()
  }
}

# Export types and setup accelerators
$typestoExport = @(
  [Logger], [ILoggerEntry], [LogEventType], [ConsoleAppender], [JsonAppender], [FileAppender]
)
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
