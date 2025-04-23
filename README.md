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

# 1. Create a logger instance and make it the default
$demo = [PsCustomObject]@{
  PsTypeName = "cliHelper.logger.demo"
  Logger     = New-Logger -Level Debug
  Version    = [Version]'0.1.1'
}
$demo.PsObject.Methods.Add([psscriptmethod]::new('InvokeFailingAction', {
      try {
        Get-Item -Path "C:\NonExistentFile.txt" -ea Stop
      } catch {
        $this.Logger | Write-LogEntry -level Error -Message "Failed to access critical file." -Exception $_.Exception
      }
    }
  )
)
```

```PowerShell
# Anything below debug (0) won't be recorded. :
[LogLevel[]][Enum]::GetNames[LogLevel]() | % {
  [PsCustomObject]@{ Name = $_ ; value = $_.value__ }
}
```

```PowerShell
try {
  [Logger]::Default = $demo.Logger
  $logPath = [string][Logger]::Default.logdir

  # 2. You also save logs to json files
  Add-JsonAppender
  Write-LogEntry -Level Info -Message "App started in directory: $logPath"
  Write-LogEntry -Level Debug -Message "Configuration loaded."

  # 3. Simulate an operation
  $user = "TestUser"
  Write-LogEntry -Level Debug -Message "Processing request for user: $user"

  # 4. Simulate an error
  $demo.InvokeFailingAction()

  Write-LogEntry -Level Warn -Message "Operation completed with warnings."
  Write-Host "Check logs in $logPath"
} finally {
  Read-LogEntries -Type Json # same as: $demo.Logger.ReadEntries(@{ type = "json" })
  # 5. IMPORTANT: Dispose the logger to flush buffers and release file handles
  $demo.Logger.Dispose()
}
```

Read the docs for [In-depth Usage examples](docs/Readme.md).

#### NOTES:

1. Remeber to **dispose** the object

    Because appenders (especially file-based ones) hold resources, you **must** call `$logger.Dispose()` when you are finished logging to ensure logs are flushed and files are closed properly.

    Use a `try...finally` block to ensure its always called.

    Failure to call `.Dispose()` can lead to:
      *   Log messages not being written to files (still stuck in buffers).
      *   File locks being held, preventing other processes (or even later runs of your script) from accessing the log files.

## License

This project is licensed under the [WTFPL License](LICENSE).
