<#
.SYNOPSIS
Validate a parsed catalogue and return an explicit success or failure result.

.DESCRIPTION
Runs a set of named checks over the retrieved content and the parsed
canonical model. The result carries every check with its pass/fail state and
an overall Status of 'Success' or 'Failure'.

.OUTPUTS
System.Management.Automation.PSCustomObject with Status and Checks.
#>
function Test-CatalogueValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [object]$Parsed
    )

    $checks = @()

    $contentPresent = -not [string]::IsNullOrWhiteSpace($Content)
    $checks += [pscustomobject]@{
        Name   = 'SourceRetrievalSucceeded'
        Passed = $contentPresent
        Detail = if ($contentPresent) { 'Source content retrieved' } else { 'Source content is empty' }
    }

    $hasServices = @($Parsed.Services).Count -gt 0
    $checks += [pscustomobject]@{
        Name   = 'AtLeastOneService'
        Passed = $hasServices
        Detail = "Parsed $(@($Parsed.Services).Count) service(s)"
    }

    $hasBlockableAddresses = @($Parsed.BlockableAddresses).Count -gt 0
    $checks += [pscustomobject]@{
        Name   = 'AtLeastOneBlockableAddress'
        Passed = $hasBlockableAddresses
        Detail = "Parsed $(@($Parsed.BlockableAddresses).Count) blockable address(es)"
    }

    $status = if (@($checks | Where-Object { -not $_.Passed }).Count -eq 0) { 'Success' } else { 'Failure' }

    [pscustomobject]@{
        Status = $status
        Checks = @($checks)
    }
}