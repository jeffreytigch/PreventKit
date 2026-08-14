<#
.SYNOPSIS
Test whether an error record signals a rate limit (HTTP 429).

.DESCRIPTION
Returns $true when the error's exception carries an HTTP 429 Too Many Requests
status, either on an HttpResponseMessage Response object or on the exception
itself. Used by the CNI write path to decide whether to back off and retry.

.OUTPUTS
System.Boolean.
#>
function Test-IsRateLimited {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$ErrorRecord
    )

    $exception = $ErrorRecord.Exception
    if (-not $exception) {
        return $false
    }

    $statusCode = $null

    $responseProp = $exception.PSObject.Properties['Response']
    if ($null -ne $responseProp -and $null -ne $responseProp.Value -and $null -ne $responseProp.Value.PSObject.Properties['StatusCode']) {
        $statusCode = $responseProp.Value.StatusCode
    }

    if ($null -eq $statusCode -and $null -ne $exception.PSObject.Properties['StatusCode']) {
        $statusCode = $exception.StatusCode
    }

    return ($statusCode -eq [System.Net.HttpStatusCode]::TooManyRequests)
}