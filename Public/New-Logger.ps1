function New-Logger {
  <#
  .SYNOPSIS
    Creates a configured logger with console and file appenders

  .DESCRIPTION
    Initializes a new logger instance with default console output and file logging

  .PARAMETER LogDirectory
    Target directory for log files (default: module's Logs directory)

  .EXAMPLE
    $logger = New-Logger -LogDirectory "C:\MyApp\Logs"
  .LINK
    https://github.com/chadnpc/cliHelper.logger/blob/main/Public/New-Logger.ps1
  #>
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'No system state is being changed')]
  [CmdletBinding()]
  param(
    [string]$LogDirectory = $([Logger]::DefaultLogDirectory)
  )

  Process {
    # Create logger with custom directory
    $logger = [Logger]::new($LogDirectory)

    # Add console appender
    $consoleAppender = [ConsoleAppender]::new()
    $logger.Appenders.Add($consoleAppender)

    # Add file appender
    $fileAppender = [FileAppender]::new((Join-Path $LogDirectory "application.log"))
    $logger.Appenders.Add($fileAppender)

    return $logger
  }
}