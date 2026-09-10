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

By default the Run reconciles both enforcement targets, TABL and CNI, to the
desired state using the plan-default capacities (TABL 1000, CNI 15000). The
Target parameter selects which destinations are reconciled; TablCapacity and
CniCapacity are preflight-limit overrides for a selected destination only.
When LogDirectory is supplied, each Run writes a durable run log entry
capturing source fingerprints, exceptions applied, per-target outcomes, and
each destination's configuration (unselected destinations are recorded as
skipped with a 'Not selected' reason).

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

.PARAMETER Target
The enforcement targets this Run reconciles, chosen from 'Tabl' and 'Cni'.
Defaults to both. A Run always reconciles at least one destination; an empty
selection is rejected.

.PARAMETER TablCapacity
Optional preflight-limit override for the Tenant Allow/Block List when TABL is
selected; defaults to the plan limit of 1000. Current entries are always read
live from the tenant via Get-TenantAllowBlockListItems -ListType Url -Block
before reconciliation; a failed read surfaces a Failed run before any write.
Supplying this while TABL is not selected is an error.

.PARAMETER CniCapacity
Optional preflight-limit override for Custom Network Indicators when CNI is
selected; defaults to the plan limit of 15000. Selecting CNI automatically
acquires a token (using -CniToken when supplied, otherwise from the signed-in
Azure CLI session), verifies the caller can read and write CNI, and reads the
current indicator state before reconciliation; a missing token or failed read
surfaces a Failed run before any request. Supplying this while CNI is not
selected is an error.

.PARAMETER CniToken
Optional access token for the MDE Custom Network Indicators API. When CNI is
selected and no token is supplied, one is acquired automatically from the
signed-in Azure CLI session. Supplying a token skips acquisition but
verification and the current-entry read still happen. Any acquisition method
works (interactive, client certificate, or managed identity).

.PARAMETER TargetOutcome
Output variable to receive per-target configuration and reconciliation
outcomes. Each entry contains Target, ConfigurationMode, Status, and
details about what was selected, validated, reconciled, skipped, or unavailable.

.EXAMPLE
Invoke-PreventKitRun -CatalogueDirectory .\catalogues -StateDirectory .\state -LogDirectory .\logs

.EXAMPLE
Invoke-PreventKitRun -CatalogueDirectory .\catalogues -Target Tabl -TablCapacity 1000 -LogDirectory .\logs

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
        [string]$ExceptionDirectory = "./exceptions",

        [Parameter()]
        [string]$StateDirectory = "./state",

        [Parameter()]
        [string]$LogDirectory = "./logs",

        [Parameter()]
        [ValidateSet('Tabl', 'Cni')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Target = @('Tabl', 'Cni'),

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [Nullable[int]]$TablCapacity,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [Nullable[int]]$CniCapacity,

        [Parameter()]
        [string]$CniToken,

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

    $planDefaultTablCapacity = 1000
    $planDefaultCniCapacity  = 15000

    try {
        $selectedTargets = @($Target | Select-Object -Unique)
        if ($selectedTargets.Count -eq 0) {
            throw 'At least one enforcement target must be selected with -Target.'
        }

        $tablSelected = $selectedTargets -contains 'Tabl'
        $cniSelected  = $selectedTargets -contains 'Cni'

        if (-not $tablSelected -and $null -ne $TablCapacity) {
            throw "A TABL capacity was supplied but TABL is not selected. Add 'Tabl' to -Target or omit -TablCapacity."
        }
        if (-not $cniSelected -and $null -ne $CniCapacity) {
            throw "A CNI capacity was supplied but CNI is not selected. Add 'Cni' to -Target or omit -CniCapacity."
        }

        $effectiveTablCapacity = if ($null -ne $TablCapacity) { [int]$TablCapacity } else { $planDefaultTablCapacity }
        $effectiveCniCapacity  = if ($null -ne $CniCapacity) { [int]$CniCapacity } else { $planDefaultCniCapacity }

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

        # Resolve TABL configuration: TABL always reads live state before
        # diffing; a failed read throws before any write.
        $tablConfig = $null
        if ($tablSelected) {
            $liveConfig = Get-AutoTablConfiguration -Capacity $effectiveTablCapacity
            $tablConfig = [pscustomobject]@{
                Capacity          = $liveConfig.Capacity
                CurrentEntries    = $liveConfig.CurrentEntries
                SessionVerified   = $true
                ConfigurationMode = 'Auto'
            }
            $targetConfigurations += @{
                Target              = 'Tabl'
                ConfigurationMode   = 'Auto'
                Capacity            = $effectiveTablCapacity
                Status              = 'Selected'
                ValidationStatus    = 'Pending'
                SelectionReason     = if ($null -ne $TablCapacity) { 'TABL selected with a caller-supplied capacity override' } else { 'TABL selected with the plan-default capacity' }
            }
        }
        else {
            $targetConfigurations += @{
                Target              = 'Tabl'
                ConfigurationMode   = 'None'
                Capacity            = $null
                Status              = 'Skipped'
                ValidationStatus    = 'NotConfigured'
                SelectionReason     = 'Not selected'
            }
        }

        # Resolve CNI configuration: selecting CNI automatically acquires a token
        # (caller-supplied -CniToken as override, otherwise from Azure CLI),
        # verifies authorization, and reads the current indicator state.
        $cniConfig = $null
        if ($cniSelected) {
            $cniConfig = Get-AutoCniConfiguration -Capacity $effectiveCniCapacity -Token $CniToken
            $targetConfigurations += @{
                Target              = 'Cni'
                ConfigurationMode   = 'Auto'
                Capacity            = $cniConfig.Capacity
                Status              = 'Selected'
                ValidationStatus    = 'Validated'
                SelectionReason     = if ($null -ne $CniCapacity -and -not [string]::IsNullOrWhiteSpace($CniToken)) { 'CNI selected with caller-supplied capacity and token overrides' } elseif ($null -ne $CniCapacity) { 'CNI selected with a caller-supplied capacity override' } elseif (-not [string]::IsNullOrWhiteSpace($CniToken)) { 'CNI selected with a caller-supplied token override' } else { 'CNI selected with plan defaults; token acquired automatically' }
            }
        }
        else {
            $targetConfigurations += @{
                Target              = 'Cni'
                ConfigurationMode   = 'None'
                Capacity            = $null
                Status              = 'Skipped'
                ValidationStatus    = 'NotConfigured'
                SelectionReason     = 'Not selected'
            }
        }

        # Execute TABL reconciliation if configured
        if ($tablConfig -and $tablConfig.ConfigurationMode -ne 'None') {
            $currentEntries = @($tablConfig.CurrentEntries)
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
                $config.FailedBatchCount = if ($result.PSObject.Properties['FailedBatchCount']) { $result.FailedBatchCount } else { $null }
            }

            $targetOutcomes += $result
        }

        # Execute CNI reconciliation if configured
        if ($cniConfig -and $cniConfig.ConfigurationMode -ne 'None') {
            $currentEntries = @($cniConfig.CurrentEntries)
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
