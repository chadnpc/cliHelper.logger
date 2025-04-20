## [![cliHelper.logger](docs/images/logging.png)](https://www.PowerShellgallery.com/packages/cliHelper.logger)

A PowerShell module for logging

>The goal is to provide a simple, thread-safe, in-memory and file-based logging module for PowerShell.

[![Downloads](https://img.shields.io/powershellgallery/dt/cliHelper.logger.svg?style=flat&logo=powershell&color=blue)](https://www.PowerShellgallery.com/packages/cliHelper.logger)

## Installation

```PowerShell
Install-Module cliHelper.logger
```

## Basic Usage

This is the easiest way to get started with scripts or interactive sessions.

```PowerShell
# Import the module
Import-Module cliHelper.logger

try {
  # 1. Create a logger instance with Console and File appenders (defaults)
  $logger = New-Logger -Level Debug
  # anything below debug level won't be logged. ie, see:
  # ([LogLevel[]][Enum]::GetNames[LogLevel]()).ForEach({ [PsCustomObject]@{ Name = $_ ; value = $_.value__ } })

  $logPath = [string]$logger.Logdir

  $logger | Add-JsonAppender
  $logger | Write-LogEntry -Level Info -Message "Application started in directory: $logPath"
  $logger | Write-LogEntry -Level Debug -Message "Configuration loaded."

  # Simulate an operation
  $user = "TestUser"
  Write-LogEntry -l $logger -level Debug -Message "Processing request for user: $user"

  # Simulate an error
  try {
    Get-Item -Path "C:\NonExistentFile.txt" -ea Stop
  } catch {
    # Log the error with the exception details
    $logger | Write-LogEntry -level Error -Message "Failed to access critical file." -Exception $_.Exception
  }
  Write-LogEntry -l $logger -level Warn -Message "Operation completed with warnings."
  Write-Host "Check logs in $logPath"
} finally {
  # 2. IMPORTANT: Dispose the logger to flush buffers and release file handles
  $logger.Dispose()
}
```

### Usage with Cmdlets

```PowerShell
try {
  $logger = [IO.Path]::Combine([IO.Path]::GetTempPath(), "MyAppLogs") | New-Logger
  # Add a JSON appender to the same logger
  $logger | Add-JsonAppender
  $logger | Write-LogEntry -level Info -Message "Added JSON appender. Logs now go to Console, `$env:TMP/*{guid-filename}.log, and `$env:TMP/*{guid-filename}.json"
  $logger.Info("This message goes to all appenders.") # Direct method call also works
} finally {
  $logger.ReadAllEntries("JSON")
  $logger.Dispose()
}
```

### Usage with no cmdlets

For more control or when building your own modules/tools, you can use the classes directly.

```PowerShell
# Import the module to make classes available
Import-Module cliHelper.logger

try {
  $Logdir = [IO.Path]::Combine([IO.Path]::GetTempPath(), "MyAppLogs")
  $logger = [Logger]::new($Logdir) # Constructor ensures directory exists
  $logger.MinLevel = [LogLevel]::Debug

  # 2. Create and add appenders manually
  $logger.AddLogAppender([ConsoleAppender]::new())
  $logger.AddLogAppender([FileAppender]::new((Join-Path $Logdir "mytool.log")))
  $logger.AddLogAppender([JsonAppender]::new((Join-Path $Logdir "mytool_metrics.json")))

  $logger.Info("Object Logger Initialized. with $($logger._appenders.Count) appenders.")
  $logger.Debug("Detailed trace message.")
  # simulate a failure:
  throw [System.IO.FileNotFoundException]::new("Required config file missing", "config.xml")
} catch {
  $logger.Fatal(("{0} :`n  {1}" -f $_.FullyQualifiedErrorId, $_.ScriptStackTrace), $_.Exception)
} finally {
  $logger.Info("Check logs in '$Logdir/mytool.log' and '$Logdir/mytool_metrics.json'")
  $logger.Dispose()
}
```

### Usage in your Custom classes (advanced). [you are on your own!]

You can create custom classes inheriting `LogEntry` if you need to add more structured data to your logs (though custom appenders would be needed to fully utilize the extra data).

```PowerShell
# Define your custom class
class CustomEntry : LogEntry {
  [LogLevel]$Severity
  [Exception]$Exception
  [datetime]$Timestamp = [datetime]::UtcNow
  [ValidateNotNullOrWhiteSpace()][string]$Message
  [string]$CorrelationId # Custom field

  # Factory methods (required pattern)
  static [CustomEntry] Create([LogLevel]$severity, [string]$message) {
    return [CustomEntry]::Create($severity, $message, $null)
  }
  static [CustomEntry] Create([LogLevel]$severity, [string]$message, [System.Exception]$exception) {
    # Example: generate or retrieve CorrelationId
    $Id = (Get-Random -Maximum 10000).ToString("D5")
    return [CustomEntry]@{
      Severity      = $severity
      Message       = $message
      Exception     = $exception
      CorrelationId = $Id
    }
  }
}

# Create a logger with the custom entry type
try {
  $logger = [Logger]::new()
  $logger.LogType = [CustomEntry]
  $logger.Info("Logging event with custom entry type.")
  $logger.Info("By default, If no LogAppender is added, Logs will only show in the console (like this).")
} finally {
  $logger.Dispose()
}
$logger.Info("Trying to log something else...")
# this should throw an error:
# OperationStopped: Cannot access a disposed object. Object name: 'ConsoleAppender is already disposed'.
```

Read the docs for more [usage info](docs/Readme.md).

#### NOTES:

1. **Remeber to **dispose** the object ex: in the `try...finally` block.**

    Failure to call `$logger.Dispose()` can lead to:
      *   Log messages not being written to files (still stuck in buffers).
      *   File locks being held, preventing other processes (or even later runs of your script) from accessing the log files.

## License

This project is licensed under the [WTFPL License](LICENSE).
