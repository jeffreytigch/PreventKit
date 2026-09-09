<#
.SYNOPSIS
Add URL block entries to the Tenant Allow/Block List as permanent managed
entries carrying the owner marker.

.DESCRIPTION
Thin seam over New-TenantAllowBlockListItems. Adds the given values as
permanent (no-expiration) URL block entries with the owner marker in
their Notes, so the read side can later classify them as PreventKit managed
entries. This is the only TABL write path used by reconciliation; it is kept
deliberately thin so the reconcile logic can be tested by mocking this seam.

.PARAMETER Values
The URL values to block.

.PARAMETER Notes
Owner marker note to stamp on each entry.
#>
function Add-TablManagedEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Values,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Notes
    )

    New-TenantAllowBlockListItems -ListType Url -Block -Entries $Values -Notes $Notes -NoExpiration
}