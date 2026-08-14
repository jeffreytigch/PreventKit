<#
.SYNOPSIS
Return the reason a blockable address has no CNI destination projection.

.DESCRIPTION
Provides the single source of truth for why an address is skipped by CNI
projection: a wildcard domain when controlled destination expansion is not
approved, or an address type with no CNI representation. Both the projection
warning and the projection table use this so the recorded reason never drifts
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
        return 'Wildcard domain requires expansion approval'
    }

    "No CNI projection for type '$Type'"
}