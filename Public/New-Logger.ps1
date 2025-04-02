function New-Logger {
  <#
  .SYNOPSIS
    Creates a configured logger instance.
  .DESCRIPTION
    Initializes a new logger instance using the cliHelper.logger module.
    By default, it adds a ConsoleAppender for console output and a FileAppender
    writing to 'default.log' within the specified LogDirectory.
    Remember to call $logger.Dispose() when finished to release file handles.
  .PARAMETER LogDirectory
    Specifies the target directory for log files.
    Defaults to the module's 'Logs' subdirectory (determined by [Logger]::DefaultLogDirectory).
  .PARAMETER DefaultLogFileName
    The base name for the default log file created by the FileAppender. Defaults to 'default.log'.
  .PARAMETER MinimumLevel
    Sets the minimum severity level for messages to be processed by the logger.
    Defaults to 'Information'. Valid values are from the LogEventType enum (Debug, Information, Warning, Error, Fatal).
  .PARAMETER AddDefaultConsoleAppender
    Switch to add the default ConsoleAppender. Defaults to $true.
  .PARAMETER AddDefaultFileAppender
    Switch to add the default FileAppender. Defaults to $true.
  .EXAMPLE
    # Create a logger writing to C:\MyApp\Logs, keeping default appenders
    $logger = New-Logger -LogDirectory "C:\MyApp\Logs"
    # Log messages...
    $logger.Dispose()
  .EXAMPLE
    # Create a logger with only Debug messages and above, default location
    $logger = New-Logger -MinimumLevel Debug
    # Log messages...
    $logger.Dispose()
  .EXAMPLE
    # Create a logger with only a console appender
    $logger = New-Logger -AddDefaultFileAppender:$false
    # Log messages...
    $logger.Dispose() # Still good practice, though less critical without file handles
  .LINK
    https://github.com/chadnpc/cliHelper.logger/blob/main/Public/New-Logger.ps1
  .NOTES
    It is crucial to call the .Dispose() method on the returned logger object
    when you are finished logging to ensure that file handles are closed
    and buffers are flushed properly. A try/finally block is recommended.
    Example:
    $logger = New-Logger
    try {
        $logger.Information("Starting process...")
        # ... your code ...
        $logger.Information("Process finished.")
    }
    finally {
        $logger.Dispose()
    }
  #>
  [CmdletBinding(SupportsShouldProcess = $false)] # Logging itself doesn't change system state directly
  param(
    [Parameter(ValueFromPipelineByPropertyName)]
    [string]$LogDirectory = [Logger]::DefaultLogDirectory,

    [Parameter()]
    [string]$DefaultLogFileName = 'default.log',

    [Parameter()]
    [LogEventType]$MinimumLevel = [LogEventType]::Information,

    [Parameter()]
    [switch]$AddDefaultConsoleAppender,

    [Parameter()]
    [switch]$AddDefaultFileAppender
  )

  Process {
    try {
      # Create logger instance. The constructor handles LogDirectory creation.
      $logger = [Logger]::new($LogDirectory)
      $logger.MinimumLevel = $MinimumLevel

      # Add default console appender if requested
      if ($AddDefaultConsoleAppender) {
        $consoleAppender = [ConsoleAppender]::new()
        $logger.Appenders.Add($consoleAppender)
        Write-Verbose "Added ConsoleAppender to logger."
      }

      # Add default file appender if requested
      if ($AddDefaultFileAppender) {
        $logFilePath = Join-Path -Path $LogDirectory -ChildPath $DefaultLogFileName
        try {
          $fileAppender = [FileAppender]::new($logFilePath)
          $logger.Appenders.Add($fileAppender)
          Write-Verbose "Added FileAppender for path '$logFilePath'."
        } catch {
          Write-Error "Failed to create or add FileAppender for path '$logFilePath'. Logging to this file may not work. Error: $_"
          # Decide if failure to add file appender is critical
          # If so, could throw here or dispose the logger and return null
        }
      }
      Write-Verbose "Logger created with MinimumLevel '$MinimumLevel' and LogDirectory '$($logger.LogDirectory)'."
      return $logger
    } catch {
      Write-Error "Failed to create logger: $_"
      # Return null or re-throw depending on desired behavior
      return $null
    }
  }
}