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

# 1. Create a logger instance (defaults to Info level, Console and File appenders)
#    Logs will go to .$env:TEMP by default. or specify a custom directory.
$logPath = [IO.Path]::Combine([IO.Path]::GetTempPath(), "MyAppLogs");
$logger = New-Logger -Logdir $logPath -Level Debug

# It's critical to use try/finally to ensure Dipose() is called.
try {
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
$logPath = [IO.Path]::Combine([IO.Path]::GetTempPath(), "MyAppLogs");
try {
  $logger = New-Logger -Logdir $logPath
  # Add a JSON appender to the same logger
  $logger | Add-JsonAppender
  $logger | Write-LogEntry -level Info -Message "Added JSON appender. Logs now go to Console, `$env:TMP/*{guid-filename}.log, and `$env:TMP/*{guid-filename}.json"
  $logger.Info("This message goes to all appenders.") # Direct method call also works
} finally {
  $logger.Dispose()
  Write-Host "Check logs in $logPath"
}
```

### Usage with no cmdlets

For more control or when building your own modules/tools, you can use the classes directly.

```PowerShell
# Import the module to make classes available
Import-Module cliHelper.logger

# Define log directory
$Logdir = [IO.Path]::Combine([IO.Path]::GetTempPath(), "MyAppLogs")

# 1. Create logger instance directly
$ObjectLogger = [Logger]::new($Logdir) # Constructor ensures directory exists

# Set minimum level
$ObjectLogger.MinLevel = [LogLevel]::Debug

# 2. Create and add appenders manually
$console = [ConsoleAppender]::new()
$file = [FileAppender]::new((Join-Path $Logdir "mytool.log"))
$json = [JsonAppender]::new((Join-Path $Logdir "mytool_metrics.json"))

$ObjectLogger.AddLogAppender($console)
$ObjectLogger.AddLogAppender($file)
$ObjectLogger.AddLogAppender($json)

# 3. Use logger methods directly (within try/finally)
try {
  $ObjectLogger.Info("Object Logger Initialized. with $($ObjectLogger._appenders.Count) appenders.")
  $ObjectLogger.Debug("Detailed trace message.")

  # simulate a failure:
  try {
    throw [System.IO.FileNotFoundException]::new("Required config file missing", "config.xml")
  } catch {
    $ObjectLogger.Fatal("Cannot start tool - configuration error.", $_)
  }
} finally {
  # 4. IMPORTANT: Dispose the logger
  if ($null -ne $ObjectLogger) {
    $ObjectLogger.Dispose()
    Write-Host "Object Logger Disposed."
  }
}

Write-Host "Check logs in $Logdir (mytool.log and mytool_metrics.json)"
```

### Usage in your Custom classes (advanced). [you are on your own!]

You can create custom classes implementing `ILoggerEntry` if you need to add more structured data to your logs (though custom appenders would be needed to fully utilize the extra data).

```PowerShell
# Define your custom class
class CustomEntry : ILoggerEntry {
  [LogLevel]$Severity
  [Exception]$Exception
  [datetime]$Timestamp = [datetime]::UtcNow
  [ValidateNotNullOrWhiteSpace()][string]$Message
  [string]$CorrelationId # Custom field

  # Factory method (required pattern)
  static [CustomEntry] Create([LogLevel]$severity, [string]$message, [System.Exception]$exception) {
    # You might generate or retrieve CorrelationId here
    $id = (Get-Random -Maximum 10000).ToString("D5")
    return [CustomEntry]@{
      Severity      = $severity
      Message       = $message
      Exception     = $exception
      CorrelationId = $id
    }
  }
}

# Create a logger with the custom entry type
$customLogger = [Logger]::new()
$customLogger.EntryType = [CustomEntry]
$customLogger._appenders += [ConsoleAppender]::new() # ie: log will passthru the console by default.

try {
  # When logging, the custom Create factory method is called
  $customLogger.Info("Logging event with custom entry type.")
} finally {
  $customLogger.Dispose()
}
```

Read the docs for more information on the [concepts](docs/Readme.md) used.

#### NOTES:

1. Remeber to **Dispose** the object

    **Always use a `try...finally` block:**

    ```PowerShell
    $logger = New-Logger # Or [Logger]::new()

    try {
      # ... Your code that uses the logger ...
      $logger.Info("Doing work...")
      throw [Exception]::new('Simulated exception')
    } catch {
      # Optional: Log exceptions from your main code block
      $logger.Error("An error occurred in the main block.", $_.Exception)
      # Re-throw if needed: throw
    } finally {
      # This block ALWAYS executes, even if errors occur
      if ($null -ne $logger) {
        $logger.Dispose()
      }
    }
    ```
    Failure to call `$logger.Dispose()` can lead to:
      *   Log messages not being written to files (still stuck in buffers).
      *   File locks being held, preventing other processes (or even later runs of your script) from accessing the log files.

## License

This project is licensed under the [WTFPL License](LICENSE).
