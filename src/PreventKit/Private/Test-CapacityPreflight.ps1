<#
.SYNOPSIS
Run a capacity preflight check before any write to an enforcement target.

.DESCRIPTION
Computes the planned managed entry count as the current managed count, minus
entries that will be removed, plus entries that will be added, and reports
whether that fits within the target capacity. The check is purely a
report; no target is read or written.

.PARAMETER CurrentManagedCount
Number of managed entries currently present in the target.

.PARAMETER AddCount
Number of entries the reconciliation plans to add.

.PARAMETER RemoveCount
Number of entries the reconciliation plans to remove.

.PARAMETER Capacity
Maximum managed entries the target can hold.

.OUTPUTS
System.Management.Automation.PSCustomObject with Passed, PlannedCount and
Capacity properties.
#>
function Test-CapacityPreflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$CurrentManagedCount,

        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$AddCount,

        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$RemoveCount,

        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Capacity
    )

    $plannedCount = $CurrentManagedCount - $RemoveCount + $AddCount

    [pscustomobject]@{
        Passed       = ($plannedCount -le $Capacity)
        PlannedCount = $plannedCount
        Capacity     = $Capacity
    }
}
