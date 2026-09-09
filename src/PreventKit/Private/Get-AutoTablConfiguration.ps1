<#
.SYNOPSIS
Get the automatic TABL configuration for a Run.

.DESCRIPTION
Determines the TABL capacity, verifies an active Exchange Online session,
and reads the current URL block entries from the tenant. Returns a configuration
object or throws if prerequisites are not met.

.OUTPUTS
System.Management.Automation.PSCustomObject with Capacity, CurrentEntries, and
SessionVerified properties.
#>
function Get-AutoTablConfiguration {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Capacity = 5000
    )

    # Verify Exchange Online session is connected
    $session = Get-ExchangeOnlineSession -ErrorAction SilentlyContinue
    if (-not $session) {
        throw 'No active Exchange Online session. Run Connect-ExchangeOnline before invoking a TABL Run.'
    }

    # Read current TABL URL block entries
    $currentEntries = @()
    try {
        $tablItems = @(Get-TenantAllowBlockListItems -ListType Url -Block -ErrorAction Stop)
        if ($tablItems.Count -gt 0) {
            $currentEntries = @($tablItems | Read-TablBlockEntry)
        }
    }
    catch {
        throw "Failed to read current TABL entries: $($_.Exception.Message)"
    }

    [pscustomobject]@{
        Capacity         = $Capacity
        CurrentEntries   = $currentEntries
        SessionVerified  = $true
        ConfigurationMode = 'Auto'
    }
}

<#
.SYNOPSIS
Check if an Exchange Online session is active and has the required cmdlets.

.DESCRIPTION
Verifies that Connect-ExchangeOnline has been run and the required
TenantAllowBlockList cmdlets are available in the session.

.OUTPUTS
Boolean - $true if session is valid, $false otherwise.
#>
function Test-ExchangeOnlineSession {
    [CmdletBinding()]
    param()

    try {
        $session = Get-ExchangeOnlineSession -ErrorAction Stop
        if (-not $session) { return $false }

        # Check required cmdlets are available
        $requiredCmdlets = @('Get-TenantAllowBlockListItems', 'New-TenantAllowBlockListItems', 'Remove-TenantAllowBlockListItems')
        foreach ($cmdlet in $requiredCmdlets) {
            if (-not (Get-Command -Name $cmdlet -ErrorAction SilentlyContinue)) {
                Write-Verbose "Required cmdlet '$cmdlet' not available in session"
                return $false
            }
        }
        return $true
    }
    catch {
        return $false
    }
}

<#
.SYNOPSIS
Get the current Exchange Online session object.

.DESCRIPTION
Retrieves the active Exchange Online session from the runspace. Used
to verify connectivity before a TABL Run.

.OUTPUTS
The Exchange Online session object or $null if not connected.
#>
function Get-ExchangeOnlineSession {
    [CmdletBinding()]
    param()

    # Exchange Online stores its session in a runspace variable
    if ($global:ExchangeOnlineSession) {
        return $global:ExchangeOnlineSession
    }

    # Fallback: check if the module is loaded and connected
    if (Get-Module -Name ExchangeOnlineManagement -ErrorAction SilentlyContinue) {
        try {
            $session = Get-ConnectionInformation -ErrorAction SilentlyContinue
            if ($session -and $session.IsConnected) {
                return $session
            }
        }
        catch {
            # Not connected
        }
    }

    return $null
}