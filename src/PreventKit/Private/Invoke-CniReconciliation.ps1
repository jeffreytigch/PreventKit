<#
.SYNOPSIS
Reconcile MDE Custom Network Indicators to the projected desired state.

.DESCRIPTION
Runs a capacity preflight before any write, then brings the CNI destination in
line with the desired entries. Missing projections are added as permanent
managed indicators carrying the provenance namespace in their description,
posted in batches paced to the API rate limit with 429 backoff; stale managed
indicators are removed via BatchDelete; unmanaged collisions are never adopted,
changed, or removed. When the preflight fails, no write happens and the run
reports Status 'Aborted'.

.PARAMETER DesiredEntries
Desired CNI projections. Each must expose Value, IndicatorType and ServiceId.

.PARAMETER CurrentEntries
Raw current CNI indicators (as returned by the read side), each exposing
indicatorValue, indicatorType, description, id and action.

.PARAMETER Capacity
Maximum managed indicators the tenant can hold.

.PARAMETER BatchSize
Maximum number of indicators or ids per API call.

.PARAMETER RateLimitPerMinute
Maximum API calls per minute across batches; 0 disables pacing.

.PARAMETER MaxRetries
Maximum attempts per batch before giving up on persistent 429 responses.

.PARAMETER BackoffSeconds
Base backoff seconds passed through to each request.

.OUTPUTS
System.Management.Automation.PSCustomObject with Destination, Status, Preflight,
AddCount, RemoveCount, UnchangedCount and UnmanagedCollisionCount properties.
#>
function Invoke-CniReconciliation {
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
        [int]$BatchSize = 500,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$RateLimitPerMinute = 30,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaxRetries = 5,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$BackoffSeconds = 30
    )

    $report = Get-CniReport -Entries $CurrentEntries
    $diff = Get-ReconcileDiff -DesiredEntries $DesiredEntries `
        -CurrentEntries $report.Entries -CurrentValueProperty 'IndicatorValue'

    $preflight = Test-CapacityPreflight -CurrentManagedCount $report.ManagedCount `
        -AddCount $diff.AddCount -RemoveCount $diff.RemoveCount -Capacity $Capacity

    if (-not $preflight.Passed) {
        return New-ReconcileResult -Destination 'Cni' -Status 'Aborted' -Preflight $preflight `
            -AddCount $diff.AddCount -RemoveCount $diff.RemoveCount `
            -UnchangedCount $diff.UnchangedCount -UnmanagedCollisionCount $diff.UnmanagedCollisionCount
    }

    if ($diff.AddCount -eq 0 -and $diff.RemoveCount -eq 0) {
        return New-ReconcileResult -Destination 'Cni' -Status 'NoChanges' -Preflight $preflight `
            -AddCount 0 -RemoveCount 0 `
            -UnchangedCount $diff.UnchangedCount -UnmanagedCollisionCount $diff.UnmanagedCollisionCount
    }

    if ($diff.AddCount -gt 0) {
        $null = Add-CniManagedEntry -Projections $diff.Adds -BatchSize $BatchSize `
            -RateLimitPerMinute $RateLimitPerMinute -MaxRetries $MaxRetries `
            -BackoffSeconds $BackoffSeconds
    }

    if ($diff.RemoveCount -gt 0) {
        $null = Remove-CniManagedEntry -Id @($diff.Removes | ForEach-Object { $_.Id }) `
            -BatchSize $BatchSize -RateLimitPerMinute $RateLimitPerMinute `
            -MaxRetries $MaxRetries -BackoffSeconds $BackoffSeconds
    }

    New-ReconcileResult -Destination 'Cni' -Status 'Reconciled' -Preflight $preflight `
        -AddCount $diff.AddCount -RemoveCount $diff.RemoveCount `
        -UnchangedCount $diff.UnchangedCount -UnmanagedCollisionCount $diff.UnmanagedCollisionCount
}