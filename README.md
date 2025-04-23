## [![cliHelper.logger](docs/images/logging.png)](https://www.PowerShellgallery.com/packages/cliHelper.logger)

A thread-safe, in-memory and file-based logging module for PowerShell.

[![Downloads](https://img.shields.io/powershellgallery/dt/cliHelper.logger.svg?style=flat&logo=powershell&color=blue)](https://www.PowerShellgallery.com/packages/cliHelper.logger)

## Installation

```PowerShell
Install-Module cliHelper.logger
```

## Usage

The easiest way to get started with scripts or interactive sessions:

```PowerShell
# Import the module
Import-Module cliHelper.logger

# 1. Create a logger instance with Console and File appenders (defaults)
$logger = New-Logger -Level Debug

<# Anything below debug level (0) won't be logged. see:
[LogLevel[]][Enum]::GetNames[LogLevel]() | % {
  [PsCustomObject]@{ Name = $_ ; value = $_.value__ }
}
#>
```

```PowerShell
try {
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
  $logger.ReadEntries(@{ type = "json" })
  # 2. IMPORTANT: Dispose the logger to flush buffers and release file handles
  # $logger.Dispose()
}
```

Read the docs for [In-depth Usage examples](docs/Readme.md).

#### NOTES:

1. Remeber to **dispose** the object

    Because appenders (especially file-based ones) hold resources, you **must** call `$logger.Dispose()` when you are finished logging to ensure logs are flushed and files are closed properly.

    Use a `try...finally` block to ensure its always called.

    Failure to call `$logger.Dispose()` can lead to:
      *   Log messages not being written to files (still stuck in buffers).
      *   File locks being held, preventing other processes (or even later runs of your script) from accessing the log files.

## License

This project is licensed under the [WTFPL License](LICENSE).
