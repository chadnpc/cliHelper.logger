function Write-LogEntry {
  <#
  .SYNOPSIS
    Writes a log message with specified severity level

  .DESCRIPTION
    Logs messages with different severity levels to all configured appenders

  .PARAMETER Logger
    Logger instance to use for logging

  .PARAMETER Message
    Message text to log

  .PARAMETER Severity
    Severity level from LogEventType enum

  .PARAMETER Exception
    Optional exception object to log

  .EXAMPLE
    Write-LogEntry -Logger $logger -Message "Database connection lost" -Severity Error -Exception $ex

  .LINK
    https://github.com/chadnpc/cliHelper.logger/blob/main/Public/Write-LogEntry.ps1
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [Logger]$Logger,

    [Parameter(Mandatory)]
    [string]$Message,

    [Parameter(Mandatory)]
    [LogEventType]$Severity,

    [Exception]$Exception
  )

  process {
    switch ($Severity) {
      Debug { $Logger.Debug($Message) }
      Information { $Logger.Information($Message) }
      Warning { $Logger.Warning($Message) }
      Error { $Logger.Error($Message, $Exception) }
      Fatal { $Logger.Fatal($Message, $Exception) }
    }
  }
}