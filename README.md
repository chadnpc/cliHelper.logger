
# [logger](https://www.powershellgallery.com/packages/logger)

A PowerShell module that provides a thread-safe in-memory and file-based logging

[![Build Module](https://github.com/chadnpc/logger/actions/workflows/build_module.yaml/badge.svg)](https://github.com/chadnpc/logger/actions/workflows/build_module.yaml)
[![Downloads](https://img.shields.io/powershellgallery/dt/logger.svg?style=flat&logo=powershell&color=blue)](https://www.powershellgallery.com/packages/logger)

## Usage

```PowerShell
Install-Module logger
```

then

```PowerShell
Import-Module logger
$logger = [Logger]::new()
$logger.Append([ColoredConsoleAppender]::new())
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
$customLogger.Append([ColoredConsoleAppender]::new())
$customLogger.Debug("Detailed debug information")
```

## License

This project is licensed under the [WTFPL License](LICENSE).
