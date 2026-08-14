<#
.SYNOPSIS
Persist a validated catalogue snapshot as the catalogue's last known good
snapshot.

.DESCRIPTION
Stores the snapshot under the state directory, one JSON file per catalogue
(name of the declaration). Only successfully retrieved and validated snapshots
should be passed; a later Run falls back to this file when retrieval or
validation of the catalogue source fails.

.OUTPUTS
None.
#>
function Save-LastKnownGoodSnapshot {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$StateDirectory,

        [Parameter(Mandatory)]
        [pscustomobject]$Snapshot
    )

    if ([string]::IsNullOrWhiteSpace($StateDirectory)) {
        return
    }

    if (-not (Test-Path -LiteralPath $StateDirectory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $StateDirectory -Force
    }

    $file = Join-Path $StateDirectory "$($Snapshot.CatalogueName).lkg.json"
    $Snapshot | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $file -Encoding utf8
}