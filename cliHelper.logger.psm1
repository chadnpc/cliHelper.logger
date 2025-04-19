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
  [LogLevel]$Severity
  [Exception]$Exception
  [datetime]$Timestamp = [datetime]::UtcNow

  static [LogEntry] Create([LogLevel]$severity, [string]$message, [Exception]$exception) {
    return [LogEntry]@{
      Message   = $message
      Severity  = $severity
      Exception = $exception
      Timestamp = [datetime]::UtcNow
    }
  }
  [Hashtable] ToHashtable() {
    return @{
      Message   = $this.Message
      Severity  = $this.Severity.ToString()
      Timestamp = $this.Timestamp.ToString('o') # ISO 8601 format
      Exception = ($null -ne $this.Exception) ? $this.Exception.ToString() : [string]::Empty
    }
  }
}

class LogAppender : IDisposable {
  hidden [ValidateNotNullOrWhiteSpace()][string]$_name = $this.PsObject.TypeNames[0]
  [void] Log([LogEntry]$entry) {
    [ValidateNotNull()][LogEntry]$entry = $entry
    throw [NotImplementedException]::new("Log method not implemented in $($this.GetType().Name)")
  }
  [string] GetlogLine([LogEntry]$entry) {
    [ValidateNotNull()][LogEntry] $entry = $entry
    $logb = $entry.ToHashtable(); $tn = $this.GetType().Name.Replace("Appender", "").ToUpper()
    $line = switch ($true) {
      ($tn -eq "JSON") { ($logb | ConvertTo-Json -Compress -Depth 5) + ','; break }
      ($tn -in ("CONSOLE", "FILE")) { "[{0:u}] [{1,-5}] {2}" -f $logb.Timestamp, $logb.Severity.ToString().Trim().ToUpper(), $logb.Message; break }
      ($tn -eq "XML") { $logb | ConvertTo-CliXml -Depth 5; break }
      default {
        throw [InvalidOperationException]::new("BUG: LogAppenderType of value '$tn' was not expected!")
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
    DEBUG = [ConsoleColor]::DarkGray
    INFO  = [ConsoleColor]::Green
    WARN  = [ConsoleColor]::Yellow
    ERROR = [ConsoleColor]::Red
    FATAL = [ConsoleColor]::Magenta
  }
  [void] Log([LogEntry]$entry) {
    Write-Host $this.GetlogLine($entry) -f ([ConsoleAppender]::ColorMap[$entry.Severity.ToString()])
  }
}

# Appender that writes formatted text logs to a file
class FileAppender : LogAppender {
  hidden [StreamWriter]$_writer
  hidden [ValidateNotNullOrWhiteSpace()][string]$FilePath
  hidden [ReaderWriterLockSlim]$_lock = @{}
  hidden [ValidateNotNullOrEmpty()][LogAppenderType]$_type = "File"

  FileAppender([string]$Path) {
    $p = [Logger]::GetUnResolvedPath($Path); $dir = Split-Path $p -Parent
    if (!(Test-Path $dir)) {
      try {
        New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop | Out-Null
      } catch {
        throw [RuntimeException]::new("Failed to create directory '$dir'", $_.Exception)
      }
    }
    if (![File]::Exists($p)) { New-Item -ItemType File -Path $p -ea Stop -Verbose:$false }
    $this.FilePath = $p
    # Open file for appending with UTF8 encoding
    $this._writer = [StreamWriter]::new($this.FilePath, $true, [Encoding]::UTF8)
    $this._writer.AutoFlush = $true # Flush after every write
  }
  [void] Log([LogEntry]$entry) {
    if ($this.IsDisposed) { throw [InvalidOperationException]::new("$($this.GetType().Name) is already disposed") }
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
      if ($null -ne $this._writer) {
        $this._writer.WriteLine($logLine)
      }
      # AutoFlush is true
    } catch {
      throw [RuntimeException]::new("FileAppender failed to write to '$($this.FilePath)'", $_.Exception)
    } finally {
      $this._lock.ExitWriteLock()
    }
  }
  [LogEntry[]] ReadAllEntries() {
    return [FileAppender]::ReadAllEntries($this.FilePath)
  }
  static [LogEntry[]] ReadAllEntries([string]$FilePath) {
    # todo: add implementation to read a .log file
    return @()
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
  hidden [ValidateNotNullOrEmpty()][LogAppenderType]$_type = "JSON"
  JsonAppender([string]$Path) : base($Path) {}
  [void] Log([LogEntry]$entry) {
    if ($this.IsDisposed) { throw [InvalidOperationException]::new("$($this.GetType().Name) is already disposed") }
    try {
      $this._writer.WriteLine($this.GetlogLine($entry))
      # AutoFlush is true, manual flush shouldn't be needed unless guaranteeing write before potential crash
    } catch {
      throw [RuntimeException]::new("JsonAppender failed to write to '$($this.FilePath)'", $_.Exception)
    }
  }
  [LogEntry[]] ReadAllEntries() {
    return [JsonAppender]::ReadAllEntries($this.FilePath)
  }
  static [LogEntry[]] ReadAllEntries([string]$FilePath) {
    if ([File]::Exists($FilePath)) {
      return '[{0}]' -f ([File]::ReadAllText($FilePath)) | ConvertFrom-Json
    }
    return @()
  }
}

class XMLAppender : FileAppender {
  hidden [ValidateNotNullOrEmpty()][LogAppenderType]$_type = "XML"
  XMLAppender([string]$Path) : base($Path) {}
  [LogEntry[]] ReadAllEntries() {
    return [XMLAppender]::ReadAllEntries($this.FilePath)
  }
  static [LogEntry[]] ReadAllEntries([string]$FilePath) {
    if ([File]::Exists($FilePath)) {
      return [File]::ReadAllText($FilePath) | ConvertFrom-CliXml
    }
    return @()
  }
}

class Logsession : IDisposable {
  [ValidateNotNullOrWhiteSpace()][string] $Id                   # Read-only after creation
  hidden [ValidateNotNullOrEmpty()][ConfigFile] $File           # Handles the config file persistence
  hidden [ValidateNotNullOrEmpty()][hashtable] $Metadata        # Extra arbitrary info (hostname, user, script, etc.)
  hidden [ValidateNotNullOrEmpty()][List[FileInfo]] $LogFiles   # Paths of associated log files created in this session
  hidden [ValidateNotNullOrEmpty()][Type] $LogType = [LogEntry] # Runtime type object
  hidden [ValidateNotNull()] [DirectoryInfo] $Logdir
  hidden [ValidateNotNull()] [LogAppender[]] $Appenders = @()
  hidden [bool] $IsDisposed = $false

  Logsession() {
    [void][Logsession]::From($this.get_instanceId(), $this.get_datapath("config"), [ref]$this)
  }
  Logsession([string]$Id) {
    [void][Logsession]::From($Id, $this.get_datapath("config"), [ref]$this)
  }
  Logsession([PsObject]$object) {
    [void][Logsession]::From($this.get_configdata($object), [ref]$this)
  }
  Logsession([string]$SessionId, [string]$Logdir) {
    [void][Logsession]::From($SessionId, $Logdir, [ref]$this)
  }
  static hidden [Logsession] From([PSCustomObject]$object, [ref]$o) {
    $d = $o.Value.get_configdata($object)
    $f = [ConfigFile]::new($d.Id); $f.SetDirectory($d.Logdir)
    # Other props to check: ("LogType", "LogFiles", "Metadata")
    return [Logsession]::From($f, $o)
  }
  static hidden [Logsession] From([ConfigFile]$configFile, [ref]$o) {
    $o.Value.Id = $configFile.BaseName
    $o.Value.Logdir = $configFile.Directory
    $o.Value.File = $configFile
    $ob = $configFile.Exists ? (ConvertFrom-Json($configFile.ReadAllText())) : [PsObject]::new()
    $ob.Metadata ? ($o.Value.Metadata = $ob.Metadata) : $null
    $ob.LogFiles ? $ob.LogFiles.ForEach({ $o.Value.AddLogFile($_) }) : $null
    $o.Value.SetLogdir(($ob.Logdir ? $ob.Logdir : $o.Value.get_datapath("Logs")))
    $o.Value.SetLogType(($ob.LogType ? $ob.LogType : [LogEntry]))
    Write-Verbose "[Logsession] Successfully created '$($o.Value.Id)'."
    return $o.Value
  }
  static hidden [Logsession] From([string]$SessionId, [string]$Logdir, [ref]$o) {
    $cf = [ConfigFile]::new($SessionId); $cf.SetDirectory($Logdir)
    return [Logsession]::From($cf, $o)
  }
  static [DirectoryInfo] GetDataPath([string]$subdirName) {
    return [PsModuleBase]::GetDataPath("cliHelper.logger", $subdirName)
  }
  [Type] GetLogType() {
    return $this.LogType
  }
  [void] SetLogType([type]$value) {
    if ($value -is [Type] -and ($value -eq [LogEntry] -or $value.IsSubclassOf([LogEntry]))) {
      $this.LogType = $value
    } else {
      throw [ArgumentException]::new("LogType must be [LogEntry] or a Type that inherits from LogEntry. Provided: '$($value.FullName)'")
    }
  }
  [string[]] GetLogFiles() {
    if ($this._appenders.count -gt 0) {
      $this._appenders.FilePath.Where({ $_ -notin $this.LogFiles.FullName }).ForEach({ $this.LogFiles += $_ })
    }
    # Return a copy to prevent external modification of the internal list
    return $this.LogFiles.ToArray()
  }
  [void] SetLogFiles([string[]]$files) { }
  [void] AddLogFile([string]$filePath) {
    $path = [PsModuleBase]::GetUnResolvedPath($filePath)
    $l = ($null -ne $this.LogFiles) ? $this.LogFiles : [List[string]]::new()
    if (!$l.Contains($path)) {
      [void]$l.LogFiles.Add($path)
      Write-Debug "[Logsession '$($this.Id)'] Added log file: $path"
    }
    $this.LogFiles = $l
  }
  [string] GetLogdir() {
    if ([string]::IsNullOrWhiteSpace($this.Logdir)) {
      $this.SetLogdir($this.get_datapath("Logs"))
    }
    return $this.Logdir
  }
  [void] SetLogdir([string]$value) {
    $dir = [PsModuleBase]::GetUnResolvedPath($value)
    if (![Path]::IsPathFullyQualified($dir)) {
      throw [ArgumentException]("Logdir path must be fully qualified: '$value'")
    }
    if (![Directory]::Exists($dir)) {
      try {
        Write-Verbose "[Logsession '$($this.Id)'] Creating log directory: '$dir'"
        [void][PsModuleBase]::CreateFolder($dir)
      } catch {
        throw [IOException]::new("Failed to create log directory '$dir'.", $_.Exception)
      }
    }
    $this.Logdir = $dir
  }

  hidden [string] get_datapath([string]$subdirName) {
    [ValidateNotNullOrWhiteSpace()][string]$subdirName = $subdirName
    return [PsModuleBase]::GetDataPath("cliHelper.logger", $subdirName)
  }
  hidden [Object] get_configdata([PsObject]$object) {
    [ValidateNotNullOrWhiteSpace()][psobject]$object = $object
    # checks for the important properties
    $props = @("Id", "Logdir"); $MissingProps = @()
    # $other_not_important_props = @("LogType", "LogFiles", "Metadata")
    $selected = $object | Select-Object * -ExcludeProperty $props
    $props.ForEach({ $selected.PsObject.Properties.Add([psnoteproperty]::new($_, ($object.$_ ? $object.$_ : $($MissingProps.Add($_); $null)))) })
    if ($MissingProps.Count -gt 0) {
      throw [MetadataException]::new(('$MissingProps = @("{0}")' -f ($MissingProps -join ', "')))
    }
    return $selected
  }
  hidden [string] get_instanceId() {
    # will always be the same if requested in the same host session.
    return (Get-Variable Host).Value.InstanceId.ToString()
  }

  [void] Save() {
    if ($this.IsDisposed) { throw [ObjectDisposedException]::new($this.GetType().Name) }
    if ($null -eq $this.File) { throw [InvalidOperationException]::new("Cannot save session, ConfigFile property is not set.") }
    Write-Verbose "[Logsession '$($this.Id)'] Saving session to '$($this.File.FullName)'..."
    $jsonContent = $this.ToJson()
    try {
      $this.File.Save($jsonContent)
      Write-Verbose "[Logsession '$($this.Id)'] Session saved successfully."
    } catch {
      throw [System.IO.IOException]::new("Failed to save session file '$($this.File.FullName)'.", $_.Exception)
    }
  }

  [hashtable] ToHashtable() {
    # Explicitly select properties for serialization
    return @{
      Id       = [string]$this.Id
      Logdir   = [string]$this.Logdir
      LogType  = [string]$this.LogType
      LogFiles = [string[]]($this.LogFiles ? $this.LogFiles.ToArray() : @()) # Store as simple array
      Metadata = $this.Metadata
    }
  }

  [string] ToJson() {
    return ConvertTo-Json -InputObject $this.ToHashtable() -Depth 5 # Adjust depth if Metadata gets complex
  }

  [void] Dispose() {
    if ($this.IsDisposed) { throw [ObjectDisposedException]::new($this.GetType().Name) }
    Write-Debug "[Logsession '$($this.Id)'] Disposing..."
    # Primarily marks as disposed. If ConfigFile held resources, it would be disposed here.
    # Currently, ConfigFile seems to manage its own state regarding file handles.
    $this.IsDisposed = $true
    [void][GC]::SuppressFinalize($this)
    # ...
    # $this.PsObject.Properties.Add([PSScriptProperty]::new('IsDisposed', { return $true }, { throw [SetValueException]::new("Its a read-only Property") }))
  }
  [string] ToString() {
    $str = "[LogSession]@{0}" -f (ConvertTo-Json(@{
          Id     = [string]$this.Id
          Logdir = [string]$this.Logdir
        }
      )
    )
    return [string]::Join('', $str.Replace(':', '=').Split("`n").Trim()).Replace(',"', '; "')
  }
}

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidInvokingEmptyMembers', '')]
class Logger : PsModuleBase, IDisposable {
  [LogLevel] $MinLevel = 'INFO'
  [Logsession] $Session = @{}

  Logger() {
    [void][Logger]::From([ref]$this)
  }
  static hidden [Logger] From([ref]$o) {
    Write-Verbose "+ 0"
    if ($null -eq $o) { throw [ArgumentException]::new("reference is null") };
    $o.Value.PsObject.Properties.Add([PSScriptProperty]::new('Logdir', { return $this.Session.GetLogdir() }, { param($value) $this.Session.SetLogdir($value) }))
    $o.Value.PsObject.Properties.Add([PSScriptProperty]::new('LogFiles', { return $this.Session.GetLogFiles() }, { throw [SetValueException]::new("LogFiles is a read-only Property") }))
    $o.Value.PsObject.Properties.Add([PSScriptProperty]::new('LogType', { return $this.Session.GetLogType() }, { param($value) $this.Session.SetLogType($value) }))
    Write-Verbose "+ 1"
    $o.Value.Session.Save()
    Write-Verbose "+ 2"
    return $o.Value
  }
  [FileAppender[]] GetFileAppenders() {
    return $this._appenders.Where({ $_.PsObject.TypeNames.Contains("FileAppender") })
  }
  [void] Log([LogEntry]$entry) {
    if ($this.IsDisposed) { throw [InvalidOperationException]::new("$($this.GetType().Name) is already disposed") }
    if ($this._appenders.Count -lt 1) { $this.AddLogAppender([ConsoleAppender]::new()) }
    foreach ($appender in $this._appenders) {
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
    if ($this.IsDisposed) { throw [InvalidOperationException]::new("$($this.GetType().Name) is already disposed") }
    if (!$this.IsEnabled($severity)) {
      Write-Debug "[Logger] "$severity" loglevel is disabled. Skipped log message : $message"
      return
    }
    $this.Log($this.CreateEntry($severity, $message, $exception))
  }
  static [Logsession[]] Getallsessions() {
    $f = [DirectoryInfo]::new([Logsession]::GetDataPath("config")).GetFiles("*-logger.json")
    $i = @(); if ($f.Count -gt 0) {
      $f.ForEach({ $i += ConvertFrom-Json([File]::ReadAllText($_)) })
    }
    return $i
  }
  [FileAppender] GetFileAppender() {
    return $this.GetAppenders('File', 1)[0]
  }
  [ConsoleAppender] GetConsoleAppender() {
    return $this.GetAppenders('CONSOLE', 1)[0]
  }
  [XMLAppender] GetXMLAppender() {
    return $this.GetAppenders("JSON", 1)[0]
  }
  [JsonAppender] GetJsonAppender() {
    return $this.GetAppenders("JSON", 1)[0]
  }
  [void] AddLogAppender() {
    $this.AddLogAppender([ConsoleAppender]::new())
  }
  [void] AddLogAppender([LogAppender]$LogAppender) {
    if ($this._appenders.Count -gt 0) {
      if ($this._appenders._name.Contains($LogAppender._name)) {
        Write-Warning "$LogAppender is already added"
        return
      }
    }
    $this._appenders += $LogAppender
  }
  [LogAppender[]] GetAppenders([LogAppenderType]$type) {
    return $this.GetAppenders($type, -1)
  }
  [LogAppender[]] GetAppenders([LogAppenderType]$type, [int]$MinCount) {
    $a = $this._appenders.Where({ $_._type -eq $type })
    if ($MinCount -ge 0 -and $a.count -gt $MinCount) { throw [InvalidOperationException]::new("Found more than one  $type appender!") }
    if ($null -eq $a) { return $null }
    return $a
  }
  [LogEntry] CreateEntry([LogLevel]$severity, [string]$message) {
    return $this.CreateEntry($severity, $message, $null)
  }
  [LogEntry] CreateEntry([LogLevel]$severity, [string]$message, [Exception]$exception) {
    if ($null -ne ($this.LogType | Get-Member -MemberType Method -Static -Name Create)) {
      return $this.LogType::Create($severity, $message, $exception)
    }
    return $this.LogType::New($severity, $message, $exception)
  }
  [LogEntry[]] ReadAllEntries([LogAppenderType]$type) {
    $a = $this."$('Get' + $Type + 'Appender')"()
    if ($null -ne $a) { return $a.ReadAllEntries() }
    return $this."$('Read' + $Type + 'Entries')"()
  }
  [LogEntry[]] ReadAllEntries([FileAppender]$appender) {
    return $this.ReadAllEntries($appender._type)
  }
  [LogEntry[]] ReadJsonEntries() {
    if ($this.IsDisposed -and $this.LogFiles.Count -gt 0) {
      return $this.LogFiles.Where({ $_.Extension -eq ".json" }).ForEach({ $this.ReadJsonEntries($_) })
    }
    $a = $this.GetJsonAppender()
    return $a ? [JsonAppender]::ReadAllEntries($a.FilePath) : @()
  }
  [LogEntry[]] ReadJsonEntries([FileInfo]$files) {
    return ($files | Select-Object @{l = 'entries'; e = { [JsonAppender]::ReadAllEntries($_) } }).entries
  }
  [void] ClearLogdir() {
    $files = $this.Logdir.EnumerateFiles()
    $files ? $files.ForEach({ Remove-Item $_.FullName -Force }) : $null
  }
  [bool] IsEnabled([LogLevel]$level) {
    return $level -ge $this.MinLevel
  }
  [void] Dispose() {
    if ($this.IsDisposed) { return }
    [void][GC]::SuppressFinalize($this); $this.Session.Dispose()
    # Dispose appenders that implement IDisposable
    foreach ($appender in $this._appenders) {
      if ($appender -is [IDisposable]) {
        try {
          $appender.Dispose()
        } catch {
          throw [RuntimeException]::new("Error disposing appender '$($appender.GetType().Name)'", $_.Exception)
        }
      }
    }
    $this.PsObject.Properties.Add([PSScriptProperty]::new('IsDisposed', { return $true }, { throw [SetValueException]::new("Its a read-only Property") }))
  }
  # --- Convenience Methods ---
  [void] Info([string]$message) { $this.Log([LogLevel]::INFO, $message) }
  [void] Debug([string]$message) { $this.Log([LogLevel]::DEBUG, $message) }

  [void] Warn([string]$message) { $this.Log([LogLevel]::WARN, $message) }

  [void] Error([string]$message) { $this.Error($message, $null) }
  [void] Error([string]$message, [Exception]$exception) { $this.Log([LogLevel]::ERROR, $message, $exception) }

  [void] Fatal([string]$message) { $this.Fatal($message, $null) }
  [void] Fatal([string]$message, [Exception]$exception = $null) { $this.Log([LogLevel]::FATAL, $message, $exception) }

  [string] ToString() {
    return @{
      Session    = $this.Session
      IsDisposed = [bool]$this.IsDisposed
      LogType    = [string]$this.Session.GetLogType()
      MinLevel   = [string]$this.MinLevel
      LogFiles   = [string[]]$this.Session.GetLogFiles()
      Logdir     = [string]$this.Session.GetLogdir()
      Appenders  = $this._appenders ? ([string[]]($this._appenders._type)) : @()
    } | ConvertTo-Json
  }
}

# A logger that does nothing. Useful as a default or for disabling logging.
class NullLogger : Logger {
  [LogLevel]$MinLevel = [LogLevel]::FATAL + 1 # Set above highest level to disable all
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
  [Logger], [LogEntry], [LogAppender], [LogLevel], [ConsoleAppender], [Logsession],
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