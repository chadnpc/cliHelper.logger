function Add-JsonAppender {
  <#
  .SYNOPSIS
    Adds a JSON-formatted file appender to an existing logger

  .DESCRIPTION
    Creates a custom appender that writes logs in JSON format to a specified file

  .PARAMETER Logger
    Logger instance to modify

  .PARAMETER JsonFilePath
    Path to JSON log file

  .EXAMPLE
    Add-JsonAppender -Logger $logger -JsonFilePath "C:\Logs\app.json"
  .LINK
    https://github.com/chadnpc/cliHelper.logger/blob/main/Public/Add-JsonAppender.ps1
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [Logger]$Logger,

    [Parameter(Mandatory)]
    [string]$JsonFilePath
  )

  process {
    $jsonAppender = [JsonAppender]::new($JsonFilePath)
    $Logger.Appenders.Add($jsonAppender)
  }
}