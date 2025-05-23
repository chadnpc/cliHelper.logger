﻿## [![cliHelper.logger](docs/images/logging.png)](https://www.PowerShellgallery.com/packages/cliHelper.logger)

A thread-safe, in-memory and file-based logging module for PowerShell.

[![Downloads](https://img.shields.io/powershellgallery/dt/cliHelper.logger.svg?style=flat&logo=powershell&color=blue)](https://www.PowerShellgallery.com/packages/cliHelper.logger)

## Installation

```PowerShell
Install-Module cliHelper.logger
```

## Usage demo

Get started:

  1. In an interactive pwsh session

      ```PowerShell
      Import-Module cliHelper.logger
      ```
      or

  2. In your script? Add:

      ```PowerShell
      #Requires -Modules cliHelper.logger, othermodulename...
      ```

Then

```PowerShell
# 1. usage in an object
$demo = [PsCustomObject]@{
  PsTypeName  = "cliHelper.logger.demo"
  Description = "Shows how a logger instance is used with cmdlets"
  Version     = [Version]'0.1.2'
  Logger      = New-Logger -Level 1
}
$demo.PsObject.Methods.Add([psscriptmethod]::new('SimulateCommand', {
      Param(
        [Parameter(Mandatory = $true)]
        [validateset('Success', 'Failing')]
        [string]$type
      )

      If($type -eq 'Success') {
        $this.Logger.LogInfoLine("Getting username ...")
        [Threading.Thread]::Sleep(2000);
        $this.Logger.LogInfoLine("Done.")
        return [IO.Path]::Join(
          [Environment]::UserDomainName,
          [Environment]::UserName
        )
      }
      $file = "C:\fake-dir{0}\NonExistentFile.txt" -f (Get-Random -Max 100000000).ToString("D9")
      try {
        $this.Logger.LogInfoLine("Getting $file ...")
        [Threading.Thread]::Sleep(1000);
        Get-Item $file -ea Stop
        $this.Logger.LogInfoLine("Done!")
      } catch {
        $this.Logger | Write-LogEntry -l Error -m "Failed to access $([IO.Path]::GetFileName($file))" -e $_.Exception
      }
    }
  )
)
# 2. You can also save logs to json files
$demo.Logger | Add-JsonAppender

$demo.Logger.set_default() # (OPTIONAL) handy only when you are in a pwsh terminal.

# Now u don't have to pipe $demo.Logger each time u write or read logs in this session:
try {
  $logPath = [string][Logger]::Default.logdir
  Write-LogEntry -Level INFO -Message "app started in directory: $logPath"
  # same as:
  $demo.Logger.LogInfoLine("app st4rt3d in d1r3ct0ry: $logPath")

  Write-LogEntry -Level Debug -Message "Configuration loaded." # Note: this logline will be skipped!
  # ie: in this case anything below level 1 (INFO) won't be recorded, since [int]$demo.Logger.MinLevel -eq 1

  #  Name value
  #  ---- -----
  # DEBUG     0
  #  INFO     1
  #  WARN     2
  # ERROR     3
  # FATAL     4
  # - that means, only DEBUG lines won't show in logs
  # - Table from command: [LogLevel[]][Enum]::GetNames[LogLevel]() | % { [PsCustomObject]@{ Name = $_ ; value = $_.value__ } }

  # 3. success command
  $user = $demo.SimulateCommand("Success")
  Write-LogEntry -Level INFO -Message "Processing request for user: $user"

  # 4. Failing command
  $demo.SimulateCommand("Failing")
  Write-LogEntry -Level 2 -Message "Operation completed with warnings."
  Write-LogEntry -Message "Logs saved in $logPath"
} finally {
  Read-LogEntries -Type Json # same as: $demo.Logger.ReadEntries(@{ type = "json" })
  # 5. IMPORTANT: Dispose the logger to flush buffers and release file handles
  # $demo.Logger.Dispose()
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
