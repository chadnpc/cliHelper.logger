function Write-LogEntry {
  <#
  .SYNOPSIS
    Writes a log message of a specified logger instance.
  .DESCRIPTION
    Logs a message with a given severity level to all configured logappenders.
  .PARAMETER Logger
    The logger instance (created via New-Logger or directly) to use for logging.
  .PARAMETER Message
    The main text of the log message.
  .PARAMETER Severity
    The severity level of the message. Must be one of the LogLevel enum values
    (Debug, Info, Warn, Error, Fatal).
  .PARAMETER Exception
    [Optional] An Exception object associated with the log entry, typically used
    with Error or Fatal severity.
  .NOTES
    Will only work when the severity meets the logger's MinLevel.
  .EXAMPLE
    $logger = New-Logger
    try {
      Write-LogEntry -l $logger -Message "Application starting." -level Information
      # ... code that might throw ...
      $riskyResult = Get-Something risky
      Write-LogEntry -l $logger -Message "Operation successful." -level Debug
    } catch {
      Write-LogEntry -l $logger -Message "An error occurred during operation." -level Error -Exception $_
    } finally {
      $logger.Dispose()
    }
  .LINK
    https://github.com/chadnpc/cliHelper.logger/blob/main/Public/Write-LogEntry.ps1
  #>
  [CmdletBinding(DefaultParameterSetName = 'm')]
  [Alias('Register-LogEntry')]
  param(
    [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
    [Alias('lo')][ValidateNotNull()]
    [Logger]$Logger = [Logger]::Default,

    [Parameter(Mandatory = $true, ParameterSetName = 'e')]
    [Alias('le', 'entry')][ValidateNotNull()]
    [LogEntry]$LogEntry,

    [Parameter(Mandatory = $true, ParameterSetName = 'm')]
    [Alias('m', 'msg')]
    [string]$Message,

    [Parameter(Mandatory = $false, ParameterSetName = 'm')]
    [Alias('s', 'l', 'level')]
    [LogLevel]$Severity = 1,

    [Parameter(Mandatory = $false, ParameterSetName = 'm')]
    [Alias('e')][AllowNull()]
    [Exception]$Exception # Optional Exception parameter
  )

  Process {
    try {
      if ($PSCmdlet.ParameterSetName -eq "m") {
        #HACK: For now, rely on the logger's internal checks or catch potential NullReferenceExceptions if methods fail.
        switch ($Severity) {
          "DEBUG" { $Logger.LogDebugLine($Message); break }
          "INFO" { $Logger.LogInfoLine($Message); break }
          "WARN" { $Logger.LogWarnLine($Message); break }
          "ERROR" { $Logger.LogErrorLine($Message, $Exception); break }
          "FATAL" { $Logger.LogFatalLine($Message, $Exception); break }
          Default {
            throw [System.Exception]::new("Unhandled LogLevel: $Severity")
          }
        }
      } else {
        $logger.Log($LogEntry)
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