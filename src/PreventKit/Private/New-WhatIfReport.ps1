<#
.SYNOPSIS
Render a human-readable WhatIf run report from the desired state.

.DESCRIPTION
Produces a readable report listing the desired state as services and blockable
addresses, what invocation exceptions suppressed, and a section per catalogue
contribution showing what each enabled catalogue declaration contributed.
Nothing is written to any enforcement destination.

.OUTPUTS
System.String, one line per report line.
#>
function New-WhatIfReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$DesiredState
    )

    $lines = @()

    $lines += 'PreventKit WhatIf run'
    $lines += '====================='
    $lines += ''

    $lines += 'Desired state'
    $lines += '============='
    $lines += Format-ReportList -Title 'Services' -Items $DesiredState.Services `
        -Format { param($service) "  - $($service.Id) ($($service.Name))" }
    $lines += ''
    $lines += Format-ReportList -Title 'Blockable addresses' -Items $DesiredState.BlockableAddresses `
        -Format { param($address) "  - $($address.Value) ($($address.Type)) <- $($address.ServiceId)" }

    $suppressed = @()
    $suppressedProperty = $DesiredState.PSObject.Properties['Suppressed']
    if ($null -ne $suppressedProperty -and $null -ne $suppressedProperty.Value) {
        $suppressed = @($suppressedProperty.Value)
    }

    if ($suppressed.Count -gt 0) {
        $lines += ''
        $lines += 'Suppressed by invocation exceptions'
        $lines += '==================================='
        $lines += Format-ReportList -Title 'Services' -Items @($suppressed | Where-Object { $_.Kind -eq 'Service' }) `
            -Format { param($item) "  - $($item.Entry.Id) ($($item.Entry.Name))" }
        $lines += Format-ReportList -Title 'Blockable addresses' -Items @($suppressed | Where-Object { $_.Kind -eq 'BlockableAddress' }) `
            -Format { param($item) "  - $($item.Entry.Value) ($($item.Entry.Type)) <- $($item.Entry.ServiceId)" }
    }

    $lines += ''
    $lines += 'Catalogue contributions'
    $lines += '======================='

    foreach ($contribution in @($DesiredState.Contributions)) {
        $cServices = @($contribution.Services)
        $cAddresses = @($contribution.BlockableAddresses)
        $lines += "[$($contribution.CatalogueName)] (scope: $($contribution.Scope))"
        $lines += "  Source: $($contribution.Fingerprint.SourceLocation)"
        $lines += "  Validation: $($contribution.Validation.Status)"
        if ($contribution.Fingerprint.UsedLastKnownGood) {
            $lines += "  Last known good fallback: $($contribution.Fingerprint.FailureReason)"
        }
        $lines += Format-ReportList -Title 'Services' -Items $cServices -Indent 2 `
            -Format { param($service) "  - $($service.Id) ($($service.Name))" }
        $lines += Format-ReportList -Title 'Blockable addresses' -Items $cAddresses -Indent 2 `
            -Format { param($address) "  - $($address.Value) ($($address.Type))" }

        $cniTable = Get-CniProjectionTable -Snapshot $contribution
        if (@($cniTable.Projections).Count -gt 0 -or @($cniTable.Unprojectable).Count -gt 0) {
            $lines += '  CNI projections:'
            foreach ($projection in @($cniTable.Projections)) {
                $expansionFlag = if ($projection.Expanded) { ' [expansion]' } else { '' }
                $lines += "    - $($projection.Value) ($($projection.IndicatorType))$expansionFlag"
            }
            foreach ($unprojectable in @($cniTable.Unprojectable)) {
                $lines += "    - skipped: $($unprojectable.Value) ($($unprojectable.Reason))"
            }
            $lines += "  ExpansionCount: $($cniTable.ExpansionCount) | Unprojectable: $(@($cniTable.Unprojectable).Count)"
        }

        $lines += ''
    }

    $lines
}

<#
.SYNOPSIS
Format a titled list of report items as report lines.

.DESCRIPTION
Emits a "Title (count):" header and one line per item rendered by the Format
script block, optionally indented.

.OUTPUTS
System.String, one line per report line.
#>
function Format-ReportList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Items,

        [Parameter(Mandatory)]
        [scriptblock]$Format,

        [Parameter()]
        [int]$Indent = 0
    )

    $pad = ' ' * $Indent
    $lines = @()
    $lines += "$pad$Title ($(@($Items).Count)):"
    foreach ($item in @($Items)) {
        $lines += "$pad$(& $Format $item)"
    }
    $lines
}