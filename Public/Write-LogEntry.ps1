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
    [Parameter(Mandatory)]
    [ValidateNotNull()] # Ensure a logger object is passed
    [Logger]$Logger,

    [Parameter(Mandatory)]
    [Alias('msg')]
    [string]$Message,

    [Parameter(Mandatory = $false)]
    [Alias('l', 'level')]
    [LogEventType]$Severity = 1,

    [Parameter()]
    [Alias('e')][AllowNull()]
    [System.Exception]$Exception # Optional Exception parameter
  )

  Process {
    # Check if the logger is disposed - prevents errors after disposal
    # Accessing a potentially private field is not ideal, but demonstrates the check.
    # A public IsDisposed property on Logger would be better.
    # For now, rely on the logger's internal checks or catch potential NullReferenceExceptions if methods fail.

    try {
      # Logger methods now handle the IsEnabled check internally
      switch ($Severity) {
        Debug { $Logger.Debug($Message) }
        Info { $Logger.Information($Message) }
        Warning { $Logger.Warning($Message) }
        Error { $Logger.Error($Message, $Exception) }
        Fatal { $Logger.Fatal($Message, $Exception) }
        Default { Write-Warning "Unhandled LogEventType: $Severity" } # Safety net
      }
    } catch {
      # Catch errors that might occur if logger is used improperly (e.g., after disposal)
      # or if an appender throws an unexpected error not caught internally.
      Write-Error "Failed to write log entry: $_. Ensure the logger is not disposed."
    }
  }
}