<#
.SYNOPSIS
Compute the reconciliation diff between the desired entries and the current
destination entries.

.DESCRIPTION
Takes the desired entries (each carrying a Value) and the current destination
entries that the caller supplies (each carrying a value field and a
Classification of 'Managed' or 'UnmanagedCollision', as produced by the read
side) and computes what must be added, what must be removed, and what is
already in place. Managed entries that are no longer desired are removed; a
desired value that is already present, managed or unmanaged, is never added a
second time; unmanaged collisions are counted but never scheduled for removal.

.PARAMETER DesiredEntries
Desired entries. Each must expose a Value property.

.PARAMETER CurrentEntries
Current classified destination entries. Each must expose the value property
named by CurrentValueProperty and a Classification property.

.PARAMETER CurrentValueProperty
Name of the value property on the current entries (TABL: 'Value', CNI:
'IndicatorValue').

.OUTPUTS
System.Management.Automation.PSCustomObject with Adds, Removes, Unchanged,
AddCount, RemoveCount, UnchangedCount and UnmanagedCollisionCount properties.
#>
function Get-ReconcileDiff {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$DesiredEntries,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$CurrentEntries,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$CurrentValueProperty
    )

    $desiredValues = @($DesiredEntries | ForEach-Object {
        $prop = $_.PSObject.Properties['Value']
        if ($prop) { [string]$prop.Value } else { [string]::Empty }
    })

    $currentNormalized = @($CurrentEntries | ForEach-Object {
        $valueProp          = $_.PSObject.Properties[$CurrentValueProperty]
        $classificationProp = $_.PSObject.Properties['Classification']
        [pscustomobject]@{
            Entry          = $_
            Value          = if ($valueProp) { [string]$valueProp.Value } else { [string]::Empty }
            Classification = if ($classificationProp) { [string]$classificationProp.Value } else { 'UnmanagedCollision' }
        }
    })

    $currentValues = @($currentNormalized | ForEach-Object { $_.Value })
    $managed       = @($currentNormalized | Where-Object { $_.Classification -eq 'Managed' })
    $unmanaged     = @($currentNormalized | Where-Object { $_.Classification -ne 'Managed' })

    $adds      = @($DesiredEntries | Where-Object { $currentValues -notcontains $_.Value })
    $removes   = @($managed    | Where-Object { $desiredValues -notcontains $_.Value } | ForEach-Object { $_.Entry })
    $unchanged = @($managed    | Where-Object { $desiredValues -contains $_.Value }   | ForEach-Object { $_.Entry })

    [pscustomobject]@{
        Adds                    = @($adds)
        Removes                 = @($removes)
        Unchanged               = @($unchanged)
        AddCount                = @($adds).Count
        RemoveCount             = @($removes).Count
        UnchangedCount          = @($unchanged).Count
        UnmanagedCollisionCount = @($unmanaged).Count
    }
}
