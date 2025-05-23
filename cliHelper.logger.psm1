﻿#!/usr/bin/env pwsh
using namespace System.IO
using namespace System.Text
using namespace System.Linq
using namespace System.Threading
using namespace System.Collections
using namespace System.Collections.Generic
using namespace System.Management.Automation
using namespace System.Collections.Concurrent
using namespace System.Collections.ObjectModel

#Requires -Psedition Core
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
# New-Object LogEntry # same as: [LogEntry]@{}
class LogEntry {
  [string]$Message
  [Exception]$Exception
  hidden [LogLevel]$Severity
  [datetime]$Timestamp = [datetime]::UtcNow

  static [LogEntry] Create([LogLevel]$severity, [string]$message, [Exception]$exception) {
    $e = [LogEntry]@{
      Message   = $message
      Severity  = $severity
      Exception = $exception
      Timestamp = [datetime]::UtcNow
    }
    $e.PsObject.Properties.Add([PsAliasProperty]::new('Level', 'Severity'))
    return $e
  }
  [Hashtable] ToHashtable() {
    return @{
      Message   = $this.Message
      Severity  = $this.Severity.ToString()
      Timestamp = $this.Timestamp.ToString('o') # ISO 8601 format
      Exception = ($null -ne $this.Exception) ? $this.Exception.ToString() : [string]::Empty
    }
  }
  [string] ToString() {
    return "[{0:u}] [{1,-5}] {2}" -f $this.Timestamp, $this.Severity.ToString().Trim().ToUpper(), $this.Message
  }
}

class LogEntries : PsReadOnlySet {
  LogEntries() : base(@()) {}
  LogEntries([LogEntry[]]$array) : base($array) {}

  [LogEntry[]] SortBy([string]$PropertyName) {
    return $this.SortBy($PropertyName, $true)
  }
  [LogEntry[]] SortBy([string]$PropertyName, [bool]$descending) {
    $validnames = [LogEntry].GetProperties().Name
    if ($PropertyName -notin $validnames) {
      $values_array = '@("{0}")' -f $($validnames -join '", "')
      throw [ArgumentException]::new("Name is invalid. provide one of $values_array and try again.", 'PropertyName')
    }
    return $this.ToSortedList($PropertyName, $descending).Values
  }
  [LogEntry[]] ToArray() {
    return $this.GetEnumerator() | Select-Object
  }
  [string[]] ToString() {
    return $this.GetEnumerator().ForEach({ $_.ToString() })
  }
}

class LogAppender : IDisposable {
  hidden [ValidateNotNullOrWhiteSpace()][string]$_name = $this.PsObject.TypeNames[0]
  [void] Log([LogEntry]$entry) {
    [ValidateNotNull()][LogEntry]$entry = $entry
    throw [PSNotImplementedException]::new("Log method not implemented in $($this.GetType().Name)")
  }
  [string] GetlogLine([LogEntry]$entry) {
    [ValidateNotNull()][LogEntry] $entry = $entry
    $logb = $entry.ToHashtable(); $atype = $this.GetType().Name.Replace("Appender", "").ToUpper()
    $logb.Exception = $logb.Exception -eq "System.Exception" ? [String]::Empty : $logb.Exception
    $line = switch ($true) {
      ($atype -eq "JSON") { ($logb | ConvertTo-Json -Compress -Depth 5) + ','; break }
      ($atype -in ("CONSOLE", "FILE")) {
        $l = "[{0:u}] [{1,-5}] {2}" -f $logb.Timestamp, $logb.Severity.ToString().Trim().ToUpper(), $logb.Message;
        if (![string]::IsNullOrWhiteSpace($logb.Exception)) {
          # Append exception on new lines, indented for readability
          $e = ($entry.Exception.ToString() -split '\r?\n' | ForEach-Object { "  $_" }) -join "`n"
          # keep the console log clean :)
          if (!($atype -eq "CONSOLE" -and (Get-Variable ErrorActionPreference).Value -in ("Ignore", "SilentlyContinue"))) {
            $l += "`n$e"
          }
        }
        $l;
        break
      }
      ($atype -eq "XML") { $logb | ConvertTo-CliXml -Depth 5; break }
      default {
        throw [InvalidOperationException]::new("BUG: LogAppenderType of value '$atype' was not expected!")
      }
    }
    return $line
  }
  hidden [bool] IsSafetoLog() {
    return $this.IsSafetoLog($false)
  }
  hidden [bool] IsSafetoLog([bool]$throwonError) {
    $s = $true
    $s = $s -and (($throwonError -and $this.IsDisposed) ? $(throw [ObjectDisposedException]::new("$($this.GetType().Name) is already disposed")) : $false)
    # todo: perform other checks here:
    # ex: $s = $s -and ...
    return $s
  }
  [void] Dispose() {
    if ($this.IsDisposed) { return }
    $this.PsObject.Properties.Add([PSScriptProperty]::new('IsDisposed', { return $true }, { throw [SetValueException]::new("IsDisposed is a ReadOnly Property") }))
  }
  [string] ToString() {
    return "[{0}]" -f $this._name
  }
}

# Appender that writes to the PowerShell console with colors
class ConsoleAppender : LogAppender {
  static [Hashtable]$ColorMap = @{
    DEBUG = [ConsoleColor]::DarkGray
    INFO  = [ConsoleColor]::Green
    WARN  = [ConsoleColor]::Yellow
    ERROR = [ConsoleColor]::Red
    FATAL = [ConsoleColor]::Magenta
  }
  ConsoleAppender() {
    $this.PsObject.Properties.Add([PSScriptProperty]::new('Type', [scriptblock]::Create("return [LogAppenderType]'CONSOLE'"), {
          throw [SetValueException]::new('"Type" is a ReadOnly property')
        }
      )
    )
  }
  [void] Log([LogEntry]$entry) {
    $this.IsSafetoLog($true)
    Write-Host $this.GetlogLine($entry) -f ([ConsoleAppender]::ColorMap[$entry.Severity.ToString()])
  }
  [LogEntries] ReadEntries() {
    Write-Warning "There is no implementation to record or read previous console entries!"
    return [LogEntries]::Empty
  }
}

# Appender that writes formatted text logs to a file
class FileAppender : LogAppender {
  hidden [StreamWriter]$_writer
  hidden [ValidateNotNullOrWhiteSpace()][string]$FilePath
  hidden [ReaderWriterLockSlim]$_lock = @{}
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
    $this.PsObject.Properties.Add([PSScriptProperty]::new('Type', [scriptblock]::Create("return [LogAppenderType]'File'"), {
          throw [SetValueException]::new('"Type" is a ReadOnly property')
        }
      )
    )
  }
  [void] Log([LogEntry]$entry) {
    [void]$this.IsSafetoLog($true)
    $logLine = $this.GetlogLine($entry)
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
  [LogEntries] ReadEntries() {
    return [FileAppender]::ReadEntries($this.FilePath)
  }
  static [LogEntries] ReadEntries([string]$FilePath) {
    throw [PSNotImplementedException]::new("there is no implementation to read a .log files")
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
    $this.PsObject.Properties.Add([PSScriptProperty]::new('IsDisposed', { return $true }, { throw [SetValueException]::new("IsDisposed is a ReadOnly Property") }))
    $this._lock.Dispose()
  }
}

# Appender that writes log entries as JSON objects to a file
class JsonAppender : FileAppender {
  JsonAppender([string]$Path) : base($Path) {
    $this.PsObject.Properties.Add([PSScriptProperty]::new('Type', [scriptblock]::Create("return [LogAppenderType]'JSON'"), {
          throw [SetValueException]::new('"Type" is a ReadOnly property')
        }
      )
    )
  }
  [void] Log([LogEntry]$entry) {
    $this.IsSafetoLog($true)
    try {
      $this._writer.WriteLine($this.GetlogLine($entry))
      # AutoFlush is true, manual flush shouldn't be needed unless guaranteeing write before potential crash
    } catch {
      throw [RuntimeException]::new("JsonAppender failed to write to '$($this.FilePath)'", $_.Exception)
    }
  }
  [LogEntries] ReadEntries() {
    return [JsonAppender]::ReadEntries($this.FilePath)
  }
  static [LogEntries] ReadEntries([string]$FilePath) {
    if ([File]::Exists($FilePath)) {
      $array = '[{0}]' -f ([File]::ReadAllText($FilePath)) | ConvertFrom-Json
      return [LogEntries]::new($array)
    }
    return @{}
  }
}

class XMLAppender : FileAppender {
  XMLAppender([string]$Path) : base($Path) {
    $this.PsObject.Properties.Add([PSScriptProperty]::new('Type', [scriptblock]::Create("return [LogAppenderType]'XML'"), {
          throw [SetValueException]::new('"Type" is a ReadOnly property')
        }
      )
    )
  }
  [LogEntries] ReadEntries() {
    return [XMLAppender]::ReadEntries($this.FilePath)
  }
  static [LogEntries] ReadEntries([string]$FilePath) {
    if ([File]::Exists($FilePath)) {
      # todo: try using [PSSerializer]::Deserialize($text)
      $array = [File]::ReadAllText($FilePath) | ConvertFrom-CliXml
      return [LogEntries]::new($array)
    }
    return @{}
  }
}

class LogFiles : HashSet[FileInfo] {
  LogFiles() {}
  LogFiles([IO.FileInfo[]]$files) {
    $files.ForEach({ $this.Add($_) })
  }
  [FileInfo[]] ToArray() {
    return $this.GetEnumerator() | Select-Object
  }
  [string[]] ToString() {
    return $this.FullName
  }
}

class LogAppenders : PsReadOnlySet {
  LogAppenders() : base(@()) { $this._init_() }
  LogAppenders([LogAppender[]]$array) : base($array) { $this._init_() }
  hidden [void] _init_() {
    $this.PsObject.Properties.Add([psscriptproperty]::new('Name', { return $this.GetEnumerator().ForEach({ $_._name }) }))
  }
  [LogAppender[]] ToArray() {
    return $this.GetEnumerator() | Select-Object
  }
}

class Logsession : IDisposable {
  [ValidateNotNull()][ConfigFile] $File                     # Handles the config file persistence
  hidden [ValidateNotNull()][LogFiles] $_logFiles = @{}     # Paths of associated log files created in this session
  hidden [ValidateNotNull()][Type] $_logType = [LogEntry]   # Runtime type object
  hidden [ValidateNotNull()][LogAppenders] $_logAppenders = @{}
  hidden [ValidateNotNull()][DirectoryInfo] $_logdir
  hidden [bool] $IsDisposed

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
    # ScriptProperties
    $o.Value.PsObject.Properties.Add([PSScriptProperty]::new('Logdir', { return $this.get_logdir() }, { Param($value) $this.set_logdir($value) }))
    $o.Value.PsObject.Properties.Add([PSScriptProperty]::new('LogFiles', { return $this.get_logFiles() }, { Param([string[]]$values) $this.add_logfiles($values) }))
    $o.Value.PsObject.Properties.Add([PSScriptProperty]::new('LogType', { return $this._logType -as [Type] }, { Param([type]$value) $this.set_logType($value) }))
    $o.Value.PsObject.Properties.Add([PSScriptProperty]::new('LogAppenders', { return $this.GetAppenders() }, { throw [SetValueException]::new("LogAppenders is a ReadOnly Property") }))
    # Imports:
    $i = $configFile.Exists ? (ConvertFrom-Json($configFile.ReadAllText())) : [PsObject]::new()
    $o.Value.PSobject.Properties.Add([PSVariableProperty]::new([PSVariable]::new("Metadata", [Hashtable]$($i.Metadata ? $i.Metadata : @{})))) # Extra arbitrary info (hostname, user, script, etc.)
    $Id = $configFile.BaseName; [ValidateNotNullOrWhiteSpace()][string] $Id = $Id
    $o.Value.PsObject.Properties.Add([PSScriptProperty]::new('Id', [scriptblock]::Create("return '$Id'"), { throw [SetValueException]::new('Id is a ReadOnly property') }))
    $o.Value.File = $configFile
    $o.Value.Logdir = $configFile.Directory
    $o.Value.Logdir = $i.Logdir ? $i.Logdir : $o.Value.get_datapath("Logs")
    $o.Value.LogType = $i.LogType ? $i.LogType : [LogEntry]
    $i.LogFiles ? $o.Value.add_logfiles($i.LogFiles) : $null
    return $o.Value
  }
  [LogAppenders] GetAppenders() {
    $array = @(); [Enum]::GetNames[LogAppenderType]().ForEach({
        $a = $this.GetAppenders($_);
        if ($null -ne $a) { $array += $a }
      }
    )
    return [LogAppenders]::new($array)
  }
  [LogAppenders] GetAppenders([LogAppenderType]$type) {
    return $this.GetAppenders($type, -1)
  }
  [LogAppenders] GetAppenders([LogAppenderType]$type, [int]$MinCount) {
    $array = $this._logAppenders.Where({ $_.Type -eq $type })
    if ($MinCount -ge 0 -and $array.count -gt $MinCount) {
      throw [InvalidOperationException]::new("Can not have more than $MinCount '$type' appender type in the same session!")
    }
    return [LogAppenders]::new($array)
  }
  [ArrayList] ListFileAppenders() {
    $list = [ArrayList]::new(); $la = $this.LogAppenders
    if ($null -ne $la) { $la.Where({ $_.PsObject.TypeNames.Contains("FileAppender") }).ForEach({ [void]$list.Add($_) }) }
    return $list
  }
  [void] Save() {
    if ($this.IsDisposed) { throw [ObjectDisposedException]::new($this.GetType().Name) }
    if ($null -eq $this.File) { throw [InvalidOperationException]::new("Cannot save session, ConfigFile property is not set.") }
    Write-Debug "[Logsession '$($this.Id)'] Saving session to '$($this.File.FullName)'..."
    $jsonContent = $this.ToJson()
    try {
      $this.File.Save($jsonContent)
      Write-Debug "[Logsession '$($this.Id)'] Saved successfully."
    } catch {
      throw [IOException]::new("Failed to save session file '$($this.File.FullName)'.", $_.Exception)
    }
  }
  static hidden [Logsession] From([string]$SessionId, [string]$Logdir, [ref]$o) {
    [ValidateNotNullOrWhiteSpace()][string]$Logdir = $Logdir
    $cf = [ConfigFile]::new($SessionId); $cf.SetDirectory($Logdir)
    return [Logsession]::From($cf, $o)
  }
  static [DirectoryInfo] GetDataPath([string]$subdirName) {
    [ValidateNotNullOrWhiteSpace()][string]$subdirName = $subdirName
    return [PsModuleBase]::GetDataPath([PsModuleBase]::ReadModuledata("cliHelper.logger", "AppDataFolderName"), $subdirName)
  }
  hidden [void] add_logfiles([string[]]$files) {
    if ($files.Count -gt 0) {
      $resolved = ($files | Select-Object @{l = 'Path'; e = { [PsModuleBase]::GetUnResolvedPath($_) } }).Path
      $resolved.ForEach({
          $f = [FileInfo]::new($_);
          if ($null -eq $this._logFiles.ToString()) {
            $this._logFiles.Add($f)
          } elseif (!$this._logFiles.ToString().Contains($f.FullName)) {
            $this._logFiles.Add($f)
          }
        }
      )
    }
  }
  hidden [LogFiles] get_logFiles() {
    $this.add_logfiles($this.ListFileAppenders().FilePath)
    return $this._logFiles
  }
  hidden [DirectoryInfo] get_logdir() {
    if ([string]::IsNullOrWhiteSpace($this._logdir)) {
      $this.set_logdir($this.get_datapath("Logs"))
    }
    return $this._logdir
  }
  hidden [void] set_logdir([string]$value) {
    $dir = [PsModuleBase]::GetUnResolvedPath($value)
    if (![Path]::IsPathFullyQualified($dir)) {
      throw [ArgumentException]("Logdir path must be fully qualified: '$value'")
    }
    if (![Directory]::Exists($dir)) {
      try {
        Write-Verbose "[Logsession '$($this.Id)'] created. Saving logs to '$dir'"
        [void][PsModuleBase]::CreateFolder($dir)
      } catch {
        throw [IOException]::new("Failed to create log directory '$dir'.", $_.Exception)
      }
    }
    $this._logdir = $dir
  }
  hidden [void] set_logType([type]$value) {
    if ($value -is [Type] -and ($value -eq [LogEntry] -or $value.IsSubclassOf([LogEntry]))) {
      $this._logType = $value
    } else {
      throw [ArgumentException]::new("LogType must be [LogEntry] or a Type that inherits from LogEntry. Provided: '$($value.FullName)'")
    }
  }
  hidden [string] get_datapath([string]$subdirName) {
    return [Logsession]::GetDataPath($subdirName)
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
  [Hashtable] ToHashtable() {
    # Explicitly select properties for serialization
    return @{
      Id       = [string]$this.Id
      Logdir   = [string]$this.Logdir
      LogType  = [string]$this.LogType
      LogFiles = [string[]]($this.LogFiles ? $this.LogFiles.ToArray() : @())
      Metadata = $this.Metadata
    }
  }
  [string] ToJson() {
    return ConvertTo-Json -InputObject $this.ToHashtable() -Depth 5 # Adjust depth if Metadata gets complex
  }
  [void] Dispose() {
    if ($this.IsDisposed) { throw [ObjectDisposedException]::new($this.GetType().Name) }
    Write-Debug "[Logsession '$($this.Id)'] Disposing..."
    foreach ($appender in $this._logAppenders) {
      if ($appender -is [IDisposable]) {
        try {
          $appender.Dispose()
        } catch {
          throw [RuntimeException]::new("Error disposing appender '$($appender.GetType().Name)'", $_.Exception)
        }
      }
    }
    # overwrite the property:
    $this.PsObject.Properties.Add([PSScriptProperty]::new('IsDisposed', { return $true }, { throw [SetValueException]::new("Its a ReadOnly Property") }))
    [void][GC]::SuppressFinalize($this)
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
  [ValidateNotNull()][LogLevel] $MinLevel
  [ValidateNotNull()][Logsession] $Session = @{}
  static [AllowNull()][Logger] $Default
  Logger() {
    [void][Logger]::From([Logsession]::GetDataPath("Logs"), 0, [ref]$this)
  }
  Logger([LogLevel]$MinLevel) {
    [void][Logger]::From([Logsession]::GetDataPath("Logs"), $MinLevel, [ref]$this)
  }
  Logger([string]$Logdirectory) {
    [void][Logger]::From($Logdirectory, 0, [ref]$this)
  }
  Logger([string]$Logdirectory, [LogLevel]$MinLevel) {
    [void][Logger]::From($Logdirectory, $MinLevel, [ref]$this)
  }
  static [Logger] Create() { return [Logger]::new() }
  static [Logger] Create([LogLevel]$MinLevel) { return [Logger]::new($MinLevel) }
  static [Logger] Create([string]$Logdirectory) { return [Logger]::new($Logdirectory) }
  static [Logger] Create([string]$Logdirectory, [LogLevel]$MinLevel) { return [Logger]::new($Logdirectory, $MinLevel) }

  # Main factory method
  static hidden [Logger] From([string]$Logdirectory, [LogLevel]$MinLevel, [ref]$o) {
    if ($null -eq $o) { throw [ArgumentException]::new("Empty PsReference for Logger object") };
    if ([string]::IsNullOrWhiteSpace($Logdirectory)) { throw [ArgumentnullException]::new("Logdirectory") }
    $o.Value.PsObject.Properties.Add([PSScriptProperty]::new('Logdir', { return $this.Session.Logdir }, { param($value) $this.Session.set_logdir($value) }))
    $o.Value.PsObject.Properties.Add([PSScriptProperty]::new('LogFiles', { return $this.Session.LogFiles }, { throw [SetValueException]::new("LogFiles is a ReadOnly Property") }))
    $o.Value.PsObject.Properties.Add([PSScriptProperty]::new('LogType', { return $this.Session.LogType }, { param($value) $this.Session.LogType = $value }))
    $o.Value.Logdir = $Logdirectory
    $o.Value.MinLevel = $MinLevel
    $o.Value.Session.Save()
    return $o.Value
  }
  static [Logsession[]] Getallsessions() {
    $f = [DirectoryInfo]::new([Logsession]::GetDataPath("config")).GetFiles("*-config.json")
    $i = @(); if ($f.Count -gt 0) {
      $f.ForEach({ $i += ConvertFrom-Json([File]::ReadAllText($_)) })
    }
    return $i
  }
  [FileAppender] GetFileAppender() {
    return $this.Session.GetAppenders('File', 1).ToArray()[0]
  }
  [ConsoleAppender] GetConsoleAppender() {
    return $this.Session.GetAppenders('CONSOLE', 1).ToArray()[0]
  }
  [XMLAppender] GetXMLAppender() {
    return $this.Session.GetAppenders("XML", 1).ToArray()[0]
  }
  [JsonAppender] GetJsonAppender() {
    return $this.Session.GetAppenders("JSON", 1).ToArray()[0]
  }
  [void] AddLogAppender() {
    $this.AddLogAppender([ConsoleAppender]::new())
  }
  [void] AddLogAppender([LogAppender]$LogAppender) {
    if ($this.Session._logAppenders.Count -gt 0) {
      if ($this.Session._logAppenders._name.Contains($LogAppender._name)) {
        Write-Verbose -Message "Skipped invalid Operation: $LogAppender was already added"
        return
      }
    }
    [LogAppender[]]$a = $this.Session._logAppenders.ToArray() + $LogAppender
    $this.Session._logAppenders = [LogAppenders]::new($a)
  }
  [ArrayList] ListFileAppenders() {
    return $this.Session.ListFileAppenders()
  }
  [LogEntry] CreateLogEntry([LogLevel]$severity, [string]$message) {
    return $this.CreateLogEntry($severity, $message, $null)
  }
  [LogEntry] CreateLogEntry([LogLevel]$severity, [string]$message, [Exception]$exception) {
    if ($null -ne ($this.LogType | Get-Member -MemberType Method -Static -Name Create)) {
      return $this.LogType::Create($severity, $message, $exception)
    }
    return $this.LogType::New($severity, $message, $exception)
  }
  [LogEntries] ReadEntries([string]$type) {
    return $this.ReadEntries(@{ type = $type })
  }
  [LogEntries] ReadEntries([FileInfo]$file) {
    return $this.ReadEntries(@{type = $file.Extension.Substring(1).ToUpper() }, $file)
  }
  [LogEntries] ReadEntries([FileAppender]$appender) {
    return $this.ReadEntries($appender.Type)
  }
  [LogEntries] ReadEntries([hashtable]$options) {
    $t = $options["type"]; [ValidateNotNullOrWhiteSpace()][string]$t = $t
    return $this.ReadEntries([LogAppenderType]$t)
    # or
    # if ($this.LogFiles.Count -gt 0) {
    #   return $this.LogFiles.Where({ $_.Extension -eq ".$t" }).ForEach({ $this."$('Read' + $t + 'Entries')"($_) })
    # }
  }
  [LogEntries] ReadEntries([hashtable]$options, [FileInfo]$file) {
    $t = $options["type"]; [ValidateNotNullOrWhiteSpace()][string]$t = $t
    return $this.ReadEntries([LogAppenderType]$t, $file)
  }
  [LogEntries] ReadEntries([LogAppenderType]$type) {
    return $this.ReadEntries($type, $false)
  }
  [LogEntries] ReadEntries([LogAppenderType]$type, [bool]$throwonError) {
    $a = $this."$('Get' + $Type + 'Appender')"()
    if ($null -ne $a) { return $a.ReadEntries() }
    if ($throwonError) { throw "no $Type entries were found" }
    return @{}
  }
  [LogEntries] ReadEntries([LogAppenderType]$type, [FileInfo]$file) {
    $n = $type.ToString() + 'Appender'; $a = $this."$('Get' + $n)"()
    return $a ? ([type]$n)::ReadEntries($a.FilePath) : @{}
  }
  [void] ClearLogdir() {
    $files = $this.Logdir.EnumerateFiles()
    $files ? $files.ForEach({ Remove-Item $_.FullName -Force }) : $null
  }
  [void] Log([LogEntry]$entry) {
    if ($this.Session._logAppenders.Count -lt 1) { $this.AddLogAppender([ConsoleAppender]::new()) }
    foreach ($appender in $this.Session._logAppenders) {
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
    if ($this.should_log($severity)) {
      $this.Log($this.CreateLogEntry($severity, $message, $exception))
      return
    }
    Write-Debug -Message "[Logger] loglevel '$severity' is Skipped. Message : $message"
  }
  hidden [bool] should_log([LogLevel]$level) {
    return $level -ge $this.MinLevel
  }
  hidden [void] set_default() {
    [Logger]::Default = ([ref]$this).Value
  }
  [void] Dispose() {
    if ($this.IsDisposed) { throw [ObjectDisposedException]::new($this.GetType().Name, "Object is already disposed!") }
    [void][GC]::SuppressFinalize($this); $this.Session.Dispose(); [Logger]::Default = $null
    $this.PsObject.Properties.Add([PSScriptProperty]::new('IsDisposed', { return $true }, { throw [SetValueException]::new("Its a ReadOnly Property") }))
  }
  # --- Convenience Methods ---
  [void] LogInfoLine([string]$message) { $this.Log([LogLevel]::INFO, $message) }
  [void] LogDebugLine([string]$message) { $this.Log([LogLevel]::DEBUG, $message) }

  [void] LogWarnLine([string]$message) { $this.Log([LogLevel]::WARN, $message) }

  [void] LogErrorLine([string]$message) { $this.LogErrorLine($message, $null) }
  [void] LogErrorLine([string]$message, [Exception]$exception) { $this.Log([LogLevel]::ERROR, $message, $exception) }

  [void] LogFatalLine([string]$message) { $this.LogFatalLine($message, $null) }
  [void] LogFatalLine([string]$message, [Exception]$exception = $null) { $this.Log([LogLevel]::FATAL, $message, $exception) }

  [hashtable] ToHashtable() {
    return @{
      Session    = $this.Session.ToHashtable()
      Logdir     = [string]$this.Session.Logdir
      LogType    = [string]$this.Session.LogType
      MinLevel   = [string]$this.MinLevel
      LogFiles   = [string[]]$this.Session.LogFiles
      Appenders  = [string[]]($this.Session.LogAppenders ? ($this.Session.LogAppenders.Type) : @())
      IsDisposed = [bool]$this.IsDisposed
    }
  }
  [string] ToJson() {
    return $this.ToHashtable() | ConvertTo-Json -Depth 3
  }
  [string] ToString() {
    $str = "[Logger]@{0}" -f (ConvertTo-Json(@{
          MinLevel = [string]$this.MinLevel
          Logdir   = [string]$this.Logdir
        }
      )
    )
    return [string]::Join('', $str.Replace(':', '=').Split("`n").Trim()).Replace(',"', '; "')
  }
}

# A logger that does nothing. Useful as a default or for disabling logging.
class NullLogger : Logger {
  [LogLevel]$MinLevel = [LogLevel]::FATAL + 1 # Set above highest level to disable all
  hidden static [NullLogger]$Instance = [NullLogger]::new()
  NullLogger() {}
  [void] Log([LogLevel]$severity, [string]$message, [Exception]$exception = $null) { } # No-op
  [void] LogDebugLine([string]$message) { }
  [void] LogInfoLine([string]$message) { }
  [void] LogWarnLine([string]$message) { }
  [void] LogErrorLine([string]$message, [Exception]$exception) { }
  [void] LogFatalLine([string]$message, [Exception]$exception) { }
  [bool] IsEnabled([LogLevel]$level) { return $false }
}

$typestoExport = @(
  [Logger], [LogEntry], [LogAppender], [LogLevel], [ConsoleAppender], [LogAppenders], [Logsession],
  [JsonAppender], [LogFiles], [LogEntries], [XMLAppender], [LogAppenderType], [FileAppender], [NullLogger]
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
    $host.UI.LogErrorLineLine($_)
  }
}

$Param = @{
  Function = $Public.BaseName
  Cmdlet   = '*'
  Alias    = '*'
  Verbose  = $false
}
Export-ModuleMember @Param