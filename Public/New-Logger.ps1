function New-Logger {
  <#
  .SYNOPSIS
    Creates a configured logger instance.
  .DESCRIPTION
    Initializes a new logger instance of the cliHelper.logger module.
    By default, it adds a ConsoleAppender for console output and a FileAppender
    writing to 'default.log' within the specified LogDirectory.
    Remember to call $logger.Dispose() when finished to release file handles.
  .PARAMETER LogDirectory
    Specifies the target directory for log files.
  .PARAMETER FileName
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
  [CmdletBinding(SupportsShouldProcess = $false)][OutputType([Logger])][Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
  param(
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias('Path', 'LogDir')]
    [string]$LogDirectory,

    [Parameter(Mandatory = $false)]
    [Alias('fname')]
    [string]$FileName = 'default.log',

    [Parameter(Mandatory = $false)]
    [Alias('Level')]
    [LogEventType]$MinimumLevel = [LogEventType]::Info,
    [switch]$AddDefaultConsoleAppender
  )
  begin {
    $ob = $null
  }
  Process {
    try {
      # Create logger instance. The constructor will handle LogDirectory creation.
      $ob = [Logger]::new($LogDirectory)
      $ob.MinimumLevel = $MinimumLevel

      # Add default console appender if requested
      if ($AddDefaultConsoleAppender) {
        $consoleAppender = [ConsoleAppender]::new()
        $ob.Appenders += $consoleAppender
        Write-Debug "[Logger] Added ConsoleAppender to logger."
      }
      $logFilePath = [IO.Path]::Combine($LogDirectory, $FileName)
      if (![IO.File]::Exists($logFilePath)) { New-Item -Path $logFilePath -ItemType File -Force | Out-Null }
      $ob.Appenders += [FileAppender]::new($logFilePath)
      Write-Debug "[Logger] Added FileAppender for path '$logFilePath'."
      Write-Debug "[Logger] created with MinimumLevel '$MinimumLevel' and LogDirectory '$($ob.LogDirectory)'."
    } catch {
      $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
          $_.Exception, "FAILED_TO_CREATE_LOGGER", [System.Management.Automation.ErrorCategory]::InvalidOperation,
          $null
        )
      )
    }
  }
  end {
    return $ob
  }
}