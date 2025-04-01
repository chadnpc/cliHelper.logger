## [![cliHelper.logger](docs/images/logging.png)](https://www.powershellgallery.com/packages/cliHelper.logger)

A PowerShell module that provides a thread-safe in-memory and file-based logging

>The goal is to create an enterprise-grade logging module for PowerShell.

[![Build Module](https://github.com/chadnpc/cliHelper.logger/actions/workflows/build_module.yaml/badge.svg)](https://github.com/chadnpc/cliHelper.logger/actions/workflows/build_module.yaml)
[![Downloads](https://img.shields.io/powershellgallery/dt/cliHelper.logger.svg?style=flat&logo=powershell&color=blue)](https://www.powershellgallery.com/packages/cliHelper.logger)

## Usage

```PowerShell
Install-Module cliHelper.logger
```
then

```PowerShell
Import-Module cliHelper.logger
```

1. Custom usage in your own module (recommended)

```PowerShell
#!/usr/bin/env pwsh
using namespace System.IO

#Requires -PSEdition Core
#Requires -Modules cliHelper.logger

$logger = [Logger]::new()
$logger.Append([ConsoleAppender]::new())
$logger.Append([FileAppender]::new("mylog.log"))

$logger.Information("System initialized")
$logger.Error("Something went wrong", [Exception]::new("Test error"))
$logger.Dispose()

# Custom entry type
class VerboseEntry : ILoggerEntry {
    static [ILoggerEntry] Yield([string]$message) {
        return [VerboseEntry]@{
            Severity  = [LoggingEventType]::Debug
            Message   = "[VERBOSE] $message"
            Timestamp = [datetime]::UtcNow
        }
    }
}

$customLogger = [Logger]::new()
$customLogger.EntryType = [VerboseEntry]
$customLogger.Append([ConsoleAppender]::new())
$customLogger.Debug("Detailed debug information")
```

2. Usage directly fom the terminal, or in your .ps1 scripts

```PowerShell
# Initialize logger
$logger = New-Logger -LogDirectory "$HOME/MyApp/Logs"

# Simple logging
Write-LogEntry -Logger $logger -Message "System initialized" -Severity Information

# Error logging with exception
try {
  Get-Item "nonexistent.file" -ErrorAction Stop
}
catch {
  Write-LogEntry -Logger $logger -Message "File access failed" -Severity Error -Exception $_
}

# Add JSON logging
Add-JsonAppender -Logger $logger -JsonFilePath "$HOME/MyApp/Logs/events.json"

# Dispose when finished
$logger.Dispose()
```

## License

This project is licensed under the [WTFPL License](LICENSE).
