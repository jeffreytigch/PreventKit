<#
.SYNOPSIS
Render a human-readable WhatIf run report from the desired state.

.DESCRIPTION
Produces a readable report listing the desired state as services and blockable
addresses, what invocation exceptions and global exceptions suppressed, and a
section per catalogue contribution showing what each enabled catalogue
declaration contributed, including the addresses that were covered by a
broader wildcard entry and the addresses that were skipped as unrepresentable.
Nothing is written to any enforcement target.

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
        $invocationSuppressed = @($suppressed | Where-Object { $_.ExceptionType -eq 'Invocation' })
        if ($invocationSuppressed.Count -gt 0) {
            $lines += ''
            $lines += 'Suppressed by invocation exceptions'
            $lines += '==================================='
            $lines += Format-ReportList -Title 'Services' -Items @($invocationSuppressed | Where-Object { $_.Kind -eq 'Service' }) `
                -Format { param($item) "  - $($item.Entry.Id) ($($item.Entry.Name))" }
            $lines += Format-ReportList -Title 'Blockable addresses' -Items @($invocationSuppressed | Where-Object { $_.Kind -eq 'BlockableAddress' }) `
                -Format { param($item) "  - $($item.Entry.Value) ($($item.Entry.Type)) <- $($item.Entry.ServiceId)" }
        }

        $globalSuppressed = @($suppressed | Where-Object { $_.ExceptionType -eq 'Global' })
        if ($globalSuppressed.Count -gt 0) {
            $lines += ''
            $lines += 'Suppressed by global exceptions'
            $lines += '==============================='
            $lines += Format-ReportList -Title 'Services' -Items @($globalSuppressed | Where-Object { $_.Kind -eq 'Service' }) `
                -Format { param($item) "  - $($item.Entry.Id) ($($item.Entry.Name))" }
            $lines += Format-ReportList -Title 'Blockable addresses' -Items @($globalSuppressed | Where-Object { $_.Kind -eq 'BlockableAddress' }) `
                -Format { param($item) "  - $($item.Entry.Value) ($($item.Entry.Type)) <- $($item.Entry.ServiceId)" }
        }
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

        $cUnrepresentable = @()
        $unrepresentableProperty = $contribution.PSObject.Properties['Unrepresentable']
        if ($null -ne $unrepresentableProperty -and $null -ne $unrepresentableProperty.Value) {
            $cUnrepresentable = @($unrepresentableProperty.Value)
        }
        $lines += Format-ReportList -Title 'Unrepresentable' -Items $cUnrepresentable -Indent 2 `
            -Format { param($entry) "  - $($entry.Value) ($($entry.Reason))" }

        $cCovered = @()
        $coveredProperty = $contribution.PSObject.Properties['Covered']
        if ($null -ne $coveredProperty -and $null -ne $coveredProperty.Value) {
            $cCovered = @($coveredProperty.Value)
        }
        $lines += Format-ReportList -Title 'Covered blockable addresses' -Items $cCovered -Indent 2 `
            -Format { param($entry) "  - $($entry.Value)" }

        $cniTable = Get-CniMappingTable -Snapshot $contribution
        if (@($cniTable.Mappings).Count -gt 0 -or @($cniTable.Unmappable).Count -gt 0) {
            $lines += '  CNI mappings:'
            foreach ($mapping in @($cniTable.Mappings)) {
                $broadenedFlag = if ($mapping.Broadened) { ' [broadened]' } else { '' }
                $lines += "    - $($mapping.Value) ($($mapping.IndicatorType))$broadenedFlag"
            }
            foreach ($unmappable in @($cniTable.Unmappable)) {
                $lines += "    - skipped: $($unmappable.Value) ($($unmappable.Reason))"
            }
            $lines += "  BroadeningCount: $($cniTable.BroadeningCount) | Unmappable: $(@($cniTable.Unmappable).Count)"
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