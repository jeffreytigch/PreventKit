<#
.SYNOPSIS
Run PreventKit over a catalogue directory, producing a snapshot per enabled
catalogue declaration.

.DESCRIPTION
The Run: for each enabled catalogue declaration in the catalogue directory,
retrieve the catalogue source, parse it with the declared source adapter into
the canonical Service / Blockable Address model, validate the result, and
produce a catalogue snapshot carrying a source fingerprint. Snapshots that pass
validation are persisted as last known good snapshots under StateDirectory; on
retrieval or validation failure the Run falls back to them (or records the
failure) and still completes. Invocation exceptions supplied through
ExceptionKey are non-overriding: matched services and blockable addresses drop
out of the desired state.

When destination capacities are supplied (TablCapacity / CniCapacity), the Run
also reconciles those enforcement destinations to the desired state and records
the reconciliation outcomes. When LogDirectory is supplied, each Run writes a
durable run log entry capturing source fingerprints, exceptions applied, and
per-destination outcomes.

With -WhatIf the run computes the desired state (after exceptions) and prints a
readable WhatIf run report showing the desired state, what was suppressed, and
each catalogue contribution, still without modifying any enforcement
destination.

.PARAMETER CatalogueDirectory
Path to the version-controlled directory of catalogue declarations
(files matching *.catalog.psd1).

.PARAMETER ExceptionKey
Invocation exception keys (e.g. 'service:lolrmm/AnyDesk', 'domain:anydesk.com').
Non-overriding: matched entries leave the desired state and are not enforced.

.PARAMETER ExceptionDirectory
Path to the version-controlled directory of global exception declarations
(files matching *.exception.psd1). Every enabled declaration contributes its
exception keys to every Run.

.PARAMETER StateDirectory
Directory where last known good catalogue snapshots are persisted.

.PARAMETER LogDirectory
Directory where run log entries are written.

.PARAMETER TablCapacity
When supplied, reconcile the Tenant Allow/Block List to the desired state
using TablCurrentEntries as the current entries.

.PARAMETER CniCapacity
When supplied, reconcile Custom Network Indicators to the desired state using
CniCurrentEntries as the current entries.

.PARAMETER CniToken
The access token for the MDE Custom Network Indicators API, supplied by the
caller. Required when CniCapacity is supplied so reconciliation never sends an
unauthenticated request. Any acquisition method works (interactive, client
certificate, or managed identity).

.PARAMETER TablCurrentEntries
Raw current TABL URL block entries (as returned by the read side).

.PARAMETER CniCurrentEntries
Raw current CNI indicators (as returned by the read side).

.EXAMPLE
Invoke-PreventKitRun -CatalogueDirectory .\catalogues -StateDirectory .\state -LogDirectory .\logs

.EXAMPLE
Invoke-PreventKitRun -CatalogueDirectory .\catalogues -ExceptionKey 'service:lolrmm/AnyDesk' -WhatIf

.EXAMPLE
Invoke-PreventKitRun -CatalogueDirectory .\tests\fixtures\clean

.OUTPUTS
System.Management.Automation.PSCustomObject, one per enabled catalogue
declaration in the catalogue directory. With -WhatIf, System.String report
lines instead.
#>
function Invoke-PreventKitRun {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$CatalogueDirectory,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$ExceptionKey = @(),

        [Parameter()]
        [string]$ExceptionDirectory,

        [Parameter()]
        [string]$StateDirectory,

        [Parameter()]
        [string]$LogDirectory,

        [Parameter()]
        [ValidateRange(-1, [int]::MaxValue)]
        [int]$TablCapacity = -1,

        [Parameter()]
        [ValidateRange(-1, [int]::MaxValue)]
        [int]$CniCapacity = -1,

        [Parameter()]
        [string]$CniToken,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$TablCurrentEntries = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$CniCurrentEntries = @()
    )

    $startedAt = [datetime]::UtcNow
    $runId = [guid]::NewGuid()

    $script:preventKitRunLogEntryWritten = $false

    $globalExceptionKey   = @()
    $snapshots            = @()
    $destinationOutcomes  = @()

    try {
        foreach ($key in @($ExceptionKey)) {
            if (-not [string]::IsNullOrWhiteSpace($key) -and $key -notlike 'service:*' -and $key -notlike 'domain:*') {
                Write-Warning "Ignoring exception key '$key': expected 'service:<serviceId>' or 'domain:<value>'."
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($ExceptionDirectory)) {
            $globalExceptionKey = @(Get-GlobalExceptionKey -ExceptionDirectory $ExceptionDirectory)
        }

        $declarationFiles = @(Get-ChildItem -Path $CatalogueDirectory -Filter '*.catalog.psd1' -File -ErrorAction Stop)

        foreach ($declarationFile in $declarationFiles) {
            $declaration = Import-PowerShellDataFile -LiteralPath $declarationFile.FullName

            if (-not $declaration.Enabled) {
                Write-Verbose "Skipping disabled catalogue declaration: $($declaration.Name)"
                continue
            }

            $snapshots += Get-RunCatalogueSnapshot -DeclarationFile $declarationFile.FullName `
                -Declaration $declaration -StateDirectory $StateDirectory
        }

        $desiredState = Get-DesiredState -Snapshot $snapshots -ExceptionKey $ExceptionKey -GlobalExceptionKey $globalExceptionKey

        if ($WhatIfPreference) {
            New-WhatIfReport -DesiredState $desiredState

            if (-not [string]::IsNullOrWhiteSpace($LogDirectory)) {
                $previousWhatIfPreference = $WhatIfPreference
                $WhatIfPreference = $false
                try {
                    $null = Write-PreventKitRunLog -LogDirectory $LogDirectory -RunId $runId -StartedAt $startedAt `
                        -CatalogueDirectory $CatalogueDirectory -ExceptionKey $ExceptionKey `
                        -GlobalExceptionKey $globalExceptionKey `
                        -Snapshots $snapshots -DestinationOutcomes @()
                }
                finally {
                    $WhatIfPreference = $previousWhatIfPreference
                }
            }
            return
        }

        if ($TablCapacity -ge 0) {
            $destinationOutcomes += Invoke-TablReconciliation -DesiredEntries @($desiredState.BlockableAddresses) `
                -CurrentEntries $TablCurrentEntries -Capacity $TablCapacity
        }

        if ($CniCapacity -ge 0) {
            if ([string]::IsNullOrWhiteSpace($CniToken)) {
                throw 'A CNI Run requires a token: supply -CniToken with an MDE Custom Network Indicators API access token.'
            }
            $cniProjections = Get-CniDesiredProjections -DesiredState $desiredState
            $destinationOutcomes += Invoke-CniReconciliation -DesiredEntries $cniProjections `
                -CurrentEntries $CniCurrentEntries -Capacity $CniCapacity -Token $CniToken
        }

        if (-not [string]::IsNullOrWhiteSpace($LogDirectory)) {
            $null = Write-PreventKitRunLog -LogDirectory $LogDirectory -RunId $runId -StartedAt $startedAt `
                -CatalogueDirectory $CatalogueDirectory -ExceptionKey $ExceptionKey `
                -GlobalExceptionKey $globalExceptionKey `
                -Snapshots $snapshots -DestinationOutcomes $destinationOutcomes
            $script:preventKitRunLogEntryWritten = $true
        }

        $snapshots
    }
    catch {
        if (-not [string]::IsNullOrWhiteSpace($LogDirectory)) {
            try {
                $null = Write-PreventKitRunLog -LogDirectory $LogDirectory -RunId $runId -StartedAt $startedAt `
                    -CatalogueDirectory $CatalogueDirectory -ExceptionKey $ExceptionKey `
                    -GlobalExceptionKey $globalExceptionKey `
                    -Snapshots $snapshots -DestinationOutcomes $destinationOutcomes `
                    -Status 'Failed' -ErrorMessage $_.Exception.Message
                $script:preventKitRunLogEntryWritten = $true
            }
            catch {
                Write-Warning "Could not write the failed Run log entry: $($_.Exception.Message)"
            }
        }
        throw
    }
}