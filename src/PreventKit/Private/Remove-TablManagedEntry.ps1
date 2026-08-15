<#
.SYNOPSIS
Remove managed URL block entries from the Tenant Allow/Block List.

.DESCRIPTION
Thin seam over Remove-TenantAllowBlockListItems. Removes the entries with the
given identities. Callers are expected to pass only identities of managed
entries (never unmanaged collisions).

.PARAMETER Identities
The identities of the TABL entries to remove.
#>
function Remove-TablManagedEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Identities
    )

    Remove-TenantAllowBlockListItems -ListType Url -Ids $Identities
}