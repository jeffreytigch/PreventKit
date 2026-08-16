<#
.SYNOPSIS
Source adapter that parses the lolrmm.io RMM domains CSV into the canonical
Service and Blockable Address model.

.DESCRIPTION
The lolrmm catalogue source is a CSV with URI and RMM_Tool columns. Each row
maps one blockable address (the URI) to a service (the tool). Addresses that
are not a representable URL, domain, or IP address are checked against the
catalogue's own representable wildcard entries: an address a wildcard entry
already enforces is recorded as subsumed with no warning, while genuinely
unrepresentable addresses are logged and skipped. Every representable address
is carried verbatim together with the service identity it represents.

.OUTPUTS
System.Management.Automation.PSCustomObject with Services, BlockableAddresses,
Unrepresentable and Subsumed collections.
#>
function ConvertFrom-LolRmmCsv {
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
        $uri = ([string]$row.URI).Trim()
        $toolName = ([string]$row.RMM_Tool).Trim()

        $type = Get-BlockableAddressType -Value $uri
        if (-not $type) {
            $unrepresentable += [pscustomobject]@{
                Value  = $uri
                Reason = "Not a representable URL, domain, or IP address"
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

        $blockableAddresses += [pscustomobject]@{
            Value     = $uri
            Type      = $type
            ServiceId = $serviceId
        }
    }

    $subsumed = @(Get-SubsumedBlockableAddress -RepresentableAddresses $blockableAddresses -Candidates $unrepresentable)
    $subsumedValues = @($subsumed | ForEach-Object { [string]$_.Value })
    $unrepresentable = @($unrepresentable | Where-Object { [string]$_.Value -notin $subsumedValues })

    foreach ($entry in $unrepresentable) {
        Write-Warning "Skipping unrepresentable blockable address: '$($entry.Value)'"
    }

    [pscustomobject]@{
        Services           = @($services.Values)
        BlockableAddresses = @($blockableAddresses)
        Unrepresentable    = @($unrepresentable)
        Subsumed           = @($subsumed)
    }
}
