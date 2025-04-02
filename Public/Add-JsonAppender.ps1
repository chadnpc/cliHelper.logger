function Add-JsonAppender {
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
  [CmdletBinding(SupportsShouldProcess = $false)] # Adding appender modifies object state, not system state
  param(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [Logger]$Logger,

    [Parameter(Mandatory)]
    [string]$JsonFilePath
  )

  Process {
    # Check if the logger is disposed
    # Again, a public IsDisposed property would be cleaner.

    if ([string]::IsNullOrWhiteSpace($JsonFilePath)) {
      Write-Error "JsonFilePath cannot be empty."
      return
    }

    try {
      # Resolve the path
      $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($JsonFilePath)
      Write-Verbose "Attempting to add JsonAppender for path: $resolvedPath"

      # Create the appender. Constructor handles directory creation and file opening.
      $jsonAppender = [JsonAppender]::new($resolvedPath)

      # Add the appender to the logger's list
      $Logger.Appenders.Add($jsonAppender)

      Write-Verbose "Successfully added JsonAppender for path '$resolvedPath'."
      # Optionally return the logger for chaining, though less common for 'Add' cmdlets
      # Write-Output $Logger
    } catch {
      Write-Error "Failed to add JsonAppender for path '$resolvedPath': $_"
      # Clean up the partially created appender if it implements IDisposable and failed *after* creation but *before* adding?
      # In this case, the constructor throws, so $jsonAppender wouldn't be assigned on failure.
    }
  }
}