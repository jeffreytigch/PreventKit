<#
.SYNOPSIS
Query run log entries from a log directory.

.DESCRIPTION
Returns every run log entry under the log directory, oldest first. When a RunId
is supplied, only that run's entry is returned, or nothing when it is not
present.

.PARAMETER LogDirectory
Directory where run log entries are written.

.PARAMETER RunId
When supplied, only the run with this id is returned.

.EXAMPLE
Get-PreventKitRunLog -LogDirectory .\logs

.EXAMPLE
Get-PreventKitRunLog -LogDirectory .\logs -RunId (Get-PreventKitRunLog -LogDirectory .\logs | Select-Object -First 1).RunId

.OUTPUTS
System.Management.Automation.PSCustomObject, one per run log entry.
#>
function Get-PreventKitRunLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LogDirectory,

        [Parameter()]
        [guid]$RunId
    )

    if ($PSBoundParameters.ContainsKey('RunId')) {
        $file = Join-Path $LogDirectory "$($RunId.Guid).run.json"
        if (Test-Path -LiteralPath $file) {
            Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
        }
        return
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $LogDirectory -Filter '*.run.json' -File | Sort-Object LastWriteTime)) {
        Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    }
}
