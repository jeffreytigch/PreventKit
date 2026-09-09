<#
.SYNOPSIS
Write a durable run log entry for one Run.

.DESCRIPTION
Persists one JSON file per Run under the log directory, capturing the run id
and timing, the catalogue directory, the exception keys applied, the source
fingerprints of every catalogue snapshot, the reconciliation outcomes per
enforcement target, the target configurations, and the Run status.
Runs that complete normally are recorded with status 'Completed'; when a
target aborts (for example a capacity preflight failure) the Run status
reflects that partial completion as 'Partial' unless the caller supplies an
explicit status; a failing Run is recorded with status 'Failed' and its error
message. The entry is emitted as an object; callers that do not want it on the
pipeline can assign it to $null.

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
        [string[]]$GlobalExceptionKey = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$Snapshots = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$TargetOutcomes = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$TargetConfigurations = @(),

        [Parameter()]
        [ValidateSet('Completed', 'Partial', 'Failed')]
        [string]$Status = 'Completed',

        [Parameter()]
        [string]$ErrorMessage
    )

    $effectiveStatus = $Status
    if (-not $PSBoundParameters.ContainsKey('Status')) {
        if (@($TargetOutcomes | Where-Object { $_.Status -in @('Aborted', 'PartiallyReconciled') }).Count -gt 0) {
            $effectiveStatus = 'Partial'
        }
    }

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

    $targetConfigs = @($TargetConfigurations | ForEach-Object {
        $config = $_
        # Handle both hashtables and pscustomobjects
        $hasProp = { param($obj, $name)
            if ($obj -is [hashtable]) { return $obj.ContainsKey($name) }
            return $obj.PSObject.Properties[$name] -ne $null
        }
        $getProp = { param($obj, $name)
            if ($obj -is [hashtable]) { return $obj[$name] }
            return $obj.$name
        }
        [pscustomobject]@{
            Target                    = & $getProp $config 'Target'
            ConfigurationMode         = & $getProp $config 'ConfigurationMode'
            Capacity                  = & $getProp $config 'Capacity'
            Status                    = & $getProp $config 'Status'
            ValidationStatus          = if (& $hasProp $config 'ValidationStatus') { & $getProp $config 'ValidationStatus' } else { $null }
            ReconciliationStatus      = if (& $hasProp $config 'ReconciliationStatus') { & $getProp $config 'ReconciliationStatus' } else { $null }
            SelectionReason           = if (& $hasProp $config 'SelectionReason') { & $getProp $config 'SelectionReason' } else { $null }
            AddCount                  = if (& $hasProp $config 'AddCount') { & $getProp $config 'AddCount' } else { $null }
            RemoveCount               = if (& $hasProp $config 'RemoveCount') { & $getProp $config 'RemoveCount' } else { $null }
            UnchangedCount            = if (& $hasProp $config 'UnchangedCount') { & $getProp $config 'UnchangedCount' } else { $null }
            UnmanagedMatchCount       = if (& $hasProp $config 'UnmanagedMatchCount') { & $getProp $config 'UnmanagedMatchCount' } else { $null }
            FailedBatchCount          = if (& $hasProp $config 'FailedBatchCount') { & $getProp $config 'FailedBatchCount' } else { $null }
        }
    })

    $entry = [pscustomobject]@{
        RunId                    = $RunId
        StartedAt                = $StartedAt
        CompletedAt              = [datetime]::UtcNow
        CatalogueDirectory       = $CatalogueDirectory
        Exceptions               = @($ExceptionKey)
        GlobalExceptions         = @($GlobalExceptionKey)
        SourceFingerprints       = @($fingerprints)
        TargetOutcomes           = @($TargetOutcomes)
        TargetConfigurations     = @($targetConfigs)
        Status                   = $effectiveStatus
        ErrorMessage             = if ([string]::IsNullOrWhiteSpace($ErrorMessage)) { $null } else { $ErrorMessage }
    }

    if (-not (Test-Path -LiteralPath $LogDirectory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $LogDirectory -Force
    }

    $file = Join-Path $LogDirectory "$($RunId.Guid).run.json"
    $entry | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $file -Encoding utf8

    $entry
}
