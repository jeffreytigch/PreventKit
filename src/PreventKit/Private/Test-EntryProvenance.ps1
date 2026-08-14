<#
.SYNOPSIS
Test whether a destination entry carries the PreventKit provenance namespace.

.DESCRIPTION
Returns $true when the named field of an enforcement destination entry contains
the provenance namespace, identifying the entry as a PreventKit managed entry.
A missing, empty, or non-matching field returns $false.

.OUTPUTS
System.Boolean.
#>
function Test-EntryProvenance {
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

    return $value.IndexOf((Get-ProvenanceNamespace), [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}
