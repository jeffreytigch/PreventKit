<#
.SYNOPSIS
Verify the integrity of the PreventKit module files.

.DESCRIPTION
Computes SHA-256 hashes of all module files and compares them against a known-good
baseline. This helps detect supply chain attacks where module files have been
tampered with after distribution.

.PARAMETER BaselineFile
Path to a JSON file containing the expected hashes. If not provided, outputs
the current hashes for creating a baseline.

.PARAMETER FailOnMismatch
If specified, throws an error when any file hash doesn't match the baseline.

.OUTPUTS
PSCustomObject with File, ExpectedHash, ActualHash, and Match properties.
#>
function Get-PreventKitModuleIntegrity {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$BaselineFile,

        [Parameter()]
        [switch]$FailOnMismatch
    )

    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $files = Get-ChildItem -Path $moduleRoot -Recurse -File -Exclude '*.md', '*.json', '*.git*'

    $results = @()
    $baseline = @{}

    if ($BaselineFile -and (Test-Path -LiteralPath $BaselineFile)) {
        $baseline = Get-Content -Raw -Path $BaselineFile | ConvertFrom-Json -AsHashtable
    }

    foreach ($file in $files) {
        $hash = Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256
        $relativePath = $file.FullName.Substring($moduleRoot.Length + 1)

        $expectedHash = if ($baseline.ContainsKey($relativePath)) { $baseline[$relativePath] } else { $null }
        $match = $true
        if ($expectedHash) {
            $match = ($hash.Hash -eq $expectedHash)
        }

        $results += [pscustomobject]@{
            File         = $relativePath
            ExpectedHash = $expectedHash
            ActualHash   = $hash.Hash
            Match        = $match
        }
    }

    if ($FailOnMismatch -and ($results | Where-Object { -not $_.Match })) {
        $mismatches = $results | Where-Object { -not $_.Match }
        throw "Module integrity check failed: $($mismatches.Count) file(s) have unexpected hashes."
    }

    return $results
}

<#
.SYNOPSIS
Create a baseline integrity file for the PreventKit module.

.DESCRIPTION
Generates a JSON file containing SHA-256 hashes of all module files. This
baseline can be used with Get-PreventKitModuleIntegrity to verify the module
has not been tampered with.

.PARAMETER OutputPath
Path where the baseline JSON file will be written.

.EXAMPLE
New-PreventKitIntegrityBaseline -OutputPath ./preventkit-baseline.json
#>
function New-PreventKitIntegrityBaseline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath
    )

    $results = Get-PreventKitModuleIntegrity
    $baseline = @{}
    foreach ($result in $results) {
        if ($result.File) {
            $baseline[$result.File] = $result.ActualHash
        }
    }

    $baseline | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding utf8

    Write-Host "Baseline written to $OutputPath with $($results.Count) files."
}