<#
.SYNOPSIS
Build the shared reconciliation result object.

.DESCRIPTION
Emits the common result shape returned by every enforcement-target
reconciliation: the target name, a status of 'Aborted', 'NoChanges' or
'Reconciled', the preflight outcome, and the diff counts. Keeping the shape in
one place stops the reconcilers from drifting.

.OUTPUTS
System.Management.Automation.PSCustomObject with Target, Status, Preflight,
AddCount, RemoveCount, UnchangedCount and UnmanagedMatchCount properties.
#>
function New-ReconcileResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Target,

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
        [int]$UnmanagedMatchCount
    )

    [pscustomobject]@{
        Target                = $Target
        Status                = $Status
        Preflight             = $Preflight
        AddCount              = $AddCount
        RemoveCount           = $RemoveCount
        UnchangedCount        = $UnchangedCount
        UnmanagedMatchCount   = $UnmanagedMatchCount
    }
}