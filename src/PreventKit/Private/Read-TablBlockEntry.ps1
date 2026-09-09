<#
.SYNOPSIS
Read and classify Tenant Allow/Block List (TABL) URL block entries.

.DESCRIPTION
Takes the raw TABL URL block entries that the caller supplies (as returned by
Get-TenantAllowBlockListItems -ListType URL -Block) and emits one normalized
entry object per input entry. Each normalized entry carries the blocked Value,
Identity, Notes and a Classification computed from the Notes field, where the
TABL owner marker lives. This is the read side of TABL reconciliation:
it never writes to, adopts, or changes any entry.

.PARAMETER Entries
Raw TABL URL block entry objects. Fields include Value, Identity, Notes,
ListType and Action.

.OUTPUTS
System.Management.Automation.PSCustomObject with Value, Identity, Notes and
Classification properties.
#>
function Read-TablBlockEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [object[]]$Entries
    )

    process {
        foreach ($entry in $Entries) {
            $valueProperty    = $entry.PSObject.Properties['Value']
            $identityProperty = $entry.PSObject.Properties['Identity']
            $notesProperty    = $entry.PSObject.Properties['Notes']

            [pscustomobject]@{
                Value          = if ($valueProperty) { [string]$valueProperty.Value } else { $null }
                Identity       = if ($identityProperty) { [string]$identityProperty.Value } else { $null }
                Notes          = if ($notesProperty) { [string]$notesProperty.Value } else { $null }
                Classification = Get-EntryClassification -Entry $entry -Field 'Notes'
            }
        }
    }
}