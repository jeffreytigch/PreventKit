<#
.SYNOPSIS
Send a request to the MDE Custom Network Indicators API with an
Authorization Bearer token and 429 rate-limit backoff and retry.

.DESCRIPTION
Sends an HTTP request (GET or POST) to the given API Uri with the body
serialized as JSON, carrying the caller-supplied token as an Authorization
Bearer header. When the request fails with HTTP 429 (Too Many Requests), it
backs off for an increasing number of seconds and retries, up to MaxRetries
attempts, keeping the token on every attempt. Any other failure is rethrown
immediately.

.PARAMETER Uri
The full API endpoint URI to call.

.PARAMETER Body
The object to serialize as the JSON request body. For GET requests, this can
be an empty hashtable @{}.

.PARAMETER Token
The access token to send as an Authorization Bearer header. Acquired by the
caller; any acquisition method works.

.PARAMETER Method
The HTTP method to use. Default is 'Post'. Supported values: 'Get', 'Post'.

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

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Token,

        [Parameter()]
        [ValidateSet('Get', 'Post')]
        [string]$Method = 'Post',

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaxRetries = 5,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$BackoffSeconds = 30
    )

    $headers = @{ Authorization = "Bearer $Token" }

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            if ($Method -eq 'Get') {
                return Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers
            }
            else {
                $json = $Body | ConvertTo-Json -Depth 6
                return Invoke-RestMethod -Method Post -Uri $Uri -ContentType 'application/json' -Headers $headers -Body $json
            }
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