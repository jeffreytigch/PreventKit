<#
.SYNOPSIS
Run PreventKit over a catalogue directory, producing a snapshot per enabled
catalogue declaration.

.DESCRIPTION
The read side of a Run: for each enabled catalogue declaration in the
catalogue directory, retrieve the catalogue source, parse it with the declared
source adapter into the canonical Service / Blockable Address model, validate
the result, and produce a catalogue snapshot carrying a source fingerprint.
No enforcement destination is read or written.

With -WhatIf the run additionally computes the desired state (the union of all
enabled catalogue entries) and prints a readable WhatIf run report showing the
desired state and each catalogue contribution, still without modifying any
enforcement destination.

.PARAMETER CatalogueDirectory
Path to the version-controlled directory of catalogue declarations
(files matching *.catalog.psd1).

.EXAMPLE
Invoke-PreventKitRun -CatalogueDirectory .\catalogues

.EXAMPLE
Invoke-PreventKitRun -CatalogueDirectory .\catalogues -WhatIf

.EXAMPLE
Invoke-PreventKitRun -CatalogueDirectory .\tests\fixtures\clean

.OUTPUTS
System.Management.Automation.PSCustomObject, one per enabled catalogue
declaration in the catalogue directory. With -WhatIf, System.String report
lines instead.
#>
function Invoke-PreventKitRun {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$CatalogueDirectory
    )

    $declarationFiles = @(Get-ChildItem -Path $CatalogueDirectory -Filter '*.catalog.psd1' -File -ErrorAction Stop)

    $snapshots = @()
    foreach ($declarationFile in $declarationFiles) {
        $declaration = Import-PowerShellDataFile -LiteralPath $declarationFile.FullName

        if (-not $declaration.Enabled) {
            Write-Verbose "Skipping disabled catalogue declaration: $($declaration.Name)"
            continue
        }

        $scope = $declaration.Scope
        $source = $declaration.Source
        $adapterName = $declaration.Adapter

        $resolvedSource = $source
        if ($source -notmatch '^https?://') {
            $resolvedSource = [System.IO.Path]::GetFullPath((Join-Path $declarationFile.DirectoryName $source))
        }

        $sourceData = Get-CatalogueSource -Source $resolvedSource

        $parsed = switch ($adapterName) {
            'LolRmmCsv' { ConvertFrom-LolRmmCsv -Content $sourceData.Content -Scope $scope }
            default {
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Unknown source adapter '$adapterName' for catalogue '$($declaration.Name)'."),
                    'UnknownSourceAdapter',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $adapterName
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
        }

        $validation = Test-CatalogueValidation -Content $sourceData.Content -Parsed $parsed

        $snapshot = New-CatalogueSnapshot -Scope $scope -Source $source -Declaration $declaration `
            -SourceData $sourceData -Parsed $parsed -Validation $validation

        if ($WhatIfPreference) {
            $snapshots += $snapshot
        }
        else {
            $snapshot
        }
    }

    if ($WhatIfPreference) {
        $desiredState = Get-DesiredState -Snapshot $snapshots
        New-WhatIfReport -DesiredState $desiredState
    }
}
