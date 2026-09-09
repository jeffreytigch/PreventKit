<#
.SYNOPSIS
Normalize and classify raw MDE Custom Network Indicator entries.

.DESCRIPTION
Takes the raw indicator objects returned by the Defender api/indicators
endpoint and normalizes each into a managed-entry record carrying the indicator
value, type, title, description, id and action, and classifies the entry as a
PreventKit managed entry or an administrator-owned unmanaged match from the
owner marker carried in its description field. One object is emitted per input
entry.

.OUTPUTS
System.Management.Automation.PSCustomObject, one per input entry.
#>
function Read-CniEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [object[]]$Entries
    )

    process {
        foreach ($entry in @($Entries)) {
            $indicatorValueProperty = $entry.PSObject.Properties['indicatorValue']
            $indicatorTypeProperty  = $entry.PSObject.Properties['indicatorType']
            $titleProperty          = $entry.PSObject.Properties['title']
            $descriptionProperty    = $entry.PSObject.Properties['description']
            $idProperty             = $entry.PSObject.Properties['id']
            $actionProperty         = $entry.PSObject.Properties['action']

            [pscustomobject]@{
                IndicatorValue = if ($indicatorValueProperty) { [string]$indicatorValueProperty.Value } else { $null }
                IndicatorType  = if ($indicatorTypeProperty) { [string]$indicatorTypeProperty.Value } else { $null }
                Title          = if ($titleProperty) { [string]$titleProperty.Value } else { $null }
                Description    = if ($descriptionProperty) { [string]$descriptionProperty.Value } else { $null }
                Id             = if ($idProperty) { [string]$idProperty.Value } else { $null }
                Action         = if ($actionProperty) { [string]$actionProperty.Value } else { $null }
                Classification = Get-EntryClassification -Entry $entry -Field 'Description'
            }
        }
    }
}