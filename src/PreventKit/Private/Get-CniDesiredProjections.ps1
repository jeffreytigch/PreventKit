<#
.SYNOPSIS
Compute the CNI desired projections for a Run's desired state.

.DESCRIPTION
Aggregates the destination projections of every validated catalogue
contribution in the desired state into a single de-duplicated list of desired
CNI indicators, honouring each contribution's own expansion approval. Only
addresses present in the desired state (after non-overriding invocation
exceptions) are projected. This is the DesiredEntries input for CNI
reconciliation.

.OUTPUTS
System.Object[] — a single array of projection objects.
#>
function Get-CniDesiredProjections {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$DesiredState
    )

    $projections = @()
    $seen = @{}
    $desiredValues = @{}
    foreach ($address in @($DesiredState.BlockableAddresses)) {
        $desiredValues[[string]$address.Value] = $true
    }

    foreach ($contribution in @($DesiredState.Contributions)) {
        if ($contribution.Validation.Status -ne 'Success') {
            continue
        }

        $table = Get-CniProjectionTable -Snapshot $contribution
        foreach ($projection in @($table.Projections)) {
            if (-not $desiredValues.ContainsKey([string]$projection.SourceValue)) {
                continue
            }
            $value = [string]$projection.Value
            if (-not $seen.ContainsKey($value)) {
                $seen[$value] = $true
                $projections += $projection
            }
        }
    }

    , @($projections)
}