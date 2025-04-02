﻿function Add-JsonAppender {
  <#
  .SYNOPSIS
    Adds a JSON-formatted file appender to an existing logger instance.
  .DESCRIPTION
    Creates and adds an appender to the specified logger that writes log entries
    as JSON objects (one per line) to the target file path.
    The directory for the JSON file will be created if it doesn't exist.
  .PARAMETER Logger
    The logger instance (created via New-Logger or directly) to modify.
  .PARAMETER JsonFilePath
    The full path to the file where JSON log entries should be written.
  .EXAMPLE
    $logger = New-Logger
    Add-JsonAppender -Logger $logger -JsonFilePath "C:\MyApp\Logs\application_events.json"
    $logger.Information("JSON appender added")
    # ... log more ...
    $logger.Dispose()
  .LINK
    Logger class
  .LINK
    JsonAppender class
  .LINK
    New-Logger
  #>
  [CmdletBinding(SupportsShouldProcess = $false)]
  param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNull()]
    [Logger]$Logger,

    [Parameter(Mandatory = $false)]
    [ValidateScript({
        if ([string]::IsNullOrWhiteSpace($_)) {
          throw [System.ArgumentNullException]::new("JsonFilePath", "Please provide a valid file path")
        }
      }
    )][Alias('o', 'outFile')]
    [string]$JsonFilePath
  )

  Process {
    try {
      if ([string]::IsNullOrWhiteSpace($JsonFilePath)) {
        throw [System.IO.InvalidDataException]::new("JsonFilePath cannot be empty.")
      }
      $resolvedPath = [Logger]::GetUnResolvedPath($JsonFilePath)
      Write-Debug "[Logger] Attempting to add JsonAppender for path: $resolvedPath"
      $jsonAppender = [JsonAppender]::new($resolvedPath)
      $Logger.Appenders.Add($jsonAppender)
      Write-Debug "[Logger] Successfully added JsonAppender for path '$resolvedPath'."
    } catch {
      $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
          $_.Exception, "FAILED_TO_ADD_JSONAPPENDER", [System.Management.Automation.ErrorCategory]::InvalidOperation,
          @{
            Path = $resolvedPath
          }
        )
      )
      # Clean up the partially created appender if it implements IDisposable and failed *after* creation but *before* adding?
      # In this case, the constructor throws, so $jsonAppender wouldn't be assigned on failure.
    }
  }
}