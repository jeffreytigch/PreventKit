<#
.SYNOPSIS
Build a catalogue snapshot that records a failed retrieval.

.DESCRIPTION
Produces a snapshot with no entries, a Failure validation status, and a
fingerprint flagging the retrieval failure. A Run emits this when a catalogue
source cannot be retrieved and no last known good snapshot exists, so the run
still completes and the report can show why.

.OUTPUTS
System.Management.Automation.PSCustomObject.
#>
function New-FailedCatalogueSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Declaration,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Source,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ResolvedSource,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FailureReason
    )

    $destinationSettings = @{}
    if ($Declaration.ContainsKey('Destinations')) {
        $destinationSettings = $Declaration.Destinations
    }

    [pscustomobject]@{
        CatalogueName      = $Declaration.Name
        Scope              = $Declaration.Scope
        Source             = $Source
        Fingerprint        = [pscustomobject]@{
            SourceLocation    = $ResolvedSource
            RetrievedAt       = [datetime]::UtcNow
            ContentHash       = $null
            ParsedCounts      = [pscustomobject]@{
                Services           = 0
                BlockableAddresses = 0
                Unrepresentable    = 0
                Subsumed           = 0
            }
            UsedLastKnownGood = $false
            FailureReason     = $FailureReason
        }
        Services           = @()
        BlockableAddresses = @()
        Unrepresentable    = @()
        Subsumed           = @()
        Validation         = [pscustomobject]@{
            Status = 'Failure'
            Checks = @(
                [pscustomobject]@{
                    Name   = 'SourceRetrievalSucceeded'
                    Passed = $false
                    Detail = $FailureReason
                }
            )
        }
        DestinationSettings = $destinationSettings
    }
}