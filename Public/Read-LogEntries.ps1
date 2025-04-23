function Read-LogEntries {
  [CmdletBinding()][OutputType([LogEntries] )]
  param (
    [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
    [Alias('l')][ValidateNotNull()]
    [Logger]$Logger = [Logger]::Default,

    # LogEntry type
    [Parameter(Mandatory = $false, Position = 1)]
    [Alias('t')]
    [LogAppenderType]$Type = 'JSON'
  )

  process {
    return $Logger.ReadEntries($Type)
  }
}