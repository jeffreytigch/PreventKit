<#
.SYNOPSIS
Assemble a catalogue snapshot from a retrieved source, its parsed model, and
its validation result.

.DESCRIPTION
Combines the retrieved source, the canonical model produced by the source
adapter, and the validation result into a single snapshot object carrying the
source fingerprint (source location, retrieval time, SHA-256 content hash, and
parsed counts).

.OUTPUTS
System.Management.Automation.PSCustomObject.
#>
function New-CatalogueSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Scope,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Source,

        [Parameter(Mandatory)]
        [hashtable]$Declaration,

        [Parameter(Mandatory)]
        [pscustomobject]$SourceData,

        [Parameter(Mandatory)]
        [pscustomobject]$Parsed,

        [Parameter(Mandatory)]
        [pscustomobject]$Validation
    )

    $parsedCounts = @{
        Services           = @($Parsed.Services).Count
        BlockableAddresses = @($Parsed.BlockableAddresses).Count
        Unrepresentable    = @($Parsed.Unrepresentable).Count
        Covered            = @($Parsed.Covered).Count
    }

    $fingerprint = [pscustomobject]@{
        SourceLocation    = $SourceData.SourceLocation
        RetrievedAt       = $SourceData.RetrievedAt
        ContentHash       = $SourceData.ContentHash
        ParsedCounts      = $parsedCounts
        UsedLastKnownGood = $false
        FailureReason     = if ($Validation.Status -eq 'Failure') {
            "Catalogue validation failed for source '$($SourceData.SourceLocation)'."
        }
        else {
            $null
        }
    }

    $targetSettings = @{}
    if ($Declaration.ContainsKey('Targets')) {
        $targetSettings = $Declaration.Targets
    }

    [pscustomobject]@{
        CatalogueName       = $Declaration.Name
        Scope               = $Scope
        Source              = $Source
        Fingerprint         = $fingerprint
        Services            = @($Parsed.Services)
        BlockableAddresses  = @($Parsed.BlockableAddresses)
        Unrepresentable     = @($Parsed.Unrepresentable)
        Covered             = @($Parsed.Covered)
        Validation          = $Validation
        TargetSettings      = $targetSettings
    }
}