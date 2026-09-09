<#
.SYNOPSIS
Classify a TABL OutputJson response as Succeeded, Failed, or Unknown.

.DESCRIPTION
The Exchange Online documentation guarantees that -OutputJson continues past
invalid entries, but does not publish a response schema. This helper recognizes
common structured success and failure markers. Unknown shapes are never
assumed successful; callers retain both raw and parsed responses for diagnosis.
#>
function Get-TablBatchResponseStatus {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Response
    )

    $pending = [System.Collections.Generic.Queue[object]]::new()
    foreach ($item in @($Response)) {
        if ($null -ne $item) {
            $pending.Enqueue($item)
        }
    }

    $successFound = $false
    while ($pending.Count -gt 0) {
        $item = $pending.Dequeue()
        if ($item -is [string] -or $item -is [ValueType]) {
            continue
        }

        $properties = if ($item -is [System.Collections.IDictionary]) {
            @($item.Keys | ForEach-Object {
                [pscustomobject]@{ Name = [string]$_; Value = $item[$_] }
            })
        }
        else {
            @($item.PSObject.Properties | ForEach-Object {
                [pscustomobject]@{ Name = $_.Name; Value = $_.Value }
            })
        }

        foreach ($property in $properties) {
            $name = $property.Name
            $value = $property.Value
            $text = [string]$value

            if ($name -match '^(Status|Result|Outcome)$') {
                if ($text -match '^(Failed|Failure|Error)$') { return 'Failed' }
                if ($text -match '^(Succeeded|Success|Completed)$') { $successFound = $true }
            }
            if ($name -match '^(Success|Succeeded|IsSuccess)$') {
                if ($text -eq 'False') { return 'Failed' }
                if ($text -eq 'True') { $successFound = $true }
            }
            if ($name -match '^(HasFailures|HasErrors)$' -and $text -eq 'True') {
                return 'Failed'
            }
            if ($name -match '^(FailedCount|ErrorCount)$' -and $value -as [int] -gt 0) {
                return 'Failed'
            }
            if ($name -eq 'StatusCode' -and $value -as [int]) {
                $statusCode = [int]$value
                if ($statusCode -ge 400) { return 'Failed' }
                if ($statusCode -ge 200 -and $statusCode -lt 300) { $successFound = $true }
            }
            if ($name -match '^(Error|Errors|ErrorMessage|Failure|Failures|FailureReason)$') {
                if ($null -ne $value) {
                    if ($value -is [string]) {
                        if (-not [string]::IsNullOrWhiteSpace($value) -and $value -notmatch '^(False|0|None)$') {
                            return 'Failed'
                        }
                    }
                    elseif ($value -is [ValueType]) {
                        if ($text -notmatch '^(False|0)$') { return 'Failed' }
                    }
                    elseif ($value -is [System.Collections.IEnumerable] -and @($value).Count -gt 0) {
                        return 'Failed'
                    }
                    elseif ($value.PSObject.Properties.Count -gt 0) {
                        return 'Failed'
                    }
                }
            }
            if ($name -eq 'ErrorCode' -and -not [string]::IsNullOrWhiteSpace($text) -and $text -ne '0') {
                return 'Failed'
            }

            if ($null -ne $value -and $value -isnot [string] -and $value -isnot [ValueType]) {
                foreach ($child in @($value)) {
                    if ($null -ne $child) {
                        $pending.Enqueue($child)
                    }
                }
            }
        }
    }

    if ($successFound) { return 'Succeeded' }
    return 'Unknown'
}
