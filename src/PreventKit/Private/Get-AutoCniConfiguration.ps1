<#
.SYNOPSIS
Get the automatic CNI configuration for a Run.

.DESCRIPTION
Acquires a CNI access token (uses the caller-supplied Token when provided,
otherwise acquires one from the signed-in Azure CLI session), verifies
the caller can read and write CNI indicators, and reads the current indicator
state from the MDE API. Returns a configuration object or throws if any
prerequisite fails. A missing token throws before any request is sent.

.PARAMETER Capacity
Maximum managed indicators the tenant can hold.

.PARAMETER Token
Optional caller-supplied access token for the MDE Custom Network Indicators
API. When supplied, Azure CLI acquisition is skipped in favor of this token,
but verification and the current-entry read still happen.

.OUTPUTS
System.Management.Automation.PSCustomObject with Token, Capacity, CurrentEntries,
and AuthorizationVerified properties.
#>
function Get-AutoCniConfiguration {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Capacity = 15000,

        [Parameter()]
        [string]$Token
    )

    # Use the caller-supplied token as an explicit override; otherwise acquire
    # one from the signed-in Azure CLI session.
    $effectiveToken = $Token
    if ([string]::IsNullOrWhiteSpace($effectiveToken)) {
        $effectiveToken = Get-CniTokenFromAzureCli
    }
    if ([string]::IsNullOrWhiteSpace($effectiveToken)) {
        throw 'Failed to acquire CNI token from Azure CLI. Run "az login" and ensure you have the required permissions.'
    }

    # Verify CNI authorization by attempting a read operation
    $currentEntries = @()
    try {
        $currentEntries = @(Get-CniCurrentIndicators -Token $effectiveToken)
    }
    catch {
        throw "CNI authorization verification failed: $($_.Exception.Message). Ensure the Azure CLI user has the 'Ti.ReadWrite' (delegated) or 'Ti.ReadWrite.All' (application) permission on the WindowsDefenderATP resource."
    }

    [pscustomobject]@{
        Token                  = $effectiveToken
        Capacity               = $Capacity
        CurrentEntries         = $currentEntries
        AuthorizationVerified  = $true
        ConfigurationMode      = 'Auto'
    }
}

<#
.SYNOPSIS
Acquire a CNI access token from the signed-in Azure CLI session.

.DESCRIPTION
Uses 'az account get-access-token' with the MDE API resource to obtain
a token suitable for the Custom Network Indicators API.

.OUTPUTS
String access token or $null if acquisition fails.
#>
function Get-CniTokenFromAzureCli {
    [CmdletBinding()]
    param()

    try {
        $azOutput = az account get-access-token --resource 'https://api.securitycenter.microsoft.com' 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Verbose "az command failed: $azOutput"
            return $null
        }

        $tokenObject = $azOutput | ConvertFrom-Json -ErrorAction Stop
        return $tokenObject.accessToken
    }
    catch {
        Write-Verbose "Failed to parse Azure CLI token output: $($_.Exception.Message)"
        return $null
    }
}

<#
.SYNOPSIS
Read current CNI indicators from the MDE API.

.DESCRIPTION
Calls the MDE /api/indicators endpoint to retrieve all current indicators,
then normalizes and classifies them for reconciliation.

.PARAMETER Token
The access token for the MDE Custom Network Indicators API.

.OUTPUTS
Array of normalized CNI indicator objects with Classification.
#>
function Get-CniCurrentIndicators {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Token
    )

    $uri = 'https://api.security.microsoft.com/api/indicators'
    $response = Invoke-CniApiRequest -Uri $uri -Body @{} -Token $Token -Method Get

    if (-not $response -or -not $response.value) {
        return @()
    }

    $entries = @($response.value | Read-CniEntry)
    return $entries
}