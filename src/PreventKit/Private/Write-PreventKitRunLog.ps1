<#
.SYNOPSIS
Write a durable run log entry for one Run.

.DESCRIPTION
Persists one JSON file per Run under the log directory, capturing the run id
and timing, the catalogue directory, the exception keys applied, the source
fingerprints of every catalogue snapshot, and the reconciliation outcomes per
enforcement destination. The entry is emitted as an object; callers that do not
want it on the pipeline can assign it to $null.

.OUTPUTS
System.Management.Automation.PSCustomObject, the written log entry.
#>
function Write-PreventKitRunLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$LogDirectory,

        [Parameter()]
        [guid]$RunId = [guid]::NewGuid(),

        [Parameter()]
        [datetime]$StartedAt = [datetime]::UtcNow,

        [Parameter()]
        [string]$CatalogueDirectory,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$ExceptionKey = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$Snapshots = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$DestinationOutcomes = @()
    )

    $fingerprints = @($Snapshots | ForEach-Object {
        [pscustomobject]@{
            CatalogueName    = $_.CatalogueName
            SourceLocation   = $_.Fingerprint.SourceLocation
            RetrievedAt      = $_.Fingerprint.RetrievedAt
            ContentHash      = $_.Fingerprint.ContentHash
            ValidationStatus = $_.Validation.Status
            UsedLastKnownGood = $_.Fingerprint.UsedLastKnownGood
            FailureReason    = $_.Fingerprint.FailureReason
            ParsedCounts     = $_.Fingerprint.ParsedCounts
        }
    })

    $entry = [pscustomobject]@{
        RunId              = $RunId
        StartedAt          = $StartedAt
        CompletedAt        = [datetime]::UtcNow
        CatalogueDirectory = $CatalogueDirectory
        Exceptions         = @($ExceptionKey)
        SourceFingerprints = @($fingerprints)
        DestinationOutcomes = @($DestinationOutcomes)
    }

    if (-not (Test-Path -LiteralPath $LogDirectory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $LogDirectory -Force
    }

    $file = Join-Path $LogDirectory "$($RunId.Guid).run.json"
    $entry | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $file -Encoding utf8

    $entry
}