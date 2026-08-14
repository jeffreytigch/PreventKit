<#
.SYNOPSIS
Produce the CNI destination projection table for a catalogue snapshot.

.DESCRIPTION
For every blockable address of a catalogue snapshot, computes its destination
projection for the Custom Network Indicators enforcement destination. The table
carries the declaration scope, whether controlled destination expansion was
approved, every projection with its expansion explicitly flagged, a count of
expansions, and the addresses with no safe projection together with the reason
each was skipped. Expansion approval is read from the snapshot's
DestinationSettings.Cni.AllowExpansion and defaults to not approved when absent.

.OUTPUTS
System.Management.Automation.PSCustomObject with Scope, AllowExpansion,
Projections, ExpansionCount and Unprojectable properties.
#>
function Get-CniProjectionTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Snapshot
    )

    $allowExpansion = $false
    $destinationSettings = $null
    $settingsProperty = $Snapshot.PSObject.Properties['DestinationSettings']
    if ($settingsProperty) {
        $destinationSettings = $settingsProperty.Value
    }

    $cniSettings = $null
    if ($destinationSettings -is [hashtable]) {
        if ($destinationSettings.ContainsKey('Cni')) {
            $cniSettings = $destinationSettings['Cni']
        }
    }
    elseif ($null -ne $destinationSettings) {
        $cniProperty = $destinationSettings.PSObject.Properties['Cni']
        if ($cniProperty) {
            $cniSettings = $cniProperty.Value
        }
    }

    if ($cniSettings -is [hashtable]) {
        if ($cniSettings.ContainsKey('AllowExpansion')) {
            $allowExpansion = [bool]$cniSettings['AllowExpansion']
        }
    }
    elseif ($null -ne $cniSettings) {
        $approvalProperty = $cniSettings.PSObject.Properties['AllowExpansion']
        if ($approvalProperty) {
            $allowExpansion = [bool]$approvalProperty.Value
        }
    }

    $projections = @()
    $unprojectable = @()

    foreach ($address in @($Snapshot.BlockableAddresses)) {
        $projection = Get-CniProjection -Address $address -AllowExpansion:$allowExpansion
        if ($null -eq $projection) {
            $value = [string]$address.Value
            $type = [string]$address.Type
            $unprojectable += [pscustomobject]@{
                Value  = $value
                Reason = Get-CniSkipReason -Value $value -Type $type
            }
        }
        else {
            $projections += $projection
        }
    }

    $expansionCount = @($projections | Where-Object { $_.Expanded }).Count

    [pscustomobject]@{
        Scope          = [string]$Snapshot.Scope
        AllowExpansion = $allowExpansion
        Projections    = @($projections)
        ExpansionCount = $expansionCount
        Unprojectable  = @($unprojectable)
    }
}