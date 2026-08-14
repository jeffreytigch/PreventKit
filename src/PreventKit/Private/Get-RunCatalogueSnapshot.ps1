<#
.SYNOPSIS
Retrieve, parse, and validate one catalogue declaration for a Run, falling back
to the last known good snapshot on failure.

.DESCRIPTION
Resolves the declared source, retrieves it, parses it with the declared source
adapter, and validates the result. A snapshot that passes validation is
persisted as the catalogue's last known good snapshot and returned. When
retrieval or validation fails, the last known good snapshot is returned with
the fallback flagged on its fingerprint; when none exists, a snapshot recording
the failure is returned. The Run therefore always completes.

.OUTPUTS
System.Management.Automation.PSCustomObject, one catalogue snapshot.
#>
function Get-RunCatalogueSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DeclarationFile,

        [Parameter(Mandatory)]
        [hashtable]$Declaration,

        [Parameter()]
        [string]$StateDirectory
    )

    $scope = $Declaration.Scope
    $source = $Declaration.Source
    $adapterName = $Declaration.Adapter

    $resolvedSource = $source
    if ($source -notmatch '^https?://') {
        $resolvedSource = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $DeclarationFile) $source))
    }

    $sourceData = $null
    $retrievalError = $null
    try {
        $sourceData = Get-CatalogueSource -Source $resolvedSource
    }
    catch {
        $retrievalError = $_.Exception.Message
    }

    if ($null -eq $sourceData) {
        $failedSnapshot = New-FailedCatalogueSnapshot -Declaration $Declaration -Source $source `
            -ResolvedSource $resolvedSource -FailureReason $retrievalError
        return Get-LastKnownGoodSnapshot -StateDirectory $StateDirectory -CatalogueName $Declaration.Name `
            -FailureReason $retrievalError -Fallback $failedSnapshot
    }

    $parsed = switch ($adapterName) {
        'LolRmmCsv' { ConvertFrom-LolRmmCsv -Content $sourceData.Content -Scope $scope }
        default {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Unknown source adapter '$adapterName' for catalogue '$($Declaration.Name)'."),
                'UnknownSourceAdapter',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                $adapterName
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }

    $validation = Test-CatalogueValidation -Content $sourceData.Content -Parsed $parsed
    $snapshot = New-CatalogueSnapshot -Scope $scope -Source $source -Declaration $Declaration `
        -SourceData $sourceData -Parsed $parsed -Validation $validation

    if ($validation.Status -eq 'Success') {
        Save-LastKnownGoodSnapshot -StateDirectory $StateDirectory -Snapshot $snapshot
        return $snapshot
    }

    $failureReason = "Catalogue validation failed for source '$resolvedSource'."
    Get-LastKnownGoodSnapshot -StateDirectory $StateDirectory -CatalogueName $Declaration.Name `
        -FailureReason $failureReason -Fallback $snapshot
}