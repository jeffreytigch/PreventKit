<#
.SYNOPSIS
Classify an enforcement target entry as managed or an unmanaged match.

.DESCRIPTION
Returns 'Managed' when the named owner-marker field of the entry carries the
owner marker, meaning PreventKit owns the entry. Returns
'UnmanagedMatch' otherwise, meaning the entry is administrator-owned and
must never be adopted or changed.

.OUTPUTS
System.String, 'Managed' or 'UnmanagedMatch'.
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

    if (Test-OwnerMarker -Entry $Entry -Field $Field) {
        return 'Managed'
    }

    'UnmanagedMatch'
}
