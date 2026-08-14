<#
.SYNOPSIS
Render a human-readable per-run report from a run log entry.

.DESCRIPTION
Produces a readable report for one Run: the run id and timing, the catalogue
directory, each source fingerprint (catalogue, source, hash, validation status,
and any last-known-good fallback), the exceptions applied, and the outcome of
each destination reconciliation.

.OUTPUTS
System.String, one line per report line.
#>
function New-PreventKitRunReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$LogEntry
    )

    $lines = @()

    $lines += "PreventKit run $($LogEntry.RunId)"
    $lines += '==================='
    $lines += "Catalogue directory: $($LogEntry.CatalogueDirectory)"
    $lines += "Started: $($LogEntry.StartedAt)"
    $lines += "Completed: $($LogEntry.CompletedAt)"
    $lines += ''

    $lines += 'Source fingerprints'
    $lines += '=================='
    foreach ($fingerprint in @($LogEntry.SourceFingerprints)) {
        $fallbackFlag = if ($fingerprint.UsedLastKnownGood) { ' [last known good fallback]' } else { '' }
        $lines += "  - $($fingerprint.CatalogueName): $($fingerprint.SourceLocation)"
        $lines += "      hash=$($fingerprint.ContentHash) validation=$($fingerprint.ValidationStatus)$fallbackFlag"
        if ($fingerprint.FailureReason) {
            $lines += "      failure: $($fingerprint.FailureReason)"
        }
    }

    $lines += ''
    $lines += "Exceptions applied ($(@($LogEntry.Exceptions).Count)):"
    foreach ($exception in @($LogEntry.Exceptions)) {
        $lines += "  - $exception"
    }

    $lines += ''
    $lines += 'Destination outcomes'
    $lines += '===================='
    foreach ($outcome in @($LogEntry.DestinationOutcomes)) {
        $lines += "  - $($outcome.Destination): $($outcome.Status) add=$($outcome.AddCount) remove=$($outcome.RemoveCount) unchanged=$($outcome.UnchangedCount) collision=$($outcome.UnmanagedCollisionCount)"
        $lines += "      preflight: passed=$($outcome.Preflight.Passed) planned=$($outcome.Preflight.PlannedCount) capacity=$($outcome.Preflight.Capacity)"
    }

    $lines
}