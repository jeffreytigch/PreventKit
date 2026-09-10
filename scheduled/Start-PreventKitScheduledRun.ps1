<#
.SYNOPSIS
Run a scheduled PreventKit Run from Windows Task Scheduler (or any scheduler),
returning a process exit code a scheduler can observe.

.DESCRIPTION
A thin, unattended entry point for PreventKit: it imports the module, invokes
the same Run engine a manual Run uses (Start-PreventKitRun -> Invoke-PreventKitRun),
writes the Run outcome to the run log, and exits with 0 on success or 1 on
failure so a scheduler can detect a failing Run without a human present.

The catalogue directory, state directory, log directory, optional global
exception directory, and target capacities are supplied as parameters;
defaults point at the standard directories of a repository checkout.

Registering with Windows Task Scheduler:

    $action  = New-ScheduledTaskAction -Execute 'pwsh.exe' `
        -Argument '-NoProfile -File "C:\PreventKit\scheduled\Start-PreventKitScheduledRun.ps1"'
    $trigger = New-ScheduledTaskTrigger -Daily -At '06:00'
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable
    Register-ScheduledTask -TaskName 'PreventKit scheduled Run' `
        -Action $action -Trigger $trigger -Settings $settings -RunLevel Limited

.INPUTS
None.

.OUTPUTS
None. The process exit code is 0 on success and 1 on failure.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$CatalogueDirectory = (Join-Path $PSScriptRoot '..' 'catalogues'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$StateDirectory = (Join-Path $PSScriptRoot '..' 'state'),

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = (Join-Path $PSScriptRoot '..' 'logs'),

    [Parameter()]
    [string]$ExceptionDirectory,

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

$modulePath = Join-Path $PSScriptRoot '..' 'src' 'PreventKit' 'PreventKit.psd1'

try {
    Import-Module $modulePath -Force -ErrorAction Stop
}
catch {
    Write-Error "Could not import the PreventKit module at '$modulePath': $($_.Exception.Message)"
    exit 1
}

$runParameters = @{
    CatalogueDirectory = $CatalogueDirectory
    StateDirectory     = $StateDirectory
    LogDirectory       = $LogDirectory
}

if ($PSBoundParameters.ContainsKey('Target')) {
    $runParameters.Target = $Target
}

if ($null -ne $TablCapacity) {
    $runParameters.TablCapacity = [int]$TablCapacity
}

if ($null -ne $CniCapacity) {
    $runParameters.CniCapacity = [int]$CniCapacity
}

if (-not [string]::IsNullOrWhiteSpace($CniToken)) {
    $runParameters.CniToken = $CniToken
}

if (-not [string]::IsNullOrWhiteSpace($ExceptionDirectory)) {
    $runParameters.ExceptionDirectory = $ExceptionDirectory
}

$exitCode = Start-PreventKitRun @runParameters
exit $exitCode