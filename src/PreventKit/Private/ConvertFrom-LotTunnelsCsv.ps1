<#
.SYNOPSIS
Source adapter that parses the lottunnels.github.io domains CSV into the
canonical Service and Blockable Address model.

.DESCRIPTION
The LOTTunnels domains catalogue is a CSV with domain and name columns. Each
row maps one blockable address to a named tunnelling service. Raw values are
first passed through Get-NormalizedBlockableAddress, which recovers a
representable address from common publishing patterns; when the caller opts in
with RecoverDerivedWildcards it also recovers patterns that require deriving a
broader wildcard parent. Addresses that remain unrepresentable are checked
against the catalogue's representable wildcard entries; covered addresses are
recorded without a warning, while genuinely unrepresentable addresses are
logged and skipped. Every representable address records the raw source value
whenever a recovery changed it.

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
        [string]$Scope,

        [Parameter()]
        [switch]$RecoverDerivedWildcards
    )

    $services = @{}
    $blockableAddresses = @()
    $unrepresentable = @()

    $rows = @($Content | ConvertFrom-Csv -ErrorAction Stop)
    foreach ($row in $rows) {
        $sourceValue = ([string]$row.domain).Trim()
        $serviceName = ([string]$row.name).Trim()

        $domain = Get-NormalizedBlockableAddress -Value $sourceValue -RecoverDerivedWildcards:$RecoverDerivedWildcards
        $type = Get-BlockableAddressType -Value $domain
        if (-not $type) {
            $reason = 'Not a representable URL, domain, or IP address'
            if (-not $RecoverDerivedWildcards) {
                $derived = Get-NormalizedBlockableAddress -Value $sourceValue -RecoverDerivedWildcards
                if (Get-BlockableAddressType -Value $derived) {
                    $reason = "Recoverable as '$derived' with Normalization.RecoverDerivedWildcards"
                }
            }
            $unrepresentable += [pscustomobject]@{
                Value  = $sourceValue
                Reason = $reason
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

        $address = [ordered]@{
            Value     = $domain
            Type      = $type
            ServiceId = $serviceId
        }
        if ($domain -ne $sourceValue) {
            $address['NormalizedFrom'] = $sourceValue
        }
        $blockableAddresses += [pscustomobject]$address
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
