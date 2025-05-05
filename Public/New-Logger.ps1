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
    $logger = New-Logger -MinLevel Debug
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
      $logger.LogInfoLine("Starting process...")
      # ... your code ...
      $logger.LogInfoLine("Process finished.")
    }
    finally {
      $logger.Dispose()
    }
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
  [CmdletBinding(SupportsShouldProcess = $false, DefaultParameterSetName = 'fa')]
  [OutputType([Logger])]
  param(
    # The target directory for log files.
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrWhiteSpace()][Alias('Path', 'Logdir')]
    [string]$Logdirectory,

    # The base name for the default logFile created by the FileAppender.
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrWhiteSpace()][Alias('fname', 'LogFile')]
    [string]$FileName = "log_$(Get-Date -Format 'yyyyMMdd-HHmmss')-$(New-Guid).log",

    # Sets the minimum severity level for messages to be processed by the logger.
    [Parameter(Mandatory = $false)]
    [Alias('Level')]
    [LogLevel]$MinLevel = 'INFO',

    # has Console appender by default
    [LogAppender[]]$appenders = @([ConsoleAppender]::new())
  )
  Process {
    # Create logger instance. The constructor will handle Logdirectory creation.
    try {
      $ob = $Logdirectory ? [Logger]::Create($Logdirectory, $MinLevel) : [Logger]::Create($MinLevel)
      $logFilePath = [IO.Path]::Combine($ob.Logdir, $FileName)
      if (![IO.File]::Exists($logFilePath)) { New-Item -Path $logFilePath -ItemType File -Force | Out-Null }
      $ob.AddLogAppender([FileAppender]::new($logFilePath))

      if ($appenders.count -gt 0) { $appenders.ForEach({ $ob.AddLogAppender($_) }) }
      Write-Debug "[Logger] Added FileAppender for path '$logFilePath'."
      Write-Debug "[Logger] created with MinLevel '$MinLevel' and Logdirectory '$($ob.Logdir)'."
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