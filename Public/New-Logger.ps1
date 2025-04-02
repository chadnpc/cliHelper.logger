function New-Logger {
  <#
  .SYNOPSIS
    Creates a configured logger instance.
  .DESCRIPTION
    Initializes a new logger instance of the cliHelper.logger module.
    By default, it adds a ConsoleAppender for console output and a FileAppender
    writing to a .log file in the specified Logdirectory.
    Remember to call $logger.Dispose() when finished to release file handles.

  .EXAMPLE
    # Create a logger writing to C:\MyApp\Logs, keeping default appenders
    $logger = New-Logger -Logdirectory "C:\MyApp\Logs"
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
    # The target directory for log files.
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias('Path', 'Logdir')]
    [string]$Logdirectory = [IO.Path]::GetTempPath(),

    # The base name for the default log file created by the FileAppender.
    [Parameter(Mandatory = $false)]
    [Alias('fname')]
    [string]$FileName = "log_$(Get-Date -Format 'yyyyMMdd-HHmmss')-$(New-Guid).log",

    # Sets the minimum severity level for messages to be processed by the logger.
    # Defaults to 'Info'. Valid values are from the LogEventType enum (Debug, Information, Warning, Error, Fatal).
    [Parameter(Mandatory = $false)]
    [Alias('Level')]
    [LogEventType]$MinimumLevel = [LogEventType]::Info,

    # has Console appender by default
    [ILogAppender[]]$Appenders = @([ConsoleAppender]::new())
  )
  begin {
    $ob = $null
  }
  Process {
    try {
      # Create logger instance. The constructor will handle Logdirectory creation.
      $ob = [Logger]::new($Logdirectory)
      $ob.MinimumLevel = $MinimumLevel
      if ($Appenders.count -gt 0) {
        $Appenders.ForEach({ $ob.Appenders += $_ })
      }
      $logFilePath = [IO.Path]::Combine($Logdirectory, $FileName)
      if (![IO.File]::Exists($logFilePath)) { New-Item -Path $logFilePath -ItemType File -Force | Out-Null }
      $ob.Appenders += [FileAppender]::new($logFilePath)
      Write-Debug "[Logger] Added FileAppender for path '$logFilePath'."
      Write-Debug "[Logger] created with MinimumLevel '$MinimumLevel' and Logdirectory '$($ob.Logdirectory)'."
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