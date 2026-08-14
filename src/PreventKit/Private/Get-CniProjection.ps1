<#
.SYNOPSIS
Project a blockable address to its MDE Custom Network Indicator representation.

.DESCRIPTION
Computes the destination projection of a blockable address for the Custom
Network Indicators enforcement destination. A projection is produced only when
it is semantics-preserving or an explicitly approved controlled destination
expansion. Bare domains project as non-expanded DomainName indicators; wildcard
domains project as the expanded root domain only when expansion is approved;
URLs and IP addresses project unchanged. Addresses with no safe projection are
skipped and logged with a warning.

.OUTPUTS
System.Management.Automation.PSCustomObject when a safe projection exists,
otherwise nothing.
#>
function Get-CniProjection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Address,

        [Parameter()]
        [switch]$AllowExpansion
    )

    $value = [string]$Address.Value
    $type = [string]$Address.Type
    $serviceId = [string]$Address.ServiceId
    $isWildcard = $value.StartsWith('*.', [System.StringComparison]::OrdinalIgnoreCase)

    switch ($type) {
        'Domain' {
            if ($isWildcard) {
                if ($AllowExpansion.IsPresent) {
                    [pscustomobject]@{
                        Value         = $value.Substring(2)
                        SourceValue   = $value
                        IndicatorType = 'DomainName'
                        Expanded      = $true
                        ServiceId     = $serviceId
                    }
                }
                else {
                    Write-Warning "Skipping unprojectable blockable address for CNI: '$value' ($(Get-CniSkipReason -Value $value -Type $type))"
                }
            }
            else {
                [pscustomobject]@{
                    Value         = $value
                    SourceValue   = $value
                    IndicatorType = 'DomainName'
                    Expanded      = $false
                    ServiceId     = $serviceId
                }
            }
        }
        'Url' {
            [pscustomobject]@{
                Value         = $value
                SourceValue   = $value
                IndicatorType = 'Url'
                Expanded      = $false
                ServiceId     = $serviceId
            }
        }
        'IpAddress' {
            [pscustomobject]@{
                Value         = $value
                SourceValue   = $value
                IndicatorType = 'IpAddress'
                Expanded      = $false
                ServiceId     = $serviceId
            }
        }
        default {
            Write-Warning "Skipping unprojectable blockable address for CNI: '$value' ($(Get-CniSkipReason -Value $value -Type $type))"
        }
    }
}