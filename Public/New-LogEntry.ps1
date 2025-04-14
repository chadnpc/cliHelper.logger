function New-LogEntry {
  <#
  .SYNOPSIS
    creates a [LogEntry] object
  .LINK
    https://github.com/chadnpc/cliHelper.logger/blob/main/Public/New-LogEntry.ps1
  .EXAMPLE
    New-LogEntry -m "Some text message ..."
  #>
  [CmdletBinding()][Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "", Justification = "Not changing state")]
  [OutputType([LogEntry])]
  param (
    [Parameter(Mandatory = $true, Position = 0)]
    [Alias("m")][ValidateNotNullOrWhiteSpace()]
    [string]$message,

    [Parameter(Mandatory = $false, Position = 1)]
    [Alias("s", "l")][LogLevel]$severity = "INFO",

    [Parameter(Mandatory = $false, Position = 2)]
    [Alias("e")][AllowNull()]
    [Exception]$exception = $null
  )

  process {
    return [LogEntry]::Create($severity, $message, $exception)
  }
}