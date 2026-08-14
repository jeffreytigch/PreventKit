<#
.SYNOPSIS
Retrieve a catalogue source and produce its content fingerprint.

.DESCRIPTION
Reads the raw content of a catalogue source given a URL or local file path,
captures the retrieval time, and computes the SHA-256 content hash over the
raw bytes. Relative file paths are resolved against the current location.

.OUTPUTS
System.Management.Automation.PSCustomObject with Content, ContentHash,
RetrievedAt and SourceLocation properties.
#>
function Get-CatalogueSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Source
    )

    $retrievedAt = [datetime]::UtcNow
    $sourceLocation = $null
    $bytes = $null

    try {
        if ($Source -match '^https?://') {
            $response = Invoke-WebRequest -Uri $Source -UseBasicParsing -ErrorAction Stop
            $sourceLocation = $Source
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($response.Content)
        }
        else {
            $sourceLocation = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Source)
            $bytes = [System.IO.File]::ReadAllBytes($sourceLocation)
        }
    }
    catch {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $_.Exception,
            'CatalogueSourceRetrievalFailed',
            [System.Management.Automation.ErrorCategory]::OperationStopped,
            $Source
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash($bytes)
    }
    finally {
        $sha256.Dispose()
    }

    $contentHash = [BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant()

    [pscustomobject]@{
        SourceLocation = $sourceLocation
        Content        = [System.Text.Encoding]::UTF8.GetString($bytes)
        ContentHash    = $contentHash
        RetrievedAt    = $retrievedAt
    }
}