# docs

*   **Logger (`[Logger]`)**: The main object you interact with. It holds configuration (like `MinLevel`) and a list of appenders. **Crucially, it should be disposed of when done (`$logger.Dispose()`)**.
*   **Appenders (`[LogAppender]`)**: Define *where* log messages go. This module includes:
    *   `[ConsoleAppender]`: Writes colored output to the PowerShell host.
    *   `[FileAppender]`: Writes formatted text to a specified file.
    *   `[JsonAppender]`: Writes JSON objects (one per line) to a specified file.
    You add instances of these to the logger's `$logger._appenders` list.
*   **Severity Levels (`[LogLevel]`)**: Define the importance of a message (Debug, Info, Warn, Error, Fatal). The logger's `MinLevel` filters messages below that level.


## **Usage examples**

- `I. With Cmdlets`

  ```PowerShell
  try {
    $logger = [IO.Path]::Combine([IO.Path]::GetTempPath(), "MyAppLogs") | New-Logger
    $logger | Add-JsonAppender
    $logger | Write-LogEntry -level Info -Message "Added JSON appender.
    Logs now go to Console, `$env:TMP/MyAppLog/*{guid-filename}.log, and .json"
    $logger.Info("This message goes to all appenders.") # Direct call
  } finally {
    $logger.ReadEntries(@{ type = "JSON" })
    $logger.Dispose()
  }
  ```

- `II. With no cmdlets`

  For more control or when building your own modules/tools, you can use the classes directly.

  ```PowerShell
  # Import the module to make classes available
  Import-Module cliHelper.logger

  try {
    $Logdir = [IO.Path]::Combine([IO.Path]::GetTempPath(), "MyAppLogs")
    $logger = [Logger]::new($Logdir)
    $logger.MinLevel = [LogLevel]::Debug

    # Create and add appenders manually
    $logger.AddLogAppender([ConsoleAppender]::new())
    $logger.AddLogAppender([FileAppender]::new((Join-Path $Logdir "mytool.log")))
    $logger.AddLogAppender([JsonAppender]::new((Join-Path $Logdir "mytool_metrics.json")))

    $logger.Info("Object Logger Initialized. with $($logger._appenders.Count) appenders.")
    $logger.Debug("Detailed trace message.")
    # simulated failure:
    throw [System.IO.FileNotFoundException]::new("Required config file missing", "config.xml")
  } catch {
    $logger.Fatal(("{0} :`n  {1}" -f $_.FullyQualifiedErrorId, $_.ScriptStackTrace), $_.Exception)
  } finally {
    $logger.Info("Check logs in '$Logdir/mytool.log' and '$Logdir/mytool_metrics.json'")
    $logger.Dispose()
  }
  ```

  ### You can also use your custom classes.

  ```PowerShell
  # .SYNPOSIS
  # A custom classes inheriting `LogEntry`
  # adds more structured data to logs.
  #.EXAMPLE
  # [CustomEntry]@{}
  class CustomEntry : LogEntry {
    [string]$CorrelationId # Custom field

    # Factory methods (required pattern)
    static [CustomEntry] Create([LogLevel]$severity, [string]$message) {
      return [CustomEntry]::Create($severity, $message, $null)
    }
    static [CustomEntry] Create([LogLevel]$severity, [string]$message, [Exception]$exception) {
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

  # then:
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
  # OperationStopped: Cannot access a disposed object.
  # Object name: 'ConsoleAppender is already disposed'.
  ```

EOF

---