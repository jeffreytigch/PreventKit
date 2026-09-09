<#
.SYNOPSIS
Map a blockable address to its MDE Custom Network Indicator representation.

.DESCRIPTION
Computes the target mapping of a blockable address for the Custom
Network Indicators enforcement target. A mapping is produced only when
it is exact or an explicitly approved broadening. Bare domains map as
non-broadened DomainName indicators; wildcard domains map as the broadened root
domain only when broadening is approved; URLs and IP addresses map unchanged.
Addresses with no safe mapping are skipped and logged with a warning.

.OUTPUTS
System.Management.Automation.PSCustomObject when a safe mapping exists,
otherwise nothing.
#>
function Get-CniMapping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Address,

        [Parameter()]
        [switch]$AllowBroadening
    )

    $value = [string]$Address.Value
    $type = [string]$Address.Type
    $serviceId = [string]$Address.ServiceId
    $isWildcard = $value.StartsWith('*.', [System.StringComparison]::OrdinalIgnoreCase)

    switch ($type) {
        'Domain' {
            if ($isWildcard) {
                if ($AllowBroadening.IsPresent) {
                    [pscustomobject]@{
                        Value         = $value.Substring(2)
                        SourceValue   = $value
                        IndicatorType = 'DomainName'
                        Broadened     = $true
                        ServiceId     = $serviceId
                    }
                }
                else {
                    Write-Warning "Skipping unmappable blockable address for CNI: '$value' ($(Get-CniSkipReason -Value $value -Type $type))"
                }
            }
            else {
                [pscustomobject]@{
                    Value         = $value
                    SourceValue   = $value
                    IndicatorType = 'DomainName'
                    Broadened     = $false
                    ServiceId     = $serviceId
                }
            }
        }
        'Url' {
            [pscustomobject]@{
                Value         = $value
                SourceValue   = $value
                IndicatorType = 'Url'
                Broadened     = $false
                ServiceId     = $serviceId
            }
        }
        'IpAddress' {
            [pscustomobject]@{
                Value         = $value
                SourceValue   = $value
                IndicatorType = 'IpAddress'
                Broadened     = $false
                ServiceId     = $serviceId
            }
        }
        default {
            Write-Warning "Skipping unmappable blockable address for CNI: '$value' ($(Get-CniSkipReason -Value $value -Type $type))"
        }
    }
}