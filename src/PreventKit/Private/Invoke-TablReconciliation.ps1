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
Operational choice (default 50) within the tenant block-entry limits: the
cmdlet accepts an -Entries array in a single call and no documented per-call
entry count cap exists; the binding limits are the tenant totals (500 / 1,000 /
10,000 block entries depending on license).

.PARAMETER RemoveBatchSize
Maximum number of identities to submit per Remove-TenantAllowBlockListItems call.
Operational choice (default 100), symmetric with the add path: the remove path
uses the same Get-BatchGroup batching.

.OUTPUTS
System.Management.Automation.PSCustomObject with Target, Status, Preflight,
AddCount, RemoveCount, UnchangedCount, UnmanagedMatchCount, FailedBatchCount,
and BatchResults properties.
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

    # One cmdlet call per batch (never per entry), with the batch -Entries array
    # in a single call. Each batch is attempted independently and its response is
    # retained so partial entry failures do not hide behind a successful command.
    $batchResults = @()

    if ($diff.AddCount -gt 0) {
        foreach ($batch in @(Get-BatchGroup -Items $diff.Adds -BatchSize $AddBatchSize)) {
            $values = @($batch | ForEach-Object { $_.Value })
            try {
                $addResult = Add-TablManagedEntry -Values $values -Notes $notes
                $normalizedResult = @($addResult | Where-Object { $_.PSObject.Properties['HasFailures'] })
                $hasFailures = @($normalizedResult | Where-Object { $_.HasFailures }).Count -gt 0
                $successConfirmed = if ($normalizedResult.Count -eq 1 -and $normalizedResult[0].PSObject.Properties['IsSuccessConfirmed']) {
                    $normalizedResult[0].IsSuccessConfirmed
                }
                else {
                    -not $hasFailures
                }
                $response = if ($normalizedResult.Count -eq 1) { $normalizedResult[0].Response } else { $addResult }
                $rawResponse = if ($normalizedResult.Count -eq 1 -and $normalizedResult[0].PSObject.Properties['RawResponse']) {
                    $normalizedResult[0].RawResponse
                }
                else {
                    $addResult
                }
                $batchResults += [pscustomobject]@{
                    Operation    = 'Add'
                    Items        = $values
                    Status       = if ($hasFailures) { 'Partial' } elseif ($successConfirmed) { 'Succeeded' } else { 'Unverified' }
                    ErrorMessage = $null
                    RawResponse  = $rawResponse
                    Response     = $response
                }
            }
            catch {
                $batchResults += [pscustomobject]@{
                    Operation    = 'Add'
                    Items        = $values
                    Status       = 'Failed'
                    ErrorMessage = $_.Exception.Message
                    RawResponse  = $null
                    Response     = $null
                }
                Write-Verbose "TABL add batch failed, continuing with remaining batches: $($_.Exception.Message)"
            }
        }
    }

    if ($diff.RemoveCount -gt 0) {
        foreach ($batch in @(Get-BatchGroup -Items $diff.Removes -BatchSize $RemoveBatchSize)) {
            $identities = @($batch | ForEach-Object { $_.Identity })
            try {
                $removeResponse = Remove-TablManagedEntry -Identities $identities
                $batchResults += [pscustomobject]@{
                    Operation    = 'Remove'
                    Items        = $identities
                    Status       = 'Succeeded'
                    ErrorMessage = $null
                    RawResponse  = $removeResponse
                    Response     = $removeResponse
                }
            }
            catch {
                $batchResults += [pscustomobject]@{
                    Operation    = 'Remove'
                    Items        = $identities
                    Status       = 'Failed'
                    ErrorMessage = $_.Exception.Message
                    RawResponse  = $null
                    Response     = $null
                }
                Write-Verbose "TABL remove batch failed, continuing with remaining batches: $($_.Exception.Message)"
            }
        }
    }

    $failedBatchCount = @($batchResults | Where-Object { $_.Status -in @('Partial', 'Failed', 'Unverified') }).Count
    $status = if ($failedBatchCount -gt 0) { 'PartiallyReconciled' } else { 'Reconciled' }

    New-ReconcileResult -Target 'Tabl' -Status $status -Preflight $preflight `
        -AddCount $diff.AddCount -RemoveCount $diff.RemoveCount `
        -UnchangedCount $diff.UnchangedCount -UnmanagedMatchCount $diff.UnmanagedMatchCount `
        -FailedBatchCount $failedBatchCount -BatchResults $batchResults
}
