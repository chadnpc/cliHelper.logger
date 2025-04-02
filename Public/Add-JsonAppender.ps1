function Add-JsonAppender {
  <#
  .SYNOPSIS
    Adds a JSON-formatted file appender to an existing logger instance.
  .DESCRIPTION
    Creates and adds an appender to the specified logger that writes log entries
    as JSON objects (one per line) to the target file path.
    The directory for the JSON file will be created if it doesn't exist.

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
    # The logger instance (created via New-Logger or directly) to modify.
    [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
    [ValidateNotNull()]
    [Logger]$Logger,

    # The full path to the file where JSON log entries should be written.
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrWhiteSpace()][Alias('FilePath')]
    [string]$JsonFilePath
  )

  Process {
    try {
      $resolvedPath = [Logger]::GetUnResolvedPath($JsonFilePath)
      if (![IO.File]::Exists($resolvedPath)) { New-Item -Path $resolvedPath -ItemType File -Force | Out-Null }
      Write-Debug "[Logger] Attempting to add JsonAppender for path: $resolvedPath"
      $jsonAppender = [JsonAppender]::new($resolvedPath)
      $Logger.Appenders += $jsonAppender
      Write-Debug "[Logger] Successfully added JsonAppender for path '$resolvedPath'."
    } catch {
      $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
          $_.Exception, "FAILED_TO_ADD_JSONAPPENDER", [System.Management.Automation.ErrorCategory]::InvalidOperation,
          @{
            Path      = $resolvedPath
            Timestamp = [datetime]::UtcNow
          }
        )
      )
      # TODO: Clean up the partially created appender if it implements IDisposable and failed *after* creation but *before* adding?
      # In this case, the constructor throws, so $jsonAppender wouldn't be assigned on failure.
    }
  }
}