<#
.SYNOPSIS
Test whether a service or blockable address is suppressed by an exception key.

.DESCRIPTION
An exception key is an exact, namespaced identifier used by invocation
exceptions (supplied through a Run's parameters) and global exceptions
(stored declarations). Keys are of the form 'service:<serviceId>', which
matches a Service with that Id (and therefore every blockable address of that
service), or 'domain:<value>', which matches a blockable address with that
Value. Matching is case-insensitive; a missing or empty candidate never
matches.

.OUTPUTS
System.Boolean, $true when the candidate is suppressed.
#>
function Test-ExceptionKey {
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