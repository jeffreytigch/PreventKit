<#
.SYNOPSIS
Aggregate classified destination entries into a managed/unmanaged collision report.

.DESCRIPTION
Takes entries already normalized and classified by a destination read function
(each carrying a Classification of 'Managed' or 'UnmanagedCollision') and
returns the shared report shape: the entries plus counts of managed entries and
unmanaged collisions. This is the single report builder for every enforcement
destination read, so the count and aggregate logic never drifts between
destinations.

.OUTPUTS
System.Management.Automation.PSCustomObject with Entries, TotalCount,
ManagedCount and UnmanagedCollisionCount properties.
#>
function Get-ClassificationReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$ClassifiedEntries
    )

    $entries = @($ClassifiedEntries)
    $managedCount = @($entries | Where-Object { $_.Classification -eq 'Managed' }).Count
    $unmanagedCount = @($entries | Where-Object { $_.Classification -eq 'UnmanagedCollision' }).Count

    [pscustomobject]@{
        Entries                 = $entries
        TotalCount              = $entries.Count
        ManagedCount            = $managedCount
        UnmanagedCollisionCount = $unmanagedCount
    }
}