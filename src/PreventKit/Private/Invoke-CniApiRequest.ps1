<#
.SYNOPSIS
POST a request body to the MDE Custom Network Indicators API with 429
rate-limit backoff and retry.

.DESCRIPTION
Sends a POST to the given API Uri with the body serialized as JSON. When the
request fails with HTTP 429 (Too Many Requests), it backs off for an
increasing number of seconds and retries, up to MaxRetries attempts. Any other
failure is rethrown immediately.

.PARAMETER Uri
The full API endpoint URI to POST to.

.PARAMETER Body
The object to serialize as the JSON request body.

.PARAMETER MaxRetries
Maximum number of attempts before giving up on persistent 429 responses.

.PARAMETER BackoffSeconds
Base number of seconds to sleep before a retry; scaled by the attempt number.

.OUTPUTS
System.Object, the parsed API response.
#>
function Invoke-CniApiRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Uri,

        [Parameter(Mandatory)]
        [object]$Body,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaxRetries = 5,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$BackoffSeconds = 30
    )

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            $json = $Body | ConvertTo-Json -Depth 6
            return Invoke-RestMethod -Method Post -Uri $Uri -ContentType 'application/json' -Body $json
        }
        catch {
            if ($attempt -gt $MaxRetries) {
                throw
            }
            if (-not (Test-IsRateLimited -ErrorRecord $_)) {
                throw
            }
            Start-Sleep -Seconds ($BackoffSeconds * $attempt)
        }
    }
}