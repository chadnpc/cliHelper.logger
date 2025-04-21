function Get-LogSession {
  [CmdletBinding()][OutputType([Logsession[]])]
  param (
    # session Id
    [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrWhiteSpace()]
    [string]$Id
  )
  process {
    $sessions = [Logger]::Getallsessions()
    if ($PSBoundParameters.ContainsKey('Id')) {
      $sessions = $Id.Contains('*') ? $sessions.Where({ $_.Id -like $Id }) : $sessions.Where({ $_.Id -eq $Id })
    }
    return $sessions
  }
}