<#
.SYNOPSIS
Build a classification report over Tenant Allow/Block List (TABL) URL block
entries.

.DESCRIPTION
Takes the raw TABL URL block entries that the caller supplies (as returned by
Get-TenantAllowBlockListItems -ListType URL -Block), normalizes and classifies
them with Read-TablBlockEntry, and builds the shared classification report of
managed entries and unmanaged collisions. A managed entry carries the PreventKit
provenance namespace in its Notes field; an unmanaged collision does not and is
administrator-owned. This function only reads and reports; it never writes to
any entry.

.PARAMETER Entries
Raw TABL URL block entry objects. Fields include Value, Identity, Notes,
ListType and Action.

.OUTPUTS
System.Management.Automation.PSCustomObject with Entries, TotalCount,
ManagedCount and UnmanagedCollisionCount properties.
#>
function Get-TablBlockReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Entries
    )

    Get-ClassificationReport -ClassifiedEntries @(Read-TablBlockEntry -Entries $Entries)
}