<#
.SYNOPSIS
Aggregate classified target entries into a managed/unmanaged match report.

.DESCRIPTION
Takes entries already normalized and classified by a target read function
(each carrying a Classification of 'Managed' or 'UnmanagedMatch') and
returns the shared report shape: the entries plus counts of managed entries and
unmanaged matches. This is the single report builder for every enforcement
target read, so the count and aggregate logic never drifts between
targets.

.OUTPUTS
System.Management.Automation.PSCustomObject with Entries, TotalCount,
ManagedCount and UnmanagedMatchCount properties.
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
    $unmanagedCount = @($entries | Where-Object { $_.Classification -eq 'UnmanagedMatch' }).Count

    [pscustomobject]@{
        Entries               = $entries
        TotalCount            = $entries.Count
        ManagedCount          = $managedCount
        UnmanagedMatchCount   = $unmanagedCount
    }
}