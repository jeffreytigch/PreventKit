<#
.SYNOPSIS
Classify an enforcement destination entry as managed or an unmanaged collision.

.DESCRIPTION
Returns 'Managed' when the named provenance field of the entry carries the
provenance namespace, meaning PreventKit owns the entry. Returns
'UnmanagedCollision' otherwise, meaning the entry is administrator-owned and
must never be adopted or changed.

.OUTPUTS
System.String, 'Managed' or 'UnmanagedCollision'.
#>
function Get-EntryClassification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Entry,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Field
    )

    if (Test-EntryProvenance -Entry $Entry -Field $Field) {
        return 'Managed'
    }

    'UnmanagedCollision'
}
