<#
.SYNOPSIS
Submit MDE Custom Network Indicator mappings as permanent managed indicators.

.DESCRIPTION
Posts the given mappings to the import endpoint as permanent (no-expiration)
Block indicators, each carrying the owner marker in its description and
the source service in its title. Mappings are posted in batches of at most
BatchSize indicators, paced to respect the API rate limit (RateLimitPerMinute
calls per minute) with a Start-Sleep between batches. Each batch request goes
through Invoke-CniApiRequest so 429 responses back off and retry.

.PARAMETER Mappings
Mapped CNI entries. Each must expose Value, IndicatorType and ServiceId.

.PARAMETER Token
The access token to authenticate the import requests. Acquired by the caller;
any acquisition method works.

.PARAMETER BatchSize
Maximum number of indicators per import call.

.PARAMETER RateLimitPerMinute
Maximum API calls per minute across batches; 0 disables pacing.

.PARAMETER MaxRetries
Maximum attempts per batch before giving up on persistent 429 responses.

.PARAMETER BackoffSeconds
Base backoff seconds passed through to each request.

.OUTPUTS
System.Array of parsed API responses, one per submitted batch.
#>
function Add-CniManagedEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Mappings,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Token,

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

    $mappings = @($Mappings)
    if ($mappings.Count -eq 0) {
        return
    }

    $uri = 'https://api.security.microsoft.com/api/indicators/import'

    $delaySeconds = 0.0
    if ($RateLimitPerMinute -gt 0) {
        $delaySeconds = 60.0 / $RateLimitPerMinute
    }

    $batches = @(Get-BatchGroup -Items $mappings -BatchSize $BatchSize)
    $responses = @()
    $batchIndex = 0

    foreach ($batch in $batches) {
        $batchIndex++
        $indicators = @($batch | ForEach-Object {
            [pscustomobject]@{
                indicatorValue = $_.Value
                indicatorType  = $_.IndicatorType
                action         = 'Block'
                title          = $_.ServiceId
                description    = "$($script:ownerMarker) managed entry"
            }
        })

        $body = @{ Indicators = @($indicators) }
        $responses += Invoke-CniApiRequest -Uri $uri -Body $body -Token $Token `
            -MaxRetries $MaxRetries -BackoffSeconds $BackoffSeconds

        if ($batchIndex -lt $batches.Count -and $delaySeconds -gt 0) {
            Start-Sleep -Seconds $delaySeconds
        }
    }

    , $responses
}