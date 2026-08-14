<#
.SYNOPSIS
Classify raw CNI entries into managed and unmanaged collision counts.

.DESCRIPTION
Normalizes the raw MDE Custom Network Indicator entries with Read-CniEntry and
builds the shared classification report, which summarizes how many are
PreventKit managed entries and how many are administrator-owned unmanaged
collisions. The destination is not read or written.

.OUTPUTS
System.Management.Automation.PSCustomObject with Entries, TotalCount,
ManagedCount and UnmanagedCollisionCount properties.
#>
function Get-CniReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Entries
    )

    Get-ClassificationReport -ClassifiedEntries @(Read-CniEntry -Entries $Entries)
}