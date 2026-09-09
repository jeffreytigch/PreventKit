<#
.SYNOPSIS
Compute the CNI desired mappings for a Run's desired state.

.DESCRIPTION
Aggregates the target mappings of every validated catalogue
contribution in the desired state into a single de-duplicated list of desired
CNI indicators, honouring each contribution's own broadening approval. Only
addresses present in the desired state (after managed-only invocation
exceptions) are mapped. This is the DesiredEntries input for CNI
reconciliation.

.OUTPUTS
System.Object[] — a single array of mapping objects.
#>
function Get-CniDesiredMappings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$DesiredState
    )

    $mappings = @()
    $seen = @{}
    $desiredValues = @{}
    foreach ($address in @($DesiredState.BlockableAddresses)) {
        $desiredValues[[string]$address.Value] = $true
    }

    foreach ($contribution in @($DesiredState.Contributions)) {
        if ($contribution.Validation.Status -ne 'Success') {
            continue
        }

        $table = Get-CniMappingTable -Snapshot $contribution
        foreach ($mapping in @($table.Mappings)) {
            if (-not $desiredValues.ContainsKey([string]$mapping.SourceValue)) {
                continue
            }
            $value = [string]$mapping.Value
            if (-not $seen.ContainsKey($value)) {
                $seen[$value] = $true
                $mappings += $mapping
            }
        }
    }

    , @($mappings)
}