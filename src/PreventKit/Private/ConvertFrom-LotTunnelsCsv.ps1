<#
.SYNOPSIS
Source adapter that parses the lottunnels.github.io domains CSV into the
canonical Service and Blockable Address model.

.DESCRIPTION
The LOTTunnels domains catalogue is a CSV with domain and name columns. Each
row maps one blockable address to a named tunnelling service. Addresses that
cannot be represented as a URL, domain, or IP address are checked against the
catalogue's representable wildcard entries; covered addresses are recorded
without a warning, while genuinely unrepresentable addresses are logged and
skipped.

.OUTPUTS
System.Management.Automation.PSCustomObject with Services, BlockableAddresses,
Unrepresentable and Covered collections.
#>
function ConvertFrom-LotTunnelsCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Scope
    )

    $services = @{}
    $blockableAddresses = @()
    $unrepresentable = @()

    $rows = @($Content | ConvertFrom-Csv -ErrorAction Stop)
    foreach ($row in $rows) {
        $domain = ([string]$row.domain).Trim()
        $serviceName = ([string]$row.name).Trim()

        $type = Get-BlockableAddressType -Value $domain
        if (-not $type) {
            $unrepresentable += [pscustomobject]@{
                Value  = $domain
                Reason = "Not a representable URL, domain, or IP address"
            }
            continue
        }

        $serviceId = "$Scope/$serviceName"
        if (-not $services.ContainsKey($serviceId)) {
            $services[$serviceId] = [pscustomobject]@{
                Id    = $serviceId
                Scope = $Scope
                Name  = $serviceName
            }
        }

        $blockableAddresses += [pscustomobject]@{
            Value     = $domain
            Type      = $type
            ServiceId = $serviceId
        }
    }

    $covered = @(Get-CoveredBlockableAddress -RepresentableAddresses $blockableAddresses -Candidates $unrepresentable)
    $coveredValues = @($covered | ForEach-Object { [string]$_.Value })
    $unrepresentable = @($unrepresentable | Where-Object { [string]$_.Value -notin $coveredValues })

    foreach ($entry in $unrepresentable) {
        Write-Warning "Skipping unrepresentable blockable address: '$($entry.Value)'"
    }

    [pscustomobject]@{
        Services           = @($services.Values)
        BlockableAddresses = @($blockableAddresses)
        Unrepresentable    = @($unrepresentable)
        Covered            = @($covered)
    }
}
