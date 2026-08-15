<#
.SYNOPSIS
Run PreventKit for a scheduled invocation, returning a process exit code.

.DESCRIPTION
Wraps Invoke-PreventKitRun for unattended, scheduled execution. It invokes the
same Run engine as a manual Run and forwards every Run parameter. A Run that
completes without throwing returns exit code 0 with the engine's own run log
entry: status Completed, or status Partial when a destination aborted (for
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

.PARAMETER CniCapacity
When supplied, reconcile Custom Network Indicators to the desired state.

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
Start-PreventKitRun -CatalogueDirectory .\catalogues -StateDirectory .\state -LogDirectory .\logs

.EXAMPLE
Start-PreventKitRun -CatalogueDirectory .\catalogues -LogDirectory .\logs; if ($LASTEXITCODE) { throw }

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
        [AllowEmptyCollection()]
        [object[]]$TablCurrentEntries = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$CniCurrentEntries = @()
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
            -TablCurrentEntries $TablCurrentEntries -CniCurrentEntries $CniCurrentEntries `
            -ErrorAction Stop

        return 0
    }
    catch {
        if (-not $script:preventKitRunLogEntryWritten -and -not [string]::IsNullOrWhiteSpace($LogDirectory)) {
            try {
                $null = Write-PreventKitRunLog -LogDirectory $LogDirectory `
                    -CatalogueDirectory $CatalogueDirectory `
                    -ExceptionKey $ExceptionKey -GlobalExceptionKey $globalExceptionKey `
                    -Snapshots @() -DestinationOutcomes @() `
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