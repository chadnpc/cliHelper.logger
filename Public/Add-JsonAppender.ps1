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
    $logger | Add-JsonAppender "app_events.json"
    $logger.Info("JSON appender added")
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
    # A JSON fileName where log entries should be written.
    [Parameter(Mandatory = $false)]
    [Alias('n', 'fname')][ValidateNotNullOrWhiteSpace()]
    [string]$FileName = "log_$(Get-Date -Format 'yyyyMMdd-HHmmss')-$(New-Guid).json",

    # The logger instance (created via New-Logger or directly) to modify.
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [Alias('l')][ValidateNotNull()]
    [Logger]$Logger
  )

  Process {
    try {
      if (!$Logger.Logdir.Exists) { throw "Please create & set Logdir first!" }
      $JsonFilePath = [Logger]::GetUnResolvedPath([IO.Path]::Combine($Logger.Logdir, $FileName))
      if (![IO.File]::Exists($JsonFilePath)) { New-Item -Path $JsonFilePath -ItemType File -Force | Out-Null }
      Write-Debug "[Logger] Attempting to add JsonAppender for path: $JsonFilePath"
      $Logger.AddLogAppender([JsonAppender]::new($JsonFilePath))
      Write-Debug "[Logger] Successfully added JsonAppender for path '$JsonFilePath'."
    } catch {
      $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
          $_.Exception, "FAILED_TO_ADD_JSONAPPENDER", [System.Management.Automation.ErrorCategory]::InvalidOperation,
          @{
            Path      = $JsonFilePath
            Timestamp = [datetime]::UtcNow
          }
        )
      )
      # TODO: Clean up the partially created appender if it implements IDisposable and failed *after* creation but *before* adding?
      # In this case, the constructor throws, so $jsonAppender wouldn't be assigned on failure.
    }
  }
}