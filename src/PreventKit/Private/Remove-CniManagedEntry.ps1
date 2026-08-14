<#
.SYNOPSIS
Remove MDE Custom Network Indicators by id via the BatchDelete endpoint.

.DESCRIPTION
Posts the given indicator ids to the BatchDelete endpoint in batches of at most
BatchSize ids, paced to respect the API rate limit (RateLimitPerMinute calls per
minute) with a Start-Sleep between batches. Each batch request goes through
Invoke-CniApiRequest so 429 responses back off and retry. Callers are expected
to pass only ids of managed indicators, never unmanaged collisions.

.PARAMETER Id
The ids of the managed indicators to remove.

.PARAMETER BatchSize
Maximum number of ids per BatchDelete call.

.PARAMETER RateLimitPerMinute
Maximum API calls per minute across batches; 0 disables pacing.

.PARAMETER MaxRetries
Maximum attempts per batch before giving up on persistent 429 responses.

.PARAMETER BackoffSeconds
Base backoff seconds passed through to each request.

.OUTPUTS
System.Array of parsed API responses, one per submitted batch.
#>
function Remove-CniManagedEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$BatchSize = 500,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$RateLimitPerMinute = 30,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaxRetries = 5,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$BackoffSeconds = 30
    )

    $ids = @($Id)
    if ($ids.Count -eq 0) {
        return
    }

    $uri = 'https://api.security.microsoft.com/api/indicators/BatchDelete'

    $delaySeconds = 0.0
    if ($RateLimitPerMinute -gt 0) {
        $delaySeconds = 60.0 / $RateLimitPerMinute
    }

    $batches = @(Get-BatchGroup -Items $ids -BatchSize $BatchSize)
    $responses = @()
    $batchIndex = 0

    foreach ($batch in $batches) {
        $batchIndex++
        $body = @{ IndicatorIds = @($batch) }
        $responses += Invoke-CniApiRequest -Uri $uri -Body $body `
            -MaxRetries $MaxRetries -BackoffSeconds $BackoffSeconds

        if ($batchIndex -lt $batches.Count -and $delaySeconds -gt 0) {
            Start-Sleep -Seconds $delaySeconds
        }
    }

    , $responses
}