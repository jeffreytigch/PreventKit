<#
.SYNOPSIS
Source adapter that parses the lolrmm.io RMM domains CSV into the canonical
Service and Blockable Address model.

.DESCRIPTION
The lolrmm catalogue source is a CSV with URI and RMM_Tool columns. Each row
maps one blockable address (the URI) to a service (the tool). Raw values are
first passed through Get-NormalizedBlockableAddress, which recovers a
representable address from common publishing patterns; when the caller opts in
with RecoverDerivedWildcards it also recovers patterns that require deriving a
broader wildcard parent. Addresses that remain unrepresentable are checked
against the catalogue's own representable wildcard entries: an address a
wildcard entry already enforces is recorded as covered with no warning, while
genuinely unrepresentable addresses are logged and skipped. Every representable
address is carried together with the service identity it represents, and records
the raw source value whenever a recovery changed it.

.OUTPUTS
System.Management.Automation.PSCustomObject with Services, BlockableAddresses,
Unrepresentable and Covered collections.
#>
function ConvertFrom-LolRmmCsv {
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
        $sourceValue = ([string]$row.URI).Trim()
        $toolName = ([string]$row.RMM_Tool).Trim()

        $uri = Get-NormalizedBlockableAddress -Value $sourceValue -RecoverDerivedWildcards:$RecoverDerivedWildcards
        $type = Get-BlockableAddressType -Value $uri
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

        $serviceId = "$Scope/$toolName"
        if (-not $services.ContainsKey($serviceId)) {
            $services[$serviceId] = [pscustomobject]@{
                Id    = $serviceId
                Scope = $Scope
                Name  = $toolName
            }
        }

        $address = [ordered]@{
            Value     = $uri
            Type      = $type
            ServiceId = $serviceId
        }
        if ($uri -ne $sourceValue) {
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
