<#
.SYNOPSIS
Classify a catalogue URI as a representable blockable address type.

.DESCRIPTION
Returns 'Domain', 'Url', or 'IpAddress' when the value is a representable
URL, domain, or IP address, and $null otherwise. A leading '*.'
wildcard is permitted for domains; any other wildcard or malformed
label makes the value unrepresentable.

.OUTPUTS
System.String when representable, otherwise $null.
#>
function Get-BlockableAddressType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Value
    )

    $ipv4Pattern = '^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$'
    if ($Value -imatch $ipv4Pattern) {
        return 'IpAddress'
    }

    $domainPattern = '^(\*\.)?[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+$'
    if ($Value -imatch $domainPattern) {
        return 'Domain'
    }

    $urlPattern = '^https?://'
    if ($Value -imatch $urlPattern) {
        return 'Url'
    }

    return $null
}