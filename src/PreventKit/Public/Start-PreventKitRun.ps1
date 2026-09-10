<#
.SYNOPSIS
Run PreventKit for a scheduled invocation, returning a process exit code.

.DESCRIPTION
Wraps Invoke-PreventKitRun for unattended, scheduled execution. It invokes the
same Run engine as a manual Run and forwards every Run parameter. A Run that
completes without throwing returns exit code 0 with the engine's own run log
entry: status Completed, or status Partial when a target aborted (for
example a capacity preflight failure). A failing Run writes a run log entry
with status Failed and the error message, then returns exit code 1 so a
scheduler can observe the failure without a human present. When no LogDirectory
is supplied, a failing Run still returns a non-zero exit code.

.PARAMETER CatalogueDirectory
Path to the version-controlled directory of catalogue declarations
(files matching *.catalog.psd1).

.PARAMETER ExceptionKey
Invocation exception keys (e.g. 'service:lolrmm/AnyDesk', 'domain:anydesk.com').

.PARAMETER ExceptionDirectory
Path to the version-controlled directory of global exception declarations
(files matching *.exception.psd1).

.PARAMETER StateDirectory
Directory where last known good catalogue snapshots are persisted.

.PARAMETER LogDirectory
Directory where run log entries are written.

.PARAMETER Target
The enforcement targets this Run reconciles, chosen from 'Tabl' and 'Cni'.
When omitted, the Run engine's default (both destinations) applies.

.PARAMETER TablCapacity
Optional preflight-limit override for the Tenant Allow/Block List when TABL is
selected. Current entries are always read live from the tenant before
reconciliation. When omitted, the engine's plan default (1000) applies.

.PARAMETER CniCapacity
Optional preflight-limit override for Custom Network Indicators when CNI is
selected. Selecting CNI automatically acquires a token (using -CniToken when
supplied, otherwise from the signed-in Azure CLI session), verifies
authorization, and reads the current indicator state before reconciliation.
When omitted, the engine's plan default (15000) applies.

.PARAMETER CniToken
Optional access token for the MDE Custom Network Indicators API. When CNI is
selected and no token is supplied, one is acquired automatically from the
signed-in Azure CLI session. Supplying a token skips acquisition but
verification and the current-entry read still happen.

.EXAMPLE
Start-PreventKitRun -CatalogueDirectory .\catalogues -StateDirectory .\state -LogDirectory .\logs

.EXAMPLE
Start-PreventKitRun -CatalogueDirectory .\catalogues -LogDirectory .\logs; if ($LASTEXITCODE) { throw }

.EXAMPLE
Start-PreventKitRun -CatalogueDirectory .\catalogues -Target Tabl -TablCapacity 1000 -LogDirectory .\logs

.OUTPUTS
System.Int32, the process exit code: 0 on success, 1 on failure.
#>
function Start-PreventKitRun {
    [CmdletBinding()]
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
        [string]$CniToken
    )

    $globalExceptionKey = @()
    try {
        if (-not [string]::IsNullOrWhiteSpace($ExceptionDirectory)) {
            $globalExceptionKey = @(Get-GlobalExceptionKey -ExceptionDirectory $ExceptionDirectory -ErrorAction Stop)
        }
    }
    catch {
        Write-Warning "PreventKit Run failed: $($_.Exception.Message)"
        return 1
    }

    $script:preventKitRunLogEntryWritten = $false

    # Forward -Target and any capacity override only when the caller supplied
    # them; the Run engine owns the default destination selection and the
    # plan-default capacities.
    $runParameters = @{
        CatalogueDirectory = $CatalogueDirectory
        ExceptionKey       = $ExceptionKey
        ExceptionDirectory = $ExceptionDirectory
        StateDirectory     = $StateDirectory
        LogDirectory       = $LogDirectory
    }
    if ($PSBoundParameters.ContainsKey('Target')) { $runParameters.Target = $Target }
    if ($null -ne $TablCapacity) { $runParameters.TablCapacity = [int]$TablCapacity }
    if ($null -ne $CniCapacity) { $runParameters.CniCapacity = [int]$CniCapacity }
    if (-not [string]::IsNullOrWhiteSpace($CniToken)) { $runParameters.CniToken = $CniToken }

    try {
        $null = Invoke-PreventKitRun @runParameters -ErrorAction Stop

        return 0
    }
    catch {
        if (-not $script:preventKitRunLogEntryWritten -and -not [string]::IsNullOrWhiteSpace($LogDirectory)) {
            try {
                $null = Write-PreventKitRunLog -LogDirectory $LogDirectory `
                    -CatalogueDirectory $CatalogueDirectory `
                    -ExceptionKey $ExceptionKey -GlobalExceptionKey $globalExceptionKey `
                    -Snapshots @() -TargetOutcomes @() `
                    -Status 'Failed' -ErrorMessage $_.Exception.Message
            }
            catch {
                Write-Warning "Could not write the failed Run log entry: $($_.Exception.Message)"
            }
        }

        Write-Warning "PreventKit Run failed: $($_.Exception.Message)"
        return 1
    }
}