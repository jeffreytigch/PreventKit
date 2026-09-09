<#
.SYNOPSIS
Add URL block entries to the Tenant Allow/Block List as permanent managed
entries carrying the owner marker.

.DESCRIPTION
Thin seam over New-TenantAllowBlockListItems. Adds the given values as
permanent (no-expiration) URL block entries with the owner marker in
their Notes, so the read side can later classify them as PreventKit managed
entries. This is the only TABL write path used by reconciliation; it is kept
deliberately thin so the reconcile logic can be tested by mocking this seam.

The cmdlet accepts the whole batch -Entries array in a single call (never one
call per entry). -OutputJson returns all entries in a single JSON value so the
command does not halt on the first entry containing a syntax error. The full
response and whether it carries a recognized failure marker are returned to
the reconciler for per-batch reporting.

.PARAMETER Values
The URL values to block.

.PARAMETER Notes
Owner marker note to stamp on each entry.
#>
function Add-TablManagedEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Values,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Notes
    )

    $rawResponse = New-TenantAllowBlockListItems -ListType Url -Block -Entries $Values `
        -Notes $Notes -NoExpiration -OutputJson -ErrorAction Stop

    $response = $rawResponse
    $responseParseFailed = $false
    if ($rawResponse -is [string]) {
        try {
            $response = $rawResponse | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            # Preserve an undocumented response verbatim; a later live run can
            # still report it without treating an unknown shape as success.
            $responseParseFailed = $true
        }
    }

    $status = if ($responseParseFailed) { 'Unknown' } else { Get-TablBatchResponseStatus -Response $response }

    [pscustomobject]@{
        Status             = $status
        HasFailures        = $status -eq 'Failed'
        IsSuccessConfirmed = $status -eq 'Succeeded'
        RawResponse        = $rawResponse
        Response           = $response
    }
}
