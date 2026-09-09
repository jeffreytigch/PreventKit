<#
.SYNOPSIS
Return the reason a blockable address has no CNI target mapping.

.DESCRIPTION
Provides the single source of truth for why an address is skipped by CNI
mapping: a wildcard domain when broadening is not
approved, or an address type with no CNI representation. Both the mapping
warning and the mapping table use this so the recorded reason never drifts
from the reason the skip was decided.

.OUTPUTS
System.String, the skip reason.
#>
function Get-CniSkipReason {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Value,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Type
    )

    if ($Type -eq 'Domain' -and $Value.StartsWith('*.', [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'Wildcard domain requires broadening approval'
    }

    "No CNI mapping for type '$Type'"
}