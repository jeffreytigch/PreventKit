<#
.SYNOPSIS
Split a collection of items into groups no larger than a batch size.

.DESCRIPTION
Partitions the input items into consecutive batches, each with at most
BatchSize items, and emits one batch per pipeline object so that callers can
treat each batch as a single unit. Empty input produces a single empty batch.

.OUTPUTS
System.Array, one batch per output object.
#>
function Get-BatchGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Items,

        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$BatchSize
    )

    $batchList = [System.Collections.Generic.List[object]]::new()
    $current   = [System.Collections.Generic.List[object]]::new()

    foreach ($item in @($Items)) {
        $current.Add($item)
        if ($current.Count -eq $BatchSize) {
            $batchList.Add(@($current))
            $current = [System.Collections.Generic.List[object]]::new()
        }
    }

    if ($current.Count -gt 0 -or $batchList.Count -eq 0) {
        $batchList.Add(@($current))
    }

    foreach ($batch in $batchList) {
        ,@($batch)
    }
}
