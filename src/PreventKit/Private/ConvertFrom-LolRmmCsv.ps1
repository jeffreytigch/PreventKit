<#
.SYNOPSIS
Source adapter that parses the lolrmm.io RMM domains CSV into the canonical
Service and Blockable Address model.

.DESCRIPTION
The lolrmm catalogue source is a CSV with URI and RMM_Tool columns. Each row
maps one blockable address (the URI) to a service (the tool). Addresses that
are not a representable URL, domain, or IP address are logged as
unrepresentable and skipped. Every representable address is carried verbatim
together with the service identity it represents.

.OUTPUTS
System.Management.Automation.PSCustomObject with Services, BlockableAddresses
and Unrepresentable collections.
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
            Write-Warning "Skipping unrepresentable blockable address: '$uri'"
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

    [pscustomobject]@{
        Services           = @($services.Values)
        BlockableAddresses = @($blockableAddresses)
        Unrepresentable    = @($unrepresentable)
    }
}