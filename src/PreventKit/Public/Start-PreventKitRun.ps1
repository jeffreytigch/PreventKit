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

.PARAMETER TablCapacity
When supplied, reconcile the Tenant Allow/Block List to the desired state.
Current entries are always read live from the tenant before reconciliation.
When -TablAuto is specified, this parameter is ignored and the default P1
capacity (5000) is used.

.PARAMETER CniCapacity
When supplied, reconcile Custom Network Indicators to the desired state.
Selecting CNI automatically acquires a token (using -CniToken when supplied,
otherwise from the signed-in Azure CLI session), verifies authorization, and
reads the current indicator state before reconciliation.

.PARAMETER CniToken
Optional access token for the MDE Custom Network Indicators API. When CNI is
selected and no token is supplied, one is acquired automatically from the
signed-in Azure CLI session. Supplying a token skips acquisition but
verification and the current-entry read still happen.

.PARAMETER TablAuto
When specified, automatically configure the TABL target: use the default
Defender for Office 365 Plan 1 capacity (5000), verify an active Exchange
Online session, and read current URL block entries from the tenant. No manual
TablCapacity required.

.PARAMETER TablCapacityP1
When specified with -TablCapacity (without -TablAuto), use the Defender for
Office 365 Plan 1 default capacity (5000) instead of the supplied value.

.EXAMPLE
Start-PreventKitRun -CatalogueDirectory .\catalogues -StateDirectory .\state -LogDirectory .\logs

.EXAMPLE
Start-PreventKitRun -CatalogueDirectory .\catalogues -LogDirectory .\logs; if ($LASTEXITCODE) { throw }

.EXAMPLE
Start-PreventKitRun -CatalogueDirectory .\catalogues -TablAuto -LogDirectory .\logs

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
        [ValidateRange(-1, [int]::MaxValue)]
        [int]$TablCapacity = -1,

        [Parameter()]
        [ValidateRange(-1, [int]::MaxValue)]
        [int]$CniCapacity = -1,

        [Parameter()]
        [string]$CniToken,

        [Parameter()]
        [switch]$TablAuto,

        [Parameter()]
        [switch]$TablCapacityP1
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

    try {
        $null = Invoke-PreventKitRun -CatalogueDirectory $CatalogueDirectory `
            -ExceptionKey $ExceptionKey -ExceptionDirectory $ExceptionDirectory `
            -StateDirectory $StateDirectory -LogDirectory $LogDirectory `
            -TablCapacity $TablCapacity -CniCapacity $CniCapacity `
            -CniToken $CniToken `
            -TablAuto:$TablAuto -TablCapacityP1:$TablCapacityP1 `
            -ErrorAction Stop

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