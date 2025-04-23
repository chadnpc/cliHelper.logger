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
    if (!$PSBoundParameters.ContainsKey('Logger')) {
      $PSCmdlet.ThrowTerminatingError(
        [System.Management.Automation.ErrorRecord]::new(
          [System.InvalidOperationException]::new("Please provide a logger object"),
          'InvalidOperationException',
          [System.Management.Automation.ErrorCategory]::InvalidOperation,
          $null
        )
      )
    }
    return $Logger.ReadEntries($Type)
  }
}