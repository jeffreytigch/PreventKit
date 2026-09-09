<#
.SYNOPSIS
Reconcile the Tenant Allow/Block List URL block entries to the mapped
desired state.

.DESCRIPTION
Runs a capacity preflight before any write, then brings the TABL URL block
target in line with the desired entries. Missing values are added as
permanent managed entries carrying the owner marker; stale managed
entries are removed; unmanaged matches are never adopted, changed, or
removed. When the preflight fails, no write happens and the run reports
Status 'Aborted'.

.PARAMETER DesiredEntries
Desired URL block values. Each must expose a Value property.

.PARAMETER CurrentEntries
Raw current TABL URL block entries (as returned by the read side), each
exposing Value, Identity and Notes.

.PARAMETER Capacity
Maximum managed URL block entries the tenant can hold.

.PARAMETER AddBatchSize
Maximum number of values to submit per New-TenantAllowBlockListItems call.

.PARAMETER RemoveBatchSize
Maximum number of identities to submit per Remove-TenantAllowBlockListItems call.

.OUTPUTS
System.Management.Automation.PSCustomObject with Target, Status, Preflight,
AddCount, RemoveCount, UnchangedCount and UnmanagedMatchCount properties.
#>
function Invoke-TablReconciliation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$DesiredEntries,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$CurrentEntries,

        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Capacity,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$AddBatchSize = 50,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$RemoveBatchSize = 100
    )

    $report = Get-TablBlockReport -Entries $CurrentEntries
    $diff = Get-ReconcileDiff -DesiredEntries $DesiredEntries `
        -CurrentEntries $report.Entries -CurrentValueProperty 'Value'

    $preflight = Test-CapacityPreflight -CurrentManagedCount $report.ManagedCount `
        -AddCount $diff.AddCount -RemoveCount $diff.RemoveCount -Capacity $Capacity

    if (-not $preflight.Passed) {
        return New-ReconcileResult -Target 'Tabl' -Status 'Aborted' -Preflight $preflight `
            -AddCount $diff.AddCount -RemoveCount $diff.RemoveCount `
            -UnchangedCount $diff.UnchangedCount -UnmanagedMatchCount $diff.UnmanagedMatchCount
    }

    if ($diff.AddCount -eq 0 -and $diff.RemoveCount -eq 0) {
        return New-ReconcileResult -Target 'Tabl' -Status 'NoChanges' -Preflight $preflight `
            -AddCount 0 -RemoveCount 0 `
            -UnchangedCount $diff.UnchangedCount -UnmanagedMatchCount $diff.UnmanagedMatchCount
    }

    $notes = "$($script:ownerMarker) managed entry"

    if ($diff.AddCount -gt 0) {
        foreach ($batch in @(Get-BatchGroup -Items $diff.Adds -BatchSize $AddBatchSize)) {
            $null = Add-TablManagedEntry -Values @($batch | ForEach-Object { $_.Value }) -Notes $notes
        }
    }

    if ($diff.RemoveCount -gt 0) {
        foreach ($batch in @(Get-BatchGroup -Items $diff.Removes -BatchSize $RemoveBatchSize)) {
            $null = Remove-TablManagedEntry -Identities @($batch | ForEach-Object { $_.Identity })
        }
    }

    New-ReconcileResult -Target 'Tabl' -Status 'Reconciled' -Preflight $preflight `
        -AddCount $diff.AddCount -RemoveCount $diff.RemoveCount `
        -UnchangedCount $diff.UnchangedCount -UnmanagedMatchCount $diff.UnmanagedMatchCount
}