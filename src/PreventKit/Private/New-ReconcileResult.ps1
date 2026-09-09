<#
.SYNOPSIS
Build the shared reconciliation result object.

.DESCRIPTION
Emits the common result shape returned by every enforcement-target
reconciliation: the target name, status, preflight outcome, diff counts, and
optional per-batch write results. Keeping the shape in one place stops the
reconcilers from drifting.

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
        [ValidateSet('Aborted', 'NoChanges', 'Reconciled', 'PartiallyReconciled')]
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
        [int]$UnmanagedMatchCount,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$FailedBatchCount = 0,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$BatchResults = @()
    )

    [pscustomobject]@{
        Target                = $Target
        Status                = $Status
        Preflight             = $Preflight
        AddCount              = $AddCount
        RemoveCount           = $RemoveCount
        UnchangedCount        = $UnchangedCount
        UnmanagedMatchCount   = $UnmanagedMatchCount
        FailedBatchCount      = $FailedBatchCount
        BatchResults          = @($BatchResults)
    }
}
