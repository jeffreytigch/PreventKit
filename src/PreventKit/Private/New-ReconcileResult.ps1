<#
.SYNOPSIS
Build the shared reconciliation result object.

.DESCRIPTION
Emits the common result shape returned by every enforcement-destination
reconciliation: the destination name, a status of 'Aborted', 'NoChanges' or
'Reconciled', the preflight outcome, and the diff counts. Keeping the shape in
one place stops the reconcilers from drifting.

.OUTPUTS
System.Management.Automation.PSCustomObject with Destination, Status, Preflight,
AddCount, RemoveCount, UnchangedCount and UnmanagedCollisionCount properties.
#>
function New-ReconcileResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination,

        [Parameter(Mandatory)]
        [ValidateSet('Aborted', 'NoChanges', 'Reconciled')]
        [string]$Status,

        [Parameter(Mandatory)]
        [pscustomobject]$Preflight,

        [Parameter(Mandatory)]
        [int]$AddCount,

        [Parameter(Mandatory)]
        [int]$RemoveCount,

        [Parameter(Mandatory)]
        [int]$UnchangedCount,

        [Parameter(Mandatory)]
        [int]$UnmanagedCollisionCount
    )

    [pscustomobject]@{
        Destination             = $Destination
        Status                  = $Status
        Preflight               = $Preflight
        AddCount                = $AddCount
        RemoveCount             = $RemoveCount
        UnchangedCount          = $UnchangedCount
        UnmanagedCollisionCount = $UnmanagedCollisionCount
    }
}