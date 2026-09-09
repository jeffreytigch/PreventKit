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
ExceptionKey are managed-only: matched services and blockable addresses drop
out of the desired state.

When target capacities are supplied (TablCapacity / CniCapacity), the Run
also reconciles those enforcement targets to the desired state and records
the reconciliation outcomes. When LogDirectory is supplied, each Run writes a
durable run log entry capturing source fingerprints, exceptions applied, and
per-target outcomes.

With -WhatIf the run computes the desired state (after exceptions) and prints a
readable WhatIf run report showing the desired state, what was suppressed, and
each catalogue contribution, still without modifying any enforcement
target.

.PARAMETER CatalogueDirectory
Path to the version-controlled directory of catalogue declarations
(files matching *.catalog.psd1).

.PARAMETER ExceptionKey
Invocation exception keys (e.g. 'service:lolrmm/AnyDesk', 'domain:anydesk.com').
Managed-only: matched entries leave the desired state and are not enforced.

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
using TablCurrentEntries as the current entries. When -TablAuto is specified,
this parameter is ignored and the default P1 capacity (5000) is used.

.PARAMETER CniCapacity
When supplied, reconcile Custom Network Indicators to the desired state using
CniCurrentEntries as the current entries. When -CniAuto is specified, this
parameter is ignored and the default capacity (15000) is used.

.PARAMETER CniToken
The access token for the MDE Custom Network Indicators API, supplied by the
caller. Required when CniCapacity is supplied so reconciliation never sends an
unauthenticated request. Any acquisition method works (interactive, client
certificate, or managed identity). Ignored when -CniAuto is specified.

.PARAMETER TablCurrentEntries
Raw current TABL URL block entries (as returned by the read side). Ignored
when -TablAuto is specified.

.PARAMETER CniCurrentEntries
Raw current CNI indicators (as returned by the read side). Ignored when
-CniAuto is specified.

.PARAMETER TablAuto
When specified, automatically configure the TABL target: use the default
Defender for Office 365 Plan 1 capacity (5000), verify an active Exchange
Online session, and read current URL block entries from the tenant. No manual
TablCapacity or TablCurrentEntries required.

.PARAMETER CniAuto
When specified, automatically configure the CNI target: acquire the
Defender token from the signed-in Azure CLI session, verify the caller can
read and write CNI, and read the current indicator state from the MDE API.
No manual CniToken or CniCurrentEntries required.

.PARAMETER TablCapacityP1
When specified with -TablCapacity (without -TablAuto), use the Defender for
Office 365 Plan 1 default capacity (5000) instead of the supplied value.

.PARAMETER TargetOutcome
Output variable to receive per-target configuration and reconciliation
outcomes. Each entry contains Target, ConfigurationMode, Status, and
details about what was selected, validated, reconciled, skipped, or unavailable.

.EXAMPLE
Invoke-PreventKitRun -CatalogueDirectory .\catalogues -StateDirectory .\state -LogDirectory .\logs

.EXAMPLE
Invoke-PreventKitRun -CatalogueDirectory .\catalogues -ExceptionKey 'service:lolrmm/AnyDesk' -WhatIf

.EXAMPLE
Invoke-PreventKitRun -CatalogueDirectory .\tests\fixtures\clean

.EXAMPLE
Invoke-PreventKitRun -CatalogueDirectory .\catalogues -TablAuto -CniAuto -LogDirectory .\logs

.EXAMPLE
Invoke-PreventKitRun -CatalogueDirectory .\catalogues -TablCapacity 5000 -TablCapacityP1 -LogDirectory .\logs

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
        [string]$ExceptionDirectory = "./exceptions",

        [Parameter()]
        [string]$StateDirectory = "./state",

        [Parameter()]
        [string]$LogDirectory = "./logs",

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
        [object[]]$CniCurrentEntries = @(),

        [Parameter()]
        [switch]$TablAuto,

        [Parameter()]
        [switch]$CniAuto,

        [Parameter()]
        [switch]$TablCapacityP1,

        [Parameter()]
        [Alias('TargetOutcome')]
        [string]$TargetOutcomeVariable
    )

    $startedAt = [datetime]::UtcNow
    $runId = [guid]::NewGuid()

    $script:preventKitRunLogEntryWritten = $false

    $globalExceptionKey   = @()
    $snapshots            = @()
    $targetOutcomes  = @()
    $targetConfigurations = @()

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
                        -Snapshots $snapshots -TargetOutcomes @()
                }
                finally {
                    $WhatIfPreference = $previousWhatIfPreference
                }
            }
            return
        }

        # Resolve TABL configuration
        $tablConfig = $null
        if ($TablAuto) {
            $tablConfig = Get-AutoTablConfiguration
            $targetConfigurations += @{
                Target         = 'Tabl'
                ConfigurationMode   = 'Auto'
                Capacity            = $tablConfig.Capacity
                Status              = 'Selected'
                ValidationStatus    = 'Validated'
                SelectionReason     = 'Default P1 capacity with auto-detected Exchange Online session'
            }
        }
        elseif ($TablCapacity -ge 0) {
            $effectiveCapacity = if ($TablCapacityP1) { 5000 } else { $TablCapacity }
            $tablConfig = [pscustomobject]@{
                Capacity         = $effectiveCapacity
                CurrentEntries   = $TablCurrentEntries
                SessionVerified  = $false
                ConfigurationMode = 'Manual'
            }
            $targetConfigurations += @{
                Target         = 'Tabl'
                ConfigurationMode   = 'Manual'
                Capacity            = $effectiveCapacity
                Status              = 'Selected'
                ValidationStatus    = 'Pending'
                SelectionReason     = if ($TablCapacityP1) { 'Manual capacity with P1 default' } else { 'Manual capacity' }
            }
        }
        else {
            $targetConfigurations += @{
                Target         = 'Tabl'
                ConfigurationMode   = 'None'
                Capacity            = $null
                Status              = 'Skipped'
                ValidationStatus    = 'NotConfigured'
                SelectionReason     = 'No TABL capacity specified'
            }
        }

        # Resolve CNI configuration
        $cniConfig = $null
        if ($CniAuto) {
            $cniConfig = Get-AutoCniConfiguration
            $targetConfigurations += @{
                Target         = 'Cni'
                ConfigurationMode   = 'Auto'
                Capacity            = $cniConfig.Capacity
                Status              = 'Selected'
                ValidationStatus    = 'Validated'
                SelectionReason     = 'Auto-configured via Azure CLI token'
            }
        }
        elseif ($CniCapacity -ge 0) {
            if ([string]::IsNullOrWhiteSpace($CniToken)) {
                throw 'A CNI Run requires a token: supply -CniToken with an MDE Custom Network Indicators API access token, or use -CniAuto to acquire it automatically.'
            }
            $cniConfig = [pscustomobject]@{
                Token                  = $CniToken
                Capacity               = $CniCapacity
                CurrentEntries         = $CniCurrentEntries
                AuthorizationVerified  = $false
                ConfigurationMode      = 'Manual'
            }
            $targetConfigurations += @{
                Target         = 'Cni'
                ConfigurationMode   = 'Manual'
                Capacity            = $CniCapacity
                Status              = 'Selected'
                ValidationStatus    = 'Pending'
                SelectionReason     = 'Manual token and capacity'
            }
        }
        else {
            $targetConfigurations += @{
                Target         = 'Cni'
                ConfigurationMode   = 'None'
                Capacity            = $null
                Status              = 'Skipped'
                ValidationStatus    = 'NotConfigured'
                SelectionReason     = 'No CNI capacity specified'
            }
        }

        # Execute TABL reconciliation if configured
        if ($tablConfig -and $tablConfig.ConfigurationMode -ne 'None') {
            $currentEntries = $tablConfig.CurrentEntries
            $capacity = $tablConfig.Capacity

            $result = Invoke-TablReconciliation -DesiredEntries @($desiredState.BlockableAddresses) `
                -CurrentEntries $currentEntries -Capacity $capacity

            # Update target configuration with reconciliation outcome
            $config = $targetConfigurations | Where-Object { $_.Target -eq 'Tabl' }
            if ($config) {
                $preflightPassed = if ($result.PSObject.Properties['Preflight']) { $result.Preflight.Passed } else { $true }
                $config.ValidationStatus = if ($preflightPassed) { 'Validated' } else { 'PreflightFailed' }
                $config.ReconciliationStatus = if ($result.PSObject.Properties['Status']) { $result.Status } else { 'Unknown' }
                $config.AddCount = if ($result.PSObject.Properties['AddCount']) { $result.AddCount } else { $null }
                $config.RemoveCount = if ($result.PSObject.Properties['RemoveCount']) { $result.RemoveCount } else { $null }
                $config.UnchangedCount = if ($result.PSObject.Properties['UnchangedCount']) { $result.UnchangedCount } else { $null }
                $config.UnmanagedMatchCount = if ($result.PSObject.Properties['UnmanagedMatchCount']) { $result.UnmanagedMatchCount } else { $null }
            }

            $targetOutcomes += $result
        }

        # Execute CNI reconciliation if configured
        if ($cniConfig -and $cniConfig.ConfigurationMode -ne 'None') {
            $currentEntries = $cniConfig.CurrentEntries
            $capacity = $cniConfig.Capacity
            $token = $cniConfig.Token

            $cniMappings = Get-CniDesiredMappings -DesiredState $desiredState
            $result = Invoke-CniReconciliation -DesiredEntries $cniMappings `
                -CurrentEntries $currentEntries -Capacity $capacity -Token $token

            # Update target configuration with reconciliation outcome
            $config = $targetConfigurations | Where-Object { $_.Target -eq 'Cni' }
            if ($config) {
                $preflightPassed = if ($result.PSObject.Properties['Preflight']) { $result.Preflight.Passed } else { $true }
                $config.ValidationStatus = if ($preflightPassed) { 'Validated' } else { 'PreflightFailed' }
                $config.ReconciliationStatus = if ($result.PSObject.Properties['Status']) { $result.Status } else { 'Unknown' }
                $config.AddCount = if ($result.PSObject.Properties['AddCount']) { $result.AddCount } else { $null }
                $config.RemoveCount = if ($result.PSObject.Properties['RemoveCount']) { $result.RemoveCount } else { $null }
                $config.UnchangedCount = if ($result.PSObject.Properties['UnchangedCount']) { $result.UnchangedCount } else { $null }
                $config.UnmanagedMatchCount = if ($result.PSObject.Properties['UnmanagedMatchCount']) { $result.UnmanagedMatchCount } else { $null }
            }

            $targetOutcomes += $result
        }

        # Output target configurations if variable requested
        if ($PSBoundParameters.ContainsKey('TargetOutcomeVariable')) {
            Set-Variable -Name $TargetOutcomeVariable -Value $targetConfigurations -Scope 1 -Force
        }

        if (-not [string]::IsNullOrWhiteSpace($LogDirectory)) {
            $null = Write-PreventKitRunLog -LogDirectory $LogDirectory -RunId $runId -StartedAt $startedAt `
                -CatalogueDirectory $CatalogueDirectory -ExceptionKey $ExceptionKey `
                -GlobalExceptionKey $globalExceptionKey `
                -Snapshots $snapshots -TargetOutcomes $targetOutcomes `
                -TargetConfigurations $targetConfigurations
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
                    -Snapshots $snapshots -TargetOutcomes $targetOutcomes `
                    -TargetConfigurations $targetConfigurations `
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