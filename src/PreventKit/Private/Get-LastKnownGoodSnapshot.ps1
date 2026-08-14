<#
.SYNOPSIS
Load a catalogue's last known good snapshot, optionally flagged as a fallback.

.DESCRIPTION
Returns the stored last known good snapshot for the named catalogue, or the
Fallback snapshot when no last known good snapshot exists. When a FailureReason
is supplied, the returned snapshot's fingerprint is flagged with
UsedLastKnownGood $true and the failure reason, so a Run can record that it
fell back. When no last known good snapshot exists, the Fallback is returned
unmodified.

.OUTPUTS
System.Management.Automation.PSCustomObject.
#>
function Get-LastKnownGoodSnapshot {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$StateDirectory,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$CatalogueName,

        [Parameter()]
        [string]$FailureReason,

        [Parameter()]
        [object]$Fallback
    )

    if ([string]::IsNullOrWhiteSpace($StateDirectory)) {
        return $Fallback
    }

    $file = Join-Path $StateDirectory "$CatalogueName.lkg.json"
    if (-not (Test-Path -LiteralPath $file)) {
        return $Fallback
    }

    $lkg = $null
    try {
        $lkg = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
    }
    catch {
        Write-Warning "Could not read last known good snapshot for catalogue '$CatalogueName': $($_.Exception.Message)"
        return $Fallback
    }

    if ([string]::IsNullOrWhiteSpace($FailureReason)) {
        return $lkg
    }

    $lkg.Fingerprint | Add-Member -NotePropertyName UsedLastKnownGood -NotePropertyValue $true -Force
    $lkg.Fingerprint | Add-Member -NotePropertyName FailureReason -NotePropertyValue $FailureReason -Force
    $lkg
}