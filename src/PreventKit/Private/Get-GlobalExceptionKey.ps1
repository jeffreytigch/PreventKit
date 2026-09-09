<#
.SYNOPSIS
Read the exception keys of every enabled global exception declaration in an
exception directory.

.DESCRIPTION
Enumerates the global exception declarations (files matching *.exception.psd1)
in the exception directory and returns the exception keys of the declarations
that are enabled. Global exceptions are stored, version-controlled, and
permanent unless edited: they suppress enforcement at every enforcement
target on every Run. A disabled declaration contributes no keys, so
disabling or removing it restores enforcement on the next Run.

.OUTPUTS
System.String, one exception key per enabled declaration entry.
#>
function Get-GlobalExceptionKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ExceptionDirectory
    )

    $keys = @()
    $declarationFiles = @(Get-ChildItem -Path $ExceptionDirectory -Filter '*.exception.psd1' -File -ErrorAction Stop)

    foreach ($declarationFile in $declarationFiles) {
        $declaration = Import-PowerShellDataFile -LiteralPath $declarationFile.FullName

        if (-not $declaration.Enabled) {
            Write-Verbose "Skipping disabled global exception declaration: $($declaration.Name)"
            continue
        }

        foreach ($key in @($declaration.ExceptionKey)) {
            if ([string]::IsNullOrWhiteSpace($key)) {
                continue
            }
            if ($key -notlike 'service:*' -and $key -notlike 'domain:*') {
                Write-Warning "Ignoring global exception key '$key' in '$($declaration.Name)': expected 'service:<serviceId>' or 'domain:<value>'."
                continue
            }
            $keys += $key
        }
    }

    $keys
}