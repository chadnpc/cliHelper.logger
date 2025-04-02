function Write-LogEntry {
  <#
  .SYNOPSIS
    Writes a log message of a specified logger instance.
  .DESCRIPTION
    Logs a message with a given severity level to all appenders configured
    in the provided logger instance, provided the severity meets the logger's MinimumLevel.
  .PARAMETER Logger
    The logger instance (created via New-Logger or directly) to use for logging.
  .PARAMETER Message
    The main text of the log message.
  .PARAMETER Severity
    The severity level of the message. Must be one of the LogEventType enum values
    (Debug, Information, Warning, Error, Fatal).
  .PARAMETER Exception
    [Optional] An Exception object associated with the log entry, typically used
    with Error or Fatal severity.
  .EXAMPLE
    $logger = New-Logger
    try {
      Write-LogEntry -Logger $logger -Message "Application starting." -Severity Information
      # ... code that might throw ...
      $riskyResult = Get-Something risky
      Write-LogEntry -Logger $logger -Message "Operation successful." -Severity Debug
    } catch {
      Write-LogEntry -Logger $logger -Message "An error occurred during operation." -Severity Error -Exception $_
    } finally {
      $logger.Dispose()
    }
  .LINK
    https://github.com/chadnpc/cliHelper.logger/blob/main/Public/Write-LogEntry.ps1
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [ValidateNotNull()]
    [Logger]$Logger,

    [Parameter(Mandatory = $true)]
    [Alias('msg')]
    [string]$Message,

    [Parameter(Mandatory = $false)]
    [Alias('l', 'level')]
    [LogEventType]$Severity = 1,

    [Parameter(Mandatory = $false)]
    [Alias('e')][AllowNull()]
    [System.Exception]$Exception # Optional Exception parameter
  )

  Process {
    #HACK: For now, rely on the logger's internal checks or catch potential NullReferenceExceptions if methods fail.
    try {
      switch ($Severity) {
        "Debug" { $Logger.Debug($Message); break }
        "Info" { $Logger.Info($Message); break }
        "Warning" { $Logger.Warning($Message); break }
        "Error" { $Logger.Error($Message, $Exception); break }
        "Fatal" { $Logger.Fatal($Message, $Exception); break }
        Default {
          throw [System.Exception]::new("Unhandled LogEventType: $Severity")
        }
      }
    } catch {
      $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
          $_.Exception, "FAILED_TO_WRITE_LOG_ENTRY", [System.Management.Automation.ErrorCategory]::InvalidOperation,
          @{
            Hint      = "Ensure the logger is not disposed"
            Timestamp = [datetime]::UtcNow
          }
        )
      )
    }
  }
}