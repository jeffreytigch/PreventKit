<#
.SYNOPSIS
Test whether a target entry carries the PreventKit owner marker.

.DESCRIPTION
Returns $true when the named field of an enforcement target entry contains
the owner marker, identifying the entry as a PreventKit managed entry.
A missing, empty, or non-matching field returns $false.

.OUTPUTS
System.Boolean.
#>
function Test-OwnerMarker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Entry,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Field
    )

    $property = $Entry.PSObject.Properties[$Field]
    if (-not $property) {
        return $false
    }

    $value = [string]$property.Value
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $false
    }

    return $value.IndexOf($script:ownerMarker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}
