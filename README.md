## [![cliHelper.logger](docs/images/logging.png)](https://www.PowerShellgallery.com/packages/cliHelper.logger)

A PowerShell module for logging

>The goal is to provide a simple, thread-safe, in-memory and file-based logging module for PowerShell.

[![Downloads](https://img.shields.io/powershellgallery/dt/cliHelper.logger.svg?style=flat&logo=powershell&color=blue)](https://www.PowerShellgallery.com/packages/cliHelper.logger)

## Installation

```PowerShell
Install-Module cliHelper.logger
```

## Basic Usage

This is the easiest way to get started in scripts or interactive sessions.

(+) Read docs for more info on [core concepts](docs/Readme.md) used.

```PowerShell
# Import the module
Import-Module cliHelper.logger

# 1. Create a logger instance (defaults to Info level, Console and File appenders)
#    Logs will go to .\Logs\default.log by default relative to the module path,
#    or specify a custom directory.
$logPath = [IO.Path]::Combine([IO.Path]::GetTempPath(), "MyAppLogs"); $logger = New-Logger -LogDir $logPath -Level Debug

# It's critical to use try/finally to ensure Dispose() is called!
try {
  $logger | Write-LogEntry -Level Info -Message "Application started in directory: $logPath"
  $logger | Write-LogEntry -Level Debug -Message "Configuration loaded."

  # Simulate an operation
  $user = "TestUser"
  Write-LogEntry -Logger $logger -Severity Debug -Message "Processing request for user: $user"

  # Simulate an error
  try {
    Get-Item -Path "C:\NonExistentFile.txt" -ErrorAction Stop
  } catch {
    # Log the error with the exception details
    $logger | Write-LogEntry -Severity Error -Message "Failed to access critical file." -Exception $_.Exception
  }
  Write-LogEntry -Logger $logger -Severity Warning -Message "Operation completed with warnings."
  Write-Host "Check logs in $logPath"
} finally {
  # 2. IMPORTANT: Dispose the logger to flush buffers and release file handles
  if ($null -ne $logger) {
    Write-Host "Disposing logger..."
    $logger.Dispose()
  }
}
# Check the console output and the 'default.log' file in $logPath
```

### Usage with Cmdlets

```PowerShell
$logPath = [IO.Path]::Combine([IO.Path]::GetTempPath(), "MyAppLogs"); $logger = New-Logger -LogDir $logPath

try {
  # Add a JSON appender to the same logger
  $logger | Add-JsonAppender -FilePath ([IO.Path]::Combine($logPath, "events.json"))
  $logger | Write-LogEntry -Severity Info -Message "Added JSON appender. Logs now go to Console, default.log, and events.json"
  $logger.Info("This message goes to all three appenders.") # Direct method call also works
} finally {
  $logger.Dispose()
}

Write-Host "Check logs in $logPath (default.log and events.json)"
```

### Usage with no cmdlets

For more control or when building your own modules/tools, you can use the classes directly.

```PowerShell
# Import the module to make classes available
Import-Module cliHelper.logger

# Define log directory
$logDir = [IO.Path]::Combine([IO.Path]::GetTempPath(), "MyAppLogs")

# 1. Create logger instance directly
$ObjectLogger = [Logger]::new($logDir) # Constructor ensures directory exists

# Set minimum level
$ObjectLogger.MinimumLevel = [LogEventType]::Debug

# 2. Create and add appenders manually
$console = [ConsoleAppender]::new()
$file = [FileAppender]::new((Join-Path $logDir "mytool.log"))
$json = [JsonAppender]::new((Join-Path $logDir "mytool_metrics.json"))

$ObjectLogger.Appenders += $console
$ObjectLogger.Appenders += $file
$ObjectLogger.Appenders += $json

# 3. Use logger methods directly (within try/finally)
try {
  $ObjectLogger.Info("Object Logger Initialized. with $($ObjectLogger.Appenders.Count) appenders.")
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

Write-Host "Check logs in $logDir (mytool.log and mytool_metrics.json)"
```

### Usage in your Custom classes (advanced). [you are on your own!]

You can create custom classes implementing `ILoggerEntry` if you need to add more structured data to your logs (though custom appenders would be needed to fully utilize the extra data).

```PowerShell
# Define your custom class
class CustomEntry : ILoggerEntry {
  [LogEventType]$Severity
  [string]$Message
  [Exception]$Exception
  [datetime]$Timestamp
  [string]$CorrelationId # Custom field

  # Factory method (required pattern)
  static [ILoggerEntry] NewEntry([LogEventType]$severity, [string]$message, [System.Exception]$exception) {
    # You might generate or retrieve CorrelationId here
    $id = (Get-Random -Maximum 10000).ToString("D5")
    return [CustomEntry]@{
      Severity      = $severity
      Message       = $message
      Exception     = $exception
      Timestamp     = [datetime]::UtcNow
      CorrelationId = $id
    }
  }
}

# Create a logger with the custom entry type
$customLogger = [Logger]::new()
$customLogger.EntryType = [CustomEntry]
$customLogger.Appenders += [ConsoleAppender]::new() # Standard appender

try {
  # When logging, the custom NewEntry factory method is called
  $customLogger.Info("Logging event with custom entry type.")
  # Note: Standard appenders won't display CorrelationId by default
  # You would need a custom appender to format/use it.
} finally {
  $customLogger.Dispose()
}
```

#### NOTES:

1. Remeber to **Dispose** the object

    **Always use a `try...finally` block:**

    ```PowerShell
    $logger = New-Logger # Or [Logger]::new()

    try {
      # ... Your code that uses the logger ...
      $logger.Info("Doing work...")
    } catch {
      # Optional: Log exceptions from your main code block
      $logger.Error("An error occurred in the main block.", $_)
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
