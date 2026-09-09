<#
.SYNOPSIS
Produce the CNI target mapping table for a catalogue snapshot.

.DESCRIPTION
For every blockable address of a catalogue snapshot, computes its target
mapping for the Custom Network Indicators enforcement target. The table
carries the declaration scope, whether broadening was
approved, every mapping with its broadening explicitly flagged, a count of
broadenings, and the addresses with no safe mapping together with the reason
each was skipped. Broadening approval is read from the snapshot's
TargetSettings.Cni.AllowBroadening and defaults to not approved when absent.

.OUTPUTS
System.Management.Automation.PSCustomObject with Scope, AllowBroadening,
Mappings, BroadeningCount and Unmappable properties.
#>
function Get-CniMappingTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Snapshot
    )

    $allowBroadening = $false
    $targetSettings = $null
    $settingsProperty = $Snapshot.PSObject.Properties['TargetSettings']
    if ($settingsProperty) {
        $targetSettings = $settingsProperty.Value
    }

    $cniSettings = $null
    if ($targetSettings -is [hashtable]) {
        if ($targetSettings.ContainsKey('Cni')) {
            $cniSettings = $targetSettings['Cni']
        }
    }
    elseif ($null -ne $targetSettings) {
        $cniProperty = $targetSettings.PSObject.Properties['Cni']
        if ($cniProperty) {
            $cniSettings = $cniProperty.Value
        }
    }

    if ($cniSettings -is [hashtable]) {
        if ($cniSettings.ContainsKey('AllowBroadening')) {
            $allowBroadening = [bool]$cniSettings['AllowBroadening']
        }
    }
    elseif ($null -ne $cniSettings) {
        $approvalProperty = $cniSettings.PSObject.Properties['AllowBroadening']
        if ($approvalProperty) {
            $allowBroadening = [bool]$approvalProperty.Value
        }
    }

    $mappings = @()
    $unmappable = @()

    foreach ($address in @($Snapshot.BlockableAddresses)) {
        $mapping = Get-CniMapping -Address $address -AllowBroadening:$allowBroadening
        if ($null -eq $mapping) {
            $value = [string]$address.Value
            $type = [string]$address.Type
            $unmappable += [pscustomobject]@{
                Value  = $value
                Reason = Get-CniSkipReason -Value $value -Type $type
            }
        }
        else {
            $mappings += $mapping
        }
    }

    $broadeningCount = @($mappings | Where-Object { $_.Broadened }).Count

    [pscustomobject]@{
        Scope            = [string]$Snapshot.Scope
        AllowBroadening  = $allowBroadening
        Mappings         = @($mappings)
        BroadeningCount  = $broadeningCount
        Unmappable       = @($unmappable)
    }
}