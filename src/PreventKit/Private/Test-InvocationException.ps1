<#
.SYNOPSIS
Test whether a service or blockable address is suppressed by an invocation
exception key.

.DESCRIPTION
An invocation exception is a non-overriding exception supplied through a Run's
parameters. Keys are exact, namespaced identifiers: 'service:<serviceId>'
matches a Service with that Id (and therefore every blockable address of that
service) and 'domain:<value>' matches a blockable address with that Value.
Matching is case-insensitive; a missing or empty candidate never matches.

.OUTPUTS
System.Boolean, $true when the candidate is suppressed.
#>
function Test-InvocationException {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$ExceptionKey,

        [Parameter()]
        [string]$ServiceId,

        [Parameter()]
        [string]$AddressValue
    )

    foreach ($key in @($ExceptionKey)) {
        if ([string]::IsNullOrWhiteSpace($key)) {
            continue
        }

        if ($key -like 'service:*') {
            $match = $key.Substring('service:'.Length)
            if (-not [string]::IsNullOrWhiteSpace($ServiceId) -and $ServiceId -ieq $match) {
                return $true
            }
        }
        elseif ($key -like 'domain:*') {
            $match = $key.Substring('domain:'.Length)
            if (-not [string]::IsNullOrWhiteSpace($AddressValue) -and $AddressValue -ieq $match) {
                return $true
            }
        }
    }

    $false
}