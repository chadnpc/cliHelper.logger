
#!/usr/bin/env pwsh
#region    Classes
class LogEntry {
  [ValidateNotNullOrEmpty()][string]$Value
  [ValidateNotNull()][datetime]$Time = [datetime]::UtcNow

  LogEntry([string]$Value) {
    $this.Value = $Value
  }

  LogEntry([string]$Value, [datetime]$Time) {
    $this.Value = $Value
    $this.Time = $Time
  }

  static [LogEntry] Parse([string]$LogString) {
    if ($LogString -match '^\[(?<time>.+?)\]\s(?<value>.*)$') {
      return [LogEntry]::new(
        $matches['value'],
        [datetime]::Parse($matches['time'])
      )
    }
    throw "Invalid log format: $LogString"
  }

  [string] ToString() {
    return '[{0:u}] {1}' -f $this.Time, $this.Value
  }
}

class LogResource : LogEntry {
  [string]$ResourceType

  LogResource([object]$Object) : base($Object.ToString(), [datetime]::UtcNow) {
    $this.ResourceType = $Object.GetType().Name
  }

  [string] ToString() {
    return '[{0:u}] [{1}] {2}' -f $this.Time, $this.ResourceType, $this.Value
  }
}

class Logger : IDisposable {
  [guid]$SessionId
  [string]$LogPath
  [bool]$IsDisposed = $false
  [System.IO.StreamWriter]$StreamWriter
  [System.Collections.ArrayList]$LogEntries
  static [System.Collections.Hashtable]$LogSessions = [System.Collections.Hashtable]::Synchronized(@{})
  static [string]$DefaultLogDirectory = "$pwd\Logs"


  Logger() { }

  Logger([string]$LogDirectory) {
    $this.SessionId = [guid]::NewGuid()
    $this.LogEntries = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())

    if (-not (Test-Path $LogDirectory)) {
      New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }

    $this.LogPath = Join-Path $LogDirectory "Log_$($this.SessionId).log"
    $this.StreamWriter = [System.IO.StreamWriter]::new($this.LogPath)

    [Logger]::LogSessions[$this.SessionId] = $this.LogEntries
  }

  [void] Log([string]$Message) {
    $this.AddLogEntry([LogEntry]::new($Message))
  }

  [void] LogObject([object]$Object) {
    $this.AddLogEntry([LogResource]::new($Object))
  }

  [void] AddLogEntry([LogEntry]$Entry) {
    if ($this.IsDisposed) {
      throw "Cannot log to disposed Logger"
    }

    $this.LogEntries.Add($Entry) | Out-Null
    $this.StreamWriter.WriteLine($Entry.ToString())
  }

  [void] Dispose() {
    if (!$this.IsDisposed) {
      $this.StreamWriter.Flush()
      $this.StreamWriter.Close()
      $this.StreamWriter.Dispose()
      [Logger]::LogSessions.Remove($this.SessionId)
      $this.IsDisposed = $true
    }
  }

  [string] GetSessionLogs() {
    return $this.LogEntries -join "`n"
  }
}
#endregion Classes
# Types that will be available to users when they import the module.
$typestoExport = @(
  [LogEntry], [LogResource], [Logger]
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
