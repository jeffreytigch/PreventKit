<#
.SYNOPSIS
Source adapter that parses the Awesome Tunneling markdown into the canonical
Service and Blockable Address model.

.DESCRIPTION
The Awesome Tunneling catalogue source is a Markdown list whose entries are
bullet links of the form '* [Name](url)'. Each entry maps one tunneling tool to
its URL; the URL's host is carried as the blockable address that represents the
tool. Code repository hosts (github.com, gitlab.com, bitbucket.org) are not
tunneling endpoints, so links to them are skipped and recorded as
unrepresentable. Non-bullet markdown content is ignored.

.OUTPUTS
System.Management.Automation.PSCustomObject with Services, BlockableAddresses,
Unrepresentable and Subsumed collections.
#>
function ConvertFrom-AwesomeTunneling {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Scope
    )

    $services = @{}
    $blockableAddresses = @()
    $unrepresentable = @()
    $codeHostPattern = '^(github\.com|gitlab\.com|bitbucket\.org)(\.|$)'

    $bulletPattern = '^\s*-\s+\[(?<name>[^\]]+)\]\((?<url>[^)]+)\)'
    $asteriskPattern = '^\s*\*\s+\[(?<name>[^\]]+)\]\((?<url>[^)]+)\)'

    foreach ($line in ($Content -split "`r?`n")) {
        $match = [regex]::Match($line, $asteriskPattern)
        if (-not $match.Success) {
            $match = [regex]::Match($line, $bulletPattern)
        }
        if (-not $match.Success) {
            continue
        }

        $name = $match.Groups['name'].Value.Trim()
        $url = $match.Groups['url'].Value.Trim()
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($url)) {
            continue
        }

        $hostName = $null
        if ($url -match '^https?://') {
            try {
                $hostName = ([System.Uri]$url).Host
            }
            catch {
                $hostName = $null
            }
        }

        if (-not $hostName) {
            $unrepresentable += [pscustomobject]@{
                Value  = $url
                Reason = 'Not a valid URL with a host'
            }
            Write-Warning "Skipping unrepresentable blockable address: '$url'"
            continue
        }

        if ($hostName -match $codeHostPattern) {
            $unrepresentable += [pscustomobject]@{
                Value  = $hostName
                Reason = 'Code repository host is not a tunneling endpoint'
            }
            Write-Warning "Skipping blockable address for code repository host: '$hostName'"
            continue
        }

        $type = Get-BlockableAddressType -Value $hostName
        if (-not $type) {
            $unrepresentable += [pscustomobject]@{
                Value  = $hostName
                Reason = 'Not a representable URL, domain, or IP address'
            }
            Write-Warning "Skipping unrepresentable blockable address: '$hostName'"
            continue
        }

        $serviceId = "$Scope/$name"
        if (-not $services.ContainsKey($serviceId)) {
            $services[$serviceId] = [pscustomobject]@{
                Id    = $serviceId
                Scope = $Scope
                Name  = $name
            }
        }

        $blockableAddresses += [pscustomobject]@{
            Value     = $hostName
            Type      = $type
            ServiceId = $serviceId
        }
    }

    [pscustomobject]@{
        Services           = @($services.Values)
        BlockableAddresses = @($blockableAddresses)
        Unrepresentable    = @($unrepresentable)
        Subsumed           = @()
    }
}