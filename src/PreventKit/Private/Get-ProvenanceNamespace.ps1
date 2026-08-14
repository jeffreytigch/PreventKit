<#
.SYNOPSIS
Return the provenance namespace PreventKit reserves at enforcement destinations.

.DESCRIPTION
The provenance namespace is the recognisable identifier PreventKit writes into
managed entries at enforcement destinations so it can find and reconcile them
without local persistent state. An entry that carries this namespace in its
provenance field is a PreventKit managed entry; one that does not is an
administrator-owned entry.

.OUTPUTS
System.String, the provenance namespace.
#>
function Get-ProvenanceNamespace {
    [CmdletBinding()]
    param()

    'PreventKit'
}
