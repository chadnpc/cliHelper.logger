function Read-LogEntries {
  [CmdletBinding()][OutputType([LogEntry[]] )]
  param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [Alias('l')][ValidateNotNull()]
    [Logger]$Logger,

    # LogEntry type
    [Parameter(Mandatory = $false, Position = 1)]
    [LogAppenderType]$Type = 'JSON'
  )

  process {
    return $Logger.ReadAllEntries($Type)
  }
}