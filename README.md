## [![cliHelper.logger](docs/images/logging.png)](https://www.PowerShellgallery.com/packages/cliHelper.logger)

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
  Version     = [Version]'0.1.1'
  Logger      = New-Logger -Level Debug
}
$demo.PsObject.Methods.Add([psscriptmethod]::new('SimulateCommand', {
      Param(
        [Parameter(Mandatory = $true)]
        [validateset('Success', 'Failing')]
        [string]$type
      )

      If($type -eq 'Success') {
        Write-Host "Getting username ..." -NoNewline;
        [Threading.Thread]::Sleep(2000);
        Write-Host " Done" -f Green
        return [IO.Path]::Join(
          [Environment]::UserDomainName,
          [Environment]::UserName
        )
      }
      $file = "C:\fake-dir{0}\NonExistentFile.txt" -f (Get-Random -Max 100000000).ToString("D9")
      try {
        Write-Host "Getting $file ...";
        [Threading.Thread]::Sleep(1000);
        Get-Item $file -ea Stop
        Write-Host " Done!" -f Green
      } catch {
        $this.Logger | fl * -Force | out-string | write-verbose
        $this.Logger | Write-LogEntry -l Error -m "Failed to access $([IO.Path]::GetFileName($file))" -e $_.Exception
      }
    }
  )
)
```

```PowerShell
# Anything below level 1 (INFO) won't be recorded. i.e:
 Name value
 ---- -----
DEBUG     0
 INFO     1
 WARN     2
ERROR     3
FATAL     4

# - It means in this case, DEBUG lines won't show in logs
# - Table from: [LogLevel[]][Enum]::GetNames[LogLevel]() | % { [PsCustomObject]@{ Name = $_ ; value = $_.value__ } }
```

```PowerShell
try {
  # set it the default (OPTIONAL If you are in a pwsh terminal)
  $demo.Logger.set_default()
  $logPath = [string][Logger]::Default.logdir

  # 2. You also save logs to json files
  Add-JsonAppender
  Write-LogEntry -Level Info  -Message "App started in directory: $logPath"
  Write-LogEntry -Level Debug -Message "Configuration loaded."

  # 3. success command
  $user = $demo.SimulateCommand("Success")
  Write-LogEntry -Level Debug -Message "Processing request for user: $user"

  # 4. Failing command
  $demo.SimulateCommand("Failing")
  Write-LogEntry -Level Warn -Message "Operation completed with warnings."
  Write-LogEntry "Logs saved in $logPath"
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
