## [![cliHelper.logger](docs/images/logging.png)](https://www.PowerShellgallery.com/packages/cliHelper.logger)

A PowerShell module that provides a thread-safe in-memory and file-based logging

>The goal is to create an enterprise-grade logging module for PowerShell.

[![Downloads](https://img.shields.io/powershellgallery/dt/cliHelper.logger.svg?style=flat&logo=powershell&color=blue)](https://www.PowerShellgallery.com/packages/cliHelper.logger)

## Installation

```PowerShell
Install-Module cliHelper.logger
```

Then import it into your session or script:

```PowerShell
Import-Module cliHelper.logger
```

## Basic Usage

This is the easiest way to get started in scripts or interactive sessions.

(+) Read docs for more info on [core concepts](docs/Readme.md) used.

```PowerShell
# Import the module
Import-Module cliHelper.logger

# 1. Create a logger instance (defaults to Information level, Console and File appenders)
#    Logs will go to .\Logs\default.log by default relative to the module path,
#    or specify a custom directory.
$logPath = Join-Path $env:TEMP "MyAppLogs" # Example: Use temp directory
$logger = New-Logger -LogDirectory $logPath -MinimumLevel Debug # Log Debug and higher

# It's critical to use try/finally to ensure Dispose() is called!
try {
  Write-LogEntry -Logger $logger -Severity Information -Message "Application started in directory: $logPath"
  Write-LogEntry -Logger $logger -Severity Debug -Message "Configuration loaded."

  # Simulate an operation
  $user = "TestUser"
  Write-LogEntry -Logger $logger -Severity Debug -Message "Processing request for user: $user"

  # Simulate an error
  try {
    Get-Item -Path "C:\NonExistentFile.txt" -ErrorAction Stop
  } catch {
    # Log the error with the exception details
    Write-LogEntry -Logger $logger -Severity Error -Message "Failed to access critical file." -Exception $_
  }

  Write-LogEntry -Logger $logger -Severity Warning -Message "Operation completed with warnings."

} finally {
  # 2. IMPORTANT: Dispose the logger to flush buffers and release file handles
  if ($null -ne $logger) {
    Write-Host "Disposing logger..."
    $logger.Dispose()
  }
}

Write-Host "Check logs in $logPath"
# Check the console output and the 'default.log' file in $logPath
```

## Adding Appenders with Cmdlets

```PowerShell
$logPath = Join-Path $env:TEMP "MyAppLogs"
$logger = New-Logger -LogDirectory $logPath

try {
  # Add a JSON appender to the same logger
  $jsonLogFile = Join-Path $logPath "events.json"
  Add-JsonAppender -Logger $logger -JsonFilePath $jsonLogFile
  Write-LogEntry -Logger $logger -Severity Information -Message "Added JSON appender. Logs now go to Console, default.log, and events.json"

  $logger.Information("This message goes to all three appenders.") # Direct method call also works

} finally {
  $logger.Dispose()
}

Write-Host "Check logs in $logPath (default.log and events.json)"
```

## Advanced Usage (SDK-Style with Classes)

For more control or when building your own modules/tools, you can use the classes directly.

```PowerShell
# Import the module to make classes available
Import-Module cliHelper.logger

# Define log directory
$logDir = Join-Path $env:TEMP "MyToolLogs"

# 1. Create logger instance directly
$sdkLogger = [Logger]::new($logDir) # Constructor ensures directory exists

# Set minimum level
$sdkLogger.MinimumLevel = [LogEventType]::Debug

# 2. Create and add appenders manually
$console = [ConsoleAppender]::new()
$file = [FileAppender]::new((Join-Path $logDir "mytool.log"))
$json = [JsonAppender]::new((Join-Path $logDir "mytool_metrics.json"))

$sdkLogger.Appenders.Add($console)
$sdkLogger.Appenders.Add($file)
$sdkLogger.Appenders.Add($json)

# 3. Use the logger's methods directly (within try/finally)
try {
  $sdkLogger.Information("SDK Logger Initialized. Appenders: $($sdkLogger.Appenders.Count)")
  $sdkLogger.Debug("Detailed trace message.")

  try {
    throw [System.IO.FileNotFoundException]::new("Required config file missing", "config.xml")
  } catch {
    $sdkLogger.Fatal("Cannot start tool - configuration error.", $_)
  }

} finally {
  # 4. IMPORTANT: Dispose the logger
  if ($null -ne $sdkLogger) {
    $sdkLogger.Dispose()
    Write-Host "SDK Logger Disposed."
  }
}

Write-Host "Check logs in $logDir (mytool.log and mytool_metrics.json)"
```

### Custom Log Entry Type (Advanced)

You can create custom classes implementing `ILoggerEntry` if you need to add more structured data to your logs (though custom appenders would be needed to fully utilize the extra data).

```PowerShell
# Define your custom entry class
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

# Create a logger using the custom entry type
$customLogger = [Logger]::new()
$customLogger.EntryType = [CustomEntry]
$customLogger.Appenders.Add([ConsoleAppender]::new()) # Standard appender

try {
  # When logging, the custom NewEntry factory method is called
  $customLogger.Information("Logging event with custom entry type.")
  # Note: Standard appenders won't display CorrelationId by default
  # You would need a custom appender to format/use it.
} finally {
  $customLogger.Dispose()
}
```

## NOTES:

1. **Logger Disposal**

    **Always use a `try...finally` block:**

    ```PowerShell
    $logger = New-Logger # Or [Logger]::new()

    try {
      # ... Your code that uses the logger ...
      $logger.Information("Doing work...")
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
