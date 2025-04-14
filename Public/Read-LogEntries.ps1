function Read-LogEntries {
  [CmdletBinding()][OutputType([LogEntry[]] )]
  param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [Alias('l')][ValidateNotNull()]
    [Logger]$Logger,

    # LogEntry type
    [Parameter(Position = 1)]
    [LogAppenderType]$Type
  )

  process {
    $e = switch ($Type) {
      'CONSOLE' { $Logger.GetConsoleAppender().ReadAllEntries() ; break }
      'JSON' { $Logger.GetJsonAppender().ReadAllEntries() ; break }
      'XML' { $Logger.GetXmlAppender().ReadAllEntries() ; break }
      Default {
        throw [System.InvalidOperationException]::new("unknown type")
      }
    }
    return $e
  }
}