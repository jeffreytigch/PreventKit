<#
.SYNOPSIS
Register a custom catalogue source adapter.

.DESCRIPTION
Adds a source adapter to the PreventKit catalogue processor registry. The adapter
must expose a scriptblock that accepts -Content and -Scope parameters and returns
a PSCustomObject with Services and BlockableAddresses properties.

.PARAMETER Name
Unique name for the adapter (e.g., 'MyCustomCsv').

.PARAMETER ParseScriptBlock
Scriptblock that parses the raw source content. Must accept parameters:
-Content (string) - The raw source content
-Scope (string) - The catalogue scope
Returns an object with Services and BlockableAddresses properties.

.PARAMETER Description
Optional description of the adapter.

.EXAMPLE
Register-CatalogueAdapter -Name 'MyCsv' -ParseScriptBlock {
    param($Content, $Scope)
    $rows = $Content | ConvertFrom-Csv
    [pscustomobject]@{
        Services = @()
        BlockableAddresses = $rows | ForEach-Object {
            [pscustomobject]@{
                Value = $_.Url
                Type = $_.Type
                ServiceId = "$Scope/$($_.Service)"
            }
        }
    }
} -Description 'Custom CSV adapter for my threat intel feed'
#>
function Register-CatalogueAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$ParseScriptBlock,

        [Parameter()]
        [string]$Description
    )

    $script:catalogueAdapters[$Name] = [pscustomobject]@{
        Name        = $Name
        ParseScript = $ParseScriptBlock
        Description = $Description
    }

    Write-Verbose "Registered catalogue adapter '$Name'"
}

<#
.SYNOPSIS
Get a registered catalogue source adapter by name.

.DESCRIPTION
Retrieves a previously registered catalogue adapter from the registry.

.PARAMETER Name
The name of the adapter to retrieve.

.OUTPUTS
The adapter object or $null if not found.
#>
function Get-CatalogueAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    return $script:catalogueAdapters[$Name]
}

<#
.SYNOPSIS
List all registered catalogue source adapters.

.OUTPUTS
Array of registered adapter objects.
#>
function Get-CatalogueAdapterList {
    [CmdletBinding()]
    param()

    return $script:catalogueAdapters.Values
}

<#
.SYNOPSIS
Unregister a catalogue source adapter.

.DESCRIPTION
Removes a previously registered adapter from the registry.

.PARAMETER Name
The name of the adapter to unregister.
#>
function Unregister-CatalogueAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    $script:catalogueAdapters.Remove($Name) | Out-Null
    Write-Verbose "Unregistered catalogue adapter '$Name'"
}

# Initialize the adapter registry with built-in adapters
$script:catalogueAdapters = @{}

# Register built-in LolRmmCsv adapter
Register-CatalogueAdapter -Name 'LolRmmCsv' -ParseScriptBlock {
    param($Content, $Scope)
    return ConvertFrom-LolRmmCsv -Content $Content -Scope $Scope
} -Description 'Built-in LolRMM CSV parser'